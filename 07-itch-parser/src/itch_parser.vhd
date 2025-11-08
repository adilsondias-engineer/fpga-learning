--------------------------------------------------------------------------------
-- Module: itch_parser
-- Description: ITCH 5.0 protocol parser for Nasdaq market data
--              Parses binary ITCH messages from UDP payload stream
--              Uses ODD byte_counter values (1,3,5,7...) due to MII timing
--
-- Message Format:
--   [Type:1][Fields:variable]
--
-- Implemented Message Types:
--   'A' (0x41): Add Order - no MPID (36 bytes)
--   'E' (0x45): Order Executed (31 bytes)
--   'X' (0x58): Order Cancel (23 bytes)
--
-- Additional message types can be added following the same odd byte_counter pattern.
-- All multi-byte fields are big-endian (network byte order).
--
-- MII Timing Note:
--   MII outputs bytes every 2 clock cycles. When transitioning from IDLE to
--   COUNT_BYTES, the type byte remains visible for 1 extra cycle. Therefore,
--   all data byte extraction uses ODD byte_counter values (1,3,5,7...).
--   Formula: Physical byte N = byte_counter = 2*N - 1
--------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity itch_parser is
    Port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;
        
        -- UDP payload interface (from udp_parser)
        udp_payload_valid   : in  std_logic;  -- UDP payload byte valid
        udp_payload_data    : in  std_logic_vector(7 downto 0);  -- Payload byte
        udp_payload_start   : in  std_logic;  -- First byte of UDP payload
        udp_payload_end     : in  std_logic;  -- Last byte of UDP payload
        
        -- Parsed message outputs
        msg_valid           : out std_logic;  -- Complete message parsed
        msg_type            : out std_logic_vector(7 downto 0);  -- Message type
        msg_error           : out std_logic;  -- Parse error (unknown type, truncated)
        
        -- Add Order ('A') fields
        add_order_valid     : out std_logic;
        stock_locate        : out std_logic_vector(15 downto 0);  -- Stock locate (bytes 1-2)
        tracking_number     : out std_logic_vector(15 downto 0);  -- Tracking number (bytes 3-4)
        timestamp           : out std_logic_vector(47 downto 0);  -- Timestamp (bytes 5-10, 6 bytes)
        order_ref           : out std_logic_vector(63 downto 0);  -- Order reference number
        buy_sell            : out std_logic;  -- '1'=Buy, '0'=Sell
        shares              : out std_logic_vector(31 downto 0);  -- Share quantity
        symbol              : out std_logic_vector(63 downto 0);  -- 8-char symbol
        price               : out std_logic_vector(31 downto 0);  -- Price (1/10000 dollars)
        
        -- Order Executed ('E') fields
        order_executed_valid : out std_logic;
        exec_shares          : out std_logic_vector(31 downto 0);  -- Executed shares
        match_number         : out std_logic_vector(63 downto 0);  -- Match number
        
        -- Order Cancel ('X') fields
        order_cancel_valid  : out std_logic;
        cancel_shares       : out std_logic_vector(31 downto 0);  -- Cancelled shares
        
        -- Statistics
        total_messages      : out std_logic_vector(31 downto 0);
        parse_errors        : out std_logic_vector(15 downto 0);

        -- Debug outputs (48 signals total - used for byte alignment debugging during MII timing discovery)
        -- NOTE: These can be removed to simplify the design once system is verified stable.
        --       Removal requires updating: mii_eth_top.vhd, uart_itch_formatter.vhd
        -- Debug outputs (for debugging byte alignment)
        debug_byte_counter  : out std_logic_vector(7 downto 0);  -- Current byte counter value
        debug_order_ref_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter when capturing order_ref bytes
        debug_order_ref_byte_val : out std_logic_vector(7 downto 0);  -- Data value when capturing order_ref bytes
        debug_buy_sell_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter when capturing buy_sell
        debug_buy_sell_byte_val : out std_logic_vector(7 downto 0);  -- Data value when capturing buy_sell
        debug_shares_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter when capturing shares bytes
        debug_shares_byte_val : out std_logic_vector(7 downto 0);  -- Data value when capturing shares bytes
        debug_symbol_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter when capturing symbol bytes
        debug_symbol_byte_val : out std_logic_vector(7 downto 0);  -- Data value when capturing symbol bytes
        debug_price_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter when capturing price bytes
        debug_price_byte_val : out std_logic_vector(7 downto 0);  -- Data value when capturing price bytes
        debug_order_ref_first_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for FIRST byte of order_ref
        debug_order_ref_first_byte_val : out std_logic_vector(7 downto 0);  -- Data value for FIRST byte of order_ref
        debug_shares_first_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for FIRST byte of shares
        debug_shares_first_byte_val : out std_logic_vector(7 downto 0);  -- Data value for FIRST byte of shares
        debug_current_byte_counter : out std_logic_vector(7 downto 0);  -- Current byte_counter value (for debugging)
        debug_stock_locate_first_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for FIRST byte of stock_locate
        debug_stock_locate_first_byte_val : out std_logic_vector(7 downto 0);  -- Data value for FIRST byte of stock_locate
        debug_stock_locate_last_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for LAST byte of stock_locate
        debug_stock_locate_last_byte_val : out std_logic_vector(7 downto 0);  -- Data value for LAST byte of stock_locate
        debug_tracking_first_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for FIRST byte of tracking_number
        debug_tracking_first_byte_val : out std_logic_vector(7 downto 0);  -- Data value for FIRST byte of tracking_number
        debug_tracking_last_byte_cnt : out std_logic_vector(7 downto 0);  -- Byte counter for LAST byte of tracking_number
        debug_tracking_last_byte_val : out std_logic_vector(7 downto 0);  -- Data value for LAST byte of tracking_number
        debug_current_payload_data : out std_logic_vector(7 downto 0);  -- Current udp_payload_data value (for debugging)
        debug_byte2_payload_data : out std_logic_vector(7 downto 0);  -- payload_data when byte_counter=1 (byte 2)
        debug_byte3_payload_data : out std_logic_vector(7 downto 0);  -- payload_data when byte_counter=2 (byte 3)
        debug_byte2_byte_counter : out std_logic_vector(7 downto 0);  -- byte_counter value when processing byte 2
        debug_byte3_byte_counter : out std_logic_vector(7 downto 0);  -- byte_counter value when processing byte 3
        
        -- Detailed cycle-by-cycle debug (payload history and timing)
        debug_payload_history_0 : out std_logic_vector(7 downto 0);  -- Most recent payload byte
        debug_payload_history_1 : out std_logic_vector(7 downto 0);  -- Previous payload byte
        debug_payload_history_2 : out std_logic_vector(7 downto 0);  -- 2 cycles ago
        debug_payload_history_3 : out std_logic_vector(7 downto 0);  -- 3 cycles ago
        debug_payload_valid_history : out std_logic_vector(7 downto 0);  -- payload_valid history (bit 0 = current, bit 1 = 1 cycle ago, etc.)
        debug_payload_start_history : out std_logic_vector(7 downto 0);  -- payload_start history
        debug_state_encoded : out std_logic_vector(2 downto 0);  -- Encoded state (IDLE=0, READ_TYPE=1, COUNT_BYTES=2, COMPLETE=3, ERROR=4)
        debug_byte_counter_at_valid : out std_logic_vector(7 downto 0);  -- byte_counter value when payload_valid='1'
        debug_processing_cycle : out std_logic;  -- High when processing a byte (payload_valid='1' and state=COUNT_BYTES)
        
        -- Critical debug: Capture exact payload_data values for bytes 1-4
        debug_byte1_data : out std_logic_vector(7 downto 0);  -- payload_data when processing byte 1 (byte_counter=0)
        debug_byte2_data : out std_logic_vector(7 downto 0);  -- payload_data when processing byte 2 (byte_counter=1)
        debug_byte3_data : out std_logic_vector(7 downto 0);  -- payload_data when processing byte 3 (byte_counter=2)
        debug_byte4_data : out std_logic_vector(7 downto 0);  -- payload_data when processing byte 4 (byte_counter=3)
        debug_byte1_counter : out std_logic_vector(7 downto 0);  -- byte_counter when processing byte 1
        debug_byte2_counter : out std_logic_vector(7 downto 0);  -- byte_counter when processing byte 2
        debug_byte3_counter : out std_logic_vector(7 downto 0);  -- byte_counter when processing byte 3
        debug_byte4_counter : out std_logic_vector(7 downto 0)  -- byte_counter when processing byte 4
    );
