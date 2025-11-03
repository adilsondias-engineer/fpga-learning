----------------------------------------------------------------------------------
-- UART Receiver (PC -> FPGA)
-- Baud Rate: 115200
-- Data: 8 bits, No parity, 1 stop bit (8N1)
--
-- Trading Relevance: Understanding data reception and synchronization
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Generic (
        CLK_FREQ : integer := 100_000_000;  -- 100 MHz system clock
        BAUD_RATE : integer := 115_200       -- Standard UART baud rate
    );
    Port (
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        
        -- UART input
        rx_serial : in STD_LOGIC;                          -- Serial input line
        
        -- Data interface
        rx_data : out STD_LOGIC_VECTOR(7 downto 0); -- Received byte
        rx_valid : out STD_LOGIC                    -- Pulse when data ready
    );
end uart_rx;

architecture Behavioral of uart_rx is
    
    -- Calculate clocks per bit
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;  -- 868
    
    -- State machine
    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : state_type := IDLE;
    
    -- Counters
    signal clk_counter : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_counter : integer range 0 to 7 := 0;
    
    -- Data register
    signal rx_shift_reg : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    
    -- Metastability protection (CRITICAL!)
    signal rx_sync : STD_LOGIC_VECTOR(1 downto 0) := (others => '1');
    
begin
    
    -- Synchronize input (prevent metastability - learned in Project 2!)
    process(clk)
    begin
        if rising_edge(clk) then
            rx_sync <= rx_sync(0) & rx_serial;
        end if;
    end process;
    
    -- Main UART receiver state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                rx_valid <= '0';
                clk_counter <= 0;
                bit_counter <= 0;
                rx_data <= (others => '0');
                
            else
                rx_valid <= '0';  -- Default: no new data
                
                case state is
                    
                    when IDLE =>
                        clk_counter <= 0;
                        bit_counter <= 0;
                        
                        -- Detect start bit (HIGH -> LOW transition)
                        if rx_sync(1) = '0' then
                            state <= START_BIT;
                        end if;
                    
                    when START_BIT =>
                        -- Wait half a bit period to sample middle of start bit
                        if clk_counter < (CLKS_PER_BIT / 2) - 1 then
                            clk_counter <= clk_counter + 1;
                        else
                            clk_counter <= 0;
                            
                            -- Verify start bit is still LOW
                            if rx_sync(1) = '0' then
                                state <= DATA_BITS;
                            else
                                state <= IDLE;  -- False start, go back
                            end if;
                        end if;
                    
                    when DATA_BITS =>
                        -- Sample in middle of each bit period
                        if clk_counter < CLKS_PER_BIT - 1 then
                            clk_counter <= clk_counter + 1;
                        else
                            clk_counter <= 0;
                            
                            -- Sample data bit (LSB first)
                            rx_shift_reg(bit_counter) <= rx_sync(1);
                            
                            if bit_counter < 7 then
                                bit_counter <= bit_counter + 1;
                            else
                                bit_counter <= 0;
                                state <= STOP_BIT;
                            end if;
                        end if;
                    
                    when STOP_BIT =>
                        if clk_counter < CLKS_PER_BIT - 1 then
                            clk_counter <= clk_counter + 1;
                        else
                            clk_counter <= 0;
                            
                            -- Verify stop bit is HIGH
                            if rx_sync(1) = '1' then
                                rx_data <= rx_shift_reg;  -- Output received data
                                rx_valid <= '1';           -- Signal valid data
                            end if;
                            
                            state <= IDLE;
                        end if;
                        
                end case;
            end if;
        end if;
    end process;
    
end Behavioral;