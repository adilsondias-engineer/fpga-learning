--------------------------------------------------------------------------------
-- MDIO Test Top Level
-- Standalone test design for MDIO controller verification
--------------------------------------------------------------------------------
-- Tests MDIO functionality by reading PHY registers on startup.
-- Displays register values on LEDs in rotating fashion.
-- This is a Phase 1B development test - will be integrated with full
-- Ethernet pipeline later.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity mdio_test_top is
    port (
        -- Clock and reset
        clk_100mhz     : in    std_logic;         -- 100 MHz system clock
        reset_n        : in    std_logic;         -- Active-low reset (CPU_RESET button)
        
        -- MDIO interface
        eth_mdc        : out   std_logic;         -- MDIO clock output
        eth_mdio       : inout std_logic;         -- MDIO bidirectional data
        
        -- Status display
        led            : out   std_logic_vector(3 downto 0);  -- Display register nibbles
        led_rgb        : out   std_logic_vector(5 downto 0)   -- RGB LEDs for status
    );
end mdio_test_top;

architecture structural of mdio_test_top is

    -- Reset synchronization
    signal reset : std_logic;
    signal reset_sync : std_logic_vector(2 downto 0) := (others => '1');
    
    -- MDIO controller signals
    signal mdio_start      : std_logic;
    signal mdio_busy       : std_logic;
    signal mdio_done       : std_logic;
    signal mdio_rw         : std_logic;
    signal mdio_phy_addr   : std_logic_vector(4 downto 0);
    signal mdio_reg_addr   : std_logic_vector(4 downto 0);
    signal mdio_write_data : std_logic_vector(15 downto 0);
    signal mdio_read_data  : std_logic_vector(15 downto 0);
    signal mdio_i          : std_logic;
    signal mdio_o          : std_logic;
    signal mdio_t          : std_logic;
    
    -- Test sequencer signals
    signal reg_display_sel : std_logic_vector(1 downto 0);
    signal reg_values      : std_logic_vector(63 downto 0);
    signal sequence_active : std_logic;
    
    -- Display signals
    signal current_reg     : std_logic_vector(15 downto 0);

    -- Add signal declaration
    signal debug_state_sig : std_logic_vector(3 downto 0);
    signal debug_mode : std_logic := '0';  -- Set to '1' for debug, '0' for normal display
begin

    ------------------------------------------------------------------------
    -- Reset synchronization (active high internally)
    ------------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            reset_sync <= reset_sync(1 downto 0) & (not reset_n);
        end if;
    end process;
    
    reset <= reset_sync(2);

    ------------------------------------------------------------------------
    -- MDIO Controller
    ------------------------------------------------------------------------
    mdio_ctrl_inst : entity work.mdio_controller
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            MDC_FREQ_HZ => 2_500_000
        )
        port map (
            clk            => clk_100mhz,
            reset          => reset,
            start          => mdio_start,
            rw             => mdio_rw,
            phy_addr       => mdio_phy_addr,
            reg_addr       => mdio_reg_addr,
            write_data     => mdio_write_data,
            busy           => mdio_busy,
            done           => mdio_done,
            read_data      => mdio_read_data,
            mdc            => eth_mdc,
            mdio_i         => mdio_i,
            mdio_o         => mdio_o,
            mdio_t         => mdio_t
        );

    ------------------------------------------------------------------------
    -- MDIO Test Sequencer
    ------------------------------------------------------------------------
    mdio_seq_inst : entity work.mdio_test_sequencer
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            PHY_ADDR    => "00001"  -- DP83848J address on Arty A7
        )
        port map (
            clk             => clk_100mhz,
            reset           => reset,
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
        );

    ------------------------------------------------------------------------
    -- MDIO Tristate Buffer
    ------------------------------------------------------------------------
    mdio_iobuf : IOBUF
        port map (
            IO => eth_mdio,
            I  => mdio_o,
            O  => mdio_i,
            T  => mdio_t
        );

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
    
    -- In display logic, choose which to show
    -- led <= debug_state_sig;  -- Show debug state
    -- led <= current_reg(3 downto 0);  -- Show register (comment out)
    -- Choose display based on mode
    led <= debug_state_sig when debug_mode = '1' else current_reg(3 downto 0);

    -- RGB LEDs: Indicate status
    -- LD4 (RGB): Green when sequence active, blue when complete
    led_rgb(2) <= sequence_active;       -- Red (off)
    led_rgb(1) <= sequence_active;       -- Green (on during sequence)
    led_rgb(0) <= not sequence_active;   -- Blue (on when complete)
    
    -- LD5 (RGB): Indicate MDIO busy state
    led_rgb(5) <= '0';                   -- Red (off)
    led_rgb(4) <= mdio_busy;             -- Green (on when busy)
    led_rgb(3) <= '0';                   -- Blue (off)

end structural;