end itch_parser;

architecture Behavioral of itch_parser is

    -- State machine
    type state_type is (IDLE, READ_TYPE, COUNT_BYTES, COMPLETE, ERROR);
    signal state : state_type := IDLE;

    -- Message parsing
    signal current_msg_type     : std_logic_vector(7 downto 0) := (others => '0');
    signal expected_length      : integer range 0 to 255 := 0;
    signal byte_counter         : integer range 0 to 255 := 0;

    signal payload_bytes_seen     : integer range 0 to 255 := 0;  -- Tracks payload bytes seen

    -- Field extraction registers
    signal stock_locate_reg     : std_logic_vector(15 downto 0) := (others => '0');
    signal tracking_number_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal timestamp_reg        : std_logic_vector(47 downto 0) := (others => '0');
    signal order_ref_reg        : std_logic_vector(63 downto 0) := (others => '0');
    signal buy_sell_reg         : std_logic := '0';
    signal shares_reg           : std_logic_vector(31 downto 0) := (others => '0');
    signal symbol_reg           : std_logic_vector(63 downto 0) := (others => '0');
    signal price_reg            : std_logic_vector(31 downto 0) := (others => '0');
    signal exec_shares_reg      : std_logic_vector(31 downto 0) := (others => '0');
    signal match_number_reg     : std_logic_vector(63 downto 0) := (others => '0');
    signal cancel_shares_reg    : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Statistics
    signal msg_counter          : unsigned(31 downto 0) := (others => '0');
    signal error_counter        : unsigned(15 downto 0) := (others => '0');
    
    -- Debug signals (for debugging byte alignment)
    signal debug_order_ref_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_order_ref_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_buy_sell_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_buy_sell_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_shares_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_shares_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_symbol_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_symbol_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_price_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_price_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_order_ref_first_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_order_ref_first_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_shares_first_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_shares_first_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_stock_locate_first_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_stock_locate_first_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_stock_locate_last_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_stock_locate_last_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_tracking_first_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_tracking_first_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_tracking_last_byte_cnt_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_tracking_last_byte_val_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_current_payload_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte2_payload_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte3_payload_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte2_byte_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte3_byte_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Detailed cycle-by-cycle debug signals
    signal debug_payload_history_0_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_payload_history_1_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_payload_history_2_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_payload_history_3_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_payload_valid_history_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_payload_start_history_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_state_encoded_reg : std_logic_vector(2 downto 0) := (others => '0');
    signal debug_byte_counter_at_valid_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_processing_cycle_reg : std_logic := '0';
    
    -- Critical debug: Capture exact payload_data for bytes 1-4
    signal debug_byte1_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte2_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte3_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte4_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte1_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte2_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte3_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal debug_byte4_counter_reg : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Function: Get expected message length based on type
    function get_msg_length(msg_type: std_logic_vector(7 downto 0)) return integer is
    begin
        case msg_type is
            when x"53" => return 12;  -- 'S' System Event
            when x"52" => return 39;  -- 'R' Stock Directory
            when x"41" => return 36;  -- 'A' Add Order (no MPID)
            when x"46" => return 40;  -- 'F' Add Order (with MPID)
            when x"45" => return 31;  -- 'E' Order Executed
            when x"43" => return 36;  -- 'C' Order Executed with Price
            when x"58" => return 23;  -- 'X' Order Cancel
            when x"44" => return 19;  -- 'D' Order Delete
            when x"55" => return 35;  -- 'U' Order Replace
            when x"50" => return 44;  -- 'P' Trade (non-cross)
            when x"51" => return 40;  -- 'Q' Cross Trade
            when others => return 0;  -- Unknown message type
        end case;
    end function;

