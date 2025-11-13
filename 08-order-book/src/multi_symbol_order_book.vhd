--------------------------------------------------------------------------------
-- Module: multi_symbol_order_book
-- Description: Multi-symbol order book wrapper
--              Instantiates 8 order book managers (one per symbol)
--              Routes ITCH messages based on symbol matching
--              Arbitrates BBO outputs using round-robin scheduling
--
-- Supported Symbols: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA
--
-- Resource Usage: ~32 RAMB36 tiles (24% of Artix-7 100T capacity)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.order_book_pkg.all;
use work.symbol_filter_pkg.all;

entity multi_symbol_order_book is
    port (
        clk                 : in  std_logic;
        reset               : in  std_logic;

        -- ITCH message inputs (from parser)
        msg_valid           : in  std_logic;
        msg_type            : in  std_logic_vector(7 downto 0);
        stock_symbol        : in  std_logic_vector(63 downto 0);
        order_ref           : in  std_logic_vector(63 downto 0);
        buy_sell            : in  std_logic;
        shares              : in  std_logic_vector(31 downto 0);
        price               : in  std_logic_vector(31 downto 0);

        -- BBO output (round-robin through symbols)
        bbo_update          : out std_logic;
        bbo_symbol          : out std_logic_vector(63 downto 0);
        bbo_valid           : out std_logic;
        bid_price           : out std_logic_vector(31 downto 0);
        bid_shares          : out std_logic_vector(31 downto 0);
        ask_price           : out std_logic_vector(31 downto 0);
        ask_shares          : out std_logic_vector(31 downto 0);
        spread              : out std_logic_vector(31 downto 0)
    );
end multi_symbol_order_book;

architecture rtl of multi_symbol_order_book is

    -- Number of symbols (matches symbol_filter_pkg)
    constant NUM_SYMBOLS : integer := MAX_SYMBOLS;  -- 8

    -- Symbol match signals
    signal symbol_match : std_logic_vector(NUM_SYMBOLS-1 downto 0);

    -- Per-symbol message valid signals
    type msg_valid_array is array (0 to NUM_SYMBOLS-1) of std_logic;
    signal book_msg_valid : msg_valid_array;

    -- Per-symbol BBO outputs (using bbo_t record type from order_book_pkg)
    type bbo_update_array is array (0 to NUM_SYMBOLS-1) of std_logic;
    type bbo_data_array is array (0 to NUM_SYMBOLS-1) of bbo_t;
    type stats_array is array (0 to NUM_SYMBOLS-1) of order_book_stats_t;
    type ready_array is array (0 to NUM_SYMBOLS-1) of std_logic;

    signal bbo_update_vec  : bbo_update_array;
    signal bbo_data_vec    : bbo_data_array;
    signal stats_vec       : stats_array;
    signal ready_vec       : ready_array;

    -- BBO arbiter
    signal current_symbol  : integer range 0 to NUM_SYMBOLS-1 := 0;
    signal arbiter_counter : unsigned(9 downto 0) := (others => '0');

    -- Previous BBO state (for change detection per symbol)
    type prev_bbo_array is array (0 to NUM_SYMBOLS-1) of bbo_t;
    signal prev_bbo : prev_bbo_array;

