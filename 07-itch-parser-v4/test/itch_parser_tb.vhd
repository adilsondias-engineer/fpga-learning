--------------------------------------------------------------------------------
-- Testbench: itch_parser
-- Description: Tests ITCH 5.0 parser for Add Order messages
--              Focuses on bytes 0-10: Type, Stock Locate, Tracking Number, Timestamp
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use work.hex_string_pkg.all;

entity itch_parser_tb is
end itch_parser_tb;

architecture Behavioral of itch_parser_tb is

    -- Constants
    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz clock (eth_rx_clk domain)

    -- Component declaration
    component itch_parser
        Port (
            clk                 : in  std_logic;
            rst                 : in  std_logic;
            udp_payload_valid   : in  std_logic;
            udp_payload_data    : in  std_logic_vector(7 downto 0);
            udp_payload_start   : in  std_logic;
            udp_payload_end     : in  std_logic;
            msg_valid           : out std_logic;
            msg_type            : out std_logic_vector(7 downto 0);
            msg_error           : out std_logic;
            add_order_valid     : out std_logic;
            stock_locate        : out std_logic_vector(15 downto 0);
            tracking_number     : out std_logic_vector(15 downto 0);
            timestamp           : out std_logic_vector(47 downto 0);
            order_ref           : out std_logic_vector(63 downto 0);
            buy_sell            : out std_logic;
            shares              : out std_logic_vector(31 downto 0);
            symbol              : out std_logic_vector(63 downto 0);
            price               : out std_logic_vector(31 downto 0);
            order_executed_valid : out std_logic;
            exec_shares          : out std_logic_vector(31 downto 0);
            match_number         : out std_logic_vector(63 downto 0);
            order_cancel_valid  : out std_logic;
            cancel_shares       : out std_logic_vector(31 downto 0);
            total_messages      : out std_logic_vector(31 downto 0);
            parse_errors        : out std_logic_vector(15 downto 0);
            debug_byte_counter  : out std_logic_vector(7 downto 0);
            debug_order_ref_byte_cnt : out std_logic_vector(7 downto 0);
            debug_order_ref_byte_val : out std_logic_vector(7 downto 0);
            debug_buy_sell_byte_cnt : out std_logic_vector(7 downto 0);
            debug_buy_sell_byte_val : out std_logic_vector(7 downto 0);
            debug_shares_byte_cnt : out std_logic_vector(7 downto 0);
            debug_shares_byte_val : out std_logic_vector(7 downto 0);
            debug_symbol_byte_cnt : out std_logic_vector(7 downto 0);
            debug_symbol_byte_val : out std_logic_vector(7 downto 0);
            debug_price_byte_cnt : out std_logic_vector(7 downto 0);
            debug_price_byte_val : out std_logic_vector(7 downto 0);
            debug_order_ref_first_byte_cnt : out std_logic_vector(7 downto 0);
            debug_order_ref_first_byte_val : out std_logic_vector(7 downto 0);
            debug_shares_first_byte_cnt : out std_logic_vector(7 downto 0);
            debug_shares_first_byte_val : out std_logic_vector(7 downto 0);
            debug_current_byte_counter : out std_logic_vector(7 downto 0);
            debug_stock_locate_first_byte_cnt : out std_logic_vector(7 downto 0);
            debug_stock_locate_first_byte_val : out std_logic_vector(7 downto 0);
            debug_stock_locate_last_byte_cnt : out std_logic_vector(7 downto 0);
            debug_stock_locate_last_byte_val : out std_logic_vector(7 downto 0);
            debug_tracking_first_byte_cnt : out std_logic_vector(7 downto 0);
            debug_tracking_first_byte_val : out std_logic_vector(7 downto 0);
            debug_tracking_last_byte_cnt : out std_logic_vector(7 downto 0);
            debug_tracking_last_byte_val : out std_logic_vector(7 downto 0);
            debug_current_payload_data : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Signals
    signal clk                  : std_logic := '0';
    signal rst                  : std_logic := '1';
    signal udp_payload_valid    : std_logic := '0';
    signal udp_payload_data     : std_logic_vector(7 downto 0) := (others => '0');
    signal udp_payload_start    : std_logic := '0';
    signal udp_payload_end      : std_logic := '0';
    signal msg_valid            : std_logic;
    signal msg_type             : std_logic_vector(7 downto 0);
    signal msg_error            : std_logic;
    signal add_order_valid      : std_logic;
    signal stock_locate         : std_logic_vector(15 downto 0);
    signal tracking_number      : std_logic_vector(15 downto 0);
    signal timestamp            : std_logic_vector(47 downto 0);
    signal order_ref            : std_logic_vector(63 downto 0);
    signal buy_sell             : std_logic;
    signal shares               : std_logic_vector(31 downto 0);
    signal symbol               : std_logic_vector(63 downto 0);
    signal price                : std_logic_vector(31 downto 0);
    signal order_executed_valid : std_logic;
    signal exec_shares          : std_logic_vector(31 downto 0);
    signal match_number         : std_logic_vector(63 downto 0);
    signal order_cancel_valid   : std_logic;
    signal cancel_shares        : std_logic_vector(31 downto 0);
    signal total_messages       : std_logic_vector(31 downto 0);
    signal parse_errors         : std_logic_vector(15 downto 0);
    signal debug_byte_counter   : std_logic_vector(7 downto 0);
    signal debug_stock_locate_first_byte_cnt : std_logic_vector(7 downto 0);
    signal debug_stock_locate_first_byte_val : std_logic_vector(7 downto 0);
    signal debug_stock_locate_last_byte_cnt : std_logic_vector(7 downto 0);
    signal debug_stock_locate_last_byte_val : std_logic_vector(7 downto 0);
    signal debug_tracking_first_byte_cnt : std_logic_vector(7 downto 0);
    signal debug_tracking_first_byte_val : std_logic_vector(7 downto 0);
    signal debug_tracking_last_byte_cnt : std_logic_vector(7 downto 0);
    signal debug_tracking_last_byte_val : std_logic_vector(7 downto 0);
    signal debug_current_byte_counter : std_logic_vector(7 downto 0);
    signal debug_current_payload_data : std_logic_vector(7 downto 0);

    -- Test message: Add Order (36 bytes)
    -- Byte 0:  'A' (0x41) - Message type
    -- Bytes 1-2: Stock Locate = 0x0001 (big-endian: 0x00 0x01)
    -- Bytes 3-4: Tracking Number = 0x0000 (big-endian: 0x00 0x00)
    -- Bytes 5-10: Timestamp = 0x000000000100 (big-endian: 0x00 0x00 0x00 0x00 0x01 0x00)
    -- Bytes 11-35: Padding zeros for rest of message
    type message_array is array (0 to 35) of std_logic_vector(7 downto 0);
    signal test_message : message_array := (
        x"41",  -- Byte 0: 'A' - Add Order
        x"00",  -- Byte 1: Stock Locate MSB
        x"01",  -- Byte 2: Stock Locate LSB (should be 0x0001)
        x"00",  -- Byte 3: Tracking Number MSB
        x"00",  -- Byte 4: Tracking Number LSB (should be 0x0000)
        x"00",  -- Byte 5: Timestamp byte 0
        x"00",  -- Byte 6: Timestamp byte 1
        x"00",  -- Byte 7: Timestamp byte 2
        x"00",  -- Byte 8: Timestamp byte 3
        x"01",  -- Byte 9: Timestamp byte 4
        x"00",  -- Byte 10: Timestamp byte 5 (should be 0x000000000100)
        x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",  -- Bytes 11-18: Order Ref (padding)
        x"42",  -- Byte 19: 'B' - Buy
        x"00", x"00", x"00", x"64",  -- Bytes 20-23: Shares = 100 (padding)
        x"41", x"41", x"50", x"4C", x"20", x"20", x"20", x"20",  -- Bytes 24-31: "AAPL    " (padding)
        x"00", x"00", x"EA", x"60"   -- Bytes 32-35: Price (padding)
    );

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    uut: itch_parser
        port map (
            clk => clk,
            rst => rst,
            udp_payload_valid => udp_payload_valid,
            udp_payload_data => udp_payload_data,
            udp_payload_start => udp_payload_start,
            udp_payload_end => udp_payload_end,
            msg_valid => msg_valid,
            msg_type => msg_type,
            msg_error => msg_error,
            add_order_valid => add_order_valid,
            stock_locate => stock_locate,
            tracking_number => tracking_number,
            timestamp => timestamp,
            order_ref => order_ref,
            buy_sell => buy_sell,
            shares => shares,
            symbol => symbol,
            price => price,
            order_executed_valid => order_executed_valid,
            exec_shares => exec_shares,
            match_number => match_number,
            order_cancel_valid => order_cancel_valid,
            cancel_shares => cancel_shares,
            total_messages => total_messages,
            parse_errors => parse_errors,
            debug_byte_counter => debug_byte_counter,
            debug_order_ref_byte_cnt => open,
            debug_order_ref_byte_val => open,
            debug_buy_sell_byte_cnt => open,
            debug_buy_sell_byte_val => open,
            debug_shares_byte_cnt => open,
            debug_shares_byte_val => open,
            debug_symbol_byte_cnt => open,
            debug_symbol_byte_val => open,
            debug_price_byte_cnt => open,
            debug_price_byte_val => open,
            debug_order_ref_first_byte_cnt => open,
            debug_order_ref_first_byte_val => open,
            debug_shares_first_byte_cnt => open,
            debug_shares_first_byte_val => open,
            debug_current_byte_counter => debug_current_byte_counter,
            debug_stock_locate_first_byte_cnt => debug_stock_locate_first_byte_cnt,
            debug_stock_locate_first_byte_val => debug_stock_locate_first_byte_val,
            debug_stock_locate_last_byte_cnt => debug_stock_locate_last_byte_cnt,
            debug_stock_locate_last_byte_val => debug_stock_locate_last_byte_val,
            debug_tracking_first_byte_cnt => debug_tracking_first_byte_cnt,
            debug_tracking_first_byte_val => debug_tracking_first_byte_val,
            debug_tracking_last_byte_cnt => debug_tracking_last_byte_cnt,
            debug_tracking_last_byte_val => debug_tracking_last_byte_val,
            debug_current_payload_data => debug_current_payload_data
        );

    -- Test process
    test_proc: process
        variable byte_idx : integer := 0;
    begin
        -- Reset
        rst <= '1';
        udp_payload_valid <= '0';
        udp_payload_data <= (others => '0');
        udp_payload_start <= '0';
        udp_payload_end <= '0';
        wait for 200 ns;
        rst <= '0';
        wait for 200 ns;  -- Extra wait to ensure parser is ready

        -- Send test message
        report "=== Starting test: Add Order message ===";
        
        for byte_idx in 0 to 35 loop
            -- Wait for clock to be low (setup time before next rising edge)
            wait until clk = '0';
            wait for CLK_PERIOD / 4;  -- Quarter period for setup
            
            -- Set data and control signals (stable before rising edge)
            udp_payload_data <= test_message(byte_idx);
            
            if byte_idx = 0 then
                udp_payload_start <= '1';
            else
                udp_payload_start <= '0';
            end if;
            
            if byte_idx = 35 then
                udp_payload_end <= '1';
            else
                udp_payload_end <= '0';
            end if;
            
            -- Assert valid
            udp_payload_valid <= '1';
            
            -- Wait for rising edge (parser samples here)
            wait until rising_edge(clk);
            
            -- Keep valid high for the entire clock cycle
            wait for CLK_PERIOD / 2;  -- Half period
            
            -- Deassert valid and start (hold after clock edge)
            udp_payload_valid <= '0';
            udp_payload_start <= '0';
            
            -- Wait for next clock edge to start next byte
            wait until rising_edge(clk);
        end loop;
        
        udp_payload_end <= '0';
        
        -- Wait for message to be parsed (wait longer for CDC hold period)
        -- Wait for at least 8 cycles (320 ns) plus some margin
        wait for 2000 ns;
        
        -- Check results
        report "=== Checking results ===";
        report "Current state (from debug): byte_counter=" & integer'image(to_integer(unsigned(debug_current_byte_counter)));
        report "Current payload data: 0x" & to_hex_string(debug_current_payload_data);
        report "Test message bytes sent:";
        report "  Byte 0: 0x" & to_hex_string(test_message(0)) & " (type)";
        report "  Byte 1: 0x" & to_hex_string(test_message(1)) & " (Stock Locate MSB)";
        report "  Byte 2: 0x" & to_hex_string(test_message(2)) & " (Stock Locate LSB)";
        report "  Byte 3: 0x" & to_hex_string(test_message(3)) & " (Tracking MSB)";
        report "  Byte 4: 0x" & to_hex_string(test_message(4)) & " (Tracking LSB)";
        report "Parser results:";
        report "Message type: 0x" & to_hex_string(msg_type) & " (expected: 41)";
        report "Message valid: " & std_logic'image(msg_valid);
        report "Add order valid: " & std_logic'image(add_order_valid);
        report "Stock locate: 0x" & to_hex_string(stock_locate) & " (expected: 0001)";
        report "  Raw bytes: MSB=0x" & to_hex_string(stock_locate(15 downto 8)) & " LSB=0x" & to_hex_string(stock_locate(7 downto 0));
        report "Tracking number: 0x" & to_hex_string(tracking_number) & " (expected: 0000)";
        report "Timestamp: 0x" & to_hex_string(timestamp) & " (expected: 000000000100)";
        report "Debug stock_locate first byte cnt: " & integer'image(to_integer(unsigned(debug_stock_locate_first_byte_cnt))) & " (expected: 1, shows byte_counter+1)";
        report "Debug stock_locate first byte val: 0x" & to_hex_string(debug_stock_locate_first_byte_val) & " (expected: 00)";
        report "Debug stock_locate last byte cnt: " & integer'image(to_integer(unsigned(debug_stock_locate_last_byte_cnt))) & " (expected: 2, shows byte_counter+1)";
        report "Debug stock_locate last byte val: 0x" & to_hex_string(debug_stock_locate_last_byte_val) & " (expected: 01)";
        report "Debug tracking first byte cnt: " & integer'image(to_integer(unsigned(debug_tracking_first_byte_cnt))) & " (expected: 3, shows byte_counter+1)";
        report "Debug tracking first byte val: 0x" & to_hex_string(debug_tracking_first_byte_val) & " (expected: 00)";
        report "Debug tracking last byte cnt: " & integer'image(to_integer(unsigned(debug_tracking_last_byte_cnt))) & " (expected: 4, shows byte_counter+1)";
        report "Debug tracking last byte val: 0x" & to_hex_string(debug_tracking_last_byte_val) & " (expected: 00)";
        
        -- Assertions
        -- NOTE: Debug signals now show byte_counter+1 as the actual byte position
        -- So debug_stock_locate_first_byte_cnt should be 1 (byte_counter was 0 when processing byte 1)
        assert msg_type = x"41" report "ERROR: Message type should be 'A' (0x41)" severity error;
        assert stock_locate = x"0001" report "ERROR: Stock locate should be 0x0001" severity error;
        assert tracking_number = x"0000" report "ERROR: Tracking number should be 0x0000" severity error;
        assert timestamp = x"000000000100" report "ERROR: Timestamp should be 0x000000000100" severity error;
        assert debug_stock_locate_first_byte_cnt = x"01" report "ERROR: Stock locate first byte counter should be 1 (byte_counter was 0)" severity error;
        assert debug_stock_locate_last_byte_cnt = x"02" report "ERROR: Stock locate last byte counter should be 2 (byte_counter was 1)" severity error;
        assert debug_tracking_first_byte_cnt = x"03" report "ERROR: Tracking first byte counter should be 3 (byte_counter was 2)" severity error;
        assert debug_tracking_last_byte_cnt = x"04" report "ERROR: Tracking last byte counter should be 4 (byte_counter was 3)" severity error;
        
        report "=== Test completed successfully ===";
        wait for 500 ns;
        
        -- Test 2: Different values
        report "=== Starting test 2: Different values ===";
        test_message(1) <= x"12";  -- Stock Locate = 0x1234
        test_message(2) <= x"34";
        test_message(3) <= x"56";  -- Tracking = 0x5678
        test_message(4) <= x"78";
        test_message(5) <= x"00";  -- Timestamp = 0x000000123456 (6 bytes: bytes 5-10)
        test_message(6) <= x"00";
        test_message(7) <= x"00";
        test_message(8) <= x"12";
        test_message(9) <= x"34";
        test_message(10) <= x"56";
        
        wait for 100 ns;
        
        -- Send test message 2
        for byte_idx in 0 to 35 loop
            -- Wait for clock to be low (setup time before next rising edge)
            wait until clk = '0';
            wait for CLK_PERIOD / 4;  -- Quarter period for setup
            
            -- Set data and control signals (stable before rising edge)
            udp_payload_data <= test_message(byte_idx);
            
            if byte_idx = 0 then
                udp_payload_start <= '1';
            else
                udp_payload_start <= '0';
            end if;
            
            if byte_idx = 35 then
                udp_payload_end <= '1';
            else
                udp_payload_end <= '0';
            end if;
            
            -- Assert valid
            udp_payload_valid <= '1';
            
            -- Wait for rising edge (parser samples here)
            wait until rising_edge(clk);
            
            -- Keep valid high for the entire clock cycle
            wait for CLK_PERIOD / 2;  -- Half period
            
            -- Deassert valid and start (hold after clock edge)
            udp_payload_valid <= '0';
            udp_payload_start <= '0';
            
            -- Wait for next clock edge to start next byte
            wait until rising_edge(clk);
        end loop;
        
        udp_payload_end <= '0';
        wait for 500 ns;
        
        report "=== Checking results test 2 ===";
        report "Stock locate: 0x" & to_hex_string(stock_locate) & " (expected: 1234)";
        report "Tracking number: 0x" & to_hex_string(tracking_number) & " (expected: 5678)";
        report "Timestamp: 0x" & to_hex_string(timestamp) & " (expected: 000000123456)";
        
        assert stock_locate = x"1234" report "ERROR: Stock locate should be 0x1234" severity error;
        assert tracking_number = x"5678" report "ERROR: Tracking number should be 0x5678" severity error;
        assert timestamp = x"000000123456" report "ERROR: Timestamp should be 0x000000123456 (got 0x" & to_hex_string(timestamp) & ")" severity error;
        
        report "=== All tests completed ===";
        wait;
    end process;

end Behavioral;