begin

    -- Main parser state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                current_msg_type <= (others => '0');
                expected_length <= 0;
                byte_counter <= 0;
                payload_bytes_seen <= 0;
                msg_valid <= '0';
                msg_error <= '0';
                add_order_valid <= '0';
                order_executed_valid <= '0';
                order_cancel_valid <= '0';
                msg_counter <= (others => '0');
                error_counter <= (others => '0');
                
                -- Reset debug signals
                debug_payload_history_0_reg <= (others => '0');
                debug_payload_history_1_reg <= (others => '0');
                debug_payload_history_2_reg <= (others => '0');
                debug_payload_history_3_reg <= (others => '0');
                debug_payload_valid_history_reg <= (others => '0');
                debug_payload_start_history_reg <= (others => '0');
                debug_state_encoded_reg <= (others => '0');
                debug_byte_counter_at_valid_reg <= (others => '0');
                debug_processing_cycle_reg <= '0';
                -- Reset critical debug signals
                debug_byte1_data_reg <= (others => '0');
                debug_byte2_data_reg <= (others => '0');
                debug_byte3_data_reg <= (others => '0');
                debug_byte4_data_reg <= (others => '0');
                debug_byte1_counter_reg <= (others => '0');
                debug_byte2_counter_reg <= (others => '0');
                debug_byte3_counter_reg <= (others => '0');
                debug_byte4_counter_reg <= (others => '0');
                
            else
                -- Default outputs (but hold valid signals during CDC hold period)
                msg_valid <= '0';
                msg_error <= '0';
                
                -- Debug: Capture payload history (shift register)
                debug_payload_history_3_reg <= debug_payload_history_2_reg;
                debug_payload_history_2_reg <= debug_payload_history_1_reg;
                debug_payload_history_1_reg <= debug_payload_history_0_reg;
                if udp_payload_valid = '1' then
                    debug_payload_history_0_reg <= udp_payload_data;
                end if;
                
                -- Debug: Capture payload_valid and payload_start history (shift register)
                debug_payload_valid_history_reg(7 downto 1) <= debug_payload_valid_history_reg(6 downto 0);
                debug_payload_valid_history_reg(0) <= udp_payload_valid;
                debug_payload_start_history_reg(7 downto 1) <= debug_payload_start_history_reg(6 downto 0);
                debug_payload_start_history_reg(0) <= udp_payload_start;
                
                -- Debug: Encode state
                case state is
                    when IDLE => debug_state_encoded_reg <= "000";
                    when READ_TYPE => debug_state_encoded_reg <= "001";
                    when COUNT_BYTES => debug_state_encoded_reg <= "010";
                    when COMPLETE => debug_state_encoded_reg <= "011";
                    when ERROR => debug_state_encoded_reg <= "100";
                    when others => debug_state_encoded_reg <= "000";
                end case;
                
                -- Debug: Capture byte_counter when payload_valid is high
                if udp_payload_valid = '1' then
                    debug_byte_counter_at_valid_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                end if;
                
                -- Debug: Indicates when processing a byte
                if udp_payload_valid = '1' and state = COUNT_BYTES and udp_payload_start = '0' then
                    debug_processing_cycle_reg <= '1';
                else
                    debug_processing_cycle_reg <= '0';
                end if;

                -- Default: clear valid signals (will be set in COMPLETE state for 1 cycle)
                add_order_valid <= '0';
                order_executed_valid <= '0';
                order_cancel_valid <= '0';

                case state is
                    when IDLE =>
                        -- Wait for start of UDP payload (ONLY use direct pulse)
                        if udp_payload_start = '1' and udp_payload_valid = '1' then
                            -- udp_payload_data is byte 0 (type byte) on this cycle
                            current_msg_type <= udp_payload_data;
                            expected_length <= get_msg_length(udp_payload_data);
                            byte_counter <= 0;  -- Will process first data byte (byte 1) on next cycle

                            -- Clear field registers for new message
                            stock_locate_reg <= (others => '0');
                            tracking_number_reg <= (others => '0');
                            timestamp_reg <= (others => '0');
                            order_ref_reg <= (others => '0');
                            buy_sell_reg <= '0';
                            shares_reg <= (others => '0');
                            symbol_reg <= (others => '0');
                            price_reg <= (others => '0');

                            -- Check if valid message type
                            if get_msg_length(udp_payload_data) = 0 then
                                state <= ERROR;
                            else
                                state <= COUNT_BYTES;
                            end if;
                        end if;

                    when READ_TYPE =>
                        -- This state is now unused - handled in IDLE
                        state <= IDLE;
                    
                    when COUNT_BYTES =>
                        -- Count remaining bytes and extract fields
                        -- payload_data is combinational from UDP parser, aligned with byte_index
                        -- Debug: Always capture current payload data when valid (for debugging)
                        if udp_payload_valid = '1' then
                            debug_current_payload_data_reg <= udp_payload_data;
                        end if;
                        
                        -- Process all payload bytes
                        -- CRITICAL FIX: MII outputs bytes every 2 cycles, data stable for 2 cycles
                        -- When transitioning from IDLE to COUNT_BYTES, type byte is still visible for 1 more cycle
                        -- byte_counter=0: Still showing type byte (SKIP!)
                        -- byte_counter=1: Stock Locate MSB appears
                        -- byte_counter=3: Stock Locate LSB appears
                        -- byte_counter=5: Tracking MSB appears
                        -- Solution: Process on ODD byte_counter values starting from 1 (1, 3, 5, 7...)
                        if udp_payload_valid = '1' then
                            -- Extract fields ONLY on odd byte_counter >= 1 (to skip type byte repetition)
                            -- byte_counter=1 = byte 1 (Stock Loc high)
                            -- byte_counter=3 = byte 2 (Stock Loc low)
                            -- byte_counter=5 = byte 3 (Track high)
                            -- byte_counter=7 = byte 4 (Track low)
                            if current_msg_type = x"41" and byte_counter >= 1 and (byte_counter mod 2) = 1 then
                                -- Stock Locate: bytes 1-2 (2 bytes, big-endian)
                                if byte_counter = 1 then
                                    stock_locate_reg(15 downto 8) <= udp_payload_data;
                                    debug_stock_locate_first_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_stock_locate_first_byte_val_reg <= udp_payload_data;
                                    debug_byte1_data_reg <= udp_payload_data;
                                    debug_byte1_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                elsif byte_counter = 3 then
                                    stock_locate_reg(7 downto 0) <= udp_payload_data;
                                    debug_stock_locate_last_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_stock_locate_last_byte_val_reg <= udp_payload_data;
                                    debug_byte2_payload_data_reg <= udp_payload_data;
                                    debug_byte2_byte_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_byte2_data_reg <= udp_payload_data;
                                    debug_byte2_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));

                                -- Tracking Number: bytes 3-4 (2 bytes, big-endian)
                                elsif byte_counter = 5 then
                                    tracking_number_reg(15 downto 8) <= udp_payload_data;
                                    debug_tracking_first_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_tracking_first_byte_val_reg <= udp_payload_data;
                                    debug_byte3_payload_data_reg <= udp_payload_data;
                                    debug_byte3_byte_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_byte3_data_reg <= udp_payload_data;
                                    debug_byte3_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                elsif byte_counter = 7 then
                                    tracking_number_reg(7 downto 0) <= udp_payload_data;
                                    debug_tracking_last_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_tracking_last_byte_val_reg <= udp_payload_data;
                                    debug_byte4_data_reg <= udp_payload_data;
                                    debug_byte4_counter_reg <= std_logic_vector(to_unsigned(byte_counter, 8));

                                -- Timestamp: bytes 5-10 (6 bytes, big-endian)
                                elsif byte_counter = 9 then
                                    timestamp_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 11 then
                                    timestamp_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 13 then
                                    timestamp_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 15 then
                                    timestamp_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 17 then
                                    timestamp_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 19 then
                                    timestamp_reg(7 downto 0) <= udp_payload_data;

                                -- Order Reference: bytes 11-18 (8 bytes, big-endian)
                                elsif byte_counter = 21 then
                                    order_ref_reg(63 downto 56) <= udp_payload_data;
                                    -- Capture debug info for FIRST byte of order_ref
                                    debug_order_ref_first_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_order_ref_first_byte_val_reg <= udp_payload_data;
                                elsif byte_counter = 23 then
                                    order_ref_reg(55 downto 48) <= udp_payload_data;
                                elsif byte_counter = 25 then
                                    order_ref_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 27 then
                                    order_ref_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 29 then
                                    order_ref_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 31 then
                                    order_ref_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 33 then
                                    order_ref_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 35 then
                                    order_ref_reg(7 downto 0) <= udp_payload_data;
                                    -- Capture debug info for LAST byte of order_ref
                                    debug_order_ref_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_order_ref_byte_val_reg <= udp_payload_data;

                                -- Buy/Sell: byte 19 ('B'=Buy, 'S'=Sell)
                                elsif byte_counter = 37 then
                                    debug_buy_sell_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_buy_sell_byte_val_reg <= udp_payload_data;
                                    if udp_payload_data = x"42" then  -- 'B'
                                        buy_sell_reg <= '1';
                                    else  -- 'S' or other
                                        buy_sell_reg <= '0';
                                    end if;

                                -- Shares: bytes 20-23 (4 bytes, big-endian)
                                elsif byte_counter = 39 then
                                    shares_reg(31 downto 24) <= udp_payload_data;
                                    -- Capture debug info for FIRST byte of shares
                                    debug_shares_first_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_shares_first_byte_val_reg <= udp_payload_data;
                                elsif byte_counter = 41 then
                                    shares_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 43 then
                                    shares_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 45 then
                                    shares_reg(7 downto 0) <= udp_payload_data;
                                    -- Capture debug info for LAST byte of shares
                                    debug_shares_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_shares_byte_val_reg <= udp_payload_data;

                                -- Symbol: bytes 24-31 (8 bytes, ASCII)
                                elsif byte_counter = 47 then
                                    symbol_reg(63 downto 56) <= udp_payload_data;
                                elsif byte_counter = 49 then
                                    symbol_reg(55 downto 48) <= udp_payload_data;
                                elsif byte_counter = 51 then
                                    symbol_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 53 then
                                    symbol_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 55 then
                                    symbol_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 57 then
                                    symbol_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 59 then
                                    symbol_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 61 then
                                    symbol_reg(7 downto 0) <= udp_payload_data;
                                    -- Capture debug info for LAST byte of symbol
                                    debug_symbol_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_symbol_byte_val_reg <= udp_payload_data;

                                -- Price: bytes 32-35 (4 bytes, big-endian, 1/10000 dollars)
                                elsif byte_counter = 63 then
                                    price_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 65 then
                                    price_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 67 then
                                    price_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 69 then
                                    price_reg(7 downto 0) <= udp_payload_data;
                                    -- Capture debug info for LAST byte of price
                                    debug_price_byte_cnt_reg <= std_logic_vector(to_unsigned(byte_counter, 8));
                                    debug_price_byte_val_reg <= udp_payload_data;
                                end if;

                            -- Order Executed ('E' = 0x45) field extraction
                            elsif current_msg_type = x"45" and byte_counter >= 1 and (byte_counter mod 2) = 1 then
                                -- Order Reference: bytes 11-18 (8 bytes, big-endian)
                                if byte_counter = 21 then
                                    order_ref_reg(63 downto 56) <= udp_payload_data;
                                elsif byte_counter = 23 then
                                    order_ref_reg(55 downto 48) <= udp_payload_data;
                                elsif byte_counter = 25 then
                                    order_ref_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 27 then
                                    order_ref_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 29 then
                                    order_ref_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 31 then
                                    order_ref_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 33 then
                                    order_ref_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 35 then
                                    order_ref_reg(7 downto 0) <= udp_payload_data;

                                -- Executed Shares: bytes 19-22 (4 bytes, big-endian)
                                elsif byte_counter = 37 then
                                    exec_shares_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 39 then
                                    exec_shares_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 41 then
                                    exec_shares_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 43 then
                                    exec_shares_reg(7 downto 0) <= udp_payload_data;

                                -- Match Number: bytes 23-30 (8 bytes, big-endian)
                                elsif byte_counter = 45 then
                                    match_number_reg(63 downto 56) <= udp_payload_data;
                                elsif byte_counter = 47 then
                                    match_number_reg(55 downto 48) <= udp_payload_data;
                                elsif byte_counter = 49 then
                                    match_number_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 51 then
                                    match_number_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 53 then
                                    match_number_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 55 then
                                    match_number_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 57 then
                                    match_number_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 59 then
                                    match_number_reg(7 downto 0) <= udp_payload_data;
                                end if;

                            -- Order Cancel ('X' = 0x58) field extraction
                            elsif current_msg_type = x"58" and byte_counter >= 1 and (byte_counter mod 2) = 1 then
                                -- Order Reference: bytes 11-18 (8 bytes, big-endian)
                                if byte_counter = 21 then
                                    order_ref_reg(63 downto 56) <= udp_payload_data;
                                elsif byte_counter = 23 then
                                    order_ref_reg(55 downto 48) <= udp_payload_data;
                                elsif byte_counter = 25 then
                                    order_ref_reg(47 downto 40) <= udp_payload_data;
                                elsif byte_counter = 27 then
                                    order_ref_reg(39 downto 32) <= udp_payload_data;
                                elsif byte_counter = 29 then
                                    order_ref_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 31 then
                                    order_ref_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 33 then
                                    order_ref_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 35 then
                                    order_ref_reg(7 downto 0) <= udp_payload_data;

                                -- Cancelled Shares: bytes 19-22 (4 bytes, big-endian)
                                elsif byte_counter = 37 then
                                    cancel_shares_reg(31 downto 24) <= udp_payload_data;
                                elsif byte_counter = 39 then
                                    cancel_shares_reg(23 downto 16) <= udp_payload_data;
                                elsif byte_counter = 41 then
                                    cancel_shares_reg(15 downto 8) <= udp_payload_data;
                                elsif byte_counter = 43 then
                                    cancel_shares_reg(7 downto 0) <= udp_payload_data;
                                end if;
                            end if;

                            -- ALWAYS increment byte counter for EVERY valid payload byte
                            -- Ensures byte_counter tracks absolute position, even for bytes not extracted
                            -- CRITICAL: Increment AFTER processing, so byte_counter reflects the byte just processed
                            byte_counter <= byte_counter + 1;

                            -- Check if message complete (check AFTER increment)
                            -- MII outputs bytes every 2 cycles, byte_counter increments every cycle
                            -- For a 36-byte message: expected_length=36 (type + 35 data bytes)
                            -- byte_counter goes 0,1,2,3,4,5...67,68,69,70 (process on odd: 1,3,5...67,69)
                            -- Byte 35 (last data byte) is processed at counter=69 (odd)
                            -- After processing and incrementing: byte_counter = 70
                            -- When byte_counter >= 2*(expected_length - 1) = 70, all data bytes processed
                            if byte_counter >= 2 * (expected_length - 1) then
                                state <= COMPLETE;
                            end if;
                        end if;
                        
                        -- Check for premature end
                        -- byte_counter starts at 0, so after increment it goes 1, 2, 3, ..., expected_length-1
                        -- For a 36-byte message: expected_length=36, bytes are 0-35
                        -- After processing byte 35, byte_counter will be 35, then increment to 36
                        -- If payload_end comes when (byte_counter + 1) < expected_length, not all bytes processed
                        if udp_payload_end = '1' and (byte_counter + 1) < expected_length then
                            state <= ERROR;
                        end if;
                    
                    when COMPLETE =>
                        -- Message successfully parsed
                        msg_valid <= '1';
                        -- msg_type is already assigned from current_msg_type in output assignments
                        msg_counter <= msg_counter + 1;

                        -- Set type-specific valid signals (1-cycle pulse)
                        if current_msg_type = x"41" then
                            add_order_valid <= '1';
                        elsif current_msg_type = x"45" then
                            order_executed_valid <= '1';
                        elsif current_msg_type = x"58" then
                            order_cancel_valid <= '1';
                        end if;

                        state <= IDLE;
                    
                    when ERROR =>
                        -- Parse error occurred
                        msg_error <= '1';
                        error_counter <= error_counter + 1;
                        state <= IDLE;
                    
                    when others =>
                        state <= IDLE;
                end case;

                -- Force return to IDLE on UDP payload end (but not if just completed)
                if udp_payload_end = '1' then
                    if state /= COMPLETE and state /= IDLE and state /= ERROR then
                        -- Check if completing this cycle (avoid race condition)
                        -- Completes when (byte_counter + 1) >= expected_length (after processing all data bytes 1 to expected_length-1)
                        if not (state = COUNT_BYTES and (byte_counter + 1) >= expected_length) then
                            msg_error <= '1';
                            error_counter <= error_counter + 1;
                            state <= IDLE;
                        end if;
                    elsif state = IDLE then
                        state <= IDLE;
                    end if;
                end if;
                
            end if;
        end if;
    end process;
    
    -- Output assignments
    msg_type <= current_msg_type;  -- Always show current message type (even if not complete)
    stock_locate <= stock_locate_reg;
    tracking_number <= tracking_number_reg;
    timestamp <= timestamp_reg;
    order_ref <= order_ref_reg;
    buy_sell <= buy_sell_reg;
    shares <= shares_reg;
    symbol <= symbol_reg;
    price <= price_reg;
    exec_shares <= exec_shares_reg;
    match_number <= match_number_reg;
    cancel_shares <= cancel_shares_reg;
    total_messages <= std_logic_vector(msg_counter);
    parse_errors <= std_logic_vector(error_counter);
    
    -- Debug output assignments
    debug_byte_counter <= std_logic_vector(to_unsigned(byte_counter, 8));
    debug_order_ref_byte_cnt <= debug_order_ref_byte_cnt_reg;
    debug_order_ref_byte_val <= debug_order_ref_byte_val_reg;
    debug_buy_sell_byte_cnt <= debug_buy_sell_byte_cnt_reg;
    debug_buy_sell_byte_val <= debug_buy_sell_byte_val_reg;
    debug_shares_byte_cnt <= debug_shares_byte_cnt_reg;
    debug_shares_byte_val <= debug_shares_byte_val_reg;
    debug_symbol_byte_cnt <= debug_symbol_byte_cnt_reg;
    debug_symbol_byte_val <= debug_symbol_byte_val_reg;
    debug_price_byte_cnt <= debug_price_byte_cnt_reg;
    debug_price_byte_val <= debug_price_byte_val_reg;
    debug_order_ref_first_byte_cnt <= debug_order_ref_first_byte_cnt_reg;
    debug_order_ref_first_byte_val <= debug_order_ref_first_byte_val_reg;
    debug_shares_first_byte_cnt <= debug_shares_first_byte_cnt_reg;
    debug_shares_first_byte_val <= debug_shares_first_byte_val_reg;
    debug_current_byte_counter <= std_logic_vector(to_unsigned(byte_counter, 8));
    debug_stock_locate_first_byte_cnt <= debug_stock_locate_first_byte_cnt_reg;
    debug_stock_locate_first_byte_val <= debug_stock_locate_first_byte_val_reg;
    debug_stock_locate_last_byte_cnt <= debug_stock_locate_last_byte_cnt_reg;
    debug_stock_locate_last_byte_val <= debug_stock_locate_last_byte_val_reg;
    debug_tracking_first_byte_cnt <= debug_tracking_first_byte_cnt_reg;
    debug_tracking_first_byte_val <= debug_tracking_first_byte_val_reg;
    debug_tracking_last_byte_cnt <= debug_tracking_last_byte_cnt_reg;
    debug_tracking_last_byte_val <= debug_tracking_last_byte_val_reg;
    debug_current_payload_data <= debug_current_payload_data_reg;
    debug_byte2_payload_data <= debug_byte2_payload_data_reg;
    debug_byte3_payload_data <= debug_byte3_payload_data_reg;
    debug_byte2_byte_counter <= debug_byte2_byte_counter_reg;
    debug_byte3_byte_counter <= debug_byte3_byte_counter_reg;
    
    -- Detailed cycle-by-cycle debug outputs
    debug_payload_history_0 <= debug_payload_history_0_reg;
    debug_payload_history_1 <= debug_payload_history_1_reg;
    debug_payload_history_2 <= debug_payload_history_2_reg;
    debug_payload_history_3 <= debug_payload_history_3_reg;
    debug_payload_valid_history <= debug_payload_valid_history_reg;
    debug_payload_start_history <= debug_payload_start_history_reg;
    debug_state_encoded <= debug_state_encoded_reg;
    debug_byte_counter_at_valid <= debug_byte_counter_at_valid_reg;
    debug_processing_cycle <= debug_processing_cycle_reg;
    
    -- Critical debug outputs
    debug_byte1_data <= debug_byte1_data_reg;
    debug_byte2_data <= debug_byte2_data_reg;
    debug_byte3_data <= debug_byte3_data_reg;
    debug_byte4_data <= debug_byte4_data_reg;
    debug_byte1_counter <= debug_byte1_counter_reg;
    debug_byte2_counter <= debug_byte2_counter_reg;
    debug_byte3_counter <= debug_byte3_counter_reg;
    debug_byte4_counter <= debug_byte4_counter_reg;

end Behavioral;
