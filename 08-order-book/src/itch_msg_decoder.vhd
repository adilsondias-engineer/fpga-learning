--------------------------------------------------------------------------------
-- Module: itch_msg_decoder
-- Description: Decodes ITCH messages from async FIFO for uart_itch_formatter
--              Unpacks serialized message format
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.itch_msg_pkg.all;

entity itch_msg_decoder is
    Port (
        clk : in std_logic;
        rst : in std_logic;

        -- From async FIFO
        fifo_rd_data : in std_logic_vector(MSG_FIFO_WIDTH-1 downto 0);
        fifo_rd_en : in std_logic;  -- Read enable: decode when FIFO read occurs

        -- Decoded message type
        msg_type : out msg_type_t;

        -- Decoded message data
        order_ref : out std_logic_vector(63 downto 0);
        buy_sell : out std_logic;
        shares : out std_logic_vector(31 downto 0);
        stock_symbol : out std_logic_vector(63 downto 0);
        price : out std_logic_vector(31 downto 0);
        stock_locate : out std_logic_vector(15 downto 0);
        tracking_number : out std_logic_vector(15 downto 0);
        timestamp : out std_logic_vector(47 downto 0);
        match_number : out std_logic_vector(63 downto 0);
        event_code : out std_logic_vector(7 downto 0);
        market_category : out std_logic_vector(7 downto 0);
        financial_status : out std_logic_vector(7 downto 0);
        round_lot_size : out std_logic_vector(31 downto 0);

        -- New message type fields
        original_order_ref : out std_logic_vector(63 downto 0);
        new_order_ref : out std_logic_vector(63 downto 0);
        new_shares : out std_logic_vector(31 downto 0);
        new_price : out std_logic_vector(31 downto 0);
        trade_price : out std_logic_vector(31 downto 0);
        cross_shares : out std_logic_vector(63 downto 0);
        cross_price : out std_logic_vector(31 downto 0);
        cross_type : out std_logic_vector(7 downto 0)
    );
end itch_msg_decoder;

architecture Behavioral of itch_msg_decoder is
    -- Registered decoded outputs (ensure stability for CDC)
    signal msg_type_reg : msg_type_t := MSG_NONE;
    signal order_ref_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal buy_sell_reg : std_logic := '0';
    signal shares_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal stock_symbol_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal price_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal stock_locate_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal tracking_number_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal timestamp_reg : std_logic_vector(47 downto 0) := (others => '0');
    signal match_number_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal event_code_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal market_category_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal financial_status_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal round_lot_size_reg : std_logic_vector(31 downto 0) := (others => '0');

    -- New message type registers
    signal original_order_ref_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal new_order_ref_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal new_shares_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal new_price_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal trade_price_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal cross_shares_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal cross_price_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal cross_type_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Track previous read enable to decode on cycle after FIFO read
    signal fifo_rd_en_prev : std_logic := '0';
