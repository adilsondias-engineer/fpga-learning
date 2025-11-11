

-- Squarer support for DSP block (DSP48E2) with pre-adder 
-- configured
-- as subtractor
-- File: squarediffmult.vhd

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity squarediffmult is
 generic(
  SIZEIN : natural := 16
 );
 port(
  clk, ce, rst : in  std_logic;
  ain, bin     : in  std_logic_vector(SIZEIN - 1 downto 0);
  square_out   : out std_logic_vector(2 * SIZEIN + 1 downto 0)
 );
end squarediffmult;

architecture rtl of squarediffmult is

 -- Declare intermediate values
 signal a_reg, b_reg : signed(SIZEIN - 1 downto 0);
 signal diff_reg     : signed(SIZEIN downto 0);
 signal m_reg, p_reg : signed(2 * SIZEIN + 1 downto 0);

begin
 process(clk)
 begin
  if rising_edge(clk) then
   if rst = '1' then
    a_reg    <= (others => '0');
    b_reg    <= (others => '0');
    diff_reg <= (others => '0');
    m_reg    <= (others => '0');
    p_reg    <= (others => '0');
   else
    a_reg    <= signed(ain);
    b_reg    <= signed(bin);
    diff_reg <= resize(a_reg, SIZEIN + 1) - resize(b_reg, SIZEIN + 1);
    m_reg    <= diff_reg * diff_reg;
    p_reg    <= m_reg;
   end if;
  end if;
 end process;

 --
 -- Type conversion for output
 --
 square_out <= std_logic_vector(p_reg);

end rtl;
