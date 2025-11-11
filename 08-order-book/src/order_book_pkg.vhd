--------------------------------------------------------------------------------
-- Package: order_book_pkg
-- Description: Constants, types, and functions for hardware order book
--
-- Phase 1: Single symbol (AAPL)
-- Phase 2: Multi-symbol support (scalable to 8 symbols)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package order_book_pkg is

    ------------------------------------------------------------------------
    -- Configuration Constants
    ------------------------------------------------------------------------

    -- Phase 1: Single symbol configuration
    constant TARGET_SYMBOL      : std_logic_vector(63 downto 0) := x"4141504C20202020";  -- "AAPL    "
    constant ENABLE_ORDER_BOOK  : boolean := true;

    -- Order storage configuration
    constant MAX_ORDERS         : integer := 1024;  -- Max concurrent orders per symbol
    constant ORDER_ADDR_WIDTH   : integer := 10;    -- log2(MAX_ORDERS) = 10 bits

    -- Price level configuration
    constant MAX_PRICE_LEVELS   : integer := 256;   -- 128 bids + 128 asks
    constant PRICE_ADDR_WIDTH   : integer := 8;     -- log2(MAX_PRICE_LEVELS) = 8 bits
    constant MAX_BID_LEVELS     : integer := 128;
    constant MAX_ASK_LEVELS     : integer := 128;

    -- BBO tracking configuration
    constant BBO_SCAN_DEPTH     : integer := 128;   -- Scan all bid/ask levels for BBO

    ------------------------------------------------------------------------
    -- Data Structure Types
    ------------------------------------------------------------------------

    -- Order Entry (stored in BRAM)
    -- Total: 130 bits (fits in dual 36Kb BRAM with width=130)
    type order_entry_t is record
        order_ref   : std_logic_vector(63 downto 0);  -- Unique order ID
        price       : std_logic_vector(31 downto 0);  -- 4-byte fixed point
        shares      : std_logic_vector(31 downto 0);  -- Remaining shares
        side        : std_logic;                      -- 0=Buy, 1=Sell
        valid       : std_logic;                      -- Order exists?
    end record;

    -- Convert order_entry_t to std_logic_vector for BRAM storage
    function order_to_slv(order : order_entry_t) return std_logic_vector;
    function slv_to_order(slv : std_logic_vector(129 downto 0)) return order_entry_t;

    -- Price Level Entry (stored in BRAM)
    -- Total: 66 bits
    type price_level_t is record
        price           : std_logic_vector(31 downto 0);  -- Price level
        total_shares    : std_logic_vector(31 downto 0);  -- Aggregated shares
        order_count     : std_logic_vector(15 downto 0);  -- Number of orders
        side            : std_logic;                      -- 0=Buy, 1=Sell
        valid           : std_logic;                      -- Level has orders?
    end record;

    -- Convert price_level_t to std_logic_vector for BRAM storage
    -- Updated to 82 bits to store full 32-bit price
    function price_level_to_slv(level : price_level_t) return std_logic_vector;
    function slv_to_price_level(slv : std_logic_vector(81 downto 0)) return price_level_t;

    -- BBO (Best Bid/Offer) Output
    type bbo_t is record
        bid_price       : std_logic_vector(31 downto 0);
        bid_shares      : std_logic_vector(31 downto 0);
        ask_price       : std_logic_vector(31 downto 0);
        ask_shares      : std_logic_vector(31 downto 0);
        spread          : std_logic_vector(31 downto 0);  -- ask - bid
        valid           : std_logic;                      -- BBO available?
    end record;

    constant BBO_INVALID : bbo_t := (
        bid_price   => (others => '0'),
        bid_shares  => (others => '0'),
        ask_price   => (others => '1'),  -- Max value (no ask)
        ask_shares  => (others => '0'),
        spread      => (others => '1'),
        valid       => '0'
    );

    ------------------------------------------------------------------------
    -- Order Book Statistics
    ------------------------------------------------------------------------

    type order_book_stats_t is record
        total_orders        : unsigned(15 downto 0);  -- Total active orders
        bid_order_count     : unsigned(15 downto 0);  -- Active buy orders
        ask_order_count     : unsigned(15 downto 0);  -- Active sell orders
        bid_level_count     : unsigned(7 downto 0);   -- Active bid levels
        ask_level_count     : unsigned(7 downto 0);   -- Active ask levels
        add_count           : unsigned(31 downto 0);  -- Lifetime adds
        execute_count       : unsigned(31 downto 0);  -- Lifetime executions
        cancel_count        : unsigned(31 downto 0);  -- Lifetime cancels
        delete_count        : unsigned(31 downto 0);  -- Lifetime deletes
        replace_count       : unsigned(31 downto 0);  -- Lifetime replaces
        bid_writes          : unsigned(7 downto 0);   -- DEBUG: Bid writes to price table
        ask_writes          : unsigned(7 downto 0);   -- DEBUG: Ask writes to price table
        addr0_writes        : unsigned(7 downto 0);   -- DEBUG: Address 0 writes
        addr0_last_price    : std_logic_vector(31 downto 0);  -- DEBUG: Last price written to addr 0
        addr0_last_shares   : std_logic_vector(31 downto 0);  -- DEBUG: Last shares written to addr 0
    end record;

    ------------------------------------------------------------------------
    -- Helper Functions
    ------------------------------------------------------------------------

    -- Price comparison (fixed-point)
    function price_greater_than(a, b : std_logic_vector(31 downto 0)) return boolean;
    function price_less_than(a, b : std_logic_vector(31 downto 0)) return boolean;
    function price_equal(a, b : std_logic_vector(31 downto 0)) return boolean;

    -- Shares arithmetic (prevent underflow)
    function shares_subtract(
        current : std_logic_vector(31 downto 0);
        amount  : std_logic_vector(31 downto 0)
    ) return std_logic_vector;

    -- Order reference hash (for BRAM addressing)
    -- Simple hash: Take lower 10 bits for 1024-entry table
    function hash_order_ref(order_ref : std_logic_vector(63 downto 0))
        return std_logic_vector;

    -- Price to address mapping
    -- Map price to BRAM address for price level table
    -- For Phase 1: Simple modulo addressing
    function price_to_addr(
        price : std_logic_vector(31 downto 0);
        side  : std_logic
    ) return std_logic_vector;

