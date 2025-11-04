----------------------------------------------------------------------------------
-- Project 6: UDP Packet Parser - Phase 1A
-- Module: Top Level
-- 
-- Description:
--   Top-level entity connecting all modules:
--   - Clock management (100 MHz system + 125 MHz Ethernet RX)
--   - RGMII receiver (PHY interface)
--   - MAC frame receiver (Ethernet parsing)
--   - Statistics counter (LED display)
--
-- Hardware: Xilinx Arty A7-100T
--   - 100 MHz oscillator - System clock
--   - RTL8211E PHY - Ethernet interface (RGMII)
--   - 4 LEDs - Status display
--   - 4 Buttons - Control inputs
--
-- Test Setup:
--   PC USB Ethernet (192.168.1.1) - Arty (192.168.1.100)
--   Send: ping 192.168.1.100
--   See: LEDs show frame count in binary!
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity udp_parser_top is
    Port (
        -- Clock (100 MHz from oscillator)
        CLK             : in  STD_LOGIC;
        
        -- Reset button (BTN0)
        ck_rst          : in  STD_LOGIC;  -- Active high reset
        
        -- RGMII Interface to PHY (RTL8211E)
        eth_rxd         : in  STD_LOGIC_VECTOR(3 downto 0);  -- Receive data
        eth_rx_clk      : in  STD_LOGIC;                      -- Receive clock (125 MHz)
        eth_rx_ctl      : in  STD_LOGIC;                      -- Receive control
        
        eth_txd         : out STD_LOGIC_VECTOR(3 downto 0);  -- Transmit data (Phase 2)
        eth_tx_clk      : out STD_LOGIC;                      -- Transmit clock (Phase 2)
        eth_tx_ctl      : out STD_LOGIC;                      -- Transmit control (Phase 2)
        
        eth_rst_n       : out STD_LOGIC;                      -- PHY reset (active low)
        
        -- LEDs (4 LEDs on Arty A7)
        led             : out STD_LOGIC_VECTOR(3 downto 0);
        
        -- RGB LEDs (LD4, LD5) - optional for Phase 2
        led0_b          : out STD_LOGIC;
        led0_g          : out STD_LOGIC;
        led0_r          : out STD_LOGIC;
        led1_b          : out STD_LOGIC;
        led1_g          : out STD_LOGIC;
        led1_r          : out STD_LOGIC
    );
end udp_parser_top;

