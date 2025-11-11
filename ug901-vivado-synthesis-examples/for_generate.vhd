--
-- A for-generate example
--
-- for_generate.vhd
--
entity for_generate is
 port(
  A, B : in  BIT_VECTOR(0 to 7);
  CIN  : in  BIT;
  SUM  : out BIT_VECTOR(0 to 7);
  COUT : out BIT
 );
end for_generate;

architecture archi of for_generate is
 signal C : BIT_VECTOR(0 to 8);
begin
 C(0) <= CIN;
 COUT <= C(8);
 LOOP_ADD : for I in 0 to 7 generate
  SUM(I)   <= A(I) xor B(I) xor C(I);
  C(I + 1) <= (A(I) and B(I)) or (A(I) and C(I)) or (B(I) and C(I));
 end generate;
end archi;