begin

    -- Register FIFO data and decode in registered process
    process(clk)
        variable msg_data_var : std_logic_vector(MSG_DATA_BITS-1 downto 0);
        variable msg_type_enc_var : std_logic_vector(MSG_TYPE_BITS-1 downto 0);
        variable msg_type_var : msg_type_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                msg_type_reg <= MSG_NONE;
                order_ref_reg <= (others => '0');
                buy_sell_reg <= '0';
                shares_reg <= (others => '0');
                stock_symbol_reg <= (others => '0');
                price_reg <= (others => '0');
                stock_locate_reg <= (others => '0');
                tracking_number_reg <= (others => '0');
                timestamp_reg <= (others => '0');
                match_number_reg <= (others => '0');
                event_code_reg <= (others => '0');
                market_category_reg <= (others => '0');
                financial_status_reg <= (others => '0');
                round_lot_size_reg <= (others => '0');
                fifo_rd_en_prev <= '0';
            else
                -- Track previous read enable
                fifo_rd_en_prev <= fifo_rd_en;
                
                -- Decode on cycle AFTER FIFO read (when fifo_rd_en was '1' in previous cycle)
                -- FIFO updates rd_data on cycle when rd_en is '1', so decode on next cycle
                if fifo_rd_en_prev = '1' then
                    -- Use current FIFO data (updated by FIFO on previous cycle when rd_en was '1')
                    -- Split into type and data (use variables for immediate use)
                    msg_type_enc_var := fifo_rd_data(MSG_FIFO_WIDTH-1 downto MSG_DATA_BITS);
                    msg_data_var := fifo_rd_data(MSG_DATA_BITS-1 downto 0);
                    
                    -- Decode message type
                    msg_type_var := decode_msg_type(msg_type_enc_var);
                    msg_type_reg <= msg_type_var;
                    
                    -- Decode data fields based on message type
                    case msg_type_var is
                    when MSG_ADD_ORDER =>
                        -- Add Order fields
                        order_ref_reg <= msg_data_var(63 downto 0);
                        buy_sell_reg <= msg_data_var(64);
                        shares_reg <= msg_data_var(96 downto 65);
                        stock_symbol_reg <= msg_data_var(160 downto 97);
                        price_reg <= msg_data_var(192 downto 161);
                        stock_locate_reg <= msg_data_var(208 downto 193);
                        tracking_number_reg <= msg_data_var(224 downto 209);
                        timestamp_reg <= msg_data_var(272 downto 225);
                        
                    when MSG_STOCK_DIRECTORY =>
                        -- Stock Directory fields
                        stock_symbol_reg <= msg_data_var(111 downto 48);
                        market_category_reg <= msg_data_var(7 downto 0);
                        financial_status_reg <= msg_data_var(15 downto 8);
                        round_lot_size_reg <= msg_data_var(47 downto 16);
                        -- Also extract common fields for consistency
                        stock_locate_reg <= msg_data_var(208 downto 193);
                        tracking_number_reg <= msg_data_var(224 downto 209);
                        timestamp_reg <= msg_data_var(272 downto 225);
                        
                    when MSG_ORDER_EXECUTED =>
                        -- Order Executed fields
                        order_ref_reg <= msg_data_var(63 downto 0);
                        shares_reg <= msg_data_var(95 downto 64);  -- exec_shares
                        match_number_reg <= msg_data_var(159 downto 96);
                        
                    when MSG_ORDER_CANCEL =>
                        -- Order Cancel fields
                        order_ref_reg <= msg_data_var(63 downto 0);
                        shares_reg <= msg_data_var(95 downto 64);  -- cancel_shares
                        
                    when MSG_SYSTEM_EVENT =>
                        -- System Event fields
                        event_code_reg <= msg_data_var(7 downto 0);
                        stock_locate_reg <= msg_data_var(208 downto 193);
                        tracking_number_reg <= msg_data_var(224 downto 209);
                        timestamp_reg <= msg_data_var(272 downto 225);

                    when MSG_ORDER_DELETE =>
                        -- Order Delete fields
                        order_ref_reg <= msg_data_var(63 downto 0);

                    when MSG_ORDER_REPLACE =>
                        -- Order Replace fields
                        original_order_ref_reg <= msg_data_var(63 downto 0);
                        new_order_ref_reg <= msg_data_var(127 downto 64);
                        new_shares_reg <= msg_data_var(159 downto 128);
                        new_price_reg <= msg_data_var(191 downto 160);

                    when MSG_TRADE_NON_CROSS =>
                        -- Trade (non-cross) fields
                        order_ref_reg <= msg_data_var(63 downto 0);
                        buy_sell_reg <= msg_data_var(64);
                        shares_reg <= msg_data_var(96 downto 65);
                        stock_symbol_reg <= msg_data_var(160 downto 97);
                        trade_price_reg <= msg_data_var(192 downto 161);
                        match_number_reg <= msg_data_var(256 downto 193);

                    when MSG_TRADE_CROSS =>
                        -- Cross Trade fields
                        cross_shares_reg <= msg_data_var(63 downto 0);
                        stock_symbol_reg <= msg_data_var(127 downto 64);
                        cross_price_reg <= msg_data_var(159 downto 128);
                        match_number_reg <= msg_data_var(223 downto 160);
                        cross_type_reg <= msg_data_var(231 downto 224);

                    when others =>
                        -- Unknown message type: clear all fields
                        null;
                    end case;
                end if;
                -- If fifo_rd_en_prev = '0', keep previous decoded values (outputs remain stable)
            end if;
        end if;
    end process;

    -- Output registered decoded values
    msg_type <= msg_type_reg;
    order_ref <= order_ref_reg;
    buy_sell <= buy_sell_reg;
    shares <= shares_reg;
    stock_symbol <= stock_symbol_reg;
    price <= price_reg;
    stock_locate <= stock_locate_reg;
    tracking_number <= tracking_number_reg;
    timestamp <= timestamp_reg;
    match_number <= match_number_reg;
    event_code <= event_code_reg;
    market_category <= market_category_reg;
    financial_status <= financial_status_reg;
    round_lot_size <= round_lot_size_reg;

    -- New message type outputs
    original_order_ref <= original_order_ref_reg;
    new_order_ref <= new_order_ref_reg;
    new_shares <= new_shares_reg;
    new_price <= new_price_reg;
    trade_price <= trade_price_reg;
    cross_shares <= cross_shares_reg;
    cross_price <= cross_price_reg;
    cross_type <= cross_type_reg;

end Behavioral;
