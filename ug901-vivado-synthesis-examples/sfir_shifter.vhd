
-- FIR filter shifter
-- File: sfir_shifter.vhd

library ieee;
use ieee.std_logic_1164.all;

entity sfir_shifter is
  generic (DSIZE : natural := 16; NBTAP : natural := 4);
  port (clk     : in  std_logic;
        datain  : in  std_logic_vector (DSIZE-1 downto 0);
        dataout : out std_logic_vector (DSIZE-1 downto 0));
end sfir_shifter;

architecture rtl of sfir_shifter is

  -- Declare signals
  --
  type CHAIN is array (0 to 2*NBTAP-1) of std_logic_vector(DSIZE-1 downto 0);
  signal tmp: CHAIN;

begin

  process(clk)
  begin
    if rising_edge(clk) then
      tmp(0) <= datain;
      looptmp :      
      for i in 0 to 2*NBTAP-2 loop
        tmp(i+1) <= tmp(i);
      end loop;
    end if;
  end process;

  dataout <= tmp(2*NBTAP-1);
  
end rtl;
