--------------------------------------------------------------------------------
-- MDIO PHY Monitor
-- Automatically reads key PHY registers on startup for diagnostics
--------------------------------------------------------------------------------
-- Sequences through reading important DP83848J registers:
-- - 0x01: Basic Status (link status, autoneg complete)
-- - 0x10: PHY Status (speed, duplex, link state)
-- - 0x02: PHY ID High (should be 0x2000)
-- - 0x03: PHY ID Low (should be 0x5C90)
--
-- Cycles display of register values on LEDs every 2 seconds.
-- LED pattern: [3:0] = Lower nibble of current register
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mdio_phy_monitor is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;
        PHY_ADDR    : std_logic_vector(4 downto 0) := "00001"  -- DP83848J address
    );
    port (
        clk               : in  std_logic;
        reset             : in  std_logic;
        
        -- MDIO controller interface
        mdio_start        : out std_logic;
        mdio_busy         : in  std_logic;
        mdio_done         : in  std_logic;
        mdio_rw           : out std_logic;  -- Always '0' (read only)
        mdio_phy_addr     : out std_logic_vector(4 downto 0);
        mdio_reg_addr     : out std_logic_vector(4 downto 0);
        mdio_write_data   : out std_logic_vector(15 downto 0);  -- Unused
        mdio_read_data    : in  std_logic_vector(15 downto 0);
        
        -- Display interface
        reg_display_sel   : out std_logic_vector(1 downto 0);  -- Which register to display
        reg_values        : out std_logic_vector(63 downto 0); -- 4 x 16-bit registers
        sequence_active   : out std_logic;                     -- Sequence in progress

         -- Debug output port
        debug_state : out std_logic_vector(3 downto 0)  -- Current state of the sequencer for debugging
    );
end mdio_phy_monitor;

architecture rtl of mdio_phy_monitor is

    -- State machine
    type state_t is (
        INIT,
        WAIT_DELAY,
        START_READ,
        WAIT_COMPLETE,
        STORE_RESULT,
        NEXT_REGISTER,
        SEQUENCE_DONE
    );
    signal state : state_t := INIT;
    
    -- Register addresses to read
    type reg_addr_array is array (0 to 3) of std_logic_vector(4 downto 0);
    constant REGISTERS_TO_READ : reg_addr_array := (
        "00001",  -- 0x01: Basic Status
        "10000",  -- 0x10: PHY Status  
        "00010",  -- 0x02: PHY ID High
        "00011"   -- 0x03: PHY ID Low
    );
    
    -- Register storage
    signal reg_0x01 : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_0x10 : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_0x02 : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_0x03 : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Sequencer control
    signal reg_index : integer range 0 to 3 := 0;
    signal delay_counter : integer range 0 to CLK_FREQ_HZ - 1 := 0;
    constant INITIAL_DELAY : integer := CLK_FREQ_HZ / 10;  -- 100ms before first read
    
    -- Display cycling (change displayed register every 2 seconds)
    signal display_counter : integer range 0 to 2 * CLK_FREQ_HZ - 1 := 0;
    signal display_index : integer range 0 to 3 := 0;



begin

    -- Output assignments
    mdio_phy_addr <= PHY_ADDR;
    mdio_rw <= '0';  -- Always read
    mdio_write_data <= (others => '0');
    sequence_active <= '1' when state /= SEQUENCE_DONE else '0';
    
    -- Multiplex register values for output
    reg_values(15 downto 0)  <= reg_0x01;
    reg_values(31 downto 16) <= reg_0x10;
    reg_values(47 downto 32) <= reg_0x02;
    reg_values(63 downto 48) <= reg_0x03;
    
    reg_display_sel <= std_logic_vector(to_unsigned(display_index, 2));

    -- Main state machine: Read registers sequentially on startup
    process(clk)
    begin
        if rising_edge(clk) then

            if reset = '1' then
                state <= INIT;
                reg_index <= 0;
                delay_counter <= 0;
                mdio_start <= '0';
                mdio_reg_addr <= (others => '0');
                reg_0x01 <= (others => '0');
                reg_0x10 <= (others => '0');
                reg_0x02 <= (others => '0');
                reg_0x03 <= (others => '0');
            else
               -- mdio_start <= '0';  -- Default: no start pulse
                
                case state is
                    when INIT =>
                        -- Initial delay before starting reads (allow PHY to stabilize)
                        delay_counter <= INITIAL_DELAY;
                        reg_index <= 0;
                        state <= WAIT_DELAY;
                    
                    when WAIT_DELAY =>
                        -- Wait for delay period
                        if delay_counter = 0 then
                            state <= START_READ;
                        else
                            delay_counter <= delay_counter - 1;
                        end if;
                    
                    when START_READ =>
                        -- Start reading current register
                        mdio_reg_addr <= REGISTERS_TO_READ(reg_index);
                        mdio_start <= '1';
                        state <= WAIT_COMPLETE;
                    
                    when WAIT_COMPLETE =>
                        
                       -- Clear start once controller is busy
                         if mdio_busy = '1' then
                            mdio_start <= '0';
                        end if;
                        -- Wait for transaction to complete
                        if mdio_done = '1' then
                            state <= STORE_RESULT;
                        end if;
                    
                    when STORE_RESULT =>
                        -- Store read result in appropriate register
                        case reg_index is
                            when 0 => reg_0x01 <= mdio_read_data;
                            when 1 => reg_0x10 <= mdio_read_data;
                            when 2 => reg_0x02 <= mdio_read_data;
                            when 3 => reg_0x03 <= mdio_read_data;
                            when others => null;
                        end case;
                        state <= NEXT_REGISTER;
                    
                    when NEXT_REGISTER =>
                        -- Move to next register or finish sequence
                        if reg_index = 3 then
                            state <= SEQUENCE_DONE;
                        else
                            reg_index <= reg_index + 1;
                            delay_counter <= CLK_FREQ_HZ / 100;  -- 10ms between reads
                            state <= WAIT_DELAY;
                        end if;
                    
                    when SEQUENCE_DONE =>
                        -- Sequence complete, stay here
                        -- Registers can be re-read by asserting reset
                        null;
                    
                    when others =>
                        state <= INIT;
                end case;
            end if;
            
           debug_state <= std_logic_vector(to_unsigned(state_t'pos(state), 4));

        end if;
    end process;

    -- Display cycling: Change displayed register every 2 seconds
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                display_counter <= 0;
                display_index <= 0;
            else
                if display_counter = 2 * CLK_FREQ_HZ - 1 then
                    display_counter <= 0;
                    if display_index = 3 then
                        display_index <= 0;
                    else
                        display_index <= display_index + 1;
                    end if;
                else
                    display_counter <= display_counter + 1;
                end if;
            end if;
        end if;
    end process;

end rtl;