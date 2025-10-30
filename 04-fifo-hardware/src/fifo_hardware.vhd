----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 30.10.2025 21:51:50
-- Design Name: 
-- Module Name: fifo2 - Behavioral
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
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo_hardware is
    Port (
        clk         : in  std_logic;
        
        -- buttons
        btn         : in  std_logic_vector(3 downto 0);
        
        -- swtiches
        swt         : in  std_logic_vector(3 downto 0);

        -- 4 standards LEDs(data output)
        led         : out std_logic_vector(3 downto 0);

        -- RGB LED 0(status indicators)
        led0_r      : out std_logic; -- Red = full
        led0_g      : out std_logic; -- Green = empty
        led0_b      : out std_logic -- Blue = has data (not empty, not full)
        
    );
end fifo_hardware;

architecture Behavioral of fifo_hardware is

    -- component declaration
    component button_debouncer is
        generic (
            DEBOUNCE_MS : integer := 20; -- Debounce time in milliseconds
            CLK_FREQ_HZ : integer := 100_000_000 -- Clock frequency in Hz
        );
        port (
            clk       : in  std_logic;
            btn_in    : in  std_logic;
            btn_out   : out std_logic            
        );
    end component;

    component edge_detector is
        port (
            clk     : in  std_logic;
            sig_in  : in  std_logic;
            rising  : out std_logic;
            falling : out std_logic
        );
    end component;

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

    --debounced button signals
    signal btn0_db, btn1_db, btn2_db : std_logic;
    --edge detected signals
    signal btn0_rising, btn1_rising, btn2_rising : std_logic;
    signal btn0_falling, btn1_falling, btn2_falling : std_logic;

    --fifo signals
    signal fifo_wr_en : std_logic;
    signal fifo_rd_en : std_logic;
    signal fifo_rst :  std_logic := '0';
    signal fifo_data_in : std_logic_vector(3 downto 0);
    signal fifo_data_out : std_logic_vector(3 downto 0);
    signal fifo_full : std_logic;
    signal fifo_empty : std_logic;
    signal fifo_count : std_logic_vector(4 downto 0);

begin

    -- Instantiate debouncers for buttons 0, 1, and 2
    btn0_debouncer: button_debouncer
        generic map (
            DEBOUNCE_MS => 20,
            CLK_FREQ_HZ => 100_000_000
        )
        port map (
            clk => clk,
            btn_in => btn(0),
            btn_out => btn0_db
        ); 
    btn1_debouncer: button_debouncer
        generic map (
            DEBOUNCE_MS => 20,
            CLK_FREQ_HZ => 100_000_000
        )   
        port map (
            clk => clk,
            btn_in => btn(1),
            btn_out => btn1_db
        );
    btn2_debouncer: button_debouncer
        generic map (
            DEBOUNCE_MS => 20,
            CLK_FREQ_HZ => 100_000_000
        )   
        port map (
            clk => clk,
            btn_in => btn(2),
            btn_out => btn2_db
        );

    -- Instantiate edge detectors for buttons 0, 1, and 2
    btn0_edge_detector: edge_detector
        port map (
            clk => clk,
            sig_in => btn0_db,
            rising => btn0_rising,
            falling => btn0_falling
        ); 
    btn1_edge_detector: edge_detector
        port map (
            clk => clk,
            sig_in => btn1_db,
            rising => btn1_rising,
            falling => btn1_falling
        );
    btn2_edge_detector: edge_detector
        port map (
            clk => clk,
            sig_in => btn2_db,
            rising => btn2_rising,
            falling => btn2_falling
        );
    -- FIFO write enable when button 0 rising edge detected
    fifo_wr_en <= btn0_rising;
    -- FIFO read enable when button 1 rising edge detected
    fifo_rd_en <= btn1_rising;
    -- FIFO reset when button 2 rising edge detected
    fifo_rst <= btn2_rising;
    -- FIFO data input from switches
    fifo_data_in <= swt;

    -- Instantiate FIFO( 4 bit data width, 16 depth)
    fifo_inst: fifo
        generic map (
            DATA_WIDTH => 4,
            FIFO_DEPTH => 16
        )
        port map (
            clk => clk,
            rst => fifo_rst,
            wr_en => fifo_wr_en,
            data_in => fifo_data_in,
            rd_en => fifo_rd_en,
            data_out => fifo_data_out,
            full => fifo_full,
            empty => fifo_empty,
            count => fifo_count
        );

    -- Connect FIFO data output to LEDs
    led <= fifo_data_out;  -- data output to standard LEDs

    -- RGB LED 0 status indicators
    led0_r <= fifo_full;               -- Red LED ON when FIFO is full
    led0_g <= fifo_empty;              -- Green LED ON when FIFO is empty
    led0_b <= not fifo_empty and not fifo_full; -- Blue LED ON when FIFO has data (not empty, not full)

end Behavioral;
