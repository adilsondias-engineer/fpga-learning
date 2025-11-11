-- Ram Inference Example using Records (True Dual port) 
-- File:rams_tdp_record.vhd

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
entity rams_tdp_record is generic (
                       A_WID    : integer := 10;
                       D_WID    : integer := 32
                      );
                port  (
                       clka    : in std_logic;
                       clkb    : in std_logic;
                       wea     : in std_logic;
                       web     : in std_logic;
                       ena    : in std_logic;
                       enb    : in std_logic;
                       addra   : in std_logic_vector(A_WID-1 downto 0);
                       addrb   : in std_logic_vector(A_WID-1 downto 0);
                       dina    : in Packet; 
                       dinb    : in Packet; 
                       douta   : out Packet;
                       doutb   : out Packet
                      );
end rams_tdp_record;

architecture arch of rams_tdp_record is
signal mem : mem_t(2**A_WID-1 downto 0);
begin

process(clka)
begin
  if(clka'event and clka='1') then
      if(ena = '1') then
      douta <= mem(to_integer(unsigned(addra)));
        if(wea = '1') then
          mem(to_integer(unsigned(addra))) <= dina;
        end if;
      end if;
  end if;
end process;


process(clkb)
begin
  if(clkb'event and clkb='1') then
      if(enb = '1') then
      doutb <= mem(to_integer(unsigned(addrb)));
        if(web = '1') then
          mem(to_integer(unsigned(addrb))) <= dinb;
        end if;
      end if;
  end if;
end process;

end arch;
