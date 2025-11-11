-- Declaration of a procedure in a package
--
-- Download: procedure_package_1.vhd
--
package PKG is
 procedure ADD(
  A, B, CIN : in  BIT;
  C         : out BIT_VECTOR(1 downto 0));
end PKG;

package body PKG is
 procedure ADD(
  A, B, CIN : in  BIT;
  C         : out BIT_VECTOR(1 downto 0)) is
  variable S, COUT : BIT;
 begin
  S    := A xor B xor CIN;
  COUT := (A and B) or (A and CIN) or (B and CIN);
  C    := COUT & S;
 end ADD;
end PKG;

use work.PKG.all;

entity procedure_package_1 is
 port(
  A, B : in  BIT_VECTOR(3 downto 0);
  CIN  : in  BIT;
  S    : out BIT_VECTOR(3 downto 0);
  COUT : out BIT
 );
end procedure_package_1;

architecture ARCHI of procedure_package_1 is
begin
 process(A, B, CIN)
  variable S0, S1, S2, S3 : BIT_VECTOR(1 downto 0);
 begin
  ADD(A(0), B(0), CIN, S0);
  ADD(A(1), B(1), S0(1), S1);
  ADD(A(2), B(2), S1(1), S2);
  ADD(A(3), B(3), S2(1), S3);
  S    <= S3(0) & S2(0) & S1(0) & S0(0);
  COUT <= S3(1);
 end process;
end ARCHI;
