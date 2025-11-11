library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dynpreaddmultadd is
 generic(
  AWIDTH : natural := 12;
  BWIDTH : natural := 16;
  CWIDTH : natural := 17
 );
 port(
  clk    : in  std_logic;
  subadd : in  std_logic;
  ain    : in  std_logic_vector(AWIDTH - 1 downto 0);
  bin    : in  std_logic_vector(BWIDTH - 1 downto 0);
  cin    : in  std_logic_vector(CWIDTH - 1 downto 0);
  din    : in  std_logic_vector(BWIDTH + CWIDTH downto 0);
  pout   : out std_logic_vector(BWIDTH + CWIDTH downto 0)
 );
end dynpreaddmultadd;

architecture rtl of dynpreaddmultadd is
 signal a          : signed(AWIDTH - 1 downto 0);
 signal b          : signed(BWIDTH - 1 downto 0);
 signal c          : signed(CWIDTH - 1 downto 0);
 signal add        : signed(BWIDTH downto 0);
 signal d, mult, p : signed(BWIDTH + CWIDTH downto 0);

begin
 process(clk)
 begin
  if rising_edge(clk) then
   a <= signed(ain);
   b <= signed(bin);
   c <= signed(cin);
   d <= signed(din);
   if subadd = '1' then
    add <= resize(a, BWIDTH + 1) - resize(b, BWIDTH + 1);
   else
    add <= resize(a, BWIDTH + 1) + resize(b, BWIDTH + 1);
   end if;
   mult <= add * c;
   p    <= mult + d;
  end if;
 end process;

 --
 -- Type conversion for output
 --
 pout <= std_logic_vector(p);

end rtl;
