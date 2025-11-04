----------------------------------------------------------------------------------
-- MII Ethernet Receiver - Top Level
-- Arty A7-100 with TI DP83848J PHY (MII Interface)
-- 
-- Receives Ethernet frames via MII interface and displays statistics on LEDs
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity mii_eth_top is
    Port (
        -- System Clock (100 MHz)
        CLK        : in  STD_LOGIC;
        
        -- Reset button (active HIGH when pressed per Arty manual)
        reset_btn  : in  STD_LOGIC;
        
        -- MII Interface to PHY
        eth_ref_clk : out STD_LOGIC;                      -- 25 MHz reference to PHY
        eth_rstn    : out STD_LOGIC;                      -- Reset to PHY (active LOW)
        eth_rx_clk  : in  STD_LOGIC;                      -- RX clock from PHY (25 MHz)
        eth_rxd     : in  STD_LOGIC_VECTOR(3 downto 0);  -- RX data from PHY
        eth_rx_dv   : in  STD_LOGIC;                      -- RX data valid from PHY
        eth_rx_er   : in  STD_LOGIC;                      -- RX error from PHY
        eth_tx_clk  : in  STD_LOGIC;                      -- TX clock from PHY (25 MHz)
        eth_txd     : out STD_LOGIC_VECTOR(3 downto 0);  -- TX data to PHY
        eth_tx_en   : out STD_LOGIC;                      -- TX enable to PHY
        eth_col     : in  STD_LOGIC;                      -- Collision detect
        eth_crs     : in  STD_LOGIC;                      -- Carrier sense
        eth_mdc     : out STD_LOGIC;                      -- MDIO clock (optional)
        eth_mdio    : inout STD_LOGIC;                    -- MDIO data (optional)
        
        -- LEDs
        led         : out STD_LOGIC_VECTOR(3 downto 0);  -- Frame counter
        led0_g      : out STD_LOGIC;                      -- Activity indicator (green)
        led1_b      : out STD_LOGIC;                      -- PHY ready (blue)
        led2_r      : out STD_LOGIC                       -- Error indicator (red)
    );
end mii_eth_top;

architecture Behavioral of mii_eth_top is

    -- Component declarations
    component mii_rx is
        Port (
            mii_rx_clk  : in  STD_LOGIC;
            mii_rxd     : in  STD_LOGIC_VECTOR(3 downto 0);
            mii_rx_dv   : in  STD_LOGIC;
            mii_rx_er   : in  STD_LOGIC;
            rx_data     : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid    : out STD_LOGIC;
            rx_error    : out STD_LOGIC;
            frame_start : out STD_LOGIC;
            frame_end   : out STD_LOGIC
        );
    end component;
    
    component mac_parser is
        Generic (
            MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0)
        );
        Port (
            clk         : in  STD_LOGIC;
            reset       : in  STD_LOGIC;
            rx_data     : in  STD_LOGIC_VECTOR(7 downto 0);
            rx_valid    : in  STD_LOGIC;
            frame_start : in  STD_LOGIC;
            frame_end   : in  STD_LOGIC;
            frame_valid : out STD_LOGIC;
            dest_mac    : out STD_LOGIC_VECTOR(47 downto 0);
            src_mac     : out STD_LOGIC_VECTOR(47 downto 0);
            ethertype   : out STD_LOGIC_VECTOR(15 downto 0);
            frame_count : out STD_LOGIC_VECTOR(31 downto 0)
        );
    end component;
    
    component stats_counter is
        Port (
            clk          : in  STD_LOGIC;
            reset        : in  STD_LOGIC;
            frame_valid  : in  STD_LOGIC;
            led          : out STD_LOGIC_VECTOR(3 downto 0);
            led_activity : out STD_LOGIC
        );
    end component;
    
    -- Clock generation signals
    signal clk_25mhz_unbuf : STD_LOGIC;
    signal clk_25mhz       : STD_LOGIC;
    signal pll_locked      : STD_LOGIC;
    signal pll_clkfb       : STD_LOGIC;
    
    -- PHY reset generation
    signal reset_counter   : unsigned(23 downto 0) := (others => '0');
    signal phy_reset_n     : STD_LOGIC := '0';
    signal phy_ready       : STD_LOGIC := '0';
    
    -- Interconnect signals
    signal rx_data         : STD_LOGIC_VECTOR(7 downto 0);
    signal rx_valid        : STD_LOGIC;
    signal rx_error        : STD_LOGIC;
    signal frame_start     : STD_LOGIC;
    signal frame_end       : STD_LOGIC;
    signal frame_valid     : STD_LOGIC;
    signal frame_valid_sync1 : STD_LOGIC := '0';
    signal frame_valid_sync2 : STD_LOGIC := '0';
    
    -- MAC address
    constant MY_MAC_ADDR   : STD_LOGIC_VECTOR(47 downto 0) := x"000A3502AF9A";
    