end package order_book_pkg;

package body order_book_pkg is

    ------------------------------------------------------------------------
    -- Order Entry Conversion Functions
    ------------------------------------------------------------------------

    function order_to_slv(order : order_entry_t) return std_logic_vector is
        variable slv : std_logic_vector(129 downto 0);
    begin
        slv(129)          := order.valid;
        slv(128)          := order.side;
        slv(127 downto 96) := order.shares;
        slv(95 downto 64)  := order.price;
        slv(63 downto 0)   := order.order_ref;
        return slv;
    end function;

    function slv_to_order(slv : std_logic_vector(129 downto 0)) return order_entry_t is
        variable order : order_entry_t;
    begin
        order.valid     := slv(129);
        order.side      := slv(128);
        order.shares    := slv(127 downto 96);
        order.price     := slv(95 downto 64);
        order.order_ref := slv(63 downto 0);
        return order;
    end function;

    ------------------------------------------------------------------------
    -- Price Level Conversion Functions
    ------------------------------------------------------------------------

    function price_level_to_slv(level : price_level_t) return std_logic_vector is
        variable slv : std_logic_vector(81 downto 0);
    begin
        slv(81)          := level.valid;
        slv(80)          := level.side;
        slv(79 downto 64) := level.order_count;
        slv(63 downto 32) := level.total_shares;
        slv(31 downto 0)  := level.price;  -- Store FULL 32-bit price
        return slv;
    end function;

    function slv_to_price_level(slv : std_logic_vector(81 downto 0)) return price_level_t is
        variable level : price_level_t;
    begin
        level.valid        := slv(81);
        level.side         := slv(80);
        level.order_count  := slv(79 downto 64);
        level.total_shares := slv(63 downto 32);
        level.price        := slv(31 downto 0);  -- Read FULL 32-bit price
        return level;
    end function;

    ------------------------------------------------------------------------
    -- Price Comparison Functions
    ------------------------------------------------------------------------

    function price_greater_than(a, b : std_logic_vector(31 downto 0)) return boolean is
    begin
        return unsigned(a) > unsigned(b);
    end function;

    function price_less_than(a, b : std_logic_vector(31 downto 0)) return boolean is
    begin
        return unsigned(a) < unsigned(b);
    end function;

    function price_equal(a, b : std_logic_vector(31 downto 0)) return boolean is
    begin
        return a = b;
    end function;

    ------------------------------------------------------------------------
    -- Shares Arithmetic
    ------------------------------------------------------------------------

    function shares_subtract(
        current : std_logic_vector(31 downto 0);
        amount  : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable result : unsigned(31 downto 0);
    begin
        if unsigned(current) >= unsigned(amount) then
            result := unsigned(current) - unsigned(amount);
        else
            result := (others => '0');  -- Prevent underflow
        end if;
        return std_logic_vector(result);
    end function;

    ------------------------------------------------------------------------
    -- Addressing Functions
    ------------------------------------------------------------------------

    function hash_order_ref(order_ref : std_logic_vector(63 downto 0))
        return std_logic_vector is
    begin
        -- Simple hash: Use lower 10 bits as address
        -- For Phase 1: Collisions possible but acceptable
        -- Phase 2: Implement better hash or linked list
        return order_ref(ORDER_ADDR_WIDTH-1 downto 0);
    end function;

    function price_to_addr(
        price : std_logic_vector(31 downto 0);
        side  : std_logic
    ) return std_logic_vector is
        variable addr : unsigned(PRICE_ADDR_WIDTH-1 downto 0);
        variable price_bits : unsigned(6 downto 0);
    begin
        -- Map price to address using upper bits
        -- Bids: [0-127], Asks: [128-255]
        price_bits := unsigned(price(31 downto 25));  -- Use top 7 bits

        if side = '0' then
            -- Buy: Map to [0-127]
            addr := resize(price_bits, PRICE_ADDR_WIDTH);
        else
            -- Sell: Map to [128-255]
            addr := resize(price_bits + 128, PRICE_ADDR_WIDTH);
        end if;

        return std_logic_vector(addr);
    end function;

end package body order_book_pkg;
