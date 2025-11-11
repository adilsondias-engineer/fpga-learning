--------------------------------------------------------------------------------
-- Module: order_book_manager
-- Description: Top-level FSM that coordinates order storage, price levels, and BBO
--
-- Handles all ITCH message types:
--   A - Add Order      : Allocate storage, update price level, update BBO
--   E - Execute        : Reduce shares, update price level, update BBO
--   X - Cancel         : Reduce shares, update price level, update BBO
--   D - Delete         : Remove order, update price level, update BBO
--   U - Replace        : Update order, update price levels, update BBO
--   P/Q - Trade        : Informational only (no order book impact)
--
-- Latency: ~12-17 clock cycles per message (includes 2-cycle price level table pipeline)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.order_book_pkg.all;
use work.itch_msg_pkg.all;

entity order_book_manager is
    Port (
        clk     : in  std_logic;
        rst     : in  std_logic;

        -- ITCH parser interface
        itch_valid          : in  std_logic;
        itch_msg_type       : in  std_logic_vector(7 downto 0);
        itch_order_ref      : in  std_logic_vector(63 downto 0);
        itch_symbol         : in  std_logic_vector(63 downto 0);
        itch_side           : in  std_logic;  -- 0=Buy, 1=Sell
        itch_price          : in  std_logic_vector(31 downto 0);
        itch_shares         : in  std_logic_vector(31 downto 0);
        itch_exec_shares    : in  std_logic_vector(31 downto 0);
        itch_cancel_shares  : in  std_logic_vector(31 downto 0);
        itch_new_order_ref  : in  std_logic_vector(63 downto 0);
        itch_new_price      : in  std_logic_vector(31 downto 0);
        itch_new_shares     : in  std_logic_vector(31 downto 0);

        -- BBO output
        bbo                 : out bbo_t;
        bbo_update          : out std_logic;

        -- Statistics
        stats               : out order_book_stats_t;

        -- Ready signal
        ready               : out std_logic
    );
end order_book_manager;

