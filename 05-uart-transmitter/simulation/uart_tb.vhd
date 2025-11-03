----------------------------------------------------------------------------------
-- UART TX/RX Testbench
-- Tests transmitter and receiver with various byte values
-- This testbench doesn't cover all edge cases but provides a basic validation of functionality or new functionalities added
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tb is
end uart_tb;

architecture Behavioral of uart_tb is
    
    -- Component declarations
    component uart_tx is
        Generic (
            CLK_FREQ : integer := 100_000_000;
            BAUD_RATE : integer := 115_200
        );
        Port (
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            tx_data : in STD_LOGIC_VECTOR(7 downto 0);
            tx_start : in STD_LOGIC;
            tx_busy : out STD_LOGIC;
            tx_serial : out STD_LOGIC
        );
    end component;
    
    component uart_rx is
        Generic (
            CLK_FREQ : integer := 100_000_000;
            BAUD_RATE : integer := 115_200
        );
        Port (
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            rx_serial : in STD_LOGIC;
            rx_data : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid : out STD_LOGIC
        );
    end component;
    
    -- Testbench signals
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    
    signal clk : STD_LOGIC := '0';
    signal reset : STD_LOGIC := '1';
    
    -- TX signals
    signal tx_data : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal tx_start : STD_LOGIC := '0';
    signal tx_busy : STD_LOGIC;
    signal tx_serial : STD_LOGIC;
    
    -- RX signals
    signal rx_data : STD_LOGIC_VECTOR(7 downto 0);
    signal rx_valid : STD_LOGIC;
    
    -- Test control
    signal test_running : boolean := true;
    
begin
    
    -- Clock generation
    clk_process : process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;
    
    -- Instantiate TX
    uart_tx_inst : uart_tx
        port map (
            clk => clk,
            reset => reset,
            tx_data => tx_data,
            tx_start => tx_start,
            tx_busy => tx_busy,
            tx_serial => tx_serial
        );
    
    -- Instantiate RX (connected to TX output for loopback test)
    uart_rx_inst : uart_rx
        port map (
            clk => clk,
            reset => reset,
            rx_serial => tx_serial,  -- Loopback connection!
            rx_data => rx_data,
            rx_valid => rx_valid
        );
    
    -- Stimulus process
    stimulus : process
    begin
        -- Reset
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;
        
        report "=== Starting UART Loopback Test ===" severity note;
        
        -- Test 1: Send 0x41 ('A')
        report "Test 1: Sending 0x41 ('A')..." severity note;
        tx_data <= X"41";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        -- Wait for transmission to complete
        wait until tx_busy = '0';
        wait for 1 us;  -- Small delay
        
        -- Check received data
        assert rx_valid = '1' report "RX valid not asserted!" severity error;
        assert rx_data = X"41" report "RX data mismatch! Expected 0x41" severity error;
        report "Test 1: PASSED - Received 0x41" severity note;
        
        wait for 10 us;
        
        -- Test 2: Send 0x55 (01010101 pattern)
        report "Test 2: Sending 0x55 (pattern)..." severity note;
        tx_data <= X"55";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        wait until tx_busy = '0';
        wait for 1 us;
        
        assert rx_data = X"55" report "RX data mismatch! Expected 0x55" severity error;
        report "Test 2: PASSED - Received 0x55" severity note;
        
        wait for 10 us;
        
        -- Test 3: Send 0xAA (10101010 pattern)
        report "Test 3: Sending 0xAA (pattern)..." severity note;
        tx_data <= X"AA";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        wait until tx_busy = '0';
        wait for 1 us;
        
        assert rx_data = X"AA" report "RX data mismatch! Expected 0xAA" severity error;
        report "Test 3: PASSED - Received 0xAA" severity note;
        
        wait for 10 us;
        
        -- Test 4: Send 0xFF (all ones)
        report "Test 4: Sending 0xFF..." severity note;
        tx_data <= X"FF";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        wait until tx_busy = '0';
        wait for 1 us;
        
        assert rx_data = X"FF" report "RX data mismatch! Expected 0xFF" severity error;
        report "Test 4: PASSED - Received 0xFF" severity note;
        
        wait for 10 us;
        
        -- Test 5: Send 0x00 (all zeros)
        report "Test 5: Sending 0x00..." severity note;
        tx_data <= X"00";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        
        wait until tx_busy = '0';
        wait for 1 us;
        
        assert rx_data = X"00" report "RX data mismatch! Expected 0x00" severity error;
        report "Test 5: PASSED - Received 0x00" severity note;
        
        wait for 10 us;
        
        report "=== ALL TESTS RUN SUCCESSFULLY ===" severity note;
        
        -- End simulation
        test_running <= false;
        wait;
    end process;
    
    -- Monitor process (displays received data)
    monitor : process
    begin
        wait until rising_edge(clk);
        if rx_valid = '1' then
            report "RECEIVED: 0x" & to_hstring(rx_data) & " (ASCII: " &
                   character'image(character'val(to_integer(unsigned(rx_data)))) & ")" 
                   severity note;
        end if;
    end process;
    
end Behavioral;