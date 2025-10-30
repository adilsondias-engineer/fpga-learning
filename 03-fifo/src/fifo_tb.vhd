library IEEE;
use IEEE.STD_LOGIC_1164.ALL; 
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo_tb is
end fifo_tb;

architecture Behavioral of fifo_tb  is

    -- Component declaration for the Unit Under Test (UUT)
    component fifo is
        Generic (
            DATA_WIDTH : integer := 8; -- Width of the data bus
            FIFO_DEPTH : integer := 16 -- Number of entries in the FIFO (must be power of 2)
        );
        Port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            --Write Interface
            wr_en       : in  std_logic;
            data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            --Read Interface
            rd_en       : in  std_logic;
            data_out    : out std_logic_vector(DATA_WIDTH-1 downto 0);

            -- Status signals
            full        : out std_logic;
            empty       : out std_logic;
            count       : out std_logic_vector(4 downto 0)
        );
    end component;

    -- Signals to connect to UUT
    signal clk_tb         : std_logic := '0';
    signal rst_tb         : std_logic := '0';
    signal wr_en_tb       : std_logic := '0';
    signal data_in_tb     : std_logic_vector(7 downto 0) := (others => '0');
    signal rd_en_tb       : std_logic := '0';
    signal data_out_tb    : std_logic_vector(7 downto 0);
    signal full_tb        : std_logic;
    signal empty_tb       : std_logic;
    signal count_tb       : std_logic_vector(4 downto 0);

    -- Clock period definition
    constant CLK_PERIOD : time := 10 ns;  --100MHz
