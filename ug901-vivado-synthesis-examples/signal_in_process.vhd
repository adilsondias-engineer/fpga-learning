-- Signal assignment in a process
-- signal_in_process.vhd

entity signal_in_process is
 port(
  A, B : in  BIT;
  S    : out BIT
 );
end signal_in_process;

architecture archi of signal_in_process is
begin
 process(A, B)
 begin
  S <= '0';
  if ((A and B) = '1') then
   S <= '1';
  end if;
 end process;
end archi;
