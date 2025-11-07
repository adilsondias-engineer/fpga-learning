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
        reset_n    : in  STD_LOGIC;  -- Active-low CPU reset button

        -- Buttons (active low on Arty A7)
        debug_btn  : in STD_LOGIC;   -- BTN3 for debug mode
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
       -- led0_g      : out STD_LOGIC;                      -- Activity indicator (green)
       -- led1_b      : out STD_LOGIC;                      -- PHY ready (blue)
       -- led2_r      : out STD_LOGIC                       -- Error indicator (red)
       led_rgb     : out std_logic_vector(8 downto 0);  -- RGB LEDs for status

        -- UART
        -- uart_txd_in : in STD_LOGIC;              -- RX: PC -> FPGA (confusing naming!)
        uart_rxd_out : out STD_LOGIC             -- TX: FPGA -> PC
    );
end mii_eth_top;

architecture structural of mii_eth_top is

    -- Component declarations

    ------------------------------------------------------------------------
    -- UART Transmitter
    ------------------------------------------------------------------------
    component uart_tx is
        Generic (
            CLK_FREQ : integer := 100_000_000;
            BAUD_RATE : integer := 115_200
        );
        Port (
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            tx_data : in STD_LOGIC_VECTOR(7 downto 0);
            tx_start : in STD_LOGIC;
            tx_busy : out STD_LOGIC;
            tx_serial : out STD_LOGIC
        );
    end component;

    --     -- Add this component declaration
    -- component uart_formatter is
    --     Generic (
    --         CLK_FREQ : integer := 100_000_000
    --     );
    --     Port (
    --         clk   : in  std_logic;
    --         reset : in  std_logic;
            
    --         -- Packet triggers
    --         frame_valid     : in  std_logic;
    --         ip_valid        : in  std_logic;
    --         udp_valid       : in  std_logic;
            
    --         -- IP packet info
    --         ip_protocol     : in  std_logic_vector(7 downto 0);
    --         ip_src          : in  std_logic_vector(31 downto 0);
    --         ip_dst          : in  std_logic_vector(31 downto 0);
    --         ip_total_length : in  std_logic_vector(15 downto 0);
    --         ip_checksum_ok  : in  std_logic;

    --         -- IP error signals (for debugging)
    --         ip_version_err  : in  std_logic;
    --         ip_ihl_err      : in  std_logic;
    --         ip_checksum_err : in  std_logic;
    --         ip_version_ihl_byte : in  std_logic_vector(7 downto 0);

    --         -- UDP packet info
    --         udp_src_port    : in  std_logic_vector(15 downto 0);
    --         udp_dst_port    : in  std_logic_vector(15 downto 0);
    --         udp_length      : in  std_logic_vector(15 downto 0);
    --         udp_checksum_ok : in  std_logic;
    --         udp_length_err  : in  std_logic;
            
    --         -- UART byte transmitter interface
    --         tx_data  : out std_logic_vector(7 downto 0);
    --         tx_start : out std_logic;
    --         tx_busy  : in  std_logic
    --     );
    -- end component;
    
    ------------------------------------------------------------------------
    -- Button Debouncer
    ------------------------------------------------------------------------
    -- component button_debouncer is
    --     generic (
    --         CLK_FREQ    : integer := 100_000_000;
    --         DEBOUNCE_MS : integer := 20
    --     );
    --     port (
    --         clk       : in  STD_LOGIC;
    --         btn_in    : in  STD_LOGIC;
    --         btn_out   : out STD_LOGIC
    --     );
    -- end component;

    ------------------------------------------------------------------------
    -- Edge Detector
    ------------------------------------------------------------------------
    -- component edge_detector is
    --     port (
    --         clk      : in  STD_LOGIC;
    --         sig_in   : in  STD_LOGIC;
    --         rising   : out STD_LOGIC;
    --         falling  : out STD_LOGIC
    --     );
    -- end component;

    ------------------------------------------------------------------------
    -- MDIO Controller
    ------------------------------------------------------------------------
    -- component mdio_controller is
    --     generic (
    --         CLK_FREQ_HZ    : integer := 100_000_000;
    --         MDC_FREQ_HZ    : integer := 2_500_000
    --     );
    --     port (
    --         clk            : in    std_logic;
    --         reset          : in    std_logic;
    --         start          : in    std_logic;
    --         rw             : in    std_logic;
    --         phy_addr       : in    std_logic_vector(4 downto 0);
    --         reg_addr       : in    std_logic_vector(4 downto 0);
    --         write_data     : in    std_logic_vector(15 downto 0);
    --         busy           : out   std_logic;
    --         done           : out   std_logic;
    --         read_data      : out   std_logic_vector(15 downto 0);
    --         mdc            : out   std_logic;
    --         mdio_i         : in    std_logic;
    --         mdio_o         : out   std_logic;
    --         mdio_t         : out   std_logic
    --     );
    -- end component;


    ------------------------------------------------------------------------
    -- MDIO PHY Monitor (Sequencer) 
    ------------------------------------------------------------------------
    -- component mdio_phy_monitor is
    --     generic (
    --         CLK_FREQ_HZ : integer := 100_000_000;
    --         PHY_ADDR    : std_logic_vector(4 downto 0) := "00001"
    --     );
    --     port (
    --         clk               : in  std_logic;
    --         reset             : in  std_logic;
            
    --         -- MDIO controller interface
    --         mdio_start        : out std_logic;
    --         mdio_busy         : in  std_logic;
    --         mdio_done         : in  std_logic;
    --         mdio_rw           : out std_logic;  -- Always '0' (read only)
    --         mdio_phy_addr     : out std_logic_vector(4 downto 0);
    --         mdio_reg_addr     : out std_logic_vector(4 downto 0);
    --         mdio_write_data   : out std_logic_vector(15 downto 0);  -- Unused
    --         mdio_read_data    : in  std_logic_vector(15 downto 0);
            
    --         -- Display interface
    --         reg_display_sel   : out std_logic_vector(1 downto 0);  -- Which register to display
    --         reg_values        : out std_logic_vector(63 downto 0); -- 4 x 16-bit registers
    --         sequence_active   : out std_logic;                     -- Sequence in progress

    --         -- Debug output port
    --         debug_state : out std_logic_vector(3 downto 0)  -- Current state of the sequencer for debugging
    --         -- Status outputs
    --         -- link_up          : out std_logic;
    --         -- phy_status_reg   : out std_logic_vector(15 downto 0)
    --     );
    -- end component;

    --  component mii_rx is
    --     Port (
    --         mii_rx_clk  : in  STD_LOGIC;
    --         mii_rxd     : in  STD_LOGIC_VECTOR(3 downto 0);
    --         mii_rx_dv   : in  STD_LOGIC;
    --         mii_rx_er   : in  STD_LOGIC;
    --         rx_data     : out STD_LOGIC_VECTOR(7 downto 0);
    --         rx_valid    : out STD_LOGIC;
    --         rx_error    : out STD_LOGIC;
    --         frame_start : out STD_LOGIC;
    --         frame_end   : out STD_LOGIC
    --     );
    -- end component;
    
    -- -- MAC Parser
    -- component mac_parser is
    --     Generic (
    --         MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0)
    --     );
    --     Port (
    --         clk         : in  STD_LOGIC;
    --         reset       : in  STD_LOGIC;
    --         rx_data     : in  STD_LOGIC_VECTOR(7 downto 0);
    --         rx_valid    : in  STD_LOGIC;
    --         frame_start : in  STD_LOGIC;
    --         frame_end   : in  STD_LOGIC;
    --         frame_valid : out STD_LOGIC;
    --         dest_mac    : out STD_LOGIC_VECTOR(47 downto 0);
    --         src_mac     : out STD_LOGIC_VECTOR(47 downto 0);
    --         ethertype   : out STD_LOGIC_VECTOR(15 downto 0);
    --         frame_count : out STD_LOGIC_VECTOR(31 downto 0);
    --         data_out     : out STD_LOGIC_VECTOR(7 downto 0);  -- NEW
    --         byte_counter : out unsigned(10 downto 0)          -- NEW
    --     );
    -- end component;
    

    
    -- -- IP parser
    -- component ip_parser is
    --     Port (
    --         clk             : in  std_logic;
    --         reset           : in  std_logic;
    --         frame_valid     : in  std_logic;
    --         data_in         : in  std_logic_vector(7 downto 0);
    --         byte_index      : in  integer range 0 to 1023;
    --         ip_valid        : out std_logic;
    --         ip_src          : out std_logic_vector(31 downto 0);
    --         ip_dst          : out std_logic_vector(31 downto 0);
    --         ip_protocol     : out std_logic_vector(7 downto 0);
    --         ip_total_length : out std_logic_vector(15 downto 0);
    --         ip_checksum_ok  : out std_logic;
    --         ip_version_err  : out std_logic;
    --         ip_ihl_err      : out std_logic;
    --         ip_checksum_err : out std_logic
    --     );
    -- end component;

    -- component udp_parser is
    --     Port (
    --         clk             : in  std_logic;
    --         reset           : in  std_logic;
            
    --         -- Input from IP parser
    --         ip_valid        : in  std_logic;              -- IP header validated
    --         ip_protocol     : in  std_logic_vector(7 downto 0);  -- Must be 0x11 for UDP
    --         ip_total_length : in  std_logic_vector(15 downto 0); -- Total IP packet length
    --         data_in         : in  std_logic_vector(7 downto 0);  -- Byte stream
    --         byte_index      : in  integer range 0 to 1023;       -- Current byte position
    --         frame_valid     : in  std_logic;                     -- In-frame gate (RX domain)
            
    --         -- Outputs
    --         udp_valid       : out std_logic;              -- Pulsed when valid UDP parsed
    --         udp_src_port    : out std_logic_vector(15 downto 0);
    --         udp_dst_port    : out std_logic_vector(15 downto 0);
    --         udp_length      : out std_logic_vector(15 downto 0);
    --         udp_checksum_ok : out std_logic;              -- Checksum validation result
    --         udp_length_err  : out std_logic;              -- Length mismatch flag
            
    --         -- Payload access
    --         payload_valid   : out std_logic;              -- High during payload bytes
    --         payload_data    : out std_logic_vector(7 downto 0);
    --         payload_length  : out std_logic_vector(15 downto 0)  -- Payload size
    --     );
    -- end component;

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
    constant MY_MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0) := x"000A3502AF9A";
    constant PHY_ADDR    : std_logic_vector(4 downto 0) := "00001";  -- DP83848J address
    constant CLK_FREQ_HZ : integer := 100_000_000;  -- 100 MHz system clock

    -- Reset signals
    signal mdio_rst    : std_logic;
    signal reset_sync  : std_logic_vector(2 downto 0) := (others => '1');

    -- MDIO controller interface signals (connect between sequencer and controller)
    signal mdio_start      : std_logic := '0';
    signal mdio_busy       : std_logic;
    signal mdio_done       : std_logic;
    signal mdio_rw         : std_logic := '0';
    signal mdio_phy_addr   : std_logic_vector(4 downto 0) := PHY_ADDR;
    signal mdio_reg_addr   : std_logic_vector(4 downto 0) := (others => '0');
    signal mdio_write_data : std_logic_vector(15 downto 0) := (others => '0');
    signal mdio_read_data  : std_logic_vector(15 downto 0);

    -- MDIO physical interface signals (tristate buffer)
    signal mdio_i : std_logic;
    signal mdio_o : std_logic;
    signal mdio_t : std_logic;

    -- Sequencer output signals
    -- signal link_up          : std_logic;
    -- signal phy_status_reg   : std_logic_vector(15 downto 0);

    -- Test sequencer signals
    signal reg_display_sel : std_logic_vector(1 downto 0);
    signal reg_values      : std_logic_vector(63 downto 0);
    signal sequence_active : std_logic;
    
    -- Display signals
    signal current_reg     : std_logic_vector(15 downto 0);

    -- Debug/display control
    signal debug_state_sig : std_logic_vector(3 downto 0);
    signal debug_mode : unsigned(1 downto 0) := "00";  -- '0' = Frame stats, '1' = MDIO debug, '2' = IP protocol

    -- Intermediate signals to avoid multiple drivers
    signal frame_count_leds : std_logic_vector(3 downto 0);
    signal frame_activity   : std_logic;
    signal stats_error      : std_logic;  -- Error output from stats_counter

    -- Button signals
    signal debug_btn_db: STD_LOGIC;
    signal debug_btn_rise : STD_LOGIC;
    signal debug_btn_fall : STD_LOGIC;
    signal reset_btn_db: STD_LOGIC;
    signal reset_btn_rise : STD_LOGIC;
    signal reset_btn_fall : STD_LOGIC;
    
    -- Reset signal
    signal reset : STD_LOGIC := '0';

    -- UART signals
    signal tx_data : STD_LOGIC_VECTOR(7 downto 0);
    signal tx_start : STD_LOGIC := '0';
    signal tx_busy : STD_LOGIC := '0';

    signal send_second_hex : std_logic := '0';  -- Flag: need to send second hex character
    signal tx_started : std_logic := '0';  -- Flag: transmission has started (tx_busy seen as '1')

        -- Helper function to convert 4-bit nibble to ASCII hex character
    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case nibble is
            when X"0" => return X"30";  -- '0'
            when X"1" => return X"31";  -- '1'
            when X"2" => return X"32";  -- '2'
            when X"3" => return X"33";  -- '3'
            when X"4" => return X"34";  -- '4'
            when X"5" => return X"35";  -- '5'
            when X"6" => return X"36";  -- '6'
            when X"7" => return X"37";  -- '7'
            when X"8" => return X"38";  -- '8'
            when X"9" => return X"39";  -- '9'
            when X"A" => return X"41";  -- 'A'
            when X"B" => return X"42";  -- 'B'
            when X"C" => return X"43";  -- 'C'
            when X"D" => return X"44";  -- 'D'
            when X"E" => return X"45";  -- 'E'
            when X"F" => return X"46";  -- 'F'
            when others => return X"3F";  -- '?'
        end case;
    end function;
    
    -- UART state machine
    type uart_state_type is (
        UART_IDLE,        -- Waiting for data to trasmit
        UART_ECHO_TX,     -- Transmitting echo/response
        UART_IP_INFO      -- IP info
    );
    signal uart_state : uart_state_type := UART_IDLE;
    signal uart_msg_counter: integer range 0 to 5 := 0;
    -- UART formatter signals
    signal uart_fmt_tx_data  : std_logic_vector(7 downto 0);
    signal uart_fmt_tx_start : std_logic;
    signal uart_fmt_tx_busy  : std_logic;

    -- IP Parser input
    signal data_in : std_logic_vector(7 downto 0) := (others => '0');
    signal byte_counter : integer range 0 to 1023 := 0;

    -- IP Parser outputs (25 MHz domain)
    signal ip_valid : std_logic;
    signal ip_src : std_logic_vector(31 downto 0);
    signal ip_dst : std_logic_vector(31 downto 0);
    signal ip_protocol : std_logic_vector(7 downto 0);
    signal ip_total_length : std_logic_vector(15 downto 0);
    signal ip_checksum_ok : std_logic;
    signal ip_version_err : std_logic;
    signal ip_ihl_err : std_logic;
    signal ip_checksum_err : std_logic;
    signal ip_version_ihl_byte : std_logic_vector(7 downto 0);

    -- IP signals synchronized to 100 MHz
    signal ip_valid_sync1, ip_valid_sync2         : std_logic := '0';
    signal ip_protocol_sync1, ip_protocol_sync2   : std_logic_vector(7 downto 0) := (others => '0');
    signal ip_checksum_ok_sync1, ip_checksum_ok_sync2 : std_logic := '0';
    signal ip_version_err_sync1, ip_version_err_sync2 : std_logic := '0';
    signal ip_ihl_err_sync1, ip_ihl_err_sync2 : std_logic := '0';
    signal ip_checksum_err_sync1, ip_checksum_err_sync2 : std_logic := '0';
    signal ip_version_ihl_byte_sync : std_logic_vector(7 downto 0) := (others => '0');
    signal ip_src_sync          : std_logic_vector(31 downto 0) := (others => '0');
    signal ip_dst_sync          : std_logic_vector(31 downto 0) := (others => '0');
    signal ip_total_length_sync : std_logic_vector(15 downto 0) := (others => '0');

    -- Reset synchronizer for 25 MHz domain
    signal mdio_rst_rxclk_sync1, mdio_rst_rxclk_sync2 : std_logic := '1';
    signal mdio_rst_rxclk : std_logic;

    -- MAC parser outputs
    signal mac_data_out    : std_logic_vector(7 downto 0);
    signal mac_dest_match  : std_logic;
    signal mac_byte_counter : unsigned(10 downto 0);

    -- UDP parser outputs (25 MHz domain - eth_rx_clk)
    signal udp_valid       : std_logic;
    signal udp_src_port    : std_logic_vector(15 downto 0);
    signal udp_dst_port    : std_logic_vector(15 downto 0);
    signal udp_length      : std_logic_vector(15 downto 0);
    signal udp_checksum_ok : std_logic;
    signal udp_length_err  : std_logic;
    signal udp_protocol_ok : std_logic;  -- Debug
    signal udp_length_ok   : std_logic;  -- Debug

    -- Debug: capture in_frame when ip_valid pulses
    signal in_frame_at_ip_valid : std_logic := '0';

    -- Synchronized to 100 MHz (clk domain)
    signal udp_valid_sync1, udp_valid_sync2           : std_logic;
    signal udp_src_port_sync                          : std_logic_vector(15 downto 0);
    signal udp_dst_port_sync                          : std_logic_vector(15 downto 0);
    signal udp_length_err_sync1, udp_length_err_sync2 : std_logic;

    -- UDP payload outputs (25 MHz domain - eth_rx_clk)
    signal payload_valid  : std_logic;
    signal payload_data   : std_logic_vector(7 downto 0);
    signal payload_length : std_logic_vector(15 downto 0);
    --in-frame flag
    signal in_frame : std_logic := '0';