architecture Behavioral of order_book_manager is

    -- Component declarations
    component order_storage is
        Port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            wr_en       : in  std_logic;
            wr_addr     : in  std_logic_vector(ORDER_ADDR_WIDTH-1 downto 0);
            wr_order    : in  order_entry_t;
            rd_en       : in  std_logic;
            rd_addr     : in  std_logic_vector(ORDER_ADDR_WIDTH-1 downto 0);
            rd_order    : out order_entry_t;
            rd_valid    : out std_logic;
            order_count : out unsigned(15 downto 0)
        );
    end component;

    component price_level_table is
        Port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            cmd_valid       : in  std_logic;
            cmd_type        : in  std_logic_vector(1 downto 0);
            cmd_addr        : in  std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);
            cmd_price       : in  std_logic_vector(31 downto 0);
            cmd_shares      : in  std_logic_vector(31 downto 0);
            cmd_side        : in  std_logic;
            rd_level        : out price_level_t;
            rd_valid        : out std_logic;
            bid_level_count : out unsigned(7 downto 0);
            ask_level_count : out unsigned(7 downto 0);
            debug_addr0_writes : out unsigned(7 downto 0);
            debug_addr0_last_price : out std_logic_vector(31 downto 0);
            debug_addr0_last_shares : out std_logic_vector(31 downto 0)
        );
    end component;

    component bbo_tracker is
        Port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            level_req       : out std_logic;
            level_addr      : out std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);
            level_data      : in  price_level_t;
            level_valid     : in  std_logic;
            update_trigger  : in  std_logic;
            bbo             : out bbo_t;
            bbo_update      : out std_logic;
            bbo_ready       : out std_logic
        );
    end component;

    -- FSM states
    type state_t is (
        IDLE,
        LOOKUP_ORDER,       -- Read existing order (for E/X/D/U)
        ADD_ORDER,          -- Add new order to storage
        WAIT_PRICE_CMD,     -- Wait for price level command to be processed
        UPDATE_ORDER,       -- Modify existing order
        DELETE_ORDER,       -- Mark order as deleted
        UPDATE_PRICE_ADD,   -- Add shares to price level
        UPDATE_PRICE_REMOVE,-- Remove shares from price level
        UPDATE_BBO,         -- Trigger BBO recalculation
        WAIT_BBO,           -- Wait for BBO ready
        DONE               -- Complete, return to IDLE
    );
    signal state : state_t := IDLE;

    -- Order storage signals
    signal stor_wr_en       : std_logic := '0';
    signal stor_wr_addr     : std_logic_vector(ORDER_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal stor_wr_order    : order_entry_t;
    signal stor_rd_en       : std_logic := '0';
    signal stor_rd_addr     : std_logic_vector(ORDER_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal stor_rd_order    : order_entry_t;
    signal stor_rd_valid    : std_logic;
    signal stor_order_count : unsigned(15 downto 0);

    -- Price level signals
    signal price_cmd_valid  : std_logic := '0';
    signal price_cmd_type   : std_logic_vector(1 downto 0) := "00";
    signal price_cmd_addr   : std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal price_cmd_price  : std_logic_vector(31 downto 0) := (others => '0');
    signal price_cmd_shares : std_logic_vector(31 downto 0) := (others => '0');
    signal price_cmd_side   : std_logic := '0';
    signal price_rd_level   : price_level_t;
    signal price_rd_valid   : std_logic;
    signal price_bid_count  : unsigned(7 downto 0);
    signal price_ask_count  : unsigned(7 downto 0);
    -- DEBUG: Address 0 write tracking
    signal debug_addr0_writes : unsigned(7 downto 0);
    signal debug_addr0_last_price : std_logic_vector(31 downto 0);
    signal debug_addr0_last_shares : std_logic_vector(31 downto 0);

    -- BBO signals
    signal bbo_trigger      : std_logic := '0';
    signal bbo_out          : bbo_t;
    signal bbo_update_out   : std_logic;
    signal bbo_ready_sig    : std_logic;
    signal bbo_level_req    : std_logic;
    signal bbo_level_addr   : std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);

    -- Statistics registers
    signal stats_reg        : order_book_stats_t;

    -- Message processing registers
    signal msg_order_ref    : std_logic_vector(63 downto 0) := (others => '0');
    signal msg_price        : std_logic_vector(31 downto 0) := (others => '0');
    signal msg_shares       : std_logic_vector(31 downto 0) := (others => '0');
    signal msg_side         : std_logic := '0';
    signal msg_type_reg     : std_logic_vector(7 downto 0) := (others => '0');

    -- Temporary order for modifications
    signal temp_order       : order_entry_t;

    -- Wait counter for pipelined operations
    signal wait_counter     : integer range 0 to 10 := 0;

begin

    -- Output assignments
    bbo <= bbo_out;
    bbo_update <= bbo_update_out;
    stats <= stats_reg;
    ready <= '1' when state = IDLE else '0';

    -- Update statistics
    stats_reg.total_orders <= stor_order_count;
    stats_reg.bid_level_count <= price_bid_count;
    stats_reg.ask_level_count <= price_ask_count;

    ------------------------------------------------------------------------
    -- Component Instantiations
    ------------------------------------------------------------------------

    order_storage_inst : order_storage
        port map (
            clk         => clk,
            rst         => rst,
            wr_en       => stor_wr_en,
            wr_addr     => stor_wr_addr,
            wr_order    => stor_wr_order,
            rd_en       => stor_rd_en,
            rd_addr     => stor_rd_addr,
            rd_order    => stor_rd_order,
            rd_valid    => stor_rd_valid,
            order_count => stor_order_count
        );

    price_level_table_inst : price_level_table
        port map (
            clk             => clk,
            rst             => rst,
            cmd_valid       => price_cmd_valid,
            cmd_type        => price_cmd_type,
            cmd_addr        => price_cmd_addr,
            cmd_price       => price_cmd_price,
            cmd_shares      => price_cmd_shares,
            cmd_side        => price_cmd_side,
            rd_level        => price_rd_level,
            rd_valid        => price_rd_valid,
            bid_level_count => price_bid_count,
            ask_level_count => price_ask_count,
            debug_addr0_writes => debug_addr0_writes,
            debug_addr0_last_price => debug_addr0_last_price,
            debug_addr0_last_shares => debug_addr0_last_shares
        );

    bbo_tracker_inst : bbo_tracker
        port map (
            clk             => clk,
            rst             => rst,
            level_req       => bbo_level_req,
            level_addr      => bbo_level_addr,
            level_data      => price_rd_level,
            level_valid     => price_rd_valid,
            update_trigger  => bbo_trigger,
            bbo             => bbo_out,
            bbo_update      => bbo_update_out,
            bbo_ready       => bbo_ready_sig
        );

    ------------------------------------------------------------------------
    -- Main FSM
    ------------------------------------------------------------------------
    process(clk)
        variable order_addr : std_logic_vector(ORDER_ADDR_WIDTH-1 downto 0);
        variable price_addr : std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);
        variable new_shares : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                stor_wr_en <= '0';
                stor_rd_en <= '0';
                price_cmd_valid <= '0';
                bbo_trigger <= '0';
                wait_counter <= 0;

                -- Reset statistics
                stats_reg.add_count <= (others => '0');
                stats_reg.execute_count <= (others => '0');
                stats_reg.cancel_count <= (others => '0');
                stats_reg.delete_count <= (others => '0');
                stats_reg.replace_count <= (others => '0');
                stats_reg.bid_order_count <= (others => '0');
                stats_reg.ask_order_count <= (others => '0');
            else
                -- Default: deassert control signals
                stor_wr_en <= '0';
                stor_rd_en <= '0';
                price_cmd_valid <= '0';  -- Default: no price command (individual states override)
                bbo_trigger <= '0';  -- Default: no trigger

                case state is
                    when IDLE =>
                        -- Allow BBO tracker to read from price level table when idle
                        if bbo_level_req = '1' then
                            price_cmd_valid <= '1';
                            price_cmd_type <= "10";  -- CMD_LOOKUP
                            price_cmd_addr <= bbo_level_addr;
                            price_cmd_price <= (others => '0');
                            price_cmd_shares <= (others => '0');
                            price_cmd_side <= '0';
                        end if;
                        
                        -- TEMPORARY DEBUG: Remove symbol check to test if order book works
                        -- if itch_valid = '1' and itch_symbol = TARGET_SYMBOL then
                        if itch_valid = '1' then  -- Accept ALL symbols for debugging
                            -- Capture message fields
                            msg_order_ref <= itch_order_ref;
                            msg_price <= itch_price;
                            msg_shares <= itch_shares;
                            msg_side <= itch_side;
                            msg_type_reg <= itch_msg_type;

                            case itch_msg_type is
                                when x"41" =>  -- 'A' - Add Order
                                    -- Add new order
                                    state <= ADD_ORDER;
                                    stats_reg.add_count <= stats_reg.add_count + 1;

                                when x"45" =>  -- 'E' - Order Executed
                                    -- Reduce shares
                                    msg_shares <= itch_exec_shares;
                                    state <= LOOKUP_ORDER;
                                    stats_reg.execute_count <= stats_reg.execute_count + 1;

                                when x"58" =>  -- 'X' - Order Cancel
                                    -- Reduce shares
                                    msg_shares <= itch_cancel_shares;
                                    state <= LOOKUP_ORDER;
                                    stats_reg.cancel_count <= stats_reg.cancel_count + 1;

                                when x"44" =>  -- 'D' - Order Delete
                                    -- Delete order
                                    state <= LOOKUP_ORDER;
                                    stats_reg.delete_count <= stats_reg.delete_count + 1;

                                when x"55" =>  -- 'U' - Order Replace
                                    -- Replace order
                                    state <= LOOKUP_ORDER;
                                    stats_reg.replace_count <= stats_reg.replace_count + 1;

                                when others =>
                                    -- Ignore other message types (S, R, P, Q)
                                    null;
                            end case;
                        end if;

                    when LOOKUP_ORDER =>
                        -- Read existing order from storage
                        order_addr := hash_order_ref(msg_order_ref);
                        stor_rd_en <= '1';
                        stor_rd_addr <= order_addr;
                        wait_counter <= 2;  -- Wait for BRAM read latency
                        state <= UPDATE_ORDER;

                    when ADD_ORDER =>
                        -- Add new order to storage
                        order_addr := hash_order_ref(msg_order_ref);

                        stor_wr_order.order_ref <= msg_order_ref;
                        stor_wr_order.price <= msg_price;
                        stor_wr_order.shares <= msg_shares;
                        stor_wr_order.side <= msg_side;
                        stor_wr_order.valid <= '1';

                        stor_wr_en <= '1';
                        stor_wr_addr <= order_addr;

                        -- Track order count by side
                        if msg_side = '0' then
                            -- Buy order (bid)
                            stats_reg.bid_order_count <= stats_reg.bid_order_count + 1;
                        else
                            -- Sell order (ask)
                            stats_reg.ask_order_count <= stats_reg.ask_order_count + 1;
                        end if;

                        -- Add shares to price level
                        price_addr := price_to_addr(msg_price, msg_side);
                        price_cmd_valid <= '1';
                        price_cmd_type <= "00";  -- CMD_ADD
                        price_cmd_addr <= price_addr;
                        price_cmd_price <= msg_price;
                        price_cmd_shares <= msg_shares;
                        price_cmd_side <= msg_side;

                        -- DEBUG: Count price table writes by side (for debugging)
                        -- Note: These are not included in stats output
                        -- if msg_side = '0' then
                        --     -- Bid write
                        -- else
                        --     -- Ask write
                        -- end if;

                        -- Wait for price level command to complete (2-cycle pipeline latency)
                        state <= WAIT_PRICE_CMD;
                        wait_counter <= 2;  -- 2 cycles: read (cycle 1) + modify/write (cycle 2)

                    when WAIT_PRICE_CMD =>
                        -- Price command was valid for one cycle in ADD_ORDER/UPDATE_ORDER state
                        -- Clear it now (price level table processes with 2-cycle pipeline)
                        price_cmd_valid <= '0';
                        -- Wait for 2-cycle pipeline to complete:
                        --   Cycle 1: BRAM read initiated, command captured
                        --   Cycle 2: Old data captured, new data computed and written
                        if wait_counter > 0 then
                            wait_counter <= wait_counter - 1;
                        else
                            state <= UPDATE_BBO;
                        end if;

                    when UPDATE_ORDER =>
                        if wait_counter > 0 then
                            wait_counter <= wait_counter - 1;
                        elsif stor_rd_valid = '1' and stor_rd_order.valid = '1' then
                            -- Order found, process based on message type
                            temp_order <= stor_rd_order;

                            case msg_type_reg is
                                when x"45" | x"58" =>  -- 'E' (Execute) or 'X' (Cancel)
                                    -- Reduce shares
                                    new_shares := shares_subtract(stor_rd_order.shares, msg_shares);
                                    temp_order.shares <= new_shares;

                                    if unsigned(new_shares) = 0 then
                                        -- Order fully executed/canceled
                                        temp_order.valid <= '0';
                                        -- Decrement order count by side
                                        if stor_rd_order.side = '0' then
                                            -- Buy order (bid)
                                            if stats_reg.bid_order_count > 0 then
                                                stats_reg.bid_order_count <= stats_reg.bid_order_count - 1;
                                            end if;
                                        else
                                            -- Sell order (ask)
                                            if stats_reg.ask_order_count > 0 then
                                                stats_reg.ask_order_count <= stats_reg.ask_order_count - 1;
                                            end if;
                                        end if;
                                    end if;

                                    -- Write back to storage
                                    order_addr := hash_order_ref(msg_order_ref);
                                    stor_wr_en <= '1';
                                    stor_wr_addr <= order_addr;
                                    stor_wr_order <= temp_order;

                                    -- Update price level (remove shares)
                                    price_addr := price_to_addr(stor_rd_order.price, stor_rd_order.side);
                                    price_cmd_valid <= '1';
                                    price_cmd_type <= "01";  -- CMD_REMOVE
                                    price_cmd_addr <= price_addr;
                                    price_cmd_price <= stor_rd_order.price;
                                    price_cmd_shares <= msg_shares;
                                    price_cmd_side <= stor_rd_order.side;

                                    -- Wait for price level command to complete (2-cycle pipeline latency)
                                    state <= WAIT_PRICE_CMD;
                                    wait_counter <= 2;  -- 2 cycles: read (cycle 1) + modify/write (cycle 2)

                                when x"44" =>  -- 'D' - Order Delete
                                    -- Mark order as deleted
                                    temp_order.valid <= '0';

                                    -- Decrement order count by side
                                    if stor_rd_order.side = '0' then
                                        -- Buy order (bid)
                                        if stats_reg.bid_order_count > 0 then
                                            stats_reg.bid_order_count <= stats_reg.bid_order_count - 1;
                                        end if;
                                    else
                                        -- Sell order (ask)
                                        if stats_reg.ask_order_count > 0 then
                                            stats_reg.ask_order_count <= stats_reg.ask_order_count - 1;
                                        end if;
                                    end if;

                                    order_addr := hash_order_ref(msg_order_ref);
                                    stor_wr_en <= '1';
                                    stor_wr_addr <= order_addr;
                                    stor_wr_order <= temp_order;

                                    -- Remove all shares from price level
                                    price_addr := price_to_addr(stor_rd_order.price, stor_rd_order.side);
                                    price_cmd_valid <= '1';
                                    price_cmd_type <= "01";  -- CMD_REMOVE
                                    price_cmd_addr <= price_addr;
                                    price_cmd_price <= stor_rd_order.price;
                                    price_cmd_shares <= stor_rd_order.shares;
                                    price_cmd_side <= stor_rd_order.side;

                                    -- Wait for price level command to complete (2-cycle pipeline latency)
                                    state <= WAIT_PRICE_CMD;
                                    wait_counter <= 2;  -- 2 cycles: read (cycle 1) + modify/write (cycle 2)

                                when others =>
                                    state <= DONE;
                            end case;
                        else
                            -- Order not found
                            state <= DONE;
                        end if;

                    when UPDATE_BBO =>
                        -- Trigger BBO recalculation
                        -- BBO tracker is edge-sensitive, so ensure trigger was low first
                        if bbo_ready_sig = '1' then
                            -- BBO tracker is ready, trigger it
                            bbo_trigger <= '1';
                            state <= WAIT_BBO;
                        else
                            -- BBO tracker is still busy, keep waiting
                            bbo_trigger <= '0';  -- Clear trigger to allow edge detection on next cycle
                            state <= UPDATE_BBO;  -- Stay in this state
                        end if;

                    when WAIT_BBO =>
                        -- Wait for BBO to complete
                        -- Keep trigger high while BBO tracker is scanning
                        if bbo_ready_sig = '0' then
                            -- BBO tracker is still scanning, keep trigger high
                            bbo_trigger <= '1';
                        else
                            -- BBO tracker is done, clear trigger
                            bbo_trigger <= '0';
                            state <= DONE;
                        end if;
                        
                        -- Convert BBO tracker read requests to price level table commands
                        -- BBO tracker uses level_req/level_addr, but price level table needs cmd_valid/cmd_type
                        -- This must happen in both IDLE and WAIT_BBO states to catch all requests
                        if bbo_level_req = '1' then
                            price_cmd_valid <= '1';
                            price_cmd_type <= "10";  -- CMD_LOOKUP
                            price_cmd_addr <= bbo_level_addr;
                            price_cmd_price <= (others => '0');  -- Not used for lookup
                            price_cmd_shares <= (others => '0');  -- Not used for lookup
                            price_cmd_side <= '0';  -- Not used for lookup
                        end if;

                    when DONE =>
                        state <= IDLE;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
