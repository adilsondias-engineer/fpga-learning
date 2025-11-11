--
-- A simple component instantiation example
--   Involves a component declaration and the component instantiation itself
--
-- instantiation_simple.vhd
--
entity sub is
 generic(
  WIDTH : integer := 4
 );
 port(
  A, B : in  BIT_VECTOR(WIDTH - 1 downto 0);
  O    : out BIT_VECTOR(2 * WIDTH - 1 downto 0)
 );
end sub;

architecture archi of sub is
begin
 O <= A & B;
end ARCHI;

entity instantiation_simple is
 generic(
  WIDTH : integer := 2);
 port(
  X, Y : in  BIT_VECTOR(WIDTH - 1 downto 0);
  Z    : out BIT_VECTOR(2 * WIDTH - 1 downto 0));
end instantiation_simple;

architecture ARCHI of instantiation_simple is
 component sub                       -- component declaration
  generic(
   WIDTH : integer := 2);
  port(
   A, B : in  BIT_VECTOR(WIDTH - 1 downto 0);
   O    : out BIT_VECTOR(2 * WIDTH - 1 downto 0));
 end component;

begin
 inst_sub : sub                      -- component instantiation
  generic map(
   WIDTH => WIDTH
  )
  port map(
   A => X,
   B => Y,
   O => Z
  );

end ARCHI;