begin

    ----------------------------------------------------------------------------
    -- Symbol Demultiplexer
    -- Routes incoming ITCH messages to correct order book based on symbol match
    ----------------------------------------------------------------------------
    process(stock_symbol)
    begin
        symbol_match <= (others => '0');
        for i in 0 to NUM_SYMBOLS-1 loop
            if stock_symbol = FILTER_SYMBOL_LIST(i) then
                symbol_match(i) <= '1';
            end if;
        end loop;
    end process;

    -- Route msg_valid to matched order book
    gen_msg_valid: for i in 0 to NUM_SYMBOLS-1 generate
        book_msg_valid(i) <= msg_valid when symbol_match(i) = '1' else '0';
    end generate;

    ----------------------------------------------------------------------------
    -- Order Book Instances (one per symbol)
    ----------------------------------------------------------------------------
    gen_order_books: for i in 0 to NUM_SYMBOLS-1 generate
        book_inst: entity work.order_book_manager
            generic map (
                TARGET_SYMBOL => FILTER_SYMBOL_LIST(i)
            )
            port map (
                clk => clk,
                rst => reset,

                -- ITCH message inputs (Note: order_book_manager needs ALL ITCH inputs)
                itch_valid          => book_msg_valid(i),
                itch_msg_type       => msg_type,
                itch_order_ref      => order_ref,
                itch_symbol         => stock_symbol,
                itch_side           => buy_sell,
                itch_shares         => shares,
                itch_price          => price,
                itch_exec_shares    => (others => '0'),  -- Not provided, set to 0
                itch_cancel_shares  => (others => '0'),  -- Not provided, set to 0
                itch_new_order_ref  => (others => '0'),  -- Not provided, set to 0
                itch_new_price      => (others => '0'),  -- Not provided, set to 0
                itch_new_shares     => (others => '0'),  -- Not provided, set to 0

                -- BBO output
                bbo                 => bbo_data_vec(i),
                bbo_update          => bbo_update_vec(i),

                -- Statistics
                stats               => stats_vec(i),

                -- Ready signal
                ready               => ready_vec(i)
            );
    end generate;

    ----------------------------------------------------------------------------
    -- BBO Arbiter (Round-Robin with Change Detection)
    -- Cycles through 8 symbols at ~10 µs per symbol (80 µs full cycle)
    -- Only outputs BBO when it has changed for current symbol
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_symbol <= 0;
                arbiter_counter <= (others => '0');
                bbo_update <= '0';

                -- Initialize previous BBO state
                for i in 0 to NUM_SYMBOLS-1 loop
                    prev_bbo(i).valid <= '0';
                    prev_bbo(i).bid_price <= (others => '0');
                    prev_bbo(i).bid_shares <= (others => '0');
                    prev_bbo(i).ask_price <= (others => '1');
                    prev_bbo(i).ask_shares <= (others => '0');
                    prev_bbo(i).spread <= (others => '1');  -- Initialize spread to max (no spread)
                end loop;

            else
                -- Default: no BBO update
                bbo_update <= '0';

                -- Round-robin arbiter: cycle every 1000 clock cycles (10 µs @ 100 MHz)
                if arbiter_counter = 999 then
                    arbiter_counter <= (others => '0');

                    -- Move to next symbol
                    if current_symbol = NUM_SYMBOLS-1 then
                        current_symbol <= 0;
                    else
                        current_symbol <= current_symbol + 1;
                    end if;

                else
                    arbiter_counter <= arbiter_counter + 1;
                end if;

                -- Check if current symbol's BBO has changed
                if (bbo_data_vec(current_symbol).valid /= prev_bbo(current_symbol).valid) or
                   (bbo_data_vec(current_symbol).bid_price /= prev_bbo(current_symbol).bid_price) or
                   (bbo_data_vec(current_symbol).bid_shares /= prev_bbo(current_symbol).bid_shares) or
                   (bbo_data_vec(current_symbol).ask_price /= prev_bbo(current_symbol).ask_price) or
                   (bbo_data_vec(current_symbol).ask_shares /= prev_bbo(current_symbol).ask_shares) or
                   (bbo_data_vec(current_symbol).spread /= prev_bbo(current_symbol).spread) then

                    -- BBO changed! Output update
                    bbo_update <= '1';
                    bbo_symbol <= FILTER_SYMBOL_LIST(current_symbol);
                    bbo_valid <= bbo_data_vec(current_symbol).valid;
                    bid_price <= bbo_data_vec(current_symbol).bid_price;
                    bid_shares <= bbo_data_vec(current_symbol).bid_shares;
                    ask_price <= bbo_data_vec(current_symbol).ask_price;
                    ask_shares <= bbo_data_vec(current_symbol).ask_shares;
                    spread <= bbo_data_vec(current_symbol).spread;

                    -- Update previous state (store entire record)
                    prev_bbo(current_symbol) <= bbo_data_vec(current_symbol);

                end if;

            end if;
        end if;
    end process;

end rtl;
