--------------------------------------------------------------------------------
-- Module: bbo_tracker
-- Description: Best Bid/Offer (BBO) tracker
--
-- Maintains:
--   - Best Bid (highest buy price)
--   - Best Ask (lowest sell price)
--   - Spread (ask - bid)
--
-- Strategy: Scan top N price levels to find best bid/ask
-- Latency: BBO_SCAN_DEPTH cycles to compute BBO
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.order_book_pkg.all;

entity bbo_tracker is
    Port (
        clk     : in  std_logic;
        rst     : in  std_logic;

        -- Price level interface (reads from price_level_table)
        level_req       : out std_logic;
        level_addr      : out std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);
        level_data      : in  price_level_t;
        level_valid     : in  std_logic;

        -- Update trigger
        update_trigger  : in  std_logic;  -- Start BBO scan

        -- BBO output
        bbo             : out bbo_t;
        bbo_update      : out std_logic;  -- Strobe when BBO changes
        bbo_ready       : out std_logic   -- BBO calculation complete
    );
end bbo_tracker;

architecture Behavioral of bbo_tracker is

    -- FSM states
    type state_t is (IDLE, SCAN_BIDS, SCAN_BIDS_WAIT1, SCAN_BIDS_WAIT2, SCAN_ASKS, SCAN_ASKS_WAIT1, SCAN_ASKS_WAIT2, COMPUTE_SPREAD, DONE);
    signal state : state_t := IDLE;

    -- BBO registers
    signal best_bid_price_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal best_bid_shares_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal best_ask_price_reg   : std_logic_vector(31 downto 0) := (others => '1');
    signal best_ask_shares_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal bbo_valid_reg        : std_logic := '0';

    -- Previous BBO (for change detection)
    signal prev_bid_price       : std_logic_vector(31 downto 0) := (others => '0');
    signal prev_ask_price       : std_logic_vector(31 downto 0) := (others => '1');

    -- Scan state
    signal scan_counter         : integer range 0 to BBO_SCAN_DEPTH := 0;
    signal scan_addr            : unsigned(PRICE_ADDR_WIDTH-1 downto 0) := (others => '0');

    -- Bid scanning (scan from highest to lowest)
    signal best_bid_found       : std_logic := '0';

    -- Ask scanning (scan from lowest to highest)
    signal best_ask_found       : std_logic := '0';

