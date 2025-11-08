--------------------------------------------------------------------------------
-- Module: uart_itch_formatter
-- Description: Formats parsed ITCH messages for UART debug output
--              Converts binary fields to human-readable ASCII text
--
-- Output Format Examples:
--   [ITCH] Type=A Ref=12345678 B 100 AAPL @ 150.2500
--   [ITCH] Type=E Ref=12345678 Exec=50 Match=98765
--   [ITCH] Type=X Ref=12345678 Cancel=25
--   [STATS] Total=1523 A=450 E=320 X=180 Err=5
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_itch_formatter is
    Port (
        clk                  : in  std_logic;
        rst                  : in  std_logic;
        
        -- From ITCH parser
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
        
        -- Statistics trigger (send stats every N messages)
        send_stats           : in  std_logic;
        total_messages       : in  std_logic_vector(31 downto 0);
        add_count            : in  std_logic_vector(31 downto 0);
        exec_count           : in  std_logic_vector(31 downto 0);
        cancel_count         : in  std_logic_vector(31 downto 0);
        error_count          : in  std_logic_vector(15 downto 0);
        
        -- Debug inputs (for debugging byte alignment)
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
        debug_current_payload_data : in  std_logic_vector(7 downto 0);
        debug_current_byte_counter : in  std_logic_vector(7 downto 0);
        debug_byte2_payload_data : in  std_logic_vector(7 downto 0);
        debug_byte3_payload_data : in  std_logic_vector(7 downto 0);
        debug_byte2_byte_counter : in  std_logic_vector(7 downto 0);
        debug_byte3_byte_counter : in  std_logic_vector(7 downto 0);
        
        -- Detailed cycle-by-cycle debug inputs
        debug_payload_history_0 : in  std_logic_vector(7 downto 0);  -- Most recent payload byte
        debug_payload_history_1 : in  std_logic_vector(7 downto 0);  -- Previous payload byte
        debug_payload_history_2 : in  std_logic_vector(7 downto 0);  -- 2 cycles ago
        debug_payload_history_3 : in  std_logic_vector(7 downto 0);  -- 3 cycles ago
        debug_payload_valid_history : in  std_logic_vector(7 downto 0);  -- payload_valid history
        debug_payload_start_history : in  std_logic_vector(7 downto 0);  -- payload_start history
        debug_state_encoded : in  std_logic_vector(2 downto 0);  -- Encoded state
        debug_byte_counter_at_valid : in  std_logic_vector(7 downto 0);  -- byte_counter when payload_valid='1'
        debug_processing_cycle : in  std_logic;  -- High when processing a byte
        
        -- Critical debug: Bytes 1-4 data and counter
        debug_byte1_data : in  std_logic_vector(7 downto 0);
        debug_byte2_data : in  std_logic_vector(7 downto 0);
        debug_byte3_data : in  std_logic_vector(7 downto 0);
        debug_byte4_data : in  std_logic_vector(7 downto 0);
        debug_byte1_counter : in  std_logic_vector(7 downto 0);
        debug_byte2_counter : in  std_logic_vector(7 downto 0);
        debug_byte3_counter : in  std_logic_vector(7 downto 0);
        debug_byte4_counter : in  std_logic_vector(7 downto 0);
        
        -- UART TX interface
        uart_tx_data         : out std_logic_vector(7 downto 0);
        uart_tx_valid        : out std_logic;
        uart_tx_ready        : in  std_logic
    );
end uart_itch_formatter;

