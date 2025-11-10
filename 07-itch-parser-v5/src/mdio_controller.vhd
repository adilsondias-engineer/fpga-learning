--------------------------------------------------------------------------------
-- MDIO Controller
-- Implements IEEE 802.3 Clause 22 MDIO protocol for PHY register access
--------------------------------------------------------------------------------
-- Provides read/write access to DP83848J PHY registers via MDIO interface.
-- MDC clock generated at 2.5 MHz from 100 MHz system clock.
-- Frame format: 32-bit preamble, start, opcode, PHY addr, reg addr, 
-- turnaround, 16-bit data.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mdio_controller is
    generic (
        CLK_FREQ_HZ    : integer := 100_000_000;  -- System clock frequency
        MDC_FREQ_HZ    : integer := 2_500_000     -- MDIO clock frequency (2.5 MHz max)
    );
    port (
        clk            : in    std_logic;         -- System clock
        reset          : in    std_logic;         -- Active high reset
        
        -- Control interface
        start          : in    std_logic;         -- Start transaction (pulse)
        rw             : in    std_logic;         -- '0' = read, '1' = write
        phy_addr       : in    std_logic_vector(4 downto 0);   -- PHY address
        reg_addr       : in    std_logic_vector(4 downto 0);   -- Register address
        write_data     : in    std_logic_vector(15 downto 0);  -- Data to write
        
        -- Status interface
        busy           : out   std_logic;         -- Transaction in progress
        done           : out   std_logic;         -- Transaction complete (pulse)
        read_data      : out   std_logic_vector(15 downto 0);  -- Data read
        
        -- MDIO interface
        mdc            : out   std_logic;         -- MDIO clock
        mdio_i         : in    std_logic;         -- MDIO input
        mdio_o         : out   std_logic;         -- MDIO output
        mdio_t         : out   std_logic          -- MDIO tristate ('1' = input)
    );
end mdio_controller;

architecture rtl of mdio_controller is

    -- MDC clock generation
    constant MDC_DIV : integer := CLK_FREQ_HZ / (2 * MDC_FREQ_HZ);  -- 20 for 2.5 MHz
    signal mdc_counter : integer range 0 to MDC_DIV-1 := 0;
    signal mdc_int : std_logic := '0';
    signal mdc_tick : std_logic := '0';  -- Pulse on MDC rising edge
    
    -- State machine
    type state_t is (
        IDLE,
        PREAMBLE,
        START_OF_FRAME,
        OPCODE,
        PHY_ADDRESS,
        REG_ADDRESS,
        TURNAROUND,
        DATA_TRANSFER,
        COMPLETE
    );
    signal state : state_t := IDLE;
    
    -- Bit counter for each phase
    signal bit_count : integer range 0 to 31 := 0;
    
    -- Latched control signals
    signal rw_reg : std_logic := '0';
    signal phy_addr_reg : std_logic_vector(4 downto 0) := (others => '0');
    signal reg_addr_reg : std_logic_vector(4 downto 0) := (others => '0');
    signal write_data_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal read_data_reg : std_logic_vector(15 downto 0) := (others => '0');
    
    -- MDIO output control
    signal mdio_out_bit : std_logic := '1';
    signal mdio_tristate : std_logic := '1';  -- '1' = input, '0' = output

