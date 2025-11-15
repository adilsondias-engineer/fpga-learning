----------------------------------------------------------------------------------
-- MII Transmitter with FCS (CRC32) Generation
-- Transmits Ethernet frames via MII interface to DP83848J PHY
--
-- Automatically calculates and appends FCS (Frame Check Sequence - CRC32)
--
-- MII Specifications:
-- - 4-bit data bus (nibbles)
-- - Single Data Rate (SDR) - falling edge drive, rising edge sample
-- - 25 MHz clock for 100 Mbps mode
--
-- Sends preamble (7 × 0x55) + SFD (0xD5) automatically
-- Sends data byte as 2 nibbles (low nibble first, then high nibble)
-- Calculates CRC32 over all data bytes
-- Appends 4-byte FCS at end of frame
-- Waits 12-byte interframe gap before returning to IDLE
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mii_tx_with_fcs is
    port (
        mii_tx_clk   : in  std_logic;  -- MII TX clock (25 MHz)
        reset        : in  std_logic;

        -- Data input (from packet builder)
        tx_data      : in  std_logic_vector(7 downto 0);  -- Byte to send
        tx_valid     : in  std_logic;  -- Data valid
        tx_ready     : out std_logic;  -- Ready to accept byte
        tx_start     : in  std_logic;  -- Start of packet
        tx_end       : in  std_logic;  -- End of packet

        -- MII TX interface (to PHY)
        eth_tx_en    : out std_logic; -- high during transmission
        eth_txd      : out std_logic_vector(3 downto 0) -- 4-bit data to PHY
    );
end mii_tx_with_fcs;

