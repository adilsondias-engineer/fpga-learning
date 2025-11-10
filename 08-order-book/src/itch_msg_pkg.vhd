--------------------------------------------------------------------------------
-- Package: itch_msg_pkg
-- Description: Shared message types and constants for ITCH parser/formatter
--              Used for async FIFO communication between clock domains
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package itch_msg_pkg is

    -- Message type enumeration
    type msg_type_t is (
        MSG_NONE,
        MSG_SYSTEM_EVENT,      -- S
        MSG_STOCK_DIRECTORY,   -- R
        MSG_ADD_ORDER,         -- A
        MSG_ORDER_EXECUTED,    -- E
        MSG_ORDER_CANCEL,      -- X
        MSG_TRADE_NON_CROSS,   -- P (future)
        MSG_TRADE_CROSS,       -- Q (future)
        MSG_ORDER_REPLACE,     -- U (future)
        MSG_ORDER_DELETE,      -- D (future)
        MSG_STATS
    );

    -- Serialized message for FIFO (fixed width)
    -- Total: 4 bits (msg_type) + 320 bits (data) = 324 bits
    constant MSG_TYPE_BITS : integer := 4;  -- Enough for 16 message types
    constant MSG_DATA_BITS : integer := 320;  -- Max data needed (can adjust)
    constant MSG_FIFO_WIDTH : integer := MSG_TYPE_BITS + MSG_DATA_BITS;

    -- Helper functions to encode/decode message type
    function encode_msg_type(msg_type : msg_type_t) return std_logic_vector;
    function decode_msg_type(encoded : std_logic_vector(MSG_TYPE_BITS-1 downto 0)) return msg_type_t;

    -- Message encoding functions
    function encode_add_order(
        order_ref : std_logic_vector(63 downto 0);
        buy_sell : std_logic;
        shares : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        price : std_logic_vector(31 downto 0);
        stock_locate : std_logic_vector(15 downto 0);
        tracking_number : std_logic_vector(15 downto 0);
        timestamp : std_logic_vector(47 downto 0)
    ) return std_logic_vector;

    function encode_order_executed(
        order_ref : std_logic_vector(63 downto 0);
        exec_shares : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0)
    ) return std_logic_vector;

    function encode_order_cancel(
        order_ref : std_logic_vector(63 downto 0);
        cancel_shares : std_logic_vector(31 downto 0)
    ) return std_logic_vector;

    function encode_system_event(
        event_code : std_logic_vector(7 downto 0)
    ) return std_logic_vector;

    function encode_stock_directory(
        market_category : std_logic_vector(7 downto 0);
        financial_status : std_logic_vector(7 downto 0);
        round_lot_size : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0)
    ) return std_logic_vector;

    function encode_order_delete(
        order_ref : std_logic_vector(63 downto 0)
    ) return std_logic_vector;

    function encode_order_replace(
        original_order_ref : std_logic_vector(63 downto 0);
        new_order_ref : std_logic_vector(63 downto 0);
        new_shares : std_logic_vector(31 downto 0);
        new_price : std_logic_vector(31 downto 0)
    ) return std_logic_vector;

    function encode_trade(
        order_ref : std_logic_vector(63 downto 0);
        buy_sell : std_logic;
        shares : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        trade_price : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0)
    ) return std_logic_vector;

    function encode_cross_trade(
        cross_shares : std_logic_vector(63 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        cross_price : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0);
        cross_type : std_logic_vector(7 downto 0)
    ) return std_logic_vector;

end package itch_msg_pkg;