architecture Behavioral of uart_itch_formatter is

    -- State machine for message formatting
    type state_type is (
        IDLE,
        SEND_ADD_ORDER,
        SEND_ORDER_EXECUTED,
        SEND_ORDER_CANCEL,
        SEND_STATS_ST,
        WAIT_TX
    );
    signal state : state_type := IDLE;
    signal current_send_state : state_type := IDLE;  -- Tracks current SEND_* state

    -- Internal signal for uart_tx_valid (can be read, unlike output port)
    signal uart_tx_valid_int : std_logic := '0';

    -- Message buffer (pre-formatted string)
    type byte_array is array (0 to 255) of std_logic_vector(7 downto 0);
    type byte_array_20 is array (0 to 19) of std_logic_vector(7 downto 0);
    type byte_array_10 is array (0 to 9) of std_logic_vector(7 downto 0);
    signal msg_buffer       : byte_array := (others => (others => '0'));
    signal msg_length       : integer range 0 to 256 := 0;
    signal byte_index       : integer range 0 to 256 := 0;
    
    -- Trigger latches
    signal add_order_pending     : std_logic := '0';
    signal order_executed_pending : std_logic := '0';
    signal order_cancel_pending  : std_logic := '0';
    signal stats_pending         : std_logic := '0';

    -- Message counter and timestamp for debugging
    signal msg_counter           : unsigned(31 downto 0) := (others => '0');
    signal timestamp_counter     : unsigned(31 downto 0) := (others => '0');
    
    -- Captured message fields
    signal captured_stock_locate : std_logic_vector(15 downto 0) := (others => '0');
    signal captured_tracking_number : std_logic_vector(15 downto 0) := (others => '0');
    signal captured_timestamp   : std_logic_vector(47 downto 0) := (others => '0');
    signal captured_order_ref    : std_logic_vector(63 downto 0) := (others => '0');
    signal captured_buy_sell     : std_logic := '0';
    signal captured_shares       : std_logic_vector(31 downto 0) := (others => '0');
    signal captured_symbol       : std_logic_vector(63 downto 0) := (others => '0');
    signal captured_price        : std_logic_vector(31 downto 0) := (others => '0');
    signal captured_exec_shares  : std_logic_vector(31 downto 0) := (others => '0');
    signal captured_match_num    : std_logic_vector(63 downto 0) := (others => '0');
    signal captured_cancel_shares : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Edge detection signals for synchronized valid pulses
    signal add_order_valid_prev : std_logic := '0';
    signal order_executed_valid_prev : std_logic := '0';
    signal order_cancel_valid_prev : std_logic := '0';
    
    -- Helper function: Convert 4-bit value to ASCII hex character
    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        case nibble is
            when x"0" => result := x"30";  -- '0'
            when x"1" => result := x"31";  -- '1'
            when x"2" => result := x"32";  -- '2'
            when x"3" => result := x"33";  -- '3'
            when x"4" => result := x"34";  -- '4'
            when x"5" => result := x"35";  -- '5'
            when x"6" => result := x"36";  -- '6'
            when x"7" => result := x"37";  -- '7'
            when x"8" => result := x"38";  -- '8'
            when x"9" => result := x"39";  -- '9'
            when x"A" => result := x"41";  -- 'A'
            when x"B" => result := x"42";  -- 'B'
            when x"C" => result := x"43";  -- 'C'
            when x"D" => result := x"44";  -- 'D'
            when x"E" => result := x"45";  -- 'E'
            when x"F" => result := x"46";  -- 'F'
            when others => result := x"3F";  -- '?'
        end case;
        return result;
    end function;
    
    -- Helper function: Convert digit (0-9) to ASCII
    function digit_to_ascii(digit : integer range 0 to 9) return std_logic_vector is
    begin
        case digit is
            when 0 => return x"30";  -- '0'
            when 1 => return x"31";  -- '1'
            when 2 => return x"32";  -- '2'
            when 3 => return x"33";  -- '3'
            when 4 => return x"34";  -- '4'
            when 5 => return x"35";  -- '5'
            when 6 => return x"36";  -- '6'
            when 7 => return x"37";  -- '7'
            when 8 => return x"38";  -- '8'
            when 9 => return x"39";  -- '9'
        end case;
    end function;