architecture Behavioral of mii_tx_with_fcs is

    type tx_state_type is (IDLE, PREAMBLE, SFD, DATA_LOW, DATA_HIGH,
                           FCS_NIBBLE_ST, INTERFRAME_GAP);
    signal tx_state : tx_state_type := IDLE;

    signal preamble_count : integer range 0 to 7 := 0;
    signal nibble_phase : std_logic := '0';  -- 0 = low nibble, 1 = high nibble
    signal current_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_ready_int : std_logic := '0';

    -- FCS (CRC32) signals
    signal fcs : std_logic_vector(31 downto 0) := (others => '0');
    signal fcs_nibble_count : integer range 0 to 7 := 0;  -- 8 nibbles = 4 bytes

    -- Interframe gap counter (12 bytes = 96 bits = 24 nibbles minimum)
    signal gap_count : integer range 0 to 31 := 0;
    constant GAP_NIBBLES : integer := 24;

    -- CRC32 polynomial
    constant CRC_POLY : std_logic_vector(31 downto 0) := x"04C11DB7";

    -- Function to compute one step of CRC32
    -- Takes current CRC and 4-bit nibble, returns new CRC
    function crc32_step(crc_in : std_logic_vector(31 downto 0);
                        nibble : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable crc_temp : std_logic_vector(31 downto 0);
        variable bit_val : std_logic;
    begin
        crc_temp := crc_in;
        -- Process 4 bits (nibble), LSB first
        for i in 0 to 3 loop
            bit_val := nibble(i);
            if (crc_temp(31) xor bit_val) = '1' then
                crc_temp := (crc_temp(30 downto 0) & '0') xor CRC_POLY;
            else
                crc_temp := crc_temp(30 downto 0) & '0';
            end if;
        end loop;
        return crc_temp;
    end function;

    -- Function to swap nibbles in each byte for FCS transmission
    -- Input:  0xAABBCCDD -> Output: 0xBBAADDCC
    function swap_nibbles_in_bytes(data : std_logic_vector(31 downto 0))
        return std_logic_vector is
        variable result : std_logic_vector(31 downto 0);
    begin
        -- Byte 3
        result(31 downto 28) := data(27 downto 24);
        result(27 downto 24) := data(31 downto 28);
        -- Byte 2
        result(23 downto 20) := data(19 downto 16);
        result(19 downto 16) := data(23 downto 20);
        -- Byte 1
        result(15 downto 12) := data(11 downto 8);
        result(11 downto 8)  := data(15 downto 12);
        -- Byte 0
        result(7 downto 4)   := data(3 downto 0);
        result(3 downto 0)   := data(7 downto 4);
        return result;
    end function;

begin
    tx_ready <= tx_ready_int;

    process(mii_tx_clk)
        variable fcs_swapped : std_logic_vector(31 downto 0);
        variable fcs_nibble : std_logic_vector(3 downto 0);
    begin
        if falling_edge(mii_tx_clk) then
            if reset = '1' then
                tx_state <= IDLE;
                eth_tx_en <= '0';
                eth_txd <= (others => '0');
                tx_ready_int <= '0';
                preamble_count <= 0;
                nibble_phase <= '0';
                fcs <= (others => '0');
                fcs_nibble_count <= 0;
                gap_count <= 0;

            else
                case tx_state is
                    when IDLE =>
                        eth_tx_en <= '0';
                        eth_txd <= (others => '0');
                        tx_ready_int <= '1';
                        preamble_count <= 0;
                        nibble_phase <= '0';
                        fcs <= (others => '0');  -- Reset CRC to all 0's (like working project)
                        fcs_nibble_count <= 0;
                        gap_count <= 0;

                        if tx_start = '1' then
                            tx_state <= PREAMBLE;
                            tx_ready_int <= '0';
                        end if;

                    when PREAMBLE =>
                        eth_tx_en <= '1';
                        tx_ready_int <= '0';

                        if nibble_phase = '0' then
                            eth_txd <= "0101";  -- 0x5 (low nibble of 0x55)
                            nibble_phase <= '1';
                        else
                            eth_txd <= "0101";  -- 0x5 (high nibble of 0x55)
                            nibble_phase <= '0';
                            preamble_count <= preamble_count + 1;

                            if preamble_count = 6 then
                                tx_state <= SFD;
                                preamble_count <= 0;
                            end if;
                        end if;

                    when SFD =>
                        eth_tx_en <= '1';
                        tx_ready_int <= '0';

                        if nibble_phase = '0' then
                            eth_txd <= "0101";  -- 0x5 (low nibble of 0xD5)
                            nibble_phase <= '1';
                        else
                            eth_txd <= "1101";  -- 0xD (high nibble of 0xD5)
                            nibble_phase <= '0';
                            tx_state <= DATA_LOW;
                            tx_ready_int <= '1';
                        end if;

                    when DATA_LOW =>
                        eth_tx_en <= '1';

                        if tx_end = '1' and tx_valid = '0' then
                            -- End of data, send FCS
                            -- Swap nibbles in each byte and invert
                            fcs_swapped := swap_nibbles_in_bytes(not fcs);
                            fcs <= fcs_swapped;  -- Store swapped version
                            fcs_nibble_count <= 0;
                            tx_state <= FCS_NIBBLE_ST;
                            tx_ready_int <= '0';

                        elsif tx_valid = '1' and tx_ready_int = '1' then
                            -- Accept byte and send low nibble
                            current_byte <= tx_data;
                            eth_txd <= tx_data(3 downto 0);
                            -- Update CRC with low nibble
                            fcs <= crc32_step(fcs, tx_data(3 downto 0));
                            tx_state <= DATA_HIGH;
                            tx_ready_int <= '0';
                        else
                            tx_ready_int <= '1';
                        end if;

                    when DATA_HIGH =>
                        eth_tx_en <= '1';
                        eth_txd <= current_byte(7 downto 4);
                        -- Update CRC with high nibble
                        fcs <= crc32_step(fcs, current_byte(7 downto 4));
                        tx_state <= DATA_LOW;
                        tx_ready_int <= '1';

                    when FCS_NIBBLE_ST =>
                        eth_tx_en <= '1';
                        -- Send FCS nibbles in reverse bit order
                        -- Extract nibble based on count (0..7)
                        case fcs_nibble_count is
                            when 0 => fcs_nibble := fcs(3 downto 0);
                            when 1 => fcs_nibble := fcs(7 downto 4);
                            when 2 => fcs_nibble := fcs(11 downto 8);
                            when 3 => fcs_nibble := fcs(15 downto 12);
                            when 4 => fcs_nibble := fcs(19 downto 16);
                            when 5 => fcs_nibble := fcs(23 downto 20);
                            when 6 => fcs_nibble := fcs(27 downto 24);
                            when 7 => fcs_nibble := fcs(31 downto 28);
                            when others => fcs_nibble := "0000";
                        end case;

                        -- Reverse bits in nibble for transmission
                        eth_txd(0) <= fcs_nibble(3);
                        eth_txd(1) <= fcs_nibble(2);
                        eth_txd(2) <= fcs_nibble(1);
                        eth_txd(3) <= fcs_nibble(0);

                        if fcs_nibble_count = 7 then
                            -- All FCS nibbles sent
                            tx_state <= INTERFRAME_GAP;
                            gap_count <= 0;
                        else
                            fcs_nibble_count <= fcs_nibble_count + 1;
                        end if;

                    when INTERFRAME_GAP =>
                        eth_tx_en <= '0';
                        eth_txd <= "0000";

                        if gap_count >= GAP_NIBBLES - 1 then
                            tx_state <= IDLE;
                            gap_count <= 0;
                        else
                            gap_count <= gap_count + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
