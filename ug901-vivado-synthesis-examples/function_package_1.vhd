-- Declaration of a function in a package
--
-- function_package_1.vhd
--
package PKG is
 function ADD(A, B, CIN : BIT) return BIT_VECTOR;
end PKG;

package body PKG is
 function ADD(A, B, CIN : BIT) return BIT_VECTOR is
  variable S, COUT : BIT;
  variable RESULT  : BIT_VECTOR(1 downto 0);
 begin
  S      := A xor B xor CIN;
  COUT   := (A and B) or (A and CIN) or (B and CIN);
  RESULT := COUT & S;
  return RESULT;
 end ADD;
end PKG;

use work.PKG.all;

entity function_package_1 is
 port(
  A, B : in  BIT_VECTOR(3 downto 0);
  CIN  : in  BIT;
  S    : out BIT_VECTOR(3 downto 0);
  COUT : out BIT
 );
end function_package_1;

architecture ARCHI of function_package_1 is
 signal S0, S1, S2, S3 : BIT_VECTOR(1 downto 0);
begin
 S0   <= ADD(A(0), B(0), CIN);
 S1   <= ADD(A(1), B(1), S0(1));
 S2   <= ADD(A(2), B(2), S1(1));
 S3   <= ADD(A(3), B(3), S2(1));
 S    <= S3(0) & S2(0) & S1(0) & S0(0);
 COUT <= S3(1);
end ARCHI;