begin

    -- Capture incoming messages with edge detection
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                add_order_pending <= '0';
                order_executed_pending <= '0';
                order_cancel_pending <= '0';
                stats_pending <= '0';
                add_order_valid_prev <= '0';
                order_executed_valid_prev <= '0';
                order_cancel_valid_prev <= '0';
            else
                -- Edge detection: latch on rising edge of synchronized valid signals
                add_order_valid_prev <= add_order_valid;
                order_executed_valid_prev <= order_executed_valid;
                order_cancel_valid_prev <= order_cancel_valid;
                
                -- Latch message type triggers on rising edge
                if add_order_valid = '1' and add_order_valid_prev = '0' then
                    add_order_pending <= '1';
                    -- CRITICAL: Capture ALL fields on the edge to avoid reading stale/changed data
                    captured_stock_locate <= stock_locate;
                    captured_tracking_number <= tracking_number;
                    captured_timestamp <= timestamp;
                    captured_order_ref <= order_ref;
                    captured_buy_sell <= buy_sell;
                    captured_shares <= shares;
                    captured_symbol <= symbol;
                    captured_price <= price;
                end if;
                
                if order_executed_valid = '1' and order_executed_valid_prev = '0' then
                    order_executed_pending <= '1';
                    captured_order_ref <= order_ref;
                    captured_exec_shares <= exec_shares;
                    captured_match_num <= match_number;
                end if;
                
                if order_cancel_valid = '1' and order_cancel_valid_prev = '0' then
                    order_cancel_pending <= '1';
                    captured_order_ref <= order_ref;
                    captured_cancel_shares <= cancel_shares;
                end if;
                
                if send_stats = '1' then
                    stats_pending <= '1';
                end if;
                
                -- Clear pending flags when message sent
                if state = SEND_ADD_ORDER and byte_index = 0 then
                    add_order_pending <= '0';
                elsif state = SEND_ORDER_EXECUTED and byte_index = 0 then
                    order_executed_pending <= '0';
                elsif state = SEND_ORDER_CANCEL and byte_index = 0 then
                    order_cancel_pending <= '0';
                elsif state = SEND_STATS_ST and byte_index = 0 then
                    stats_pending <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Main formatter state machine
    process(clk)
        variable idx : integer range 0 to 256;
        -- Decimal conversion variables
        variable order_ref_val : unsigned(63 downto 0);
        variable shares_val : unsigned(31 downto 0);
        variable price_val : unsigned(31 downto 0);
        variable symbol_start : integer range 0 to 8;
        variable symbol_end : integer range 0 to 8;
        variable symbol_found : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                uart_tx_valid_int <= '0';
                byte_index <= 0;
                msg_length <= 0;
                msg_counter <= (others => '0');
                timestamp_counter <= (others => '0');

            else
                -- Increment timestamp counter every cycle (for debugging)
                timestamp_counter <= timestamp_counter + 1;
                case state is
                    when IDLE =>
                        uart_tx_valid_int <= '0';
                        byte_index <= 0;
                        
                        -- Priority: Add Order > Execute > Cancel > Stats
                        if add_order_pending = '1' then
                            state <= SEND_ADD_ORDER;
                            current_send_state <= SEND_ADD_ORDER;
                            msg_counter <= msg_counter + 1;  -- Increment message counter

                            -- Format: "[#XX] [ITCH] Type=A Ref=XXXXXXXXXXXXXXXX B/S=X Shr=XXXXXXXX Sym=XXXXXXXXXXXXXXXX Px=XXXXXXXX\r\n"
                            order_ref_val := unsigned(captured_order_ref);
                            shares_val := unsigned(captured_shares);
                            price_val := unsigned(captured_price);

                            -- Build message buffer
                            idx := 0;
                            -- "[#XX] "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"23"; idx := idx + 1;  -- '#'
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(7 downto 4))); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(3 downto 0))); idx := idx + 1;
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "[ITCH] Type=A "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Ref=" + order reference (16 hex digits)
                            msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(63 downto 60)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(59 downto 56)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(55 downto 52)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(51 downto 48)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(47 downto 44)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(43 downto 40)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(39 downto 36)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(35 downto 32)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "B/S=" + Buy/Sell indicator
                            msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                            msg_buffer(idx) <= x"2F"; idx := idx + 1;  -- '/'
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            if captured_buy_sell = '1' then
                                msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                            else
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            end if;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Shr=" + shares (8 hex digits)
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_shares(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Sym=" + symbol (16 hex digits = 8 ASCII chars)
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(63 downto 60)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(59 downto 56)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(55 downto 52)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(51 downto 48)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(47 downto 44)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(43 downto 40)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(39 downto 36)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(35 downto 32)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_symbol(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Px=" + price (8 hex digits)
                            msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_price(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_price(3 downto 0)); idx := idx + 1;

                            -- Line ending
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- '\r'
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- '\n'

                            msg_length <= idx;
                        
                        elsif order_executed_pending = '1' then
                            state <= SEND_ORDER_EXECUTED;
                            current_send_state <= SEND_ORDER_EXECUTED;
                            msg_counter <= msg_counter + 1;  -- Increment message counter

                            -- Format: "[#XX] [ITCH] Type=E Ref=XXXXXXXXXXXXXXXX ExecShr=XXXXXXXX Match=XXXXXXXXXXXXXXXX\r\n"
                            idx := 0;
                            -- "[#XX] "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"23"; idx := idx + 1;  -- '#'
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(7 downto 4))); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(3 downto 0))); idx := idx + 1;
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "[ITCH] Type=E "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Ref=" + order reference (16 hex digits)
                            msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(63 downto 60)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(59 downto 56)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(55 downto 52)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(51 downto 48)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(47 downto 44)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(43 downto 40)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(39 downto 36)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(35 downto 32)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "ExecShr=" + executed shares (8 hex digits)
                            msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_exec_shares(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Match=" + match number (16 hex digits)
                            msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                            msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(63 downto 60)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(59 downto 56)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(55 downto 52)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(51 downto 48)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(47 downto 44)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(43 downto 40)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(39 downto 36)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(35 downto 32)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_match_num(3 downto 0)); idx := idx + 1;

                            -- Line ending
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- '\r'
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- '\n'

                            msg_length <= idx;
                        
                        elsif order_cancel_pending = '1' then
                            state <= SEND_ORDER_CANCEL;
                            current_send_state <= SEND_ORDER_CANCEL;
                            msg_counter <= msg_counter + 1;  -- Increment message counter

                            -- Format: "[#XX] [ITCH] Type=X Ref=XXXXXXXXXXXXXXXX CxlShr=XXXXXXXX\r\n"
                            idx := 0;
                            -- "[#XX] "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"23"; idx := idx + 1;  -- '#'
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(7 downto 4))); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(3 downto 0))); idx := idx + 1;
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "[ITCH] Type=X "
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= x"58"; idx := idx + 1;  -- 'X'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Ref=" + order reference (16 hex digits)
                            msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(63 downto 60)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(59 downto 56)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(55 downto 52)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(51 downto 48)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(47 downto 44)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(43 downto 40)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(39 downto 36)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(35 downto 32)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_order_ref(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "CxlShr=" + cancelled shares (8 hex digits)
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(captured_cancel_shares(3 downto 0)); idx := idx + 1;

                            -- Line ending
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- '\r'
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- '\n'

                            msg_length <= idx;
                        
                        elsif stats_pending = '1' then
                            state <= SEND_STATS_ST;
                            current_send_state <= SEND_STATS_ST;
                            
                            -- Format: "[STATS] Messages received\r\n" (simplified)
                            idx := 0;
                            msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                            msg_buffer(idx) <= x"4B"; idx := idx + 1;  -- 'K'
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- '\r'
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- '\n'
                            
                            msg_length <= idx;
                        end if;
                    
                    when SEND_ADD_ORDER | SEND_ORDER_EXECUTED | SEND_ORDER_CANCEL | SEND_STATS_ST =>
                        -- Send bytes from buffer
                        if byte_index < msg_length then
                            if uart_tx_ready = '1' and uart_tx_valid_int = '0' then
                                -- UART ready and byte not started yet
                                uart_tx_data <= msg_buffer(byte_index);
                                uart_tx_valid_int <= '1';  -- Pulse start
                            elsif uart_tx_valid_int = '1' then
                                -- Start pulsed, now clear it and wait for transmission
                                uart_tx_valid_int <= '0';
                                state <= WAIT_TX;
                            end if;
                        else
                            -- All bytes sent
                            uart_tx_valid_int <= '0';
                            state <= IDLE;
                        end if;

                    when WAIT_TX =>
                        -- Wait for UART transmission to complete
                        uart_tx_valid_int <= '0';  -- Ensure valid stays low
                        if uart_tx_ready = '1' then
                            -- Transmission complete, move to next byte
                            byte_index <= byte_index + 1;

                            -- Return to send state for next byte (or IDLE if done)
                            if byte_index + 1 >= msg_length then
                                -- Last byte was sent
                                state <= IDLE;
                            else
                                -- More bytes to send - return to the previous SEND_* state
                                state <= current_send_state;
                            end if;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Connect internal signal to output port
    uart_tx_valid <= uart_tx_valid_int;

end Behavioral;