begin

    -- Output assignments
    busy <= '1' when state /= IDLE else '0';
    read_data <= read_data_reg;
    mdc <= mdc_int;
    mdio_o <= mdio_out_bit;
    mdio_t <= mdio_tristate;

    -- MDC clock generation (2.5 MHz from 100 MHz)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mdc_counter <= 0;
                mdc_int <= '0';
                mdc_tick <= '0';
            else
                mdc_tick <= '0';
                
                if mdc_counter = MDC_DIV - 1 then
                    mdc_counter <= 0;
                    mdc_int <= not mdc_int;
                    if mdc_int = '0' then
                        mdc_tick <= '1';  -- Pulse on rising edge
                    end if;
                else
                    mdc_counter <= mdc_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- MDIO state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                bit_count <= 0;
                done <= '0';
                mdio_out_bit <= '1';
                mdio_tristate <= '1';
                rw_reg <= '0';
                phy_addr_reg <= (others => '0');
                reg_addr_reg <= (others => '0');
                write_data_reg <= (others => '0');
                read_data_reg <= (others => '0');
            else
                done <= '0';  -- Default: pulse for one cycle
                
                if mdc_tick = '1' then
                    case state is
                        when IDLE =>
                            mdio_out_bit <= '1';
                            mdio_tristate <= '1';
                            bit_count <= 0;
                            
                            if start = '1' then
                                -- Latch control signals
                                rw_reg <= rw;
                                phy_addr_reg <= phy_addr;
                                reg_addr_reg <= reg_addr;
                                write_data_reg <= write_data;
                                state <= PREAMBLE;
                            end if;
                        
                        when PREAMBLE =>
                            -- Output 32 bits of '1'
                            mdio_out_bit <= '1';
                            mdio_tristate <= '0';  -- Drive output
                            
                            if bit_count = 31 then
                                bit_count <= 0;
                                state <= START_OF_FRAME;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                        
                        when START_OF_FRAME =>
                            -- Output '01'
                            mdio_tristate <= '0';  -- Drive output
                            
                            if bit_count = 0 then
                                mdio_out_bit <= '0';
                                bit_count <= 1;
                            else
                                mdio_out_bit <= '1';
                                bit_count <= 0;
                                state <= OPCODE;
                            end if;
                        
                        when OPCODE =>
                            -- Output '10' for read, '01' for write
                            mdio_tristate <= '0';  -- Drive output
                            
                            if bit_count = 0 then
                                mdio_out_bit <= not rw_reg;  -- '1' for read, '0' for write
                                bit_count <= 1;
                            else
                                mdio_out_bit <= rw_reg;      -- '0' for read, '1' for write
                                bit_count <= 0;
                                state <= PHY_ADDRESS;
                            end if;
                        
                        when PHY_ADDRESS =>
                            -- Output 5-bit PHY address (MSB first)
                            mdio_tristate <= '0';  -- Drive output
                            mdio_out_bit <= phy_addr_reg(4 - bit_count);
                            
                            if bit_count = 4 then
                                bit_count <= 0;
                                state <= REG_ADDRESS;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                        
                        when REG_ADDRESS =>
                            -- Output 5-bit register address (MSB first)
                            mdio_tristate <= '0';  -- Drive output
                            mdio_out_bit <= reg_addr_reg(4 - bit_count);
                            
                            if bit_count = 4 then
                                bit_count <= 0;
                                state <= TURNAROUND;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                        
                        when TURNAROUND =>
                            -- Read: 'Z0' (tristate first bit, sample '0' on second)
                            -- Write: '10' (output both bits)
                            
                            if bit_count = 0 then
                                if rw_reg = '1' then
                                    -- Write turnaround: output '1'
                                    mdio_tristate <= '0';
                                    mdio_out_bit <= '1';
                                else
                                    -- Read turnaround: tristate (PHY will drive)
                                    mdio_tristate <= '1';
                                end if;
                                bit_count <= 1;
                            else
                                if rw_reg = '1' then
                                    -- Write turnaround: output '0'
                                    mdio_tristate <= '0';
                                    mdio_out_bit <= '0';
                                else
                                    -- Read turnaround: stay tristated, PHY outputs '0'
                                    mdio_tristate <= '1';
                                end if;
                                bit_count <= 0;
                                state <= DATA_TRANSFER;
                            end if;
                        
                        when DATA_TRANSFER =>
                            -- Transfer 16 bits of data (MSB first)
                            
                            if rw_reg = '1' then
                                -- Write: output data
                                mdio_tristate <= '0';
                                mdio_out_bit <= write_data_reg(15 - bit_count);
                            else
                                -- Read: sample input data
                                mdio_tristate <= '1';
                                read_data_reg(15 - bit_count) <= mdio_i;
                            end if;
                            
                            if bit_count = 15 then
                                bit_count <= 0;
                                state <= COMPLETE;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                        
                        when COMPLETE =>
                            -- Transaction complete, return to idle
                            mdio_tristate <= '1';  -- Release bus
                            mdio_out_bit <= '1';
                            done <= '1';
                            state <= IDLE;
                        
                        when others =>
                            state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;

end rtl;