begin

    ----------------------------------------------------------------------------------
    -- Clock Generation: 100 MHz -> 25 MHz Reference Clock for PHY
    -- Using PLLE2_BASE (simpler than MMCM for this application)
    ----------------------------------------------------------------------------------
    
    ref_clock_gen : PLLE2_BASE
        generic map (
            BANDWIDTH        => "OPTIMIZED",
            CLKFBOUT_MULT    => 8,           -- 100 MHz × 8 = 800 MHz (VCO)
            CLKOUT0_DIVIDE   => 32,          -- 800 MHz ÷ 32 = 25 MHz
            CLKIN1_PERIOD    => 10.0,        -- 100 MHz input (10 ns period)
            DIVCLK_DIVIDE    => 1,
            STARTUP_WAIT     => "FALSE"
        )
        port map (
            CLKIN1   => CLK,
            CLKOUT0  => clk_25mhz_unbuf,
            LOCKED   => pll_locked,
            PWRDWN   => '0',
            RST      => '0',
            CLKFBOUT => pll_clkfb,
            CLKFBIN  => pll_clkfb
        );
    
    -- Buffer 25 MHz clock
    ref_clk_bufg : BUFG
        port map (
            I => clk_25mhz_unbuf,
            O => clk_25mhz
        );
    
    -- Drive reference clock to PHY
    eth_ref_clk <= clk_25mhz;
    
    ----------------------------------------------------------------------------------
    -- PHY Reset Generation
    -- Minimum 10ms reset pulse (per manual), we use 20ms to be safe
    -- Reset is active LOW
    ----------------------------------------------------------------------------------
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            if reset_counter < 2_000_000 then  -- 20ms at 100 MHz
                reset_counter <= reset_counter + 1;
                phy_reset_n   <= '0';  -- Hold PHY in reset
                phy_ready     <= '0';
            else
                phy_reset_n   <= '1';  -- Release reset
                phy_ready     <= '1';  -- PHY is ready
            end if;
        end if;
    end process;
    
    eth_rstn <= phy_reset_n;
    
    ----------------------------------------------------------------------------------
    -- Transmit Interface (Not implemented - receive only)
    ----------------------------------------------------------------------------------
    
    eth_txd   <= (others => '0');
    eth_tx_en <= '0';
    eth_mdc   <= '0';
    eth_mdio  <= 'Z';  -- High-Z
    
    ----------------------------------------------------------------------------------
    -- MII Receiver
    ----------------------------------------------------------------------------------
    
    mii_receiver : mii_rx
        port map (
            mii_rx_clk  => eth_rx_clk,  -- 25 MHz from PHY
            mii_rxd     => eth_rxd,
            mii_rx_dv   => eth_rx_dv,
            mii_rx_er   => eth_rx_er,
            rx_data     => rx_data,
            rx_valid    => rx_valid,
            rx_error    => rx_error,
            frame_start => frame_start,
            frame_end   => frame_end
        );
    
    ----------------------------------------------------------------------------------
    -- MAC Frame Parser
    -- Runs on eth_rx_clk domain (25 MHz from PHY)
    ----------------------------------------------------------------------------------
    
    mac_frame_parser : mac_parser
        generic map (
            MAC_ADDR => MY_MAC_ADDR
        )
        port map (
            clk         => eth_rx_clk,  -- 25 MHz from PHY
            reset       => reset_btn,
            rx_data     => rx_data,
            rx_valid    => rx_valid,
            frame_start => frame_start,
            frame_end   => frame_end,
            frame_valid => frame_valid,
            dest_mac    => open,
            src_mac     => open,
            ethertype   => open,
            frame_count => open
        );
    
    ----------------------------------------------------------------------------------
    -- Clock Domain Crossing: 25 MHz -> 100 MHz
    -- 2-stage synchronizer for frame_valid signal
    ----------------------------------------------------------------------------------
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            frame_valid_sync1 <= frame_valid;
            frame_valid_sync2 <= frame_valid_sync1;
        end if;
    end process;
    
    ----------------------------------------------------------------------------------
    -- Statistics Counter
    -- Runs on system clock domain (100 MHz)
    ----------------------------------------------------------------------------------
    
    frame_stats : stats_counter
        port map (
            clk          => CLK,
            reset        => reset_btn,
            frame_valid  => frame_valid_sync2,
            led          => led,
            led_activity => led0_g
        );
    
    ----------------------------------------------------------------------------------
    -- Status LEDs
    ----------------------------------------------------------------------------------
    
    led1_b <= phy_ready;     -- Blue: PHY ready after reset
    led2_r <= rx_error;      -- Red: Error detected

end Behavioral;