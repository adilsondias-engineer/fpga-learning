-- Convergent rounding(Odd) Example which makes use of pattern detect 
-- File: convergentRoundingOdd.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity convergentRoundingOdd is
  port (clk   : in  std_logic;
        a     : in  std_logic_vector (23 downto 0);
        b     : in  std_logic_vector (15 downto 0);
        zlast : out std_logic_vector (23 downto 0));
end convergentRoundingOdd;

architecture beh of convergentRoundingOdd is

  signal ar : signed(a'range);
  signal br : signed(b'range);
  signal z1 : signed(a'length + b'length - 1 downto 0);

  signal multadd, multaddr : signed(a'length + b'length - 1 downto 0);
  signal pattern_detect    : boolean;

  constant pattern : signed(15 downto 0) := (others => '1');
  constant c       : signed := "0000000000000000000000000111111111111111";

  -- Convergent Rounding: LSB Correction Technique
  -- ---------------------------------------------
  -- For static convergent rounding,  the pattern detector can be
  -- used to detect  the midpoint case. For example,  in an 8-bit
  -- round, if the decimal place is  set at 4, the C input should
  -- be  set to  0000.0111.   Round to  odd  rounding should  use
  -- CARRYIN =  "0" and  check for  PATTERN "XXXX.1111"  and then
  -- replace  the  units place  bit  with  1  if the  pattern  is
  -- matched. See UG193 for details

begin

  multadd <= z1 + c;

  process(clk)
  begin
    if rising_edge(clk) then
      ar       <= signed(a);
      br       <= signed(b);
      z1       <= ar * br;
      multaddr <= multadd;
      if multadd(15 downto 0) = pattern then
        pattern_detect <= true;
      else
        pattern_detect <= false;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if pattern_detect = true then
        zlast <= std_logic_vector(multaddr(39 downto 17)) & "1";
      else
        zlast <= std_logic_vector(multaddr(39 downto 16));
      end if;
    end if;
  end process;

end beh;
