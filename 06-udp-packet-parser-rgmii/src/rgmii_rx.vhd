----------------------------------------------------------------------------------
-- Project 6: UDP Packet Parser - Phase 1A
-- Module: RGMII Receiver
-- 
-- Description:
--   Receives data from Ethernet PHY (RTL8211E) via RGMII interface
--   - Captures 4-bit nibbles at 125 MHz (DDR - both clock edges)
--   - Assembles nibbles into 8-bit bytes
--   - Detects frame start/end using RX_CTL signal
--   - Provides byte stream to MAC layer
--
-- RGMII Timing:
--   - 125 MHz clock from PHY (Gigabit Ethernet)
--   - 4 bits per clock edge (DDR = Double Data Rate)
--   - 8 bits per full clock cycle
--   - 1000 Mbps throughput
--
-- Trading Relevance:
--   This is the hardware entry point for market data packets!
--   Every nanosecond here matters for tick-to-trade latency.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

entity rgmii_rx is
    Port ( 
        -- Clock (fomr PHY via BUFG)
        rx_clk          : in  STD_LOGIC;          -- 125 MHz clock from PHY
        reset           : in  STD_LOGIC;          -- Active low reset

        -- RMGII Interface (from RTL8211E PHY)
        rgmii_rxd        : in  STD_LOGIC_VECTOR(3 downto 0); -- RGMII RX data (4 bits)
        rgmii_rx_ctl     : in  STD_LOGIC;          -- RGMII RX control signal, Data Valid / Error

        -- Output Byte Stream to MAC
        rx_data          : out STD_LOGIC_VECTOR(7 downto 0); -- Assembled RX byte
        rx_data_valid    : out STD_LOGIC;          -- RX byte valid signal
        rx_frame_start   : out STD_LOGIC;          -- Start of frame indicator
        rx_frame_end     : out STD_LOGIC;           -- End of frame indicator
        rx_error         : out STD_LOGIC           -- RX error indicator
    );
end rgmii_rx;

architecture  Behavioral of rgmii_rx  is

    -- RMGII uses DDR (both clock edges), but it will be simplified for SDR for Phase 1A.
    -- This handles 100Mbps initially. Phase 2 will add DDR for full Gigabit support.
    -- Internal signals
    signal rxd_reg       : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal rx_ctl_reg    : STD_LOGIC := '0';
    signal rx_ctl_prev      : STD_LOGIC := '0';

    -- Nibble assembly(2 nibbles = 1 byte)
    signal nibble_count  : STD_LOGIC := '0'; -- '0' = first(lower) nibble, '1' = second(upper) nibble
    signal byte_lower    : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal byte_upper    : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal byte_ready    : STD_LOGIC := '0';

    -- Frame state
    signal in_frame      : STD_LOGIC := '0';
    signal frame_start_flag : STD_LOGIC := '0';
    signal frame_end_flag : STD_LOGIC := '0';
begin

    ----------------------------------------------------------------------------------
    -- RGMII Receive Process (Simplified SDR for Phase 1)
    --
    -- RGMII normally uses DDR (Double Data Rate) - data on both clock edges
    -- For Phase 1, it uses SDR (Single Data Rate) - rising edge only
    -- This limits to ~100 Mbps but simplifies the logic for my learning
    --
    -- Phase 2 will add DDR support using IDDR primitives for full Gigabit
    ----------------------------------------------------------------------------------
process(rx_clk)
    begin
        if rising_edge(rx_clk) then
            if reset = '1' then
                -- Reset all registers
                rxd_reg          <= (others => '0');
                rx_ctl_reg       <= '0';
                rx_ctl_prev      <= '0';
                nibble_count     <= '0';
                byte_lower       <= (others => '0');
                byte_upper       <= (others => '0');
                byte_ready       <= '0';
                in_frame         <= '0';
                frame_start_flag <= '0';
                frame_end_flag   <= '0';
                rx_data          <= (others => '0');
                rx_data_valid    <= '0';
                rx_frame_start   <= '0';
                rx_frame_end     <= '0';
                rx_error         <= '0';
                
            else
                -- Sample inputs (register to improve timing)
                rxd_reg     <= rgmii_rxd;
                rx_ctl_prev <= rx_ctl_reg;
                rx_ctl_reg  <= rgmii_rx_ctl;
                
                -- Default: clear one-cycle pulses
                byte_ready       <= '0';
                frame_start_flag <= '0';
                frame_end_flag   <= '0';
                rx_data_valid    <= '0';
                rx_frame_start   <= '0';
                rx_frame_end     <= '0';
                rx_error         <= '0';
                
                -- Detect frame start (RX_CTL rises)
                if rx_ctl_reg = '1' and rx_ctl_prev = '0' then
                    in_frame         <= '1';
                    frame_start_flag <= '1';
                    rx_frame_start   <= '1';
                    nibble_count     <= '0';  -- Start with lower nibble
                end if;
                
                -- Detect frame end (RX_CTL falls)
                if rx_ctl_reg = '0' and rx_ctl_prev = '1' then
                    in_frame       <= '0';
                    frame_end_flag <= '1';
                    rx_frame_end   <= '1';
                    nibble_count   <= '0';  -- Reset for next frame
                end if;
                
                -- Process data when in frame
                if in_frame = '1' and rx_ctl_reg = '1' then
                    -- Nibble assembly: 2 nibbles → 1 byte
                    if nibble_count = '0' then
                        -- First nibble (lower 4 bits)
                        byte_lower   <= rxd_reg;
                        nibble_count <= '1';
                    else
                        -- Second nibble (upper 4 bits)
                        byte_upper   <= rxd_reg;
                        nibble_count <= '0';
                        
                        -- Byte complete! Output it
                        rx_data       <= byte_upper & byte_lower;  -- Concatenate
                        rx_data_valid <= '1';
                        byte_ready    <= '1';
                    end if;
                end if;
                
            end if;
        end if;
    end process;


end  Behavioral;