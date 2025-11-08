--------------------------------------------------------------------------------
-- Testbench: uart_itch_formatter
-- Description: Tests UART formatter for ITCH messages
--              Focuses on formatting Stock Locate, Tracking Number, and Timestamp
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hex_string_pkg.all;

entity uart_itch_formatter_tb is
end uart_itch_formatter_tb;

architecture Behavioral of uart_itch_formatter_tb is

    -- Constants
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz clock

    -- Component declaration
    component uart_itch_formatter
        Port (
            clk                  : in  std_logic;
            rst                  : in  std_logic;
            msg_valid            : in  std_logic;
            msg_type             : in  std_logic_vector(7 downto 0);
            add_order_valid      : in  std_logic;
            order_executed_valid : in  std_logic;
            order_cancel_valid   : in  std_logic;
            stock_locate         : in  std_logic_vector(15 downto 0);
            tracking_number      : in  std_logic_vector(15 downto 0);
            timestamp            : in  std_logic_vector(47 downto 0);
            order_ref            : in  std_logic_vector(63 downto 0);
            buy_sell             : in  std_logic;
            shares               : in  std_logic_vector(31 downto 0);
            symbol               : in  std_logic_vector(63 downto 0);
            price                : in  std_logic_vector(31 downto 0);
            exec_shares          : in  std_logic_vector(31 downto 0);
            match_number         : in  std_logic_vector(63 downto 0);
            cancel_shares        : in  std_logic_vector(31 downto 0);
            send_stats           : in  std_logic;
            total_messages       : in  std_logic_vector(31 downto 0);
            add_count            : in  std_logic_vector(31 downto 0);
            exec_count           : in  std_logic_vector(31 downto 0);
            cancel_count         : in  std_logic_vector(31 downto 0);
            error_count          : in  std_logic_vector(15 downto 0);
            debug_order_ref_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_order_ref_byte_val : in  std_logic_vector(7 downto 0);
            debug_buy_sell_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_buy_sell_byte_val : in  std_logic_vector(7 downto 0);
            debug_shares_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_shares_byte_val : in  std_logic_vector(7 downto 0);
            debug_symbol_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_symbol_byte_val : in  std_logic_vector(7 downto 0);
            debug_price_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_price_byte_val : in  std_logic_vector(7 downto 0);
            debug_order_ref_first_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_order_ref_first_byte_val : in  std_logic_vector(7 downto 0);
            debug_shares_first_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_shares_first_byte_val : in  std_logic_vector(7 downto 0);
            debug_stock_locate_first_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_stock_locate_first_byte_val : in  std_logic_vector(7 downto 0);
            debug_stock_locate_last_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_stock_locate_last_byte_val : in  std_logic_vector(7 downto 0);
            debug_tracking_first_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_tracking_first_byte_val : in  std_logic_vector(7 downto 0);
            debug_tracking_last_byte_cnt : in  std_logic_vector(7 downto 0);
            debug_tracking_last_byte_val : in  std_logic_vector(7 downto 0);
            uart_tx_data         : out std_logic_vector(7 downto 0);
            uart_tx_valid        : out std_logic;
            uart_tx_ready        : in  std_logic
        );
    end component;

    -- Signals
    signal clk                  : std_logic := '0';
    signal rst                  : std_logic := '1';
    signal msg_valid            : std_logic := '0';
    signal msg_type             : std_logic_vector(7 downto 0) := (others => '0');
    signal add_order_valid      : std_logic := '0';
    signal order_executed_valid : std_logic := '0';
    signal order_cancel_valid   : std_logic := '0';
    signal stock_locate         : std_logic_vector(15 downto 0) := (others => '0');
    signal tracking_number      : std_logic_vector(15 downto 0) := (others => '0');
    signal timestamp            : std_logic_vector(47 downto 0) := (others => '0');
    signal order_ref            : std_logic_vector(63 downto 0) := (others => '0');
    signal buy_sell             : std_logic := '0';
    signal shares               : std_logic_vector(31 downto 0) := (others => '0');
    signal symbol               : std_logic_vector(63 downto 0) := (others => '0');
    signal price                : std_logic_vector(31 downto 0) := (others => '0');
    signal exec_shares          : std_logic_vector(31 downto 0) := (others => '0');
    signal match_number         : std_logic_vector(63 downto 0) := (others => '0');
    signal cancel_shares        : std_logic_vector(31 downto 0) := (others => '0');
    signal send_stats           : std_logic := '0';
    signal total_messages       : std_logic_vector(31 downto 0) := (others => '0');
    signal add_count            : std_logic_vector(31 downto 0) := (others => '0');
    signal exec_count           : std_logic_vector(31 downto 0) := (others => '0');
    signal cancel_count         : std_logic_vector(31 downto 0) := (others => '0');
    signal error_count          : std_logic_vector(15 downto 0) := (others => '0');
    signal debug_stock_locate_first_byte_cnt : std_logic_vector(7 downto 0) := x"01";
    signal debug_stock_locate_first_byte_val : std_logic_vector(7 downto 0) := x"00";
    signal debug_stock_locate_last_byte_cnt : std_logic_vector(7 downto 0) := x"02";
    signal debug_stock_locate_last_byte_val : std_logic_vector(7 downto 0) := x"01";
    signal debug_tracking_first_byte_cnt : std_logic_vector(7 downto 0) := x"03";
    signal debug_tracking_first_byte_val : std_logic_vector(7 downto 0) := x"00";
    signal debug_tracking_last_byte_cnt : std_logic_vector(7 downto 0) := x"04";
    signal debug_tracking_last_byte_val : std_logic_vector(7 downto 0) := x"00";
    signal uart_tx_data         : std_logic_vector(7 downto 0);
    signal uart_tx_valid        : std_logic;
    signal uart_tx_ready        : std_logic := '1';

    -- Expected output string (for comparison)
    type string_array is array (natural range <>) of character;
    signal received_chars : string_array(0 to 255);
    signal char_count : integer := 0;
    signal reset_char_count : std_logic := '0';

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    uut: uart_itch_formatter
        port map (
            clk => clk,
            rst => rst,
            msg_valid => msg_valid,
            msg_type => msg_type,
            add_order_valid => add_order_valid,
            order_executed_valid => order_executed_valid,
            order_cancel_valid => order_cancel_valid,
            stock_locate => stock_locate,
            tracking_number => tracking_number,
            timestamp => timestamp,
            order_ref => order_ref,
            buy_sell => buy_sell,
            shares => shares,
            symbol => symbol,
            price => price,
            exec_shares => exec_shares,
            match_number => match_number,
            cancel_shares => cancel_shares,
            send_stats => send_stats,
            total_messages => total_messages,
            add_count => add_count,
            exec_count => exec_count,
            cancel_count => cancel_count,
            error_count => error_count,
            debug_order_ref_byte_cnt => (others => '0'),
            debug_order_ref_byte_val => (others => '0'),
            debug_buy_sell_byte_cnt => (others => '0'),
            debug_buy_sell_byte_val => (others => '0'),
            debug_shares_byte_cnt => (others => '0'),
            debug_shares_byte_val => (others => '0'),
            debug_symbol_byte_cnt => (others => '0'),
            debug_symbol_byte_val => (others => '0'),
            debug_price_byte_cnt => (others => '0'),
            debug_price_byte_val => (others => '0'),
            debug_order_ref_first_byte_cnt => (others => '0'),
            debug_order_ref_first_byte_val => (others => '0'),
            debug_shares_first_byte_cnt => (others => '0'),
            debug_shares_first_byte_val => (others => '0'),
            debug_stock_locate_first_byte_cnt => debug_stock_locate_first_byte_cnt,
            debug_stock_locate_first_byte_val => debug_stock_locate_first_byte_val,
            debug_stock_locate_last_byte_cnt => debug_stock_locate_last_byte_cnt,
            debug_stock_locate_last_byte_val => debug_stock_locate_last_byte_val,
            debug_tracking_first_byte_cnt => debug_tracking_first_byte_cnt,
            debug_tracking_first_byte_val => debug_tracking_first_byte_val,
            debug_tracking_last_byte_cnt => debug_tracking_last_byte_cnt,
            debug_tracking_last_byte_val => debug_tracking_last_byte_val,
            uart_tx_data => uart_tx_data,
            uart_tx_valid => uart_tx_valid,
            uart_tx_ready => uart_tx_ready
        );

    -- Capture UART output
    capture_proc: process(clk)
    begin
        if rising_edge(clk) then
            -- Reset counter when requested
            if reset_char_count = '1' then
                char_count <= 0;
            elsif rst = '0' and uart_tx_valid = '1' and uart_tx_ready = '1' then
                if char_count < 256 then
                    received_chars(char_count) <= character'val(to_integer(unsigned(uart_tx_data)));
                    char_count <= char_count + 1;
                    report "UART TX: 0x" & to_hex_string(uart_tx_data) & " ('" & character'val(to_integer(unsigned(uart_tx_data))) & "')";
                end if;
            end if;
        end if;
    end process;

    -- Test process
    test_proc: process
    begin
        -- Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        -- Test 1: Add Order message with known values
        report "=== Test 1: Add Order message ===";
        msg_type <= x"41";  -- 'A'
        stock_locate <= x"0001";
        tracking_number <= x"0000";
        timestamp <= x"000000000100";
        add_order_valid <= '1';
        wait for CLK_PERIOD;
        add_order_valid <= '0';
        
        -- Wait for formatter to process
        wait for 2000 ns;
        
        -- Print received string
        report "=== Received output ===";
        for i in 0 to char_count - 1 loop
            if received_chars(i) = character'val(13) then
                report "  [CR]";
            elsif received_chars(i) = character'val(10) then
                report "  [LF]";
            else
                report "  '" & received_chars(i) & "'";
            end if;
        end loop;
        
        wait for 500 ns;
        
        -- Test 2: Different values
        report "=== Test 2: Different values ===";
        reset_char_count <= '1';
        wait for CLK_PERIOD;
        reset_char_count <= '0';
        stock_locate <= x"1234";
        tracking_number <= x"5678";
        timestamp <= x"000000123456";
        add_order_valid <= '1';
        wait for CLK_PERIOD;
        add_order_valid <= '0';
        
        wait for 2000 ns;
        
        -- Print received string
        report "=== Received output test 2 ===";
        for i in 0 to char_count - 1 loop
            if received_chars(i) = character'val(13) then
                report "  [CR]";
            elsif received_chars(i) = character'val(10) then
                report "  [LF]";
            else
                report "  '" & received_chars(i) & "'";
            end if;
        end loop;
        
        report "=== All tests completed ===";
        wait;
    end process;

end Behavioral;