begin

    --Instantiate the Unit Under Test (UUT)
    uut: fifo
        generic map (
            DATA_WIDTH => 8,
            FIFO_DEPTH => 16
        )
        Port map (
            clk         => clk_tb,
            rst         => rst_tb,
            wr_en       => wr_en_tb,
            data_in     => data_in_tb,
            rd_en       => rd_en_tb,
            data_out    => data_out_tb,
            full        => full_tb,
            empty       => empty_tb,
            count       => count_tb
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
        -- TEST 1: Reset behavior
        report "===  TEST 1: Reset behavior ===";
        -- Reset the FIFO
       rst_tb <= '1';
       wait for CLK_PERIOD * 2;
       rst_tb <= '0';
       wait for CLK_PERIOD;

       assert empty_tb = '1' report "FIFO should be empty after reset" severity error;
       assert full_tb = '0' report "FIFO should not be full after reset" severity error;
       assert count_tb = "00000" report "FIFO count should be 0 after reset" severity error;

--         TEST 2: Write single item
       report "===  TEST 2: Write single item ===";
--         Write data into FIFO
       wr_en_tb <= '1';
       data_in_tb <= x"AA";
       wait for CLK_PERIOD;
       wr_en_tb <= '0';
       wait for CLK_PERIOD;

       assert empty_tb = '0' report "FIFO should not be empty after one write" severity error;
       assert count_tb = "00001" report "FIFO count should be 1 after one write" severity error;

        -- TEST 3: Read Single item
       report "===  TEST 3: Read single item ===";
       rd_en_tb <= '1';
       wait for CLK_PERIOD;
       rd_en_tb <= '0';
       wait for CLK_PERIOD;

       assert data_out_tb = x"AA" report "Data read from FIFO does not match data written" severity error;
       assert empty_tb = '1' report "FIFO should be empty after reading the only item" severity error;
       assert count_tb = "00000" report "FIFO count should be 0 after reading the only item" severity error;
       
        -- TEST 4: Fill FIFO to capacity
        report "===  TEST 4: Fill FIFO to capacity ===";
        for i in 0 to 15 loop
            wr_en_tb <= '1';
            data_in_tb <= std_logic_vector(to_unsigned(i, 8));
            wait for CLK_PERIOD;
        end loop;
        wr_en_tb <= '0';
        wait for CLK_PERIOD;

        assert full_tb = '1' report "FIFO should be full after writing maximum items" severity error;
        assert count_tb = "10000" report "FIFO count should be 16 after filling to capacity" severity error;

         -- Test 5: Try to write when full (should be ignored)
       report "TEST 5: Write when full (should be ignored)";
       wr_en_tb <= '1';
       data_in_tb <= x"FF";
       wait for CLK_PERIOD;
       wr_en_tb <= '0';
       wait for CLK_PERIOD;
        
       assert unsigned(count_tb) = 16 report "Count should still be 16" severity error;

        -- TEST 6: Empty FIFO completely (16 reads)
        report "===  TEST 6: Empty FIFO completely ===";
--         Read data from FIFO
        for i in 0 to 15 loop
            rd_en_tb <= '1';
            wait for CLK_PERIOD;
            assert data_out_tb = std_logic_vector(to_unsigned(i, 8)) 
                report "Data read from FIFO does not match expected value" severity error;
        end loop;
        rd_en_tb <= '0';
        wait for Clk_PERIOD;

        assert empty_tb = '1' report "FIFO should be empty after reading all items" severity error;
        assert count_tb = "00000" report "FIFO count should be 0 after reading all items" severity error;

        -- TEST 7: Try to read when empty (should be ignored)
        report "TEST 7: Read when empty (should be ignored)"; 
        rd_en_tb <= '1';
        wait for CLK_PERIOD;
        rd_en_tb <= '0';
        wait for CLK_PERIOD;
        
        assert unsigned(count_tb) = 0 report "Count should still be 0" severity error;
    
        -- TEST 8: Simoultaneous read and write
        report "===  TEST 8: Simoultaneous read and write ===";
        -- Write initial data
        wr_en_tb <= '1';
        data_in_tb <= x"55";
        wait for CLK_PERIOD;
        wr_en_tb <= '0';
        wait for CLK_PERIOD;
        
        -- Now perform simultaneous read and write
        wr_en_tb <= '1';
        data_in_tb <= x"AA";
        rd_en_tb <= '1';
        wait for CLK_PERIOD;
        wr_en_tb <= '0';
        rd_en_tb <= '0';
        wait for CLK_PERIOD;
        
        assert data_out_tb = x"55" report "Data read from FIFO does not match expected value during simultaneous read/write" severity error;
        assert count_tb = "00001" report "FIFO count should be 1 after simultaneous read/write" severity error;
        
        --TEST 9: Wrap-around behavior
        report "===  TEST 9: Wrap-around behavior ===";
        rst_tb <= '1';
        wait for CLK_PERIOD;
        rst_tb <= '0';
        wait for CLK_PERIOD;

        -- Wrtie 20 items to test wrap-around -> it will wrap after 16
        for i in 0 to 19 loop
            wr_en_tb <= '1';
            data_in_tb <= std_logic_vector(to_unsigned(i, 8));
            wait for CLK_PERIOD;

            -- Read after 4 writes to start emptying FIFO and keep FIFO partially filled
            if(i >= 4) then
                rd_en_tb <= '1';
            end if;
            wait for CLK_PERIOD;

            wr_en_tb <= '0';
            rd_en_tb <= '0';
            wait for CLK_PERIOD;

        end loop;
        
        -- After 20 writes and 16 reads, there should be 4 items left: 16,17,18,19
        assert count_tb = "00100" report "FIFO count should be 4 after wrap-around test" severity error;
        for i in 16 to 19 loop
            rd_en_tb <= '1';
            wait for CLK_PERIOD;
            assert data_out_tb = std_logic_vector(to_unsigned(i, 8)) 
                report "Data read from FIFO does not match expected value after wrap-around" severity error;
            rd_en_tb <= '0';
            wait for CLK_PERIOD;
        end loop;

        report "=== ALL TESTS RUN SUCCESSFULLY ===";
        
        -- Finish simulation
        wait;
    end process;

end Behavioral; 