begin

    -- =========================================================================
    -- UART Module Instantiation
    -- =========================================================================
    -- Instantiate UART transmitter
    uart_tx_inst : entity work.uart_tx
        port map (
            clk => clk,
            reset => reset,
            tx_data   => uart_fmt_tx_data,    -- FROM uart_formatter
            tx_start  => uart_fmt_tx_start,   -- FROM uart_formatter
            tx_busy   => uart_fmt_tx_busy,    -- TO uart_formatter
            tx_serial => uart_rxd_out      -- Note: confusing Xilinx naming!
        );

    -- UART message formatter
    uart_fmt_inst: entity work.uart_formatter
    generic map (
        CLK_FREQ => 100_000_000
    )
    port map (
        clk   => clk,
        reset => reset,
        
        -- Packet triggers (use synchronized signals)
        frame_valid => frame_valid_sync2,
        ip_valid    => ip_valid_sync2,
        udp_valid   => udp_valid_sync2,
        
        -- IP packet info (use synchronized signals)
        ip_protocol     => ip_protocol_sync2,
        ip_src          => ip_src_sync,
        ip_dst          => ip_dst_sync,
        ip_total_length => ip_total_length_sync,
        ip_checksum_ok  => ip_checksum_ok_sync2,

        -- IP error signals (for debugging)
        ip_version_err  => ip_version_err_sync2,
        ip_ihl_err      => ip_ihl_err_sync2,
        ip_checksum_err => ip_checksum_err_sync2,
        ip_version_ihl_byte => ip_version_ihl_byte_sync,

        -- UDP packet info (use synchronized signals)
        udp_src_port    => udp_src_port_sync,
        udp_dst_port    => udp_dst_port_sync,
        udp_length      => udp_length,       -- Already stable when udp_valid
        udp_checksum_ok => udp_checksum_ok,  -- Already stable when udp_valid
        udp_length_err  => udp_length_err_sync2,
        udp_protocol_ok => udp_protocol_ok,  -- Debug
        udp_length_ok   => udp_length_ok,    -- Debug
        in_frame_at_ip_valid => in_frame_at_ip_valid,  -- Debug

        -- UART TX interface
        tx_data  => uart_fmt_tx_data,
        tx_start => uart_fmt_tx_start,
        tx_busy  => uart_fmt_tx_busy
    );
    -- =========================================================================
    -- Button Debouncing and Edge Detection
    -- =========================================================================

    -- Reset button (active low on Arty A7)
    reset_btn_debouncer: entity work.button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => reset_btn,
            btn_out => reset_btn_db
        );

    reset_btn_edge: entity work.edge_detector
        port map (
            clk => clk,
            sig_in => reset_btn_db,
            rising => reset_btn_rise,
            falling => reset_btn_fall
        );

    -- Debug button (BTN3) debouncing and edge detection
    debug_btn_debouncer: entity work.button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => debug_btn,
            btn_out => debug_btn_db
        );

    debug_btn_edge: entity work.edge_detector
        port map (
            clk => clk,
            sig_in => debug_btn_db,
            rising => debug_btn_rise,
            falling => debug_btn_fall
        );

    -- Debug mode control: Toggle on BTN3 press
    process(clk)
    begin
        if rising_edge(clk) then
           if debug_btn_rise = '1' then
                if debug_mode = "10" then
                    debug_mode <= "00";  -- Wrap around after mode 2
                else
                    debug_mode <= debug_mode + 1;
                end if;
           end if;
        end if;
    end process;
    ------------------------------------------------------------------------
    -- Reset synchronization (active high internally)
    -- MDIO reset generation based on reset button and CPU reset
    ------------------------------------------------------------------------
    process(CLK)
    begin
        if rising_edge(CLK) then
            if reset_btn_rise = '1' then
                reset <= '1';  -- Assert reset for one cycle
            else
                reset <= '0';
            end if;
            reset_sync <= reset_sync(1 downto 0) & (not reset_n);

       end if;

    end process;
    
    mdio_rst <= reset or reset_sync(2);

    ------------------------------------------------------------------------
    -- MDIO Sequencer Instance
    ------------------------------------------------------------------------
    mdio_seq_inst : entity work.mdio_phy_monitor
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            PHY_ADDR    => PHY_ADDR
        )
        port map (
            clk             => CLK,
            reset           => mdio_rst,
            mdio_start      => mdio_start,
            mdio_busy       => mdio_busy,
            mdio_done       => mdio_done,
            mdio_rw         => mdio_rw,
            mdio_phy_addr   => mdio_phy_addr,
            mdio_reg_addr   => mdio_reg_addr,
            mdio_write_data => mdio_write_data,
            mdio_read_data  => mdio_read_data,
            reg_display_sel => reg_display_sel,
            reg_values      => reg_values,
            sequence_active => sequence_active,
            debug_state     => debug_state_sig  -- Connect to internal signal   
            -- link_up         => link_up,
            -- phy_status_reg  => phy_status_reg
        );

    ------------------------------------------------------------------------
    -- MDIO Tristate Buffer
    -- IOBUF: Single-ended Bi-directional Buffer 7 Series
    -- Xilinx HDL Language Template, version 2025.1
    ------------------------------------------------------------------------
    mdio_iobuf : IOBUF
    port map (
        IO => eth_mdio,  -- Buffer inout port (connect to top-level port)
        O  => mdio_i,    -- Buffer output (from pad to FPGA)
        I  => mdio_o,    -- Buffer input (from FPGA to pad)
        T  => mdio_t     -- 3-state enable ('1' = high-Z/input, '0' = drive output)
    );

    -- End of mdio_iobuf instantiation
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
    


    ------------------------------------------------------------------------
    -- MDIO Controller
    ------------------------------------------------------------------------
    mdio_ctrl_inst : entity work.mdio_controller
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            MDC_FREQ_HZ => 2_500_000
        )
        port map (
            clk        => CLK,
            reset      => mdio_rst,
            start      => mdio_start,
            rw         => mdio_rw,
            phy_addr   => mdio_phy_addr,
            reg_addr   => mdio_reg_addr,
            write_data => mdio_write_data,
            busy       => mdio_busy,
            done       => mdio_done,
            read_data  => mdio_read_data,
            mdc        => eth_mdc,
            mdio_i     => mdio_i,
            mdio_o     => mdio_o,
            mdio_t     => mdio_t
        );

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
    
    ----------------------------------------------------------------------------------
    -- Reset Synchronizer for 25 MHz domain (eth_rx_clk)
    ----------------------------------------------------------------------------------
    process(eth_rx_clk)
    begin
        if rising_edge(eth_rx_clk) then
            mdio_rst_rxclk_sync1 <= mdio_rst;
            mdio_rst_rxclk_sync2 <= mdio_rst_rxclk_sync1;
        end if;
    end process;

    mdio_rst_rxclk <= mdio_rst_rxclk_sync2;
    
    -- In-frame flag: asserted between frame_start and frame_end (eth_rx_clk domain)
    process(eth_rx_clk)
    begin
        if rising_edge(eth_rx_clk) then
            if mdio_rst_rxclk = '1' then
                in_frame <= '0';
            else
                if frame_start = '1' then
                    in_frame <= '1';
                elsif frame_end = '1' then
                    in_frame <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Debug: Capture in_frame when ip_valid pulses
    process(eth_rx_clk)
    begin
        if rising_edge(eth_rx_clk) then
            if mdio_rst_rxclk = '1' then
                in_frame_at_ip_valid <= '0';
            else
                if ip_valid = '1' then
                    in_frame_at_ip_valid <= in_frame;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------
    -- MII Receiver
    ----------------------------------------------------------------------------------

    mii_receiver : entity work.mii_rx
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
    
    mac_frame_parser : entity work.mac_parser
        generic map (
            MAC_ADDR => MY_MAC_ADDR
        )
        port map (
            clk         => eth_rx_clk,  -- 25 MHz from PHY
            reset       => mdio_rst_rxclk,  -- Use synchronized reset
            rx_data     => rx_data,
            rx_valid    => rx_valid,
            frame_start => frame_start,
            frame_end   => frame_end,
            frame_valid => frame_valid,
            dest_mac    => open,
            src_mac     => open,
            ethertype   => open,
            frame_count => open,
            data_out     => mac_data_out,      -- NEW
            byte_counter => mac_byte_counter   -- NEW
        );
    
    ----------------------------------------------------------------------------------
    -- Statistics Counter
    -- Runs on IP parser clock domain (25 MHz)
    ----------------------------------------------------------------------------------
    
    stats_inst: entity work.stats_counter
        generic map (
            CLK_FREQ => 100_000_000
        )
        port map (
            clk   => clk,
            reset => reset,
            
            -- MAC frame statistics
            frame_valid => frame_valid_sync2,
            
            -- IP statistics
            ip_valid        => ip_valid_sync2,
            ip_protocol     => ip_protocol_sync2,
            ip_checksum_ok  => ip_checksum_ok_sync2,
            ip_version_err  => ip_version_err_sync2,
            ip_checksum_err => ip_checksum_err_sync2,
            
            -- UDP statistics
            udp_valid      => udp_valid_sync2,
            udp_dst_port   => udp_dst_port_sync,
            udp_length_err => udp_length_err_sync2,
            
            -- Display control
            debug_mode      => debug_btn_rise,
            mdio_reg_values => reg_values,
            mdio_seq_done   => sequence_active,
            
            -- Outputs
            led          => frame_count_leds,
            led_activity => frame_activity,
            led_error    => stats_error
        );


     -- Instantiate IP Parser
    ip_parser_inst: entity work.ip_parser
        port map (
            clk => eth_rx_clk, -- Run in same domain as data
            reset => mdio_rst_rxclk,  -- Use synchronized reset
            -- From MAC parser
            frame_valid => in_frame,
            data_in     => mac_data_out,
            byte_index  => to_integer(mac_byte_counter),

            -- Outputs
            ip_valid        => ip_valid,
            ip_src          => ip_src,
            ip_dst          => ip_dst,
            ip_protocol     => ip_protocol,
            ip_total_length => ip_total_length,
            ip_checksum_ok  => ip_checksum_ok,
            ip_version_err  => ip_version_err,
            ip_ihl_err      => ip_ihl_err,
            ip_checksum_err => ip_checksum_err,
            ip_version_ihl_byte => ip_version_ihl_byte
        );

    -- Instantiate UDP Parser
    udp_parser_inst: entity work.udp_parser
        port map (
            clk => eth_rx_clk, -- Run in same domain as data
            reset => mdio_rst_rxclk,  -- Use synchronized reset
            -- From IP parser
            ip_valid => ip_valid,
            ip_protocol => ip_protocol,
            ip_total_length => ip_total_length,
            data_in => mac_data_out,
            byte_index => to_integer(mac_byte_counter),
            frame_valid => in_frame,
            -- Outputs
            udp_valid => udp_valid,
            udp_src_port => udp_src_port,
            udp_dst_port => udp_dst_port,
            udp_length => udp_length,
            udp_checksum_ok => udp_checksum_ok,
            udp_length_err => udp_length_err,
            payload_valid => payload_valid,
            payload_data => payload_data,
            payload_length => payload_length,
            -- Debug
            udp_protocol_ok => udp_protocol_ok,
            udp_length_ok => udp_length_ok
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


    -- Clock domain crossing: IP parser signals (25 MHz -> 100 MHz)
    -- FIX: Use synchronized ip_valid pulse to gate multi-bit captures
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ip_valid_sync1 <= '0';
                ip_valid_sync2 <= '0';
                ip_protocol_sync1 <= (others => '0');
                ip_protocol_sync2 <= (others => '0');
                ip_checksum_ok_sync1 <= '0';
                ip_checksum_ok_sync2 <= '0';
                ip_version_err_sync1 <= '0';
                ip_version_err_sync2 <= '0';
                ip_ihl_err_sync1 <= '0';
                ip_ihl_err_sync2 <= '0';
                ip_checksum_err_sync1 <= '0';
                ip_checksum_err_sync2 <= '0';
                ip_version_ihl_byte_sync <= (others => '0');
                ip_src_sync <= (others => '0');
                ip_dst_sync <= (others => '0');
                ip_total_length_sync <= (others => '0');
            else
                -- 2FF synchronizer for single-bit signals
                ip_valid_sync1 <= ip_valid;
                ip_valid_sync2 <= ip_valid_sync1;

                ip_checksum_ok_sync1 <= ip_checksum_ok;
                ip_checksum_ok_sync2 <= ip_checksum_ok_sync1;

                ip_version_err_sync1 <= ip_version_err;
                ip_version_err_sync2 <= ip_version_err_sync1;

                ip_ihl_err_sync1 <= ip_ihl_err;
                ip_ihl_err_sync2 <= ip_ihl_err_sync1;

                ip_checksum_err_sync1 <= ip_checksum_err;
                ip_checksum_err_sync2 <= ip_checksum_err_sync1;

                -- Latch multi-bit fields when synchronized valid pulse observed
                -- FIX: Use ip_valid_sync1 (synchronized) instead of ip_valid (async)
                if ip_valid_sync1 = '1' then
                    ip_protocol_sync1        <= ip_protocol;
                    ip_version_ihl_byte_sync <= ip_version_ihl_byte;
                    ip_src_sync              <= ip_src;
                    ip_dst_sync              <= ip_dst;
                    ip_total_length_sync     <= ip_total_length;
                end if;
                ip_protocol_sync2 <= ip_protocol_sync1;
            end if;
        end if;
    end process;
   
       -- CDC: UDP signals (25 MHz -> 100 MHz)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                udp_valid_sync1 <= '0';
                udp_valid_sync2 <= '0';
                udp_length_err_sync1 <= '0';
                udp_length_err_sync2 <= '0';
            else
                -- 2FF synchronizer for single-bit signals
                udp_valid_sync1 <= udp_valid;
                udp_valid_sync2 <= udp_valid_sync1;

                udp_length_err_sync1 <= udp_length_err;
                udp_length_err_sync2 <= udp_length_err_sync1;

                -- Multi-bit signals: sample when synchronized valid pulse observed
                if udp_valid_sync1 = '1' then
                    udp_src_port_sync <= udp_src_port;
                    udp_dst_port_sync <= udp_dst_port;
                end if;
            end if;
        end if;
    end process;
    ------------------------------------------------------------------------
    -- Display Logic
    ------------------------------------------------------------------------
    -- Select which register to display on LEDs
    with reg_display_sel select
        current_reg <= reg_values(15 downto 0)  when "00",  -- Register 0x01
                      reg_values(31 downto 16) when "01",  -- Register 0x10
                      reg_values(47 downto 32) when "10",  -- Register 0x02
                      reg_values(63 downto 48) when "11",  -- Register 0x03
                      (others => '0') when others;

    -- LED Multiplexer: Select between MDIO debug and Frame stats
    -- debug_mode = '0': Show frame count from stats_counter
    -- debug_mode = '1': Show MDIO register values cycling every 2 seconds
    -- debub_mode = '2': IP info
   -- led <= ip_protocol(3 downto 0) when debug_mode = "10" else 
   --         current_reg(3 downto 0) when debug_mode = "01" else 
   --         frame_count_leds;

    led <= ip_protocol_sync2(3 downto 0) when debug_mode = "10" else 
        current_reg(3 downto 0) when debug_mode = "01" else 
        frame_count_leds;
         
    -- led <= debug_state_sig when debug_mode = '1' else current_reg(3 downto 0);

    ----------------------------------------------------------------------------------
    -- Status LEDs
    ----------------------------------------------------------------------------------

    -- LED[3:0]: Multiplexed between frame count and MDIO registers (see above)

    -- RGB LEDs:
    -- LD4 (RGB0-2): System status
    led_rgb(2) <= rx_error;             -- LD4 Red: MII RX error (PHY level)
    led_rgb(1) <= frame_activity;       -- LD4 Green: Activity from stats_counter
    led_rgb(0) <= phy_ready;            -- LD4 Blue: PHY ready after reset

    -- LD5 (RGB3-5): Protocol errors and MDIO status
    -- Red should be OFF during reset, ON when any error bit asserted, auto-clears when errors clear
    led_rgb(5) <= '0' when reset = '1' else
                  '1' when (ip_checksum_err_sync2 = '1' or
                            ip_version_err_sync2  = '1' or
                            ip_ihl_err_sync2      = '1' or
                            udp_length_err_sync2  = '1') else
                  '0';          -- LD5 Red: IP/UDP protocol errors (IP checksum, version, UDP length)
    led_rgb(4) <= mdio_busy;            -- LD5 Green: MDIO transaction in progress
    led_rgb(3) <= '0';                  -- LD5 Blue: (unused)

    -- RGB LEDs: Indicate status
    -- LD6 (RGB): DEBUG mode indicator
    led_rgb(8) <= sequence_active when debug_mode /= "00" else '0';       -- Red (off)
    led_rgb(7) <= sequence_active when debug_mode /= "00" else '0';       -- Green (on during sequence)
    led_rgb(6) <= not sequence_active when debug_mode /= "00" else '0';   -- Blue (on when complete)


    -- =========================================================================
    -- UART State Machine
    -- =========================================================================
    -- Handles UART transmission for debug commands
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                uart_state <= UART_IDLE;
                tx_start <= '0';
                send_second_hex <= '0';
                tx_started <= '0';
                uart_msg_counter <= 0;

            else
                -- Default: no transmission
                tx_start <= '0';
                case uart_state is

                    when UART_IDLE =>
                        -- if debug enabled, send "HELLO" message repeatedly
                        if ip_valid_sync1 = '1' then  -- Higher priority
                            uart_state <= UART_IP_INFO;
                        elsif debug_mode /= "00" then  -- Lower priority
                            -- tx_data <=  debug_state_sig <= X"0A" <= X"0D"; -- Send current MDIO state as ASCII
                            -- tx_data <= X"0A"; -- '\r'
                            -- tx_data <= X"0D"; -- '\n'
                            case uart_msg_counter is
                                when 0 => tx_data <=  nibble_to_hex(debug_state_sig(3 downto 0)); -- Send current MDIO state as ASCII
                                -- when 1 => tx_data <= X"45"; -- 'E'
                                -- when 2 => tx_data <= X"4C"; -- 'L'
                                -- when 3 => tx_data <= X"4C"; -- 'L'
                                -- when 4 => tx_data <= X"4F"; -- 'O'
                                when 1 => tx_data <= X"0A"; -- '\n'
                                when 2 => tx_data <= X"0D"; -- '\r'
                                when  others => tx_data <= X"00"; -- Should not occur
                            end case;
                            tx_start <= '1';
                            uart_state <= UART_ECHO_TX;
                            if(uart_msg_counter >= 2) then
                                uart_msg_counter <= 0;
                            else
                                uart_msg_counter <= uart_msg_counter + 1;
                            end if;
                        end if;
                    when UART_ECHO_TX =>
                        -- Wait for transmission to start, then wait for it to complete
                        if tx_busy = '1' then
                            tx_started <= '1';  -- Mark that I've seen transmission start
                        elsif tx_started = '1' and tx_busy = '0' then
                            -- Transmission has completed
                            tx_started <= '0';  -- Clear flag
                            uart_state <= UART_IDLE;
                        end if;
                    when UART_IP_INFO =>
                        -- send IP Parser info to UART
                        case uart_msg_counter is
                            when 0 => tx_data <= nibble_to_hex(ip_src(3 downto 0));
                            when 1 => tx_data <= nibble_to_hex(ip_src(7 downto 4));
                            when 2 => tx_data <= nibble_to_hex(ip_dst(3 downto 0));
                            when 3 => tx_data <= nibble_to_hex(ip_dst(7 downto 4));
                            when 4 => tx_data <= nibble_to_hex(ip_protocol(3 downto 0));
                            when 5 => tx_data <= nibble_to_hex(ip_protocol(7 downto 4));
                        end case;
                        tx_start <= '1';
                        uart_state <= UART_ECHO_TX;
                        if(uart_msg_counter >= 5) then
                            uart_msg_counter <= 0;
                        else
                            uart_msg_counter <= uart_msg_counter + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end structural;