architecture Behavioral of udp_parser_top is
    
    -- Clock Buffering Note:
    -- eth_rx_clk uses BUFR (regional buffer) instead of BUFG because
    -- pin F16 is on the N-side of a differential pair and cannot drive BUFG.
    -- BUFR provides regional clocking within a single clock region, which is
    -- sufficient for the Ethernet receiver logic.
    
    -- Component declarations
    component rgmii_rx is
        Port (
            rx_clk          : in  STD_LOGIC;
            reset           : in  STD_LOGIC;
            rgmii_rxd       : in  STD_LOGIC_VECTOR(3 downto 0);
            rgmii_rx_ctl    : in  STD_LOGIC;
            rx_data         : out STD_LOGIC_VECTOR(7 downto 0);
            rx_data_valid   : out STD_LOGIC;
            rx_frame_start  : out STD_LOGIC;
            rx_frame_end    : out STD_LOGIC;
            rx_error        : out STD_LOGIC
        );
    end component;
    
    component mac_rx is
        Port (
            clk             : in  STD_LOGIC;
            reset           : in  STD_LOGIC;
            rx_data         : in  STD_LOGIC_VECTOR(7 downto 0);
            rx_data_valid   : in  STD_LOGIC;
            rx_frame_start  : in  STD_LOGIC;
            rx_frame_end    : in  STD_LOGIC;
            frame_valid     : out STD_LOGIC;
            dest_mac        : out STD_LOGIC_VECTOR(47 downto 0);
            src_mac         : out STD_LOGIC_VECTOR(47 downto 0);
            ethertype       : out STD_LOGIC_VECTOR(15 downto 0);
            payload_data    : out STD_LOGIC_VECTOR(7 downto 0);
            payload_valid   : out STD_LOGIC;
            payload_start   : out STD_LOGIC;
            payload_end     : out STD_LOGIC;
            frame_count     : out STD_LOGIC_VECTOR(31 downto 0);
            frame_error     : out STD_LOGIC
        );
    end component;
    
    component stats_counter is
        Port (
            clk             : in  STD_LOGIC;
            reset           : in  STD_LOGIC;
            frame_received  : in  STD_LOGIC;
            ipv4_received   : in  STD_LOGIC;
            udp_received    : in  STD_LOGIC;
            error_detected  : in  STD_LOGIC;
            total_frames    : out STD_LOGIC_VECTOR(31 downto 0);
            ipv4_packets    : out STD_LOGIC_VECTOR(31 downto 0);
            udp_packets     : out STD_LOGIC_VECTOR(31 downto 0);
            error_count     : out STD_LOGIC_VECTOR(31 downto 0);
            led_display     : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;
    
    -- Clock signals
    signal clk_100mhz       : STD_LOGIC;  -- System clock (from input)
    signal eth_rx_clk_buf   : STD_LOGIC;  -- Buffered Ethernet RX clock
    
    -- Reset signals
    signal reset            : STD_LOGIC;
    signal reset_sync       : STD_LOGIC;
    signal reset_counter    : unsigned(23 downto 0) := (others => '0');  -- Extended for PHY
    
    -- RGMII to MAC signals
    signal rgmii_rx_data    : STD_LOGIC_VECTOR(7 downto 0);
    signal rgmii_rx_valid   : STD_LOGIC;
    signal rgmii_frame_start: STD_LOGIC;
    signal rgmii_frame_end  : STD_LOGIC;
    signal rgmii_error      : STD_LOGIC;
    
    -- MAC outputs
    signal mac_frame_valid  : STD_LOGIC;
    signal mac_dest_mac     : STD_LOGIC_VECTOR(47 downto 0);
    signal mac_src_mac      : STD_LOGIC_VECTOR(47 downto 0);
    signal mac_ethertype    : STD_LOGIC_VECTOR(15 downto 0);
    signal mac_payload_data : STD_LOGIC_VECTOR(7 downto 0);
    signal mac_payload_valid: STD_LOGIC;
    signal mac_frame_count  : STD_LOGIC_VECTOR(31 downto 0);
    signal mac_frame_error  : STD_LOGIC;
    
    -- Statistics
    signal stats_total_frames : STD_LOGIC_VECTOR(31 downto 0);
    signal stats_led_display  : STD_LOGIC_VECTOR(7 downto 0);
    
    -- Clock domain crossing flag (from 125 MHz to 100 MHz)
    signal frame_valid_cdc   : STD_LOGIC;
    signal frame_valid_sync1 : STD_LOGIC := '0';
    signal frame_valid_sync2 : STD_LOGIC := '0';
    
    -- MMCM signals for TX clock generation
    signal eth_tx_clk_unbuf : STD_LOGIC;
    signal mmcm_locked      : STD_LOGIC;
    signal mmcm_clkfb       : STD_LOGIC;

begin

    ----------------------------------------------------------------------------------
    -- Clock Management
    ----------------------------------------------------------------------------------
    
    -- System clock is already 100 MHz from input
    clk_100mhz <= CLK;
    
    ----------------------------------------------------------------------------------
    -- TX Clock Generation (125 MHz from 100 MHz system clock)
    -- Required for PHY link autonegotiation even in receive-only mode
    ----------------------------------------------------------------------------------

    mmcm_tx_clock : MMCME2_BASE
        generic map (
            BANDWIDTH          => "OPTIMIZED",
            CLKFBOUT_MULT_F    => 10.0,      -- 100 MHz * 10 = 1000 MHz (VCO)
            CLKOUT0_DIVIDE_F   => 8.0,       -- 1000 MHz / 8 = 125 MHz
            CLKIN1_PERIOD      => 10.0,      -- 100 MHz input (10ns period)
            DIVCLK_DIVIDE      => 1,
            STARTUP_WAIT       => FALSE
        )
        port map (
            CLKIN1   => CLK,                 -- 100 MHz system clock input
            CLKFBOUT => mmcm_clkfb,          -- Feedback output
            CLKFBIN  => mmcm_clkfb,          -- Feedback input
            CLKOUT0  => eth_tx_clk_unbuf,    -- 125 MHz unbuffered output
            LOCKED   => mmcm_locked,         -- PLL lock indicator
            PWRDWN   => '0',                 -- Never power down
            RST      => '0'                  -- Never reset (KEY FIX!)
        );

    -- Buffer the TX clock
    eth_tx_clk_bufg : BUFG
        port map (
            I => eth_tx_clk_unbuf,
            O => eth_tx_clk                  -- Connect to PHY
        );
        
    
    -- Ethernet RX clock (125 MHz from PHY) uses BUFR (regional buffer)
    -- Pin F16 is N-side of differential pair, cannot drive BUFG
    -- BUFR is appropriate for regional clocking (single clock region)
    eth_rx_clk_bufr : BUFR
        generic map (
            BUFR_DIVIDE => "BYPASS"
        )
        port map (
            I   => eth_rx_clk,
            O   => eth_rx_clk_buf,
            CE  => '1',
            CLR => '0'
        );
    
    ----------------------------------------------------------------------------------
    -- Reset Logic
    ----------------------------------------------------------------------------------
    
    -- Synchronize and extend reset
    -- PHY (RTL8211E) requires minimum 10ms reset pulse
    -- Count to 2,000,000 @ 100MHz = 20ms (safe margin)
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if ck_rst = '1' then
                reset_counter <= (others => '0');
                reset_sync    <= '1';
            elsif reset_counter < 2_000_000 then  -- 20ms @ 100MHz
                reset_counter <= reset_counter + 1;
                reset_sync    <= '1';
            else
                reset_sync    <= '0';
            end if;
        end if;
    end process;
    
    reset <= reset_sync;
    
    -- PHY reset (keep PHY out of reset)
    eth_rst_n <= not reset;
    
    ----------------------------------------------------------------------------------
    -- Module Instantiations
    ----------------------------------------------------------------------------------
    
    -- RGMII Receiver
    rgmii_receiver : rgmii_rx
        port map (
            rx_clk         => eth_rx_clk_buf,
            reset          => reset,
            rgmii_rxd      => eth_rxd,
            rgmii_rx_ctl   => eth_rx_ctl,
            rx_data        => rgmii_rx_data,
            rx_data_valid  => rgmii_rx_valid,
            rx_frame_start => rgmii_frame_start,
            rx_frame_end   => rgmii_frame_end,
            rx_error       => rgmii_error
        );
    
    -- MAC Frame Receiver
    mac_receiver : mac_rx
        port map (
            clk            => eth_rx_clk_buf,
            reset          => reset,
            rx_data        => rgmii_rx_data,
            rx_data_valid  => rgmii_rx_valid,
            rx_frame_start => rgmii_frame_start,
            rx_frame_end   => rgmii_frame_end,
            frame_valid    => mac_frame_valid,
            dest_mac       => mac_dest_mac,
            src_mac        => mac_src_mac,
            ethertype      => mac_ethertype,
            payload_data   => mac_payload_data,
            payload_valid  => mac_payload_valid,
            payload_start  => open,
            payload_end    => open,
            frame_count    => mac_frame_count,
            frame_error    => mac_frame_error
        );
    
    ----------------------------------------------------------------------------------
    -- Clock Domain Crossing (125 MHz -> 100 MHz)
    --
    -- Use 2-stage synchronizer to safely cross clock domains
    -- Same technique as used in Project 2 (Button Debouncer)
    ----------------------------------------------------------------------------------
    
    frame_valid_cdc <= mac_frame_valid;
    
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset = '1' then
                frame_valid_sync1 <= '0';
                frame_valid_sync2 <= '0';
            else
                frame_valid_sync1 <= frame_valid_cdc;
                frame_valid_sync2 <= frame_valid_sync1;
            end if;
        end if;
    end process;
    
    -- Statistics Counter (runs on 100 MHz system clock)
    stats : stats_counter
        port map (
            clk            => clk_100mhz,
            reset          => reset,
            frame_received => frame_valid_sync2,
            ipv4_received  => '0',  -- Phase 2
            udp_received   => '0',  -- Phase 2
            error_detected => '0',
            total_frames   => stats_total_frames,
            ipv4_packets   => open,
            udp_packets    => open,
            error_count    => open,
            led_display    => stats_led_display
        );
    
    ----------------------------------------------------------------------------------
    -- LED Display
    ----------------------------------------------------------------------------------
    
    -- Show frame count on 4 LEDs (lower 4 bits)
    -- LED0-2: Frame count
    -- LED3: Reset status (OFF = still in reset, ON = ready)
    led(2 downto 0) <= stats_led_display(2 downto 0);
    led(3) <= not reset_sync;  -- ON when reset released (PHY ready)
    
    -- RGB LEDs: Visual indicators
    -- LD4 (RGB): Green = receiving frames, Red = errors
    led0_r <= rgmii_error;
    led0_g <= mac_frame_valid;
    led0_b <= '1';  -- Off
    
    -- LD5 (RGB): Blue heartbeat (blink at 1 Hz)
    led1_r <= '1';  -- Off
    led1_g <= '1';  -- Off
    led1_b <= stats_total_frames(25);  -- Blink using counter bit
    
    ----------------------------------------------------------------------------------
    -- Transmit Data/Control (Phase 2 - Not implemented yet)
    -- Note: eth_tx_clk is generated by MMCM above (required for link autonegotiation)
    ----------------------------------------------------------------------------------
    
    eth_txd    <= (others => '0');  -- No data transmitted yet
    eth_tx_ctl <= '0';               -- TX disabled

end Behavioral;