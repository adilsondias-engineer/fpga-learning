----------------------------------------------------------------------------------
-- UDP Transmitter Top Level - Project 13
-- Arty A7-100 with TI DP83848J PHY (MII Interface)
--
-- Sends UDP packets periodically via MII interface
-- Uses simple packet builder with hardcoded "HELLO" payload
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity udp_tx_top is
    Port (
        -- System Clock (100 MHz)
        CLK        : in  STD_LOGIC;

        -- Reset button (active HIGH when pressed per Arty manual)
        reset_btn  : in  STD_LOGIC;

        -- MII Interface to PHY
        eth_ref_clk : out STD_LOGIC;                      -- 25 MHz reference to PHY
        eth_rstn    : out STD_LOGIC;                      -- Reset to PHY (active LOW)
        eth_tx_clk  : in  STD_LOGIC;                      -- TX clock from PHY (25 MHz)
        eth_txd     : out STD_LOGIC_VECTOR(3 downto 0);  -- TX data to PHY
        eth_tx_en   : out STD_LOGIC;                      -- TX enable to PHY

        -- MDIO Interface
        eth_mdc     : out STD_LOGIC;                      -- MDIO clock
        eth_mdio    : inout STD_LOGIC;                    -- MDIO bidirectional data

        -- LEDs
        led         : out STD_LOGIC_VECTOR(3 downto 0)  -- Status LEDs
    );
end udp_tx_top;

architecture structural of udp_tx_top is

    -- Clock generation signals
    signal clk_25mhz_unbuf : STD_LOGIC;
    signal clk_25mhz       : STD_LOGIC;
    signal pll_locked      : STD_LOGIC;
    signal pll_clkfb       : STD_LOGIC;

    -- PHY reset generation
    signal reset_counter   : unsigned(23 downto 0) := (others => '0');
    signal phy_reset_n     : STD_LOGIC := '0';
    signal phy_ready       : STD_LOGIC := '0';

    -- Reset synchronizers (one per clock domain)
    signal reset_sync      : std_logic_vector(2 downto 0) := (others => '1');
    signal reset           : std_logic := '1';
    signal reset_25mhz_sync : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_25mhz      : std_logic := '1';
    signal reset_tx_sync   : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_tx        : std_logic := '1';

    -- Packet builder signals
    signal send_packet     : std_logic := '0';
    signal send_packet_tx  : std_logic := '0';  -- Synchronized to eth_tx_clk domain
    signal send_packet_tx_sync : std_logic_vector(2 downto 0) := (others => '0');
    signal send_packet_prev : std_logic := '0';  -- Previous value for edge detection
    signal send_packet_tx_stretch : unsigned(7 downto 0) := (others => '0');  -- Pulse stretcher
    signal packet_sent     : std_logic;
    signal tx_data         : std_logic_vector(7 downto 0);
    signal tx_valid        : std_logic;
    signal tx_ready        : std_logic;
    signal tx_start        : std_logic;
    signal tx_end          : std_logic;

    -- Packet burst control: Send 10 packets then stop
    signal packet_count : unsigned(3 downto 0) := (others => '0');
    constant MAX_PACKETS : unsigned(3 downto 0) := to_unsigned(10, 4);
    signal burst_active : std_logic := '0';

    -- Inter-packet delay timer (10ms between packets @ 25MHz = 250,000 cycles)
    signal delay_counter : unsigned(19 downto 0) := (others => '0');
    constant PACKET_DELAY : unsigned(19 downto 0) := to_unsigned(250_000, 20);  -- 10ms @ 25MHz

    -- Packet counter for LEDs
    signal packet_counter : unsigned(3 downto 0) := (others => '0');

    -- Heartbeat counter to prove design is running
    signal heartbeat_counter : unsigned(26 downto 0) := (others => '0');
    signal heartbeat : std_logic := '0';

    -- Pulse stretcher for send_packet visibility
    signal send_packet_stretch : unsigned(23 downto 0) := (others => '0');
    signal send_packet_visible : std_logic := '0';

    -- PWM for LED brightness control (25% duty cycle)
    signal pwm_enable : std_logic := '0';  -- High for 25% of the time
    signal led_pwm : std_logic_vector(3 downto 0) := (others => '0');  -- PWM-modulated LED outputs

    -- MDIO signals
    signal mdio_start      : std_logic := '0';
    signal mdio_busy       : std_logic;
    signal mdio_done       : std_logic;
    signal mdio_rw         : std_logic := '1';  -- 1 = write
    signal mdio_phy_addr   : std_logic_vector(4 downto 0) := "00001";  -- PHY addr = 1 (try 1 first, Arty uses addr 1)
    signal mdio_reg_addr   : std_logic_vector(4 downto 0) := (others => '0');
    signal mdio_write_data : std_logic_vector(15 downto 0) := (others => '0');
    signal mdio_read_data  : std_logic_vector(15 downto 0);
    signal mdio_i          : std_logic;
    signal mdio_o          : std_logic;
    signal mdio_t          : std_logic;  -- 1 = input, 0 = output

    -- PHY configuration state machine
    type phy_config_state_t is (WAIT_RESET, WAIT_STABLE, CONFIG_REG0, WAIT_DONE, PHY_READY_ST);
    signal phy_config_state : phy_config_state_t := WAIT_RESET;
    signal phy_configured   : std_logic := '0';
    signal mdio_delay_counter : unsigned(27 downto 0) := (others => '0');  -- 28 bits for 200ms count
    
    -- Test mode: bypass phy_configured requirement for initial testing
    constant TEST_MODE_BYPASS_PHY_CONFIG : boolean := true;  -- Set to true to test without PHY config
    signal phy_configured_or_test : std_logic;

    -- Internal MII TX signals (for ILA monitoring)
    signal eth_tx_en_int  : std_logic;
    signal eth_txd_int    : std_logic_vector(3 downto 0);

    -- Clock detection and debug signals
    signal eth_tx_clk_detected : std_logic := '0';
    signal eth_tx_clk_counter : unsigned(23 downto 0) := (others => '0');
    signal use_clk_25mhz_for_tx : std_logic := '1';  -- Start with fallback, switch to eth_tx_clk when detected
    signal tx_clk_actual : std_logic;  -- Actual clock to use for TX

begin

    ----------------------------------------------------------------------------------
    -- MDIO Tristate Buffer
    ----------------------------------------------------------------------------------
    eth_mdio <= mdio_o when mdio_t = '0' else 'Z';
    mdio_i <= eth_mdio;

    ----------------------------------------------------------------------------------
    -- Reset Logic (100 MHz domain)
    ----------------------------------------------------------------------------------
    process(CLK)
    begin
        if rising_edge(CLK) then
            reset_sync <= reset_sync(1 downto 0) & reset_btn;
        end if;
    end process;

    reset <= reset_sync(2);

    ----------------------------------------------------------------------------------
    -- Reset Synchronizer for clk_25mhz domain
    ----------------------------------------------------------------------------------
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            reset_25mhz_sync <= reset_25mhz_sync(1 downto 0) & reset;
        end if;
    end process;

    reset_25mhz <= reset_25mhz_sync(2);

    ----------------------------------------------------------------------------------
    -- Clock Selection: MUST use eth_tx_clk from PHY per MII specification
    -- The PHY samples TX data on the rising edge of eth_tx_clk
    -- We drive data on the falling edge to meet setup/hold requirements
    ----------------------------------------------------------------------------------
    -- CRITICAL: Use eth_tx_clk from PHY (MII spec requirement)
    tx_clk_actual <= eth_tx_clk;  -- Use PHY's TX clock (required by MII spec)
    use_clk_25mhz_for_tx <= '0';  -- Using eth_tx_clk from PHY
    
    -- Allow testing without PHY configuration complete
    phy_configured_or_test <= phy_configured when TEST_MODE_BYPASS_PHY_CONFIG = false else '1';

    ----------------------------------------------------------------------------------
    -- Reset Synchronizer for TX clock domain
    -- Use FALLING edge to match packet builder and MII TX modules
    -- Reference implementation resets on negedge eth.tx_clk
    ----------------------------------------------------------------------------------
    process(tx_clk_actual)
    begin
        if falling_edge(tx_clk_actual) then
            reset_tx_sync <= reset_tx_sync(1 downto 0) & reset;
        end if;
    end process;

    reset_tx <= reset_tx_sync(2);

    ----------------------------------------------------------------------------------
    -- Clock Generation: 100 MHz -> 25 MHz Reference Clock for PHY
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
    -- Minimum 10ms reset pulse, uses 20ms for margin
    ----------------------------------------------------------------------------------
    process(CLK)
    begin
        if rising_edge(CLK) then
            if reset = '1' then
                reset_counter <= (others => '0');
                phy_reset_n <= '0';
                phy_ready <= '0';
            elsif reset_counter < 2_000_000 then  -- 20ms at 100 MHz
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
    -- PHY Configuration via MDIO
    -- Wait for PHY to stabilize after reset, then enable auto-negotiation
    ----------------------------------------------------------------------------------
    process(CLK)
    begin
        if rising_edge(CLK) then
            if reset = '1' then
                phy_config_state <= WAIT_RESET;
                mdio_start <= '0';
                phy_configured <= '0';
                mdio_delay_counter <= (others => '0');
            else
                case phy_config_state is
                    when WAIT_RESET =>
                        mdio_start <= '0';
                        phy_configured <= '0';
                        mdio_delay_counter <= (others => '0');
                        if phy_ready = '1' then
                            -- PHY reset complete, wait for stabilization
                            phy_config_state <= WAIT_STABLE;
                        end if;

                    when WAIT_STABLE =>
                        -- Wait 100ms for PHY to stabilize after reset
                        -- 100ms @ 100MHz = 10,000,000 cycles
                        mdio_start <= '0';
                        if mdio_delay_counter >= 10_000_000 then
                            -- PHY stabilized, configure Register 0
                            mdio_delay_counter <= (others => '0');
                            phy_config_state <= CONFIG_REG0;
                        else
                            mdio_delay_counter <= mdio_delay_counter + 1;
                        end if;

                    when CONFIG_REG0 =>
                        -- Write to Register 0 (Basic Control Register)
                        -- Bit 15: Reset (0 = normal operation)
                        -- Bit 14: Loopback (0 = disabled)
                        -- Bit 13: Speed Select (1 = 100Mbps)
                        -- Bit 12: Auto-Negotiation Enable (1 = enabled)
                        -- Bit 11: Power Down (0 = normal)
                        -- Bit 10: Isolate (0 = normal)
                        -- Bit 9:  Restart Auto-Negotiation (1 = restart)
                        -- Bit 8:  Duplex Mode (1 = full duplex)
                        -- Bits 7-0: Reserved/unused
                        -- Value: 0x3300 = 0011_0011_0000_0000
                        --        (bits 13,12,9,8 set = 100Mbps, Auto-neg, Restart, Full-duplex)
                        if mdio_busy = '0' and mdio_start = '0' then
                            mdio_reg_addr <= "00000";  -- Register 0
                            mdio_write_data <= x"3300";
                            mdio_rw <= '1';  -- Write
                            mdio_start <= '1';
                            phy_config_state <= WAIT_DONE;
                        else
                            mdio_start <= '0';
                        end if;

                    when WAIT_DONE =>
                        mdio_start <= '0';
                        if mdio_done = '1' then
                            -- MDIO write complete, PHY is now configured
                            phy_config_state <= PHY_READY_ST;
                        end if;

                    when PHY_READY_ST =>
                        phy_configured <= '1';
                        -- Stay in this state
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------
    -- Packet Burst Controller (eth_tx_clk domain)
    -- Sends 10 packets with 10ms delay between each, then stops
    -- Triggered when PHY is ready
    ----------------------------------------------------------------------------------
    process(eth_tx_clk)
    begin
        if rising_edge(eth_tx_clk) then
            if reset_tx = '1' then
                burst_active <= '0';
                packet_count <= (others => '0');
                delay_counter <= (others => '0');
                send_packet <= '0';
            elsif phy_configured_or_test = '1' then
                -- Default: clear send_packet
                send_packet <= '0';

                if burst_active = '0' then
                    -- Start burst when PHY is configured
                    burst_active <= '1';
                    packet_count <= (others => '0');
                    delay_counter <= (others => '0');
                    send_packet <= '1';  -- Send first packet immediately

                elsif packet_count < MAX_PACKETS then
                    -- Burst in progress
                    if delay_counter >= PACKET_DELAY then
                        -- Delay period elapsed, send next packet
                        delay_counter <= (others => '0');
                        packet_count <= packet_count + 1;
                        send_packet <= '1';
                    else
                        -- Still waiting
                        delay_counter <= delay_counter + 1;
                    end if;
                else
                    -- Burst complete, stop
                    burst_active <= '0';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------
    -- No CDC needed - trigger is generated on eth_tx_clk, packet builder runs on eth_tx_clk
    -- Direct connection (both on same clock domain now)
    ----------------------------------------------------------------------------------
    send_packet_tx <= send_packet;

    ----------------------------------------------------------------------------------
    -- UDP Packet Builder (Simple - Hardcoded "HELLO" Payload)
    -- Run on TX clock domain (eth_tx_clk if available, else clk_25mhz)
    ----------------------------------------------------------------------------------
    packet_builder_inst: entity work.udp_packet_builder_simple
        generic map (
            SRC_MAC  => x"00183E045DE7",      -- Your FPGA MAC
            DST_MAC  => x"FFFFFFFFFFFF",      -- Broadcast MAC
            SRC_IP   => x"C0A800D4",          -- 192.168.0.212 (FPGA IP)
            DST_IP   => x"C0A8005D",          -- 192.168.0.93 (Broadcast IP)
            SRC_PORT => x"1388",              -- 5000
            DST_PORT => x"1388"               -- 5000
        )
        port map (
            clk         => tx_clk_actual,  -- Use actual TX clock (eth_tx_clk or clk_25mhz fallback)
            reset       => reset_tx,        -- Use reset synchronized to TX clock domain
            send_packet => send_packet_tx,  -- Synchronized trigger
            packet_sent => packet_sent,
            tx_data     => tx_data,
            tx_valid    => tx_valid,
            tx_ready    => tx_ready,
            tx_start    => tx_start,
            tx_end      => tx_end
        );

    ----------------------------------------------------------------------------------
    -- MDIO Controller
    ----------------------------------------------------------------------------------
    mdio_ctrl_inst: entity work.mdio_controller
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            MDC_FREQ_HZ => 2_500_000
        )
        port map (
            clk        => CLK,
            reset      => reset,
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
    -- MII Transmitter with FCS (CRC32) Generation
    -- Use actual TX clock - ideally eth_tx_clk from PHY, but clk_25mhz as fallback for debugging
    -- NOTE: For proper MII operation, eth_tx_clk MUST be used. Fallback is for debugging only.
    -- Automatically calculates and appends FCS at end of each frame
    ----------------------------------------------------------------------------------
    mii_tx_inst: entity work.mii_tx_with_fcs
        port map (
            mii_tx_clk => tx_clk_actual,  -- Use actual TX clock (eth_tx_clk preferred, clk_25mhz fallback)
            reset      => reset_tx,       -- Use reset synchronized to TX clock domain
            tx_data    => tx_data,
            tx_valid   => tx_valid,
            tx_ready   => tx_ready,
            tx_start   => tx_start,
            tx_end     => tx_end,
            eth_tx_en  => eth_tx_en_int,
            eth_txd    => eth_txd_int
        );

    -- Connect internal signals to output ports
    eth_tx_en <= eth_tx_en_int;
    eth_txd   <= eth_txd_int;

    ----------------------------------------------------------------------------------
    -- ILA for debugging MII TX
    -- Use clk_25mhz for ILA clock so it always runs (even if eth_tx_clk isn't)
    -- This allows us to see what's happening even when PHY link isn't established
    ----------------------------------------------------------------------------------
    ila_inst : entity work.ila_0
        port map (
            clk    => clk_25mhz,  -- Use clk_25mhz so ILA always runs (for debugging)
            probe0(0) => send_packet,                    -- 1 bit (original trigger in clk_25mhz domain)
            probe1(0) => send_packet_tx,                  -- 1 bit (synchronized trigger to packet builder)
            probe2(0) => tx_start,                       -- 1 bit (packet builder output)
            probe3(0) => tx_valid,                        -- 1 bit
            probe4(0) => tx_ready,                        -- 1 bit
            probe5(0) => reset_25mhz,                     -- 1 bit (check if reset is stuck in 25MHz domain)
            probe6    => (reset & phy_configured_or_test & reset_25mhz & eth_tx_en_int),  -- 4 bits: reset(100MHz), phy_configured_or_test, reset_25mhz, eth_tx_en_int
            probe7    => ("0000" & eth_txd_int)          -- 8 bits: pad eth_txd_int (4 bits) to 8 bits
        );

    ----------------------------------------------------------------------------------
    -- Packet Counter for LEDs (25MHz domain)
    ----------------------------------------------------------------------------------
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if reset = '1' then
                packet_counter <= (others => '0');
            elsif send_packet = '1' then
                packet_counter <= packet_counter + 1;
            end if;
        end if;
    end process;

    -- Pulse stretcher - make send_packet visible (10ms pulse @ 25MHz)
    -- 10ms @ 25MHz = 250,000 cycles
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if reset = '1' then
                send_packet_stretch <= (others => '0');
                send_packet_visible <= '0';
            else
                if send_packet = '1' then
                    -- Start 10ms pulse (250,000 cycles @ 25MHz)
                    send_packet_stretch <= to_unsigned(250_000, 24);
                    send_packet_visible <= '1';
                elsif send_packet_stretch > 0 then
                    send_packet_stretch <= send_packet_stretch - 1;
                    send_packet_visible <= '1';
                else
                    send_packet_visible <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Heartbeat - toggle every 0.5 seconds to prove design is running
    process(CLK)
    begin
        if rising_edge(CLK) then
            if heartbeat_counter >= 50_000_000 then  -- 0.5s @ 100MHz
                heartbeat_counter <= (others => '0');
                heartbeat <= not heartbeat;
            else
                heartbeat_counter <= heartbeat_counter + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------
    -- PWM Dimmer for LED Brightness Control (25% duty cycle)
    -- Runs at ~390 kHz (100MHz / 256) which is fast enough to avoid flicker
    ----------------------------------------------------------------------------------
    pwm_dimmer_inst: entity work.pwm_dimmer
        generic map (
            COUNTER_BITS => 8,      -- 256 steps, gives ~390 kHz @ 100 MHz
            DUTY_CYCLE   => 64      -- 25% brightness (64/256)
        )
        port map (
            clk       => CLK,
            reset     => reset,
            pwm_out   => pwm_enable
        );

    ----------------------------------------------------------------------------------
    -- LED Logic (before PWM)
    -- LED[0] = PLL locked (clk_25mhz generated)
    -- LED[1] = send_packet_visible (10ms pulse when packet sent) OR phy_ready (if no packets)
    -- LED[2] = phy_configured (ready to send) OR mdio_busy (if not configured) OR test mode indicator
    -- LED[3] = heartbeat (toggles every 0.5s, proves design running)
    ----------------------------------------------------------------------------------
    led_pwm(0) <= pll_locked;
    led_pwm(1) <= send_packet_visible when phy_configured_or_test = '1' else phy_ready;
    led_pwm(2) <= '1' when TEST_MODE_BYPASS_PHY_CONFIG else
                  '1' when mdio_busy = '1' else
                  phy_configured;
    led_pwm(3) <= heartbeat;

    -- Apply PWM to all LEDs for brightness control (25% brightness)
    led(0) <= led_pwm(0) and pwm_enable;
    led(1) <= led_pwm(1) and pwm_enable;
    led(2) <= led_pwm(2) and pwm_enable;
    led(3) <= led_pwm(3) and pwm_enable;

end structural;
