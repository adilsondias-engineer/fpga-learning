-- State Machine with single sequential block
-- File: fsm_1.vhd
library IEEE;
use IEEE.std_logic_1164.all;

entity fsm_1 is
 port(
  clk, reset, flag : IN  std_logic;
  sm_out           : OUT std_logic
 );
end entity;

architecture behavioral of fsm_1 is
 type state_type is (s1, s2, s3, s4, s5);
 signal state : state_type;
begin
 process(clk)
 begin
  if rising_edge(clk) then
   if (reset = '1') then
    state  <= s1;
    sm_out <= '1';

   else
    case state is
     when s1 => if flag = '1' then
       state  <= s2;
       sm_out <= '1';

      else
       state  <= s3;
       sm_out <= '0';

      end if;
     when s2 => state <= s4;
      sm_out       <= '0';
     when s3 => state <= s4;
      sm_out       <= '0';
     when s4 => state <= s5;
      sm_out       <= '1';
     when s5 => state <= s1;
      sm_out       <= '1';
    end case;
   end if;
  end if;
 end process;

end behavioral;
