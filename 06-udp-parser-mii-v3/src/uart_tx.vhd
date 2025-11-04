----------------------------------------------------------------------------------
-- UART Transmitter (FPGA -> PC)
-- Baud Rate: 115200
-- Data: 8 bits, No parity, 1 stop bit (8N1)
--
-- Trading Relevance: Foundation for serial protocols and data serialization
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL; 
-- use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Generic (
        CLK_FREQ : integer := 100_000_000; -- 100 MHz system clock
        BAUD_RATE : integer := 115_200 -- Standard UART baud rate
    );
    Port (
        clk         : in  std_logic;
        reset       : in  std_logic;
       
        -- Data interface
        tx_data : in std_logic_vector(7 downto 0); -- byte to transmit
        tx_start : in std_logic; -- signal to start transmission , pulse transmission
        tx_busy : out std_logic; -- transmitter busy flag   High when transmitting

         -- UART output
        tx_serial : out std_logic  -- UART transmit line
    );
end uart_tx;


architecture Behavioral of uart_tx is

    -- Calculcate the number of per bit
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE; -- 868 for 100MHz and 115200 baud

    --state machine
    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : state_type := IDLE;

    -- Counters
    signal clk_counter : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_counter : integer range 0 to 7 := 0;

    -- data register
    signal tx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');


    begin
                
        process(clk)
        begin
            if rising_edge(clk) then
                if reset = '1' then
                    state <= IDLE;
                    tx_serial <= '1'; -- idle state is high
                    tx_busy <= '0';
                    clk_counter <= 0;
                    bit_counter <= 0;
                else
                    case state is
                        when IDLE =>
                            tx_serial <= '1'; -- idle state is high
                            tx_busy <= '0';
                            clk_counter <= 0;
                            bit_counter <= 0;
                            if tx_start = '1' then
                                tx_shift_reg <= tx_data; -- load data to shift register
                                state <= START_BIT;
                                tx_busy <= '1';
                            end if;

                        when START_BIT =>
                            tx_serial <= '0'; -- start bit = LOW
                            if clk_counter < CLKS_PER_BIT - 1 then
                                clk_counter <= clk_counter + 1;
                            else
                                clk_counter <= 0;
                                state <= DATA_BITS;
                            end if;

                        when DATA_BITS =>
                            tx_serial <= tx_shift_reg(bit_counter); -- send LSB first
                            if clk_counter < CLKS_PER_BIT - 1 then
                                clk_counter <= clk_counter + 1;
                            else
                                clk_counter <= 0;
                                if bit_counter < 7 then
                                    bit_counter <= bit_counter + 1;
                                else
                                    bit_counter <= 0;
                                    state <= STOP_BIT;
                                end if;
                            end if;

                        when STOP_BIT =>
                            tx_serial <= '1'; -- stop bit = HIGH
                            if clk_counter < CLKS_PER_BIT - 1 then
                                clk_counter <= clk_counter + 1;
                            else
                                clk_counter <= 0;
                                state <= IDLE;
                            end if;
                    end case;
                end if;
            end if;
        end process;

end Behavioral;