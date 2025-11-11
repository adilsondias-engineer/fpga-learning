--
-- FIR filter top
-- File: sfir_even_symmetric_systolic_top.vhd


-- FIR filter shifter
-- submodule used in top (sfir_even_symmetric_systolic_top)
library ieee;
use ieee.std_logic_1164.all;

entity sfir_shifter is
 generic(
  DSIZE : natural := 16;
  NBTAP : natural := 4
 );
 port(
  clk     : in  std_logic;
  datain  : in  std_logic_vector(DSIZE - 1 downto 0);
  dataout : out std_logic_vector(DSIZE - 1 downto 0)
 );
end sfir_shifter;

architecture rtl of sfir_shifter is

 -- Declare signals
 --
 type CHAIN is array (0 to 2 * NBTAP - 1) of std_logic_vector(DSIZE - 1 downto 0);
 signal tmp : CHAIN;

begin
 process(clk)
 begin
  if rising_edge(clk) then
   tmp(0) <= datain;
   looptmp : for i in 0 to 2 * NBTAP - 2 loop
    tmp(i + 1) <= tmp(i);
   end loop;
  end if;
 end process;

 dataout <= tmp(2 * NBTAP - 1);

end rtl;

--
-- FIR filter engine (multiply with pre-add and post-add)
-- submodule used in top (sfir_even_symmetric_systolic_top)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sfir_even_symmetric_systolic_element is
 generic(DSIZE : natural := 16);
 port(clk                      : in  std_logic;
   coeffin, datain, datazin : in  std_logic_vector(DSIZE - 1 downto 0);
   cascin                   : in  std_logic_vector(2 * DSIZE downto 0);
   cascdata                 : out std_logic_vector(DSIZE - 1 downto 0);
   cascout                  : out std_logic_vector(2 * DSIZE downto 0));
end sfir_even_symmetric_systolic_element;

architecture rtl of sfir_even_symmetric_systolic_element is

 -- Declare signals
 --
 signal coeff, data, dataz, datatwo : signed(DSIZE - 1 downto 0);
 signal preadd                      : signed(DSIZE downto 0);
 signal product, cascouttmp         : signed(2 * DSIZE downto 0);

begin
 process(clk)
 begin
  if rising_edge(clk) then
   coeff      <= signed(coeffin);
   data       <= signed(datain);
   datatwo    <= data;
   dataz      <= signed(datazin);
   preadd     <= resize(datatwo, DSIZE + 1) + resize(dataz, DSIZE + 1);
   product    <= preadd * coeff;
   cascouttmp <= product + signed(cascin);
  end if;
 end process;

 -- Type conversion for output
 --
 cascout  <= std_logic_vector(cascouttmp);
 cascdata <= std_logic_vector(datatwo);

end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sfir_even_symmetric_systolic_top is
 generic(NBTAP : natural := 4;
      DSIZE : natural := 16;
      PSIZE : natural := 33);
 port(clk    : in  std_logic;
   datain : in  std_logic_vector(DSIZE - 1 downto 0);
   firout : out std_logic_vector(PSIZE - 1 downto 0));
end sfir_even_symmetric_systolic_top;

architecture rtl of sfir_even_symmetric_systolic_top is

 -- Declare signals
 --
 type DTAB is array (0 to NBTAP - 1) of std_logic_vector(DSIZE - 1 downto 0);
 type HTAB is array (0 to NBTAP - 1) of std_logic_vector(0 to DSIZE - 1);
 type PTAB is array (0 to NBTAP - 1) of std_logic_vector(PSIZE - 1 downto 0);

 signal arraydata, dataz : DTAB;
 signal arrayprod        : PTAB;
 signal shifterout       : std_logic_vector(DSIZE - 1 downto 0);

 -- Initialize coefficients and a "zero" for the first filter element
 --
 constant h : HTAB := ((std_logic_vector(TO_SIGNED(63, DSIZE))),
  (std_logic_vector(TO_SIGNED(18, DSIZE))),
  (std_logic_vector(TO_SIGNED(-100, DSIZE))),
  (std_logic_vector(TO_SIGNED(1, DSIZE))));
 constant zero_psize : std_logic_vector(PSIZE - 1 downto 0) := (others => '0');

begin

 -- Connect last product to output
 --
 firout <= arrayprod(nbtap - 1);

 -- Shifter
 --
 shift_u0 : entity work.sfir_shifter
  generic map(DSIZE, NBTAP)
  port map(clk, datain, shifterout);

 -- Connect the arithmetic building blocks of the FIR
 --
 gen : for I in 0 to NBTAP - 1 generate
 begin
  g0 : if I = 0 generate
   element_u0 : entity work.sfir_even_symmetric_systolic_element
    generic map(DSIZE)
    port map(clk, h(I), datain, shifterout, zero_psize, arraydata(I), arrayprod(I));
  end generate g0;
  gi : if I /= 0 generate
   element_ui : entity work.sfir_even_symmetric_systolic_element
    generic map(DSIZE)
    port map(clk, h(I), arraydata(I - 1), shifterout, arrayprod(I - 1), arraydata(I), arrayprod(I));
  end generate gi;
 end generate gen;

end rtl;
