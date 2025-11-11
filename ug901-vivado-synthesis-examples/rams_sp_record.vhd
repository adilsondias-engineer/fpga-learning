-- Ram Inference Example using Records (Single port) 
-- File:rams_sp_record.vhd

library ieee;
use ieee.std_logic_1164.all;
package mypack is
  type Packet is record
    addr : std_logic_vector(3 downto 0);
    data : std_logic_vector(27 downto 0);
  end record Packet;
  type mem_t is array(integer range<>) of Packet;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mypack.all;
entity rams_sp_record is generic (
                       A_WID    : integer := 10;
                       D_WID    : integer := 32
                      );
                port  (
                       clk    : in std_logic;
                       we     : in std_logic;
                       ena    : in std_logic;
                       addr   : in std_logic_vector(A_WID-1 downto 0);
                       din    : in Packet; 
                       dout   : out Packet 
                      );
end rams_sp_record;

architecture arch of rams_sp_record is
signal mem : mem_t(2**A_WID-1 downto 0);
begin
process(clk)
begin
  if(clk'event and clk='1') then
      if(ena = '1') then
        if(we = '1') then
          mem(to_integer(unsigned(addr))) <= din;
        end if;
        dout <= mem(to_integer(unsigned(addr)));
      end if;
  end if;
end process;

end arch;