package body itch_msg_pkg is

    function encode_msg_type(msg_type : msg_type_t) return std_logic_vector is
        variable result : std_logic_vector(MSG_TYPE_BITS-1 downto 0);
    begin
        case msg_type is
            when MSG_NONE            => result := "0000";
            when MSG_SYSTEM_EVENT    => result := "0001";
            when MSG_STOCK_DIRECTORY => result := "0010";
            when MSG_ADD_ORDER       => result := "0011";
            when MSG_ORDER_EXECUTED  => result := "0100";
            when MSG_ORDER_CANCEL    => result := "0101";
            when MSG_TRADE_NON_CROSS => result := "0110";
            when MSG_TRADE_CROSS     => result := "0111";
            when MSG_ORDER_REPLACE   => result := "1000";
            when MSG_ORDER_DELETE    => result := "1001";
            when MSG_STATS           => result := "1111";
            when others              => result := "0000";
        end case;
        return result;
    end function;

    function decode_msg_type(encoded : std_logic_vector(MSG_TYPE_BITS-1 downto 0)) return msg_type_t is
    begin
        case encoded is
            when "0000" => return MSG_NONE;
            when "0001" => return MSG_SYSTEM_EVENT;
            when "0010" => return MSG_STOCK_DIRECTORY;
            when "0011" => return MSG_ADD_ORDER;
            when "0100" => return MSG_ORDER_EXECUTED;
            when "0101" => return MSG_ORDER_CANCEL;
            when "0110" => return MSG_TRADE_NON_CROSS;
            when "0111" => return MSG_TRADE_CROSS;
            when "1000" => return MSG_ORDER_REPLACE;
            when "1001" => return MSG_ORDER_DELETE;
            when "1111" => return MSG_STATS;
            when others => return MSG_NONE;
        end case;
    end function;

    -- Encode Add Order message
    -- Packing: order_ref(64) & buy_sell(1) & shares(32) & stock_symbol(64) & price(32) &
    --          stock_locate(16) & tracking_number(16) & timestamp(48) = 273 bits
    function encode_add_order(
        order_ref : std_logic_vector(63 downto 0);
        buy_sell : std_logic;
        shares : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        price : std_logic_vector(31 downto 0);
        stock_locate : std_logic_vector(15 downto 0);
        tracking_number : std_logic_vector(15 downto 0);
        timestamp : std_logic_vector(47 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := order_ref;
        result(64) := buy_sell;
        result(96 downto 65) := shares;
        result(160 downto 97) := stock_symbol;
        result(192 downto 161) := price;
        result(208 downto 193) := stock_locate;
        result(224 downto 209) := tracking_number;
        result(272 downto 225) := timestamp;
        return result;
    end function;

    -- Encode Order Executed message
    -- Packing: order_ref(64) & exec_shares(32) & match_number(64) = 160 bits
    function encode_order_executed(
        order_ref : std_logic_vector(63 downto 0);
        exec_shares : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := order_ref;
        result(95 downto 64) := exec_shares;
        result(159 downto 96) := match_number;
        return result;
    end function;

    -- Encode Order Cancel message
    -- Packing: order_ref(64) & cancel_shares(32) = 96 bits
    function encode_order_cancel(
        order_ref : std_logic_vector(63 downto 0);
        cancel_shares : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := order_ref;
        result(95 downto 64) := cancel_shares;
        return result;
    end function;

    -- Encode System Event message
    -- Packing: event_code(8) = 8 bits
    function encode_system_event(
        event_code : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(7 downto 0) := event_code;
        return result;
    end function;

    -- Encode Stock Directory message
    -- Packing: market_category(8) & financial_status(8) & round_lot_size(32) & stock_symbol(64) = 112 bits
    function encode_stock_directory(
        market_category : std_logic_vector(7 downto 0);
        financial_status : std_logic_vector(7 downto 0);
        round_lot_size : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(7 downto 0) := market_category;
        result(15 downto 8) := financial_status;
        result(47 downto 16) := round_lot_size;
        result(111 downto 48) := stock_symbol;
        return result;
    end function;

    -- Encode Order Delete message
    -- Packing: order_ref(64) = 64 bits
    function encode_order_delete(
        order_ref : std_logic_vector(63 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := order_ref;
        return result;
    end function;

    -- Encode Order Replace message
    -- Packing: original_order_ref(64) & new_order_ref(64) & new_shares(32) & new_price(32) = 192 bits
    function encode_order_replace(
        original_order_ref : std_logic_vector(63 downto 0);
        new_order_ref : std_logic_vector(63 downto 0);
        new_shares : std_logic_vector(31 downto 0);
        new_price : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := original_order_ref;
        result(127 downto 64) := new_order_ref;
        result(159 downto 128) := new_shares;
        result(191 downto 160) := new_price;
        return result;
    end function;

    -- Encode Trade message
    -- Packing: order_ref(64) & buy_sell(1) & shares(32) & stock_symbol(64) & trade_price(32) & match_number(64) = 257 bits
    function encode_trade(
        order_ref : std_logic_vector(63 downto 0);
        buy_sell : std_logic;
        shares : std_logic_vector(31 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        trade_price : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := order_ref;
        result(64) := buy_sell;
        result(96 downto 65) := shares;
        result(160 downto 97) := stock_symbol;
        result(192 downto 161) := trade_price;
        result(256 downto 193) := match_number;
        return result;
    end function;

    -- Encode Cross Trade message
    -- Packing: cross_shares(64) & stock_symbol(64) & cross_price(32) & match_number(64) & cross_type(8) = 232 bits
    function encode_cross_trade(
        cross_shares : std_logic_vector(63 downto 0);
        stock_symbol : std_logic_vector(63 downto 0);
        cross_price : std_logic_vector(31 downto 0);
        match_number : std_logic_vector(63 downto 0);
        cross_type : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(MSG_DATA_BITS-1 downto 0) := (others => '0');
    begin
        result(63 downto 0) := cross_shares;
        result(127 downto 64) := stock_symbol;
        result(159 downto 128) := cross_price;
        result(223 downto 160) := match_number;
        result(231 downto 224) := cross_type;
        return result;
    end function;

end package body itch_msg_pkg;
