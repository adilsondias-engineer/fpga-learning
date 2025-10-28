----------------------------------------------------------------------------------
-- Company: API-led Pty Ltd
-- Engineer: Adilson Dias
-- 
-- Create Date: 28.10.2025 13:41:26
-- Design Name: 
-- Module Name: button_debouncer - Behavioral
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

entity button_debouncer is
   Generic (
        DEBOUNCE_TIME : integer := 2_000_000  -- Default for hardware
    );
     Port (
        clk: in std_logic;
        btn_in: in std_logic;
        led_out: out std_logic
       );
end button_debouncer;

architecture Behavioral of button_debouncer is
        -- =============================================
        -- STAGE 1: Synchroniser (Matasbility Protection) 
        -- =============================================
        -- CRITICAL: Always use 2-3 flip-flops to cross clock domains!
        signal btn_sync: std_logic_vector(2 downto 0) := "000";

        -- =============================================
        -- STAGE 2: Debouncer
        -- =============================================
        -- Debountce time: 20ms at 100MHz clock = 2,000,000 cycles
        -- constant DEBOUNCE_TIME : integer := 2_000_000;
        signal deboung_counter : unsigned(20 downto 0)  := (others => '0');
        signal btn_stable: std_logic := '0';        

        -- =============================================
        -- STAGE 3: Edge Detector | One-Pulse Generator
        -- =============================================
        signal btn_prev: std_logic := '0';
        signal btn_rising_edge: std_logic := '0'; 

        -- =============================================
        -- STAGE 4: LED Control | LED Toggle Flip-Flop
        -- =============================================
        signal led_state: std_logic := '0';     

begin

        -- =============================================
        -- STAGE 1: Synchroniser (Matasbility Protection)
        -- =============================================
        -- This prevents metastability when the button signal crosses clock domains.
        -- NEVER connect external signals directly to your logic without synchronisation!

        process(clk)
        begin
            if rising_edge(clk) then
                -- Shift register : btn_in -> sync(0) -> sync(1) ->  sync(2)
                btn_sync <= btn_sync(1 downto 0) & btn_in;
            end if;
        end process;

        -- =============================================
        -- STAGE 2: Debouncer
        -- =============================================
        -- Wait for stable signal before accepting changes.
        process(clk)
        begin
            if rising_edge(clk) then
                -- If the synchronized button state matches the stable state
                if btn_sync(2) = btn_stable then
                    -- Button state is stable, reset counter
                    deboung_counter <= (others => '0');
                else
                    -- Button state changed, increment counter
                    deboung_counter <= deboung_counter + 1;
                    -- If stable for full debounce period, update stable state
                    if deboung_counter = DEBOUNCE_TIME -1 then
                        -- Button state has been stable for the debounce period
                        btn_stable <= btn_sync(2);
                        deboung_counter <= (others => '0');
                    end if;
                end if;
            end if;
        end process;

        -- =============================================
        -- STAGE 3: Edge Detector | One-Pulse Generator
        -- =============================================
        -- Only trigger on the rising edge of the debounced button signal.(button press, not hold)
        process(clk)
        begin
            if rising_edge(clk) then
                btn_rising_edge <= '0'; -- Default no edge
                if btn_stable = '1' and btn_prev = '0' then
                    btn_rising_edge <= '1'; -- Rising edge detected
                end if;
                btn_prev <= btn_stable; -- Update previous state
            end if;
        end process;

        -- =============================================
        -- STAGE 4: LED Control | LED Toggle Flip-Flop
        -- =============================================
        -- Toggle LED state on each button press (rising edge)
        process(clk)
        begin
            if rising_edge(clk) then
                if btn_rising_edge = '1' then
                    led_state <= not led_state; -- Toggle LED state
                end if;
            end if;
        end process;

        -- Output assignment
        led_out <= led_state;

end Behavioral;
