--------------------------------------------------------------------------------
-- Module: symbol_filter_pkg
-- Description: Symbol filtering package for ITCH parser
--              Configurable symbol list for filtering market data messages
--              v5 Feature: Reduces downstream processing load
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package symbol_filter_pkg is

    -- Symbol configuration
    constant SYMBOL_WIDTH : integer := 64; -- 8 bytes = 64 bits
    constant MAX_SYMBOLS  : integer := 8;  -- Support up to 8 symbols

    -- Symbol filter list (8 bytes each, space-padded)
    -- Default list: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA
    type symbol_array_t is array (0 to MAX_SYMBOLS-1) of std_logic_vector(SYMBOL_WIDTH-1 downto 0);

    constant FILTER_SYMBOL_LIST : symbol_array_t := (
        0 => x"4141504C20202020",  -- "AAPL    "
        1 => x"54534C4120202020",  -- "TSLA    "
        2 => x"5350592020202020",  -- "SPY     "
        3 => x"5151512020202020",  -- "QQQ     "
        4 => x"474F4F474C202020",  -- "GOOGL   "
        5 => x"4D53465420202020",  -- "MSFT    "
        6 => x"414D5A4E20202020",  -- "AMZN    "
        7 => x"4E56444120202020"   -- "NVDA    "
    );

    -- Filter enable/disable
    constant ENABLE_SYMBOL_FILTER : boolean := true;  -- Set to false to disable filtering

    -- Function to check if symbol matches filter list
    function is_symbol_filtered(symbol : std_logic_vector(SYMBOL_WIDTH-1 downto 0)) return boolean;

end package symbol_filter_pkg;

package body symbol_filter_pkg is

    -- Check if symbol is in the filter list
    function is_symbol_filtered(symbol : std_logic_vector(SYMBOL_WIDTH-1 downto 0)) return boolean is
    begin
        -- If filtering is disabled, pass all symbols
        if not ENABLE_SYMBOL_FILTER then
            return true;
        end if;

        -- Check against each symbol in the filter list
        for i in 0 to MAX_SYMBOLS-1 loop
            if symbol = FILTER_SYMBOL_LIST(i) then
                return true;  -- Symbol matches filter list
            end if;
        end loop;

        return false;  -- Symbol not in filter list
    end function;

end package body symbol_filter_pkg;
