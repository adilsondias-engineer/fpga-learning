--
-- True-Dual-Port BRAM with Byte-wide Write Enable
--  No change mode
--
-- bytewrite_tdp_ram_nc.vhd
--
-- NO_CHANGE ByteWide WriteEnable Block RAM Template

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity bytewrite_tdp_ram_nc is
 generic(
  SIZE       : integer := 1024;
  ADDR_WIDTH : integer := 10;
  COL_WIDTH  : integer := 9;
  NB_COL     : integer := 4
 );

 port(
  clka  : in  std_logic;
  ena   : in  std_logic;
  wea   : in  std_logic_vector(NB_COL - 1 downto 0);
  addra : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
  dia   : in  std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
  doa   : out std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
  clkb  : in  std_logic;
  enb   : in  std_logic;
  web   : in  std_logic_vector(NB_COL - 1 downto 0);
  addrb : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
  dib   : in  std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
  dob   : out std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0)
 );

end bytewrite_tdp_ram_nc;

architecture byte_wr_ram_nc of bytewrite_tdp_ram_nc is
 type ram_type is array (0 to SIZE - 1) of std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
 shared variable RAM : ram_type := (others => (others => '0'));

begin

 -------  Port A -------
 process(clka)
 begin
  if rising_edge(clka) then
   if ena = '1' then
    if (wea = (wea'range => '0')) then
     doa <= RAM(conv_integer(addra));
    end if;
    for i in 0 to NB_COL - 1 loop
     if wea(i) = '1' then
      RAM(conv_integer(addra))((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH) := dia((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH);
     end if;
    end loop;
   end if;
  end if;
 end process;

 -------  Port B -------
 process(clkb)
 begin
  if rising_edge(clkb) then
   if enb = '1' then
    if (web = (web'range => '0')) then
     dob <= RAM(conv_integer(addrb));
    end if;
    for i in 0 to NB_COL - 1 loop
     if web(i) = '1' then
      RAM(conv_integer(addrb))((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH) := dib((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH);
     end if;
    end loop;
   end if;
  end if;
 end process;
end byte_wr_ram_nc;
