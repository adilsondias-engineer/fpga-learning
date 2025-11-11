-- Signed 40-bit streaming accumulator with 16-bit inputs
-- File: multipliers3.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity macc is
 generic(SIZEIN  : natural := 16;
      SIZEOUT : natural := 40
 );
 port(clk, ce, sload : in  std_logic;
   a, b           : in  signed(SIZEIN - 1 downto 0);
   accum_out      : out signed(SIZEOUT - 1 downto 0)
 );
end entity;

architecture rtl of macc is
 -- Declare registers for intermediate values
 signal a_reg, b_reg          : signed(SIZEIN - 1 downto 0);
 signal sload_reg             : std_logic;
 signal mult_reg              : signed(2 * SIZEIN - 1 downto 0);
 signal adder_out, old_result : signed(SIZEOUT - 1 downto 0);

begin
 process(adder_out, sload_reg)
 begin
  if sload_reg = '1' then
   old_result <= (others => '0');
  else
   -- 'sload' is now active (=low) and opens the accumulation loop.
   -- The accumulator takes the next multiplier output in
   -- the same cycle.
   old_result <= adder_out;
  end if;
 end process;

 process(clk)
 begin
  if rising_edge(clk) then
   if ce = '1' then
    a_reg     <= a;
    b_reg     <= b;
    mult_reg  <= a_reg * b_reg;
    sload_reg <= sload;
    -- Store accumulation result into a register
    adder_out <= old_result + mult_reg;
   end if;
  end if;
 end process;

 -- Output accumulation result
 accum_out <= adder_out;

end rtl;