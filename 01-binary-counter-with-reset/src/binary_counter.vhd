----------------------------------------------------------------------------------
-- Company: API-led Pty Ltd
-- Engineer: Adilson Dias
-- 
-- Create Date: 27.10.2025 17:38:53
-- Design Name: 
-- Module Name: binary_counter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity binary_counter is
    Generic (
        -- constant COUNT_MAX : integer := 99;  -- Change this!
        COUNT_MAX : integer := 99999999  -- 1 second @ 100MHz -- 99 Fast for simulation!
    );
    Port (
        clk: in STD_LOGIC;
        reset : in STD_LOGIC;  -- Add this!
        led: out std_logic_vector(3 downto 0 )
        );
        
end binary_counter;

architecture Behavioral of binary_counter is
    -- clock divider: 100HMZ/ 100M = 1HZ
    signal counter : unsigned(26 downto 0) := (others => '0');
    signal led_count: unsigned(3 downto 0) := (others => '0');
    
   -- Simulation-friendly count (100 clocks instead of 100M)

begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            -- Increment clock divider
            counter <= counter + 1;
            
            --Every second (100M clock cycles)
            if reset = '1' then
              counter <= (others => '0');
              led_count <= (others => '0');
              
            elsif counter = COUNT_MAX then
                counter <= (others => '0');
                led_count <= led_count + 1; --Increment LED counter
                report "LED count incremented to: " & integer'image(to_integer(led_count + 1));
                assert led_count < 16
                    report "Counter wrapped around!"
                    severity note;
            else
                counter <= counter + 1;
             end if;
         end if;
     end process; 
     
    -- Output to LEDs
    led <= std_logic_vector(led_count);
    
end Behavioral;
