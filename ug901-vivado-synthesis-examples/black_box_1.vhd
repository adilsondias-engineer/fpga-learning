-- Black Box
-- black_box_1.vhd
library ieee;
use ieee.std_logic_1164.all;

entity black_box_1 is
 port(DI_1, DI_2 : in  std_logic;
   DOUT       : out std_logic);
end black_box_1;
architecture rtl of black_box_1 is
 component black_box1
  port(I1 : in  std_logic;
    I2 : in  std_logic;
    O  : out std_logic);
 end component;

 attribute black_box : string;
 attribute black_box of black_box1 : component is "yes";

begin
 U1 : black_box1 port map(I1 => DI_1, I2 => DI_2, O => DOUT);
end rtl;
