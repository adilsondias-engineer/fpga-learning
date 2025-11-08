----------------------------------------------------------------------------------
-- MII Receiver
-- Receives Ethernet frames via MII interface from DP83848J PHY
-- 
-- MII Specifications:
-- - 4-bit data bus (nibbles)
-- - Single Data Rate (SDR) - rising edge only
-- - 25 MHz clock for 100 Mbps mode
-- - 2.5 MHz clock for 10 Mbps mode
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mii_rx is
    Port (
        -- MII Interface (from PHY)
        mii_rx_clk  : in  STD_LOGIC;                      -- 25 MHz for 100 Mbps
        mii_rxd     : in  STD_LOGIC_VECTOR(3 downto 0);   -- 4-bit data
        mii_rx_dv   : in  STD_LOGIC;                      -- Data valid
        mii_rx_er   : in  STD_LOGIC;                      -- Error (optional)
        
        -- Byte-level output
        rx_data     : out STD_LOGIC_VECTOR(7 downto 0);   -- Assembled byte
        rx_valid    : out STD_LOGIC;                      -- Byte valid
        rx_error    : out STD_LOGIC;                      -- Error detected
        
        -- Frame control
        frame_start : out STD_LOGIC;                      -- Start of frame
        frame_end   : out STD_LOGIC                       -- End of frame
    );
end mii_rx;

architecture Behavioral of mii_rx is

    -- Nibble assembly
    signal nibble_low  : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal nibble_high : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal nibble_cnt  : STD_LOGIC := '0';  -- 0 = waiting for low nibble, 1 = waiting for high

    -- Frame detection
    signal dv_prev     : STD_LOGIC := '0';
    signal in_frame    : STD_LOGIC := '0';

    -- Preamble/SFD detection
    signal byte_data   : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal sfd_detected : STD_LOGIC := '0';
    signal preamble_done : STD_LOGIC := '0';

    constant SFD_BYTE  : STD_LOGIC_VECTOR(7 downto 0) := x"D5";

begin

    ----------------------------------------------------------------------------------
    -- MII Reception Process
    -- Assembles 4-bit nibbles into bytes
    -- MII sends data LSB-first (low nibble then high nibble)
    -- Strips 7-byte preamble (0x55) and 1-byte SFD (0xD5)
    ----------------------------------------------------------------------------------

    process(mii_rx_clk)
    begin
        if rising_edge(mii_rx_clk) then

            -- Default outputs
            rx_valid    <= '0';
            frame_start <= '0';
            frame_end   <= '0';
            rx_error    <= mii_rx_er;

            -- Store previous data valid
            dv_prev <= mii_rx_dv;

            -- Detect start of PHY data (DV goes high)
            if mii_rx_dv = '1' and dv_prev = '0' then
                in_frame       <= '1';
                nibble_cnt     <= '0';  -- Reset nibble counter
                sfd_detected   <= '0';  -- Reset SFD detector
                preamble_done  <= '0';  -- Reset preamble flag
            end if;

            -- Detect frame end (DV goes low)
            if mii_rx_dv = '0' and dv_prev = '1' then
                frame_end      <= '1';
                in_frame       <= '0';
                nibble_cnt     <= '0';
                sfd_detected   <= '0';
                preamble_done  <= '0';
            end if;

            -- Process data when valid
            if mii_rx_dv = '1' then

                if nibble_cnt = '0' then
                    -- First nibble (low nibble / bits 3:0)
                    nibble_low <= mii_rxd;
                    nibble_cnt <= '1';

                else
                    -- Second nibble (high nibble / bits 7:4)
                    nibble_high <= mii_rxd;
                    nibble_cnt  <= '0';

                    -- Assemble complete byte
                    byte_data <= mii_rxd & nibble_low;  -- High nibble & Low nibble

                    -- Check for SFD byte (0xD5) - marks end of preamble
                    if (mii_rxd & nibble_low) = SFD_BYTE and sfd_detected = '0' then
                        sfd_detected  <= '1';
                        preamble_done <= '1';
                        frame_start   <= '1';  -- Signal start of actual frame data
                        -- Don't output this byte
                    else
                        -- Only output bytes AFTER SFD
                        if preamble_done = '1' then
                            rx_data  <= mii_rxd & nibble_low;
                            rx_valid <= '1';
                        end if;
                    end if;

                end if;

            else
                -- No valid data
                nibble_cnt <= '0';
            end if;

        end if;
    end process;

end Behavioral;