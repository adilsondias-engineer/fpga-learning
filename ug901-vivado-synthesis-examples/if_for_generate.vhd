
-- A for-generate nested in a if-generate
--
-- if_for_generate.vhd
--
entity if_for_generate is
 generic(
  N : INTEGER := 8
 );
 port(
  A, B : in  BIT_VECTOR(N downto 0);
  CIN  : in  BIT;
  SUM  : out BIT_VECTOR(N downto 0);
  COUT : out BIT
 );
end if_for_generate;

architecture archi of if_for_generate is
 signal C : BIT_VECTOR(N + 1 downto 0);
begin
 IF_N : if (N >= 4 and N <= 32) generate
  C(0) <= CIN;
  COUT <= C(N + 1);
  LOOP_ADD : for I in 0 to N generate
   SUM(I)   <= A(I) xor B(I) xor C(I);
   C(I + 1) <= (A(I) and B(I)) or (A(I) and C(I)) or (B(I) and C(I));
  end generate;
 end generate;
end archi;
