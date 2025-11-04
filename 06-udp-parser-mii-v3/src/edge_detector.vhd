library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity edge_detector is
    Port (
        clk      : in  STD_LOGIC;
        sig_in   : in  STD_LOGIC;
        rising   : out STD_LOGIC;
        falling  : out STD_LOGIC
    );
end edge_detector;

architecture Behavioral of edge_detector is
    signal sig_delayed : STD_LOGIC := '0';
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            sig_delayed <= sig_in;
        end if;
    end process;
    
    -- Rising edge: sig_in=1 and sig_delayed=0
    rising <= sig_in and (not sig_delayed);
    
    -- Falling edge: sig_in=0 and sig_delayed=1
    falling <= (not sig_in) and sig_delayed;
    
end Behavioral;
