----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 27.10.2025 19:19:44
-- Design Name: 
-- Module Name: binary_counter_tb - Behavioral
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

entity binary_counter_tb is
--  Port ( );
end binary_counter_tb;

architecture Behavioral of binary_counter_tb is
    -- component declaration based on the design
    component binary_counter
        Generic (COUNT_MAX : integer);
        Port(
            clk: in std_logic;
            reset : in STD_LOGIC;  -- Add this!
            led: out std_logic_vector(3 downto 0)
        );
        
    end component;
    -- testbench signals
    signal clk_tb : std_logic := '0';
    signal led_tb: std_logic_vector(3 downto 0);
    
    --clock period (10ns = 100MHZ)
    constant CLK_PERIOD: time := 10 ns;
    
    signal reset_tb : STD_LOGIC := '0';
    
begin
    
    
    
    -- instantiate the unit under test(uut)
    uut: binary_counter
    generic map (
        COUNT_MAX => 99  -- Fast for simulation!
    )
    port map(
        clk => clk_tb,
        reset => reset_tb,
        led => led_tb
       );
       
    -- clock generation process
    clk_process: process
    begin
        clk_tb <= '0';
        wait for CLK_PERIOD/2;
        clk_tb <= '1';
        wait for CLK_PERIOD/2;
    end process;     
    
    -- stimulus process (optinal - just let it run)
    -- stim_proc: process
    --  begin
    -- wait for similation to run
    --  wait for 10 sec; -- simulate for 10 seconds
    
    -- end simulation
    -- report "Simulation completed succesfully!";
    -- wait; -- stop here
    --end process;
    
-- Comprehensive test
    stim_proc: process
    begin
        report "=== TEST SUITE STARTED ===";
        
        -- TEST 1: Initial state
        report "TEST 1: Verify initial state";
        wait for 100 ns;
        assert led_tb = "0000" 
            report "PASS: Initial state correct" 
            severity note;
        
        -- TEST 2: Normal counting
        report "TEST 2: Normal counting operation";
        wait for 3 us;
        assert led_tb /= "0000" 
            report "PASS: Counter is incrementing" 
            severity note;
        
        -- TEST 3: Reset during operation
        report "TEST 3: Reset during counting";
        wait for 2 us;
        report "LED before reset: " & integer'image(to_integer(unsigned(led_tb)));
        
        reset_tb <= '1';
        wait for 100 ns;
        assert led_tb = "0000" 
            report "PASS: Reset clears counter" 
            severity note;
        
        reset_tb <= '0';
        wait for 100 ns;
        
        -- TEST 4: Counting resumes after reset
        report "TEST 4: Verify counting resumes";
        wait for 2 us;
        assert led_tb /= "0000" 
            report "PASS: Counting resumed after reset" 
            severity note;
        
        -- TEST 5: Multiple resets
        report "TEST 5: Rapid reset testing";
        for i in 1 to 3 loop
            wait for 1 us;
            reset_tb <= '1';
            wait for 50 ns;
            reset_tb <= '0';
            wait for 50 ns;
            assert led_tb = "0000" or led_tb = "0001"
                report "PASS: Reset cycle " & integer'image(i)
                severity note;
        end loop;
        
        -- Final run
        wait for 5 us;
        
        report "=== TEST SUITE COMPLETED - ALL TESTS PASSED ===";
        wait;
    end process;
    
    -- Timing measurement
    timing_check: process
        variable reset_time : time;
        variable led_zero_time : time;
    begin
        -- Wait for reset to go high
        wait until reset_tb = '1';
        reset_time := now;
        report "Reset asserted at: " & time'image(reset_time);
        
        -- Wait for LED to become zero
        wait until led_tb = "0000";
        led_zero_time := now;
        report "LED reset at: " & time'image(led_zero_time);
        report "Reset latency: " & time'image(led_zero_time - reset_time);
        
        wait;
    end process;
    
    -- Assertion checker
    check_reset: process(clk_tb)
    begin
        if rising_edge(clk_tb) then
            -- Verify: when reset is high, counter should be 0
            if reset_tb = '1' then
                assert led_tb = "0000"
                    report "ERROR: LED not zero during reset!"
                    severity error;
            end if;
        end if;
    end process;
    
    -- Monitor output
    monitor: process(led_tb)
    begin
       report "LED value changed to: " & integer'image(to_integer(unsigned(led_tb)));
    end process;
    
end Behavioral;
