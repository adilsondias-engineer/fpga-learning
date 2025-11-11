--------------------------------------------------------------------------------
-- Module: itch_msg_encoder
-- Description: Encodes ITCH messages from parser into serialized format for FIFO
--              Sits between itch_parser and async_fifo
--              Captures messages when valid signals are asserted and writes to FIFO
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.itch_msg_pkg.all;

entity itch_msg_encoder is
    Port (
        clk : in std_logic;
        rst : in std_logic;

        -- From itch_parser
        add_order_valid : in std_logic;
        order_executed_valid : in std_logic;
        order_cancel_valid : in std_logic;
        system_event_valid : in std_logic;
        stock_directory_valid : in std_logic;
        order_delete_valid : in std_logic;
        order_replace_valid : in std_logic;
        trade_valid : in std_logic;
        cross_trade_valid : in std_logic;

        -- Message data
        stock_locate : in std_logic_vector(15 downto 0);
        tracking_number : in std_logic_vector(15 downto 0);
        timestamp : in std_logic_vector(47 downto 0);
        order_ref : in std_logic_vector(63 downto 0);
        buy_sell : in std_logic;
        shares : in std_logic_vector(31 downto 0);
        stock_symbol : in std_logic_vector(63 downto 0);
        price : in std_logic_vector(31 downto 0);
        exec_shares : in std_logic_vector(31 downto 0);
        match_number : in std_logic_vector(63 downto 0);
        cancel_shares : in std_logic_vector(31 downto 0);
        event_code : in std_logic_vector(7 downto 0);
        market_category : in std_logic_vector(7 downto 0);
        financial_status : in std_logic_vector(7 downto 0);
        round_lot_size : in std_logic_vector(31 downto 0);

        -- New message type fields
        original_order_ref : in std_logic_vector(63 downto 0);
        new_order_ref : in std_logic_vector(63 downto 0);
        new_shares : in std_logic_vector(31 downto 0);
        new_price : in std_logic_vector(31 downto 0);
        trade_price : in std_logic_vector(31 downto 0);
        cross_shares : in std_logic_vector(63 downto 0);
        cross_price : in std_logic_vector(31 downto 0);
        cross_type : in std_logic_vector(7 downto 0);

        -- To async FIFO
        fifo_wr_en : out std_logic;
        fifo_wr_data : out std_logic_vector(MSG_FIFO_WIDTH-1 downto 0);
        fifo_wr_full : in std_logic;

        -- Overflow diagnostics
        overflow_error : out std_logic;  -- Pulses when message lost due to full buffers
        overflow_count : out std_logic_vector(15 downto 0)  -- Count of lost messages
    );
end itch_msg_encoder;

architecture Behavioral of itch_msg_encoder is
    -- Message buffer (holds message until it can be written to FIFO)
    type msg_buffer_type is record
        valid : std_logic;
        msg_type : std_logic_vector(MSG_TYPE_BITS-1 downto 0);
        msg_data : std_logic_vector(MSG_DATA_BITS-1 downto 0);
    end record;
    signal msg_buffer : msg_buffer_type := (
        valid => '0',
        msg_type => (others => '0'),
        msg_data => (others => '0')
    );

    -- Capture register: Always capture valid messages immediately, regardless of FIFO state
    signal captured_msg : msg_buffer_type := (
        valid => '0',
        msg_type => (others => '0'),
        msg_data => (others => '0')
    );

    -- Overflow detection
    signal overflow_count_reg : unsigned(15 downto 0) := (others => '0');
    signal overflow_error_reg : std_logic := '0';
