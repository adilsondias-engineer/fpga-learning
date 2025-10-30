library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity button_debouncer is
    Generic (
        CLK_FREQ    : integer := 100_000_000;  -- 100 MHz
        DEBOUNCE_MS : integer := 20            -- 20 ms debounce time
    );
    Port (
        clk       : in  STD_LOGIC;
        btn_in    : in  STD_LOGIC;
        btn_out   : out STD_LOGIC
    );
end button_debouncer;

architecture Behavioral of button_debouncer is
    -- Synchronizer (3 flip-flops for metastability protection)
    signal btn_sync : STD_LOGIC_VECTOR(2 downto 0) := "000";
    
    -- Debounce counter
    constant DEBOUNCE_COUNT : integer := (CLK_FREQ / 1000) * DEBOUNCE_MS;
    signal counter : integer range 0 to DEBOUNCE_COUNT := 0;
    
    -- Debounced signal
    signal btn_stable : STD_LOGIC := '0';
    
begin
    
    -- Output the stable signal
    btn_out <= btn_stable;
    
    process(clk)
    begin
        if rising_edge(clk) then
            -- Stage 1: Synchronizer (prevents metastability)
            btn_sync <= btn_sync(1 downto 0) & btn_in;
            
            -- Stage 2: Debouncer
            if btn_sync(2) = btn_stable then
                -- Button state matches stable state, reset counter
                counter <= 0;
            else
                -- Button state different, count up
                if counter < DEBOUNCE_COUNT then
                    counter <= counter + 1;
                else
                    -- Counter reached threshold, update stable state
                    btn_stable <= btn_sync(2);
                    counter <= 0;
                end if;
            end if;
        end if;
    end process;
    
end Behavioral;