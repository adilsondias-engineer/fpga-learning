----------------------------------------------------------------------------------
-- MII Transmitter
-- Transmits Ethernet frames via MII interface to DP83848J PHY
-- 
-- MII Specifications:
-- - 4-bit data bus (nibbles)
-- - Single Data Rate (SDR) - rising edge only
-- - 25 MHz clock for 100 Mbps mode
-- - 2.5 MHz clock for 10 Mbps mode
-- 
-- Sends preamble (7 × 0x55) + SFD (0xD5) automatically
-- Sends data byte as 2 nibbles (low nibble first, then high nibble)
-- Each byte takes 2 clock cycles @ 25 MHz
-- Assert eth_tx_en during transmission
-- 
-- Handshaking Protocol:
-- - tx_ready = '1' means ready to accept a byte
-- - When tx_valid = '1' and tx_ready = '1', byte is accepted on next clock
-- - After accepting, tx_ready goes low for 1 cycle, then high again
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mii_tx is
    port (
        mii_tx_clk   : in  std_logic;  -- MII TX clock from PHY
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
end mii_tx;

architecture Behavioral of mii_tx is

    type tx_state_type is (IDLE, PREAMBLE, SFD, DATA_LOW, DATA_HIGH);
    signal tx_state : tx_state_type := IDLE;
    
    signal preamble_count : integer range 0 to 7 := 0;  -- 7 bytes
    signal nibble_phase : std_logic := '0';  -- 0 = low nibble, 1 = high nibble
    signal current_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal byte_accepted : std_logic := '0';  -- Flag when byte was accepted
    signal tx_ready_int : std_logic := '0';  -- Internal ready signal
    
begin
    -- Assign internal signal to output
    tx_ready <= tx_ready_int;

    process(mii_tx_clk)
    begin
        -- Use FALLING edge to match reference implementation
        -- PHY samples on rising edge, so we drive on falling edge for setup/hold
        if falling_edge(mii_tx_clk) then
            if reset = '1' then
                tx_state <= IDLE;
                eth_tx_en <= '0';
                eth_txd <= (others => '0');
                tx_ready_int <= '0';
                preamble_count <= 0;
                nibble_phase <= '0';
                byte_accepted <= '0';
                
            else
                case tx_state is
                    when IDLE =>
                        eth_tx_en <= '0';
                        eth_txd <= (others => '0');
                        tx_ready_int <= '1';  -- Ready for packet
                        preamble_count <= 0;
                        nibble_phase <= '0';
                        byte_accepted <= '0';
                        
                        if tx_start = '1' then
                            tx_state <= PREAMBLE;
                            tx_ready_int <= '0';  -- Not ready during preamble
                        end if;
                        
                    when PREAMBLE =>
                        eth_tx_en <= '1';
                        tx_ready_int <= '0';  -- Not ready during preamble
                        
                        if nibble_phase = '0' then
                            -- Send low nibble of 0x55
                            eth_txd <= "0101";  -- 0x5
                            nibble_phase <= '1';
                        else
                            -- Send high nibble of 0x55
                            eth_txd <= "0101";  -- 0x5
                            nibble_phase <= '0';
                            preamble_count <= preamble_count + 1;
                            
                            if preamble_count = 6 then  -- Sent 7 bytes
                                tx_state <= SFD;
                                preamble_count <= 0;
                            end if;
                        end if;
                        
                    when SFD =>
                        eth_tx_en <= '1';
                        tx_ready_int <= '0';  -- Not ready during SFD
                        
                        if nibble_phase = '0' then
                            -- Send low nibble of 0xD5
                            eth_txd <= "0101";  -- 0x5
                            nibble_phase <= '1';
                        else
                            -- Send high nibble of 0xD5
                            eth_txd <= "1101";  -- 0xD
                            nibble_phase <= '0';
                            tx_state <= DATA_LOW;
                            tx_ready_int <= '1';  -- Ready for first data byte
                        end if;
                        
                    when DATA_LOW =>
                        eth_tx_en <= '1';
                        
                        -- Check for end of packet
                        if tx_end = '1' and tx_valid = '0' then
                            -- End of packet and no more data
                            tx_state <= IDLE;
                            eth_tx_en <= '0';
                            tx_ready_int <= '0';
                            byte_accepted <= '0';
                            
                        elsif tx_valid = '1' and tx_ready_int = '1' then
                            -- Accept byte: capture and send low nibble
                            current_byte <= tx_data;
                            eth_txd <= tx_data(3 downto 0);  -- Low nibble
                            tx_state <= DATA_HIGH;
                            tx_ready_int <= '0';  -- Not ready while sending
                            byte_accepted <= '1';
                        else
                            -- Waiting for valid data
                            tx_ready_int <= '1';  -- Ready to accept
                            byte_accepted <= '0';
                        end if;
                        
                    when DATA_HIGH =>
                        eth_tx_en <= '1';
                        -- Send high nibble
                        eth_txd <= current_byte(7 downto 4);
                        tx_state <= DATA_LOW;
                        tx_ready_int <= '1';  -- Ready for next byte
                        byte_accepted <= '0';
                        
                end case;
            end if;
        end if;
    end process;

end Behavioral;
