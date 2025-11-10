--------------------------------------------------------------------------------
-- Module: itch_stats_counter
-- Description: Statistics counter and display controller for ITCH parser
--              Tracks message counts by type and displays on LEDs
--
-- Display Modes (selected by switches):
--   Mode 0: Total message count (binary, lower 4 bits)
--   Mode 1: Add Order count
--   Mode 2: Execute count
--   Mode 3: Cancel count
--   Mode 4: Parse error count
--   Mode 5: Message type of last message (hex code)
--   Mode 6: Activity indicator (blinks on each message)
--   Mode 7: System Event count
--   Mode 8: Stock Directory count
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity itch_stats_counter is
    Port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;
        
        -- From ITCH parser
        msg_valid           : in  std_logic;
        msg_type            : in  std_logic_vector(7 downto 0);

        -- Message type valid signals
        add_order_valid     : in  std_logic;
        order_executed_valid : in  std_logic;
        order_cancel_valid  : in  std_logic;
        system_event_valid      : in  std_logic;
        stock_directory_valid   : in  std_logic;

         -- Error count input
        parse_errors        : in  std_logic_vector(15 downto 0);
        total_messages      : in  std_logic_vector(31 downto 0);
        
        -- Display mode selection
        display_mode        : in  std_logic_vector(2 downto 0);
        
        -- LED outputs
        led_out             : out std_logic_vector(3 downto 0);
        led_activity        : out std_logic  -- Blinks on message
    );
end itch_stats_counter;

architecture Behavioral of itch_stats_counter is

    -- Message type counters
    signal add_order_count      : unsigned(31 downto 0) := (others => '0');
    signal order_executed_count : unsigned(31 downto 0) := (others => '0');
    signal order_cancel_count   : unsigned(31 downto 0) := (others => '0');
    signal last_msg_type        : std_logic_vector(7 downto 0) := (others => '0');
    signal system_event_count   : unsigned(15 downto 0) := (others => '0');
    signal stock_directory_count : unsigned(15 downto 0) := (others => '0');

    -- Activity indicator
    signal activity_counter     : unsigned(23 downto 0) := (others => '0');
    signal activity_blink       : std_logic := '0';
    
    -- LED display value
    signal led_value            : std_logic_vector(3 downto 0) := (others => '0');

begin

    -- Count messages by type
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                add_order_count <= (others => '0');
                order_executed_count <= (others => '0');
                order_cancel_count <= (others => '0');
                last_msg_type <= (others => '0');
                
            else
               
                -- Increment per-type counters
                if system_event_valid = '1' then
                    system_event_count <= system_event_count + 1;
                end if;                
                if stock_directory_valid = '1' then
                    stock_directory_count <= stock_directory_count + 1;
                end if;
               
                -- Increment type-specific counters (no MPID)
                if add_order_valid = '1' then
                    add_order_count <= add_order_count + 1;
                end if;
                
                if order_executed_valid = '1' then
                    order_executed_count <= order_executed_count + 1;
                end if;
                
                if order_cancel_valid = '1' then
                    order_cancel_count <= order_cancel_count + 1;
                end if;
                
                -- Capture last message type
                if msg_valid = '1' then
                    last_msg_type <= msg_type;
                end if;
            end if;
        end if;
    end process;
    
    -- Activity indicator (blinks for 100ms on each message)
    -- At 100 MHz, 100ms = 10,000,000 cycles
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                activity_counter <= (others => '0');
                activity_blink <= '0';
            else
                if msg_valid = '1' then
                    -- Start blink on new message
                    activity_counter <= (others => '0');
                    activity_blink <= '1';
                elsif activity_counter < 10000000 then
                    -- Keep blinking for 100ms
                    activity_counter <= activity_counter + 1;
                    activity_blink <= '1';
                else
                    -- Turn off after 100ms
                    activity_blink <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- LED display multiplexer
    process(clk)
    begin
        if rising_edge(clk) then
            case display_mode is
                when "000" =>
                    -- Mode 0: Total messages (lower 4 bits)
                    led_value <= total_messages(3 downto 0);
                
                when "001" =>
                    -- Mode 1: Add Order count (lower 4 bits)
                    led_value <= std_logic_vector(add_order_count(3 downto 0));
                when "010" =>
                 -- System Event count (lower 4 bits)
                    led_value <= std_logic_vector(system_event_count(3 downto 0));
                        
                when "011" =>
                    -- Stock Directory count (lower 4 bits)
                    led_value <= std_logic_vector(stock_directory_count(3 downto 0));
                when "100" =>
                    -- Mode 2: Execute count (lower 4 bits)
                    led_value <= std_logic_vector(order_executed_count(3 downto 0));
                
                when "101" =>
                    -- Mode 3: Cancel count (lower 4 bits)
                    led_value <= std_logic_vector(order_cancel_count(3 downto 0));
                
                when "110" =>
                    -- Mode 4: Parse errors (lower 4 bits)
                    led_value <= parse_errors(3 downto 0);
                
                when "111" =>
                    -- Mode 5: Last message type (lower 4 bits of ASCII)
                    led_value <= last_msg_type(3 downto 0);

                when others =>
                    -- Mode 6: Activity pattern (all LEDs blink)
                    if activity_blink = '1' then
                        led_value <= "1111";
                    else
                        led_value <= "0000";
                    end if;
            end case;
        end if;
    end process;
    
    -- Output assignments
    led_out <= led_value;
    led_activity <= activity_blink;

end Behavioral;
