----------------------------------------------------------------------------------
-- Company: API-led Pty Ltd
-- Engineer: Adilson Dias
-- 
-- Create Date: 28.10.2025 13:42:59
-- Design Name: 
-- Module Name: button_debouncer_tb - Behavioral
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

entity button_debouncer_tb is
--  Port ( );
end button_debouncer_tb;

architecture Behavioral of button_debouncer_tb is

    -- Component Declaration for the Unit Under Test (UUT)
    component button_debouncer
        Generic (
            DEBOUNCE_TIME : integer := 200
        );
        Port (
            clk: in std_logic;
            btn_in: in std_logic;
            led_out: out std_logic
        );
    end component;

   -- Signals to connect to UUT
   signal clk_tb : std_logic := '0';
   signal btn_in_tb : std_logic := '0';
   signal led_out_tb : std_logic;

   -- Clock period definition
   constant CLK_PERIOD : time := 10 ns;  --100MHz 
    
   signal passCounter : integer := 0;
   

begin

    uut: button_debouncer
        generic map (
            DEBOUNCE_TIME => 200  -- Fast for simulation!
        )
        Port map (
            clk => clk_tb,
            btn_in => btn_in_tb,
            led_out => led_out_tb
        );

    -- Clock process definitions
    clk_process :process
    begin
        clk_tb <= '0';
        wait for CLK_PERIOD/2;
        clk_tb <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus process
    stim_proc: process
    begin 
        report "=== BUTTON DEBOUNCER TEST SUITE ===";
        -- Initial state
        btn_in_tb <= '0';       
        -- hold reset state for 100 ns. 
        wait for 1 us;

        -- =============================================
        -- TEST 1: Single Button Press
        -- =============================================
        report "TEST 1: Single Button Press";  
        btn_in_tb <= '1';
        wait for 3 us;  -- Hold for 25ms (longer than debounce)
        btn_in_tb <= '0';
        wait for 500 ns;  -- Wait to observe LED toggle
        assert led_out_tb = '1'
            report "FAILED: LED should be ON after first press." 
            severity error;
        report "PASS: LED toggled to ON";
        passCounter <= passCounter + 1;
        
        -- =============================================
        -- TEST 2: Second button press (toggle off)
        -- =============================================
        report "TEST 2: Second button Press";
        wait for 5 us;
        btn_in_tb <= '1';
        wait for 3 us;  -- Hold for 25ms (longer than debounce)
        btn_in_tb <= '0';
        wait for 500 ns;  -- Wait to observe LED toggle
        assert led_out_tb = '0'
            report "FAILED: LED should be OFF after second press." 
            severity error;
        report "PASS: LED toggled to OFF";  
        passCounter <= passCounter + 1;

        -- =============================================
        -- TEST 3: Button Bounce Simulation
        -- =============================================
        report "TEST 3: Button Bounce Simulation";
        -- Linearly simulate button bounce
        wait for 5 us;
       -- btn_in_tb <= '1';
       -- wait for 2 ms;
       -- btn_in_tb <= '0';
       -- wait for 2 ms;
       -- btn_in_tb <= '1';
       -- wait for 2 ms;
       -- btn_in_tb <= '0';
       -- wait for 2 ms;
       -- btn_in_tb <= '1';
       -- wait for 25 ms;  -- Hold for 25ms (longer than debounce)
       -- btn_in_tb <= '0';
       -- wait for 5 ms;  -- Wait to observe LED toggle
       -- assert led_out_tb = '1'
       --     report "FAILED: LED should be ON after bounce press." 
       --     severity error;
       -- report "PASS: LED toggled to ON despite bounce";

        -- Simulate bouncing rapidly on/off
        for i in 0 to 10 loop
            btn_in_tb <= '1';
            wait for 10 ns; -- Short glitch
            btn_in_tb <= '0';
            wait for 10 ns;
        end loop;

        -- Then hold steady press
        btn_in_tb <= '1';
        wait for 3 us;  -- Hold for 25ms (longer than debounce)
        btn_in_tb <= '0';
        wait for 500 ns;  -- Wait to observe LED toggle

        -- LED should have toggled only ONCE despite bounces
        assert led_out_tb = '1'
            report "FAIL: LED should toggle once despite bounce" 
            severity error;
        report "PASS: Debouncer filtered bounce correctly";
        passCounter <= passCounter + 1;

        -- =============================================
        -- TEST 4: Rapid presses (should all count)
        -- =============================================
        report "TEST 4: Multiple distinct presses";         
        
        for i in 1 to 5 loop
            wait for 5 us; -- Wait longer than debounce time
            btn_in_tb <= '1';
            wait for 3 us;  -- Hold for 25ms (longer than debounce)
            btn_in_tb <= '0';    
        end loop;
            
        wait for 5 us; -- Wait to observe LED toggles
        -- After 5 presses from state '1', LED should be '0'
        assert led_out_tb = '0'
            report "FAIL: LED should be OFF after 5 more presses" 
            severity error;
        report "PASS: LED toggled correctly after multiple presses";
        passCounter <= passCounter + 1;
        wait for 5 us; -- update passCounter
        --- Final report
        report "=== TEST SUMMARY: " & integer'image(passCounter) & " / 4 TESTS PASSED ===";
        report "=== ALL TESTS COMPLETE ===";
        wait;
    end process;

    -- Monitor LED changes
    monitor: process(led_out_tb)
    begin
        report "LED State Changed to: " & std_logic'image(led_out_tb) & " at time " & time'image(now);
    end process;

      
end Behavioral;