begin

    -- Output BBO
    bbo.bid_price   <= best_bid_price_reg;
    bbo.bid_shares  <= best_bid_shares_reg;
    bbo.ask_price   <= best_ask_price_reg;
    bbo.ask_shares  <= best_ask_shares_reg;
    bbo.valid       <= bbo_valid_reg;

    -- Calculate spread (ask - bid)
    process(best_ask_price_reg, best_bid_price_reg, bbo_valid_reg)
        variable spread : unsigned(31 downto 0);
    begin
        if bbo_valid_reg = '1' then
            if unsigned(best_ask_price_reg) > unsigned(best_bid_price_reg) then
                spread := unsigned(best_ask_price_reg) - unsigned(best_bid_price_reg);
            else
                spread := (others => '0');
            end if;
            bbo.spread <= std_logic_vector(spread);
        else
            bbo.spread <= (others => '1');  -- Invalid spread
        end if;
    end process;

    ------------------------------------------------------------------------
    -- BBO Tracking FSM
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                best_bid_price_reg <= (others => '0');
                best_bid_shares_reg <= (others => '0');
                best_ask_price_reg <= (others => '1');
                best_ask_shares_reg <= (others => '0');
                bbo_valid_reg <= '0';
                bbo_update <= '0';
                bbo_ready <= '1';
                level_req <= '0';
                scan_counter <= 0;
                best_bid_found <= '0';
                best_ask_found <= '0';
            else
                -- Default outputs
                bbo_update <= '0';
                level_req <= '0';

                case state is
                    when IDLE =>
                        bbo_ready <= '1';

                        if update_trigger = '1' then
                            -- Start BBO scan
                            state <= SCAN_BIDS;
                            scan_counter <= 0;
                            scan_addr <= to_unsigned(MAX_BID_LEVELS - 1, PRICE_ADDR_WIDTH);  -- Start from highest bid
                            best_bid_found <= '0';
                            best_ask_found <= '0';
                            prev_bid_price <= best_bid_price_reg;
                            prev_ask_price <= best_ask_price_reg;
                            bbo_ready <= '0';
                        end if;

                    when SCAN_BIDS =>
                        -- TEMPORARY DEBUG: Only scan address 0 for bids (where $150 should map)
                        if scan_counter = 0 then
                            level_req <= '1';
                            level_addr <= std_logic_vector(to_unsigned(0, PRICE_ADDR_WIDTH));  -- Force address 0
                            state <= SCAN_BIDS_WAIT1;
                        else
                            -- Done scanning bids
                            if best_bid_found = '0' then
                                -- No bids found
                                best_bid_price_reg <= (others => '0');
                                best_bid_shares_reg <= (others => '0');
                            end if;

                            -- Move to ask scanning
                            state <= SCAN_ASKS;
                            scan_counter <= 0;
                            scan_addr <= to_unsigned(MAX_BID_LEVELS, PRICE_ADDR_WIDTH);  -- Start from lowest ask
                        end if;

                    when SCAN_BIDS_WAIT1 =>
                        -- Wait cycle 1 (2-cycle read latency)
                        level_req <= '0';
                        state <= SCAN_BIDS_WAIT2;

                    when SCAN_BIDS_WAIT2 =>
                        -- Wait cycle 2 - data should be valid now
                        level_req <= '0';

                        -- TEMPORARY DEBUG: Always capture data regardless of valid flags
                        if best_bid_found = '0' then
                            best_bid_price_reg <= level_data.price;
                            best_bid_shares_reg <= level_data.total_shares;
                            best_bid_found <= '1';
                        end if;

                        ---- Check if we received valid data (2-cycle latency)
                        --if level_valid = '1' and level_data.valid = '1' and level_data.side = '0' then
                        --    -- Found valid bid level
                        --    if best_bid_found = '0' then
                        --        -- This is the best bid (highest price)
                        --        best_bid_price_reg <= level_data.price;
                        --        best_bid_shares_reg <= level_data.total_shares;
                        --        best_bid_found <= '1';
                        --    end if;
                        --end if;

                        -- Move to next level (just one iteration for address 0)
                        if scan_addr > 0 then
                            scan_addr <= scan_addr - 1;
                        end if;
                        scan_counter <= scan_counter + 1;
                        state <= SCAN_BIDS;

                    when SCAN_ASKS =>
                        -- TEMPORARY DEBUG: Only scan address 128 for asks
                        if scan_counter = 0 then
                            level_req <= '1';
                            level_addr <= std_logic_vector(to_unsigned(128, PRICE_ADDR_WIDTH));  -- Force address 128
                            state <= SCAN_ASKS_WAIT1;
                        --if scan_counter < BBO_SCAN_DEPTH then
                        --    level_req <= '1';
                        --    level_addr <= std_logic_vector(scan_addr);
                        --    state <= SCAN_ASKS_WAIT1;
                        else
                            -- Done scanning asks
                            if best_ask_found = '0' then
                                -- No asks found
                                best_ask_price_reg <= (others => '1');
                                best_ask_shares_reg <= (others => '0');
                            end if;

                            state <= COMPUTE_SPREAD;
                        end if;

                    when SCAN_ASKS_WAIT1 =>
                        -- Wait cycle 1 (2-cycle read latency)
                        level_req <= '0';
                        state <= SCAN_ASKS_WAIT2;

                    when SCAN_ASKS_WAIT2 =>
                        -- Wait cycle 2 - data should be valid now
                        level_req <= '0';

                        -- TEMPORARY DEBUG: Always capture data regardless of valid flags
                        if best_ask_found = '0' then
                            best_ask_price_reg <= level_data.price;
                            best_ask_shares_reg <= level_data.total_shares;
                            best_ask_found <= '1';
                        end if;

                        --if level_valid = '1' and level_data.valid = '1' and level_data.side = '1' then
                        --    -- Found valid ask level
                        --    if best_ask_found = '0' then
                        --        -- This is the best ask (lowest price)
                        --        best_ask_price_reg <= level_data.price;
                        --        best_ask_shares_reg <= level_data.total_shares;
                        --        best_ask_found <= '1';
                        --    end if;
                        --end if;

                        -- Move to next level
                        if scan_addr < MAX_PRICE_LEVELS - 1 then
                            scan_addr <= scan_addr + 1;
                        end if;
                        scan_counter <= scan_counter + 1;
                        state <= SCAN_ASKS;

                    when COMPUTE_SPREAD =>
                        -- TEMPORARY DEBUG: Always set BBO as valid to test
                        --if best_bid_found = '1' and best_ask_found = '1' then
                        --    bbo_valid_reg <= '1';
                        --else
                        --    bbo_valid_reg <= '0';
                        --end if;
                        bbo_valid_reg <= '1';  -- Force valid to see if prices are captured

                        state <= DONE;

                    when DONE =>
                        -- TEMPORARY DEBUG: Always pulse bbo_update to test if DONE state is reached
                        --if (best_bid_price_reg /= prev_bid_price) or (best_ask_price_reg /= prev_ask_price) then
                            bbo_update <= '1';  -- BBO changed!
                        --end if;

                        state <= IDLE;
                        bbo_ready <= '1';

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