begin

    -- Output overflow signals
    overflow_count <= std_logic_vector(overflow_count_reg);
    overflow_error <= overflow_error_reg;

    process(clk)
        variable msg_data_var : std_logic_vector(MSG_DATA_BITS-1 downto 0);
        variable msg_type_enc_var : std_logic_vector(MSG_TYPE_BITS-1 downto 0);
        variable has_valid_pulse : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fifo_wr_en <= '0';
                msg_buffer.valid <= '0';
                captured_msg.valid <= '0';
                overflow_count_reg <= (others => '0');
                overflow_error_reg <= '0';
            else
                fifo_wr_en <= '0';
                overflow_error_reg <= '0';  -- Clear error pulse (asserts for 1 cycle)
                has_valid_pulse := false;
                msg_type_enc_var := (others => '0');
                msg_data_var := (others => '0');

                -- ALWAYS capture valid messages immediately (highest priority)
                -- Ensures no 1-cycle valid pulse is missed
                if add_order_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_ADD_ORDER);
                    msg_data_var := encode_add_order(order_ref, buy_sell, shares, stock_symbol, price,
                                                     stock_locate, tracking_number, timestamp);
                    has_valid_pulse := true;

                elsif order_executed_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_ORDER_EXECUTED);
                    msg_data_var := encode_order_executed(order_ref, exec_shares, match_number);
                    has_valid_pulse := true;

                elsif order_cancel_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_ORDER_CANCEL);
                    msg_data_var := encode_order_cancel(order_ref, cancel_shares);
                    has_valid_pulse := true;

                elsif system_event_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_SYSTEM_EVENT);
                    msg_data_var := encode_system_event(event_code);
                    has_valid_pulse := true;

                elsif stock_directory_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_STOCK_DIRECTORY);
                    msg_data_var := encode_stock_directory(market_category, financial_status,
                                                           round_lot_size, stock_symbol);
                    has_valid_pulse := true;

                elsif order_delete_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_ORDER_DELETE);
                    msg_data_var := encode_order_delete(order_ref);
                    has_valid_pulse := true;

                elsif order_replace_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_ORDER_REPLACE);
                    msg_data_var := encode_order_replace(original_order_ref, new_order_ref,
                                                         new_shares, new_price);
                    has_valid_pulse := true;

                elsif trade_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_TRADE_NON_CROSS);
                    msg_data_var := encode_trade(order_ref, buy_sell, shares, stock_symbol,
                                                 trade_price, match_number);
                    has_valid_pulse := true;

                elsif cross_trade_valid = '1' then
                    msg_type_enc_var := encode_msg_type(MSG_TRADE_CROSS);
                    msg_data_var := encode_cross_trade(cross_shares, stock_symbol, cross_price,
                                                       match_number, cross_type);
                    has_valid_pulse := true;
                end if;

                -- Register captured message (always capture when valid pulse detected)
                if has_valid_pulse then
                    captured_msg.valid <= '1';
                    captured_msg.msg_type <= msg_type_enc_var;
                    captured_msg.msg_data <= msg_data_var;
                end if;

                -- Write logic: Write from buffer first, then from captured message
                if fifo_wr_full = '0' then
                    if msg_buffer.valid = '1' then
                        -- Write buffered message first (was waiting for FIFO space)
                        fifo_wr_data <= msg_buffer.msg_type & msg_buffer.msg_data;
                        fifo_wr_en <= '1';
                        msg_buffer.valid <= '0';
                        
                        -- Move captured message to buffer for next cycle (if exists)
                        if captured_msg.valid = '1' then
                            msg_buffer <= captured_msg;
                            captured_msg.valid <= '0';
                        end if;

                    elsif captured_msg.valid = '1' then
                        -- Write captured message immediately (no buffered message)
                        fifo_wr_data <= captured_msg.msg_type & captured_msg.msg_data;
                        fifo_wr_en <= '1';
                        captured_msg.valid <= '0';
                    end if;

                elsif captured_msg.valid = '1' then
                    -- FIFO is full - move captured message to buffer
                    if msg_buffer.valid = '0' then
                        msg_buffer <= captured_msg;
                        captured_msg.valid <= '0';
                    else
                        -- OVERFLOW: Both buffer and captured_msg are full, cannot accept new message
                        -- This should NEVER happen with 512-deep FIFO (0.6 seconds of buffering)
                        -- If it does, sustained message rate exceeds UART output rate
                        overflow_error_reg <= '1';
                        if overflow_count_reg /= x"FFFF" then  -- Prevent rollover
                            overflow_count_reg <= overflow_count_reg + 1;
                        end if;
                        -- Drop the captured message (no choice)
                        captured_msg.valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
