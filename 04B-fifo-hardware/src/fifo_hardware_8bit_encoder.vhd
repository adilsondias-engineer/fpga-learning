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
use IEEE.NUMERIC_STD.ALL;

entity fifo_hardware_8bit_encoder is
    Port (
        clk   : in  STD_LOGIC;
        
        -- Buttons
        btn   : in  STD_LOGIC_VECTOR(3 downto 0);
        
        -- Rotary encoder (wired to A11, AI0, A9)
        encoder_a  : in  STD_LOGIC;  -- CLK pin -> A11[12] (V12)
        encoder_b  : in  STD_LOGIC;  -- DT pin  -> AI0[11] (W16)
        encoder_sw : in  STD_LOGIC;  -- SW pin  -> A9[10]  (J15)
        
        -- Onboard LEDs (show current value lower 4 bits)
        led   : out STD_LOGIC_VECTOR(3 downto 0);
        
        -- External 8 LEDs (rainbow display - shows current value in real-time)
        led_ext : out STD_LOGIC_VECTOR(7 downto 0);
        
        -- Buzzer
        buzzer : out STD_LOGIC;
        
        -- RGB LED 0 (status indicators)
        led0_r : out STD_LOGIC;
        led0_g : out STD_LOGIC;
        led0_b : out STD_LOGIC
    );
end fifo_hardware_8bit_encoder;

architecture Behavioral of fifo_hardware_8bit_encoder is
    
    -- Component declarations
    component button_debouncer is
        Generic (
            CLK_FREQ    : integer := 100_000_000;
            DEBOUNCE_MS : integer := 20
        );
        Port (
            clk       : in  STD_LOGIC;
            btn_in    : in  STD_LOGIC;
            btn_out   : out STD_LOGIC
        );
    end component;
    
    component edge_detector is
        Port (
            clk      : in  STD_LOGIC;
            sig_in   : in  STD_LOGIC;
            rising   : out STD_LOGIC;
            falling  : out STD_LOGIC
        );
    end component;
    
    component rotary_encoder is
        Port (
            clk         : in  STD_LOGIC;
            rst         : in  STD_LOGIC;
            encoder_a   : in  STD_LOGIC;
            encoder_b   : in  STD_LOGIC;
            cw_pulse    : out STD_LOGIC;
            ccw_pulse   : out STD_LOGIC
        );
    end component;
    
    component fifo is
        Generic (
            DATA_WIDTH : integer := 8;
            FIFO_DEPTH : integer := 16
        );
        Port (
            clk      : in  STD_LOGIC;
            rst      : in  STD_LOGIC;
            wr_en    : in  STD_LOGIC;
            data_in  : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            rd_en    : in  STD_LOGIC;
            data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            full     : out STD_LOGIC;
            empty    : out STD_LOGIC;
            count    : out STD_LOGIC_VECTOR(4 downto 0)
        );
    end component;
    
    component buzzer_controller is
        Generic (CLK_FREQ : integer := 100_000_000);
        Port (
            clk    : in  STD_LOGIC;
            rst    : in  STD_LOGIC;
            empty  : in  STD_LOGIC;
            full   : in  STD_LOGIC;
            count  : in  STD_LOGIC_VECTOR(4 downto 0);
            buzzer : out STD_LOGIC
        );
    end component;
    
    -- Button signals
    signal btn0_db, btn1_db, btn2_db : STD_LOGIC;
    signal btn0_rise, btn1_rise, btn2_rise : STD_LOGIC;
    
    -- Encoder signals
    signal encoder_sw_inverted : STD_LOGIC;  -- Invert for ACTIVE LOW switch --normally not required due to PULLDOWN TRUE
    signal encoder_sw_db : STD_LOGIC;
    signal encoder_sw_rise : STD_LOGIC;
    signal cw_pulse, ccw_pulse : STD_LOGIC;
    
    -- FIFO signals
    signal fifo_rst, fifo_wr_en, fifo_rd_en : STD_LOGIC;
    signal fifo_data_in, fifo_data_out : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_full, fifo_empty : STD_LOGIC;
    signal fifo_count : STD_LOGIC_VECTOR(4 downto 0);
    
    -- Current value being edited (shown on rainbow LEDs in real-time)
    signal current_value : unsigned(7 downto 0) := (others => '0');
    
    -- Display control signals
    signal display_mode : STD_LOGIC := '0';  -- 0=edit mode, 1=read mode
    signal display_value : STD_LOGIC_VECTOR(7 downto 0);
    
    -- Beep control signals
    signal write_beep : STD_LOGIC := '0';
    signal read_beep : STD_LOGIC := '0';
    signal beep_timer : integer range 0 to 10_000_000 := 0;  -- 100ms @100MHz 
    signal manual_beep : STD_LOGIC := '0';
     
begin
        
    -- Invert encoder switch (most encoder switches are ACTIVE LOW) - my encoder is ACTIVE HIGH
    -- When pressed: encoder_sw = '0' (connected to GND) - my encoder is 1 when pressed
    -- After inversion: encoder_sw_inverted = '1' (gives rising edge on press)
    -- encoder_sw_inverted <= not encoder_sw; not required due to constraint PULLDOWN TRUE
    

    -- Debounce buttons
    btn0_debouncer: button_debouncer
        port map (clk => clk, btn_in => btn(0), btn_out => btn0_db);
        
    btn1_debouncer: button_debouncer
        port map (clk => clk, btn_in => btn(1), btn_out => btn1_db);
        
    btn2_debouncer: button_debouncer
        port map (clk => clk, btn_in => btn(2), btn_out => btn2_db);
    
    -- Debounce encoder button
    encoder_sw_debouncer: button_debouncer
        --generic map (CLK_FREQ => 100_000_000, DEBOUNCE_MS => 100)
        port map (clk => clk, btn_in => encoder_sw, btn_out => encoder_sw_db);
    
    -- Edge detectors for buttons
    btn0_edge: edge_detector
        port map (clk => clk, sig_in => btn0_db, rising => btn0_rise, falling => open);

    btn1_edge: edge_detector
        port map (clk => clk, sig_in => btn1_db, rising => btn1_rise, falling => open);
        
    btn2_edge: edge_detector
        port map (clk => clk, sig_in => btn2_db, rising => btn2_rise, falling => open);
    
   -- Debounce encoder button (use INVERTED signal for ACTIVE LOW switch)
    encoder_sw_edge: edge_detector
        port map (clk => clk, sig_in => encoder_sw_db, rising => encoder_sw_rise , falling => open);
    
    -- Rotary encoder decoder
    encoder: rotary_encoder
        port map (
            clk       => clk,
            rst       => btn2_rise,
            encoder_a => encoder_a,
            encoder_b => encoder_b,
            cw_pulse  => cw_pulse,
            ccw_pulse => ccw_pulse
        );
    
    -- Current value management
    -- This value is displayed on rainbow LEDs in REAL-TIME
    -- User can see the value before writing it to FIFO!
    process(clk)
    begin
        if rising_edge(clk) then
            if btn2_rise = '1' then
                -- Reset clears current value
                current_value <= (others => '0');
                display_mode <= '0';
                
            elsif cw_pulse = '1' then
                -- Increment (wraps at 255 -> 0)
                current_value <= current_value + 1;
                display_mode <= '0';  -- Back to edit mode

            elsif ccw_pulse = '1' then
                -- Decrement (wraps at 0 -> 255)
                current_value <= current_value - 1;
                display_mode <= '0';  -- Back to edit mode
           elsif btn1_rise = '1' then
                -- When reading, switch to read display mode
                display_mode <= '1';      
            end if;
        end if;
    end process;
    
    -- Display multiplexer: show current_value or fifo_data_out
    display_value <= fifo_data_out when display_mode = '1' else 
                     std_logic_vector(current_value);

    -- Beep generation for write/read operations
    process(clk)
    begin
        if rising_edge(clk) then
            -- Clear beep flags by default
            write_beep <= '0';
            read_beep <= '0';
            
            if btn2_rise = '1' then
                -- Reset clears beep timer
                beep_timer <= 0;
                manual_beep <= '0';
                
            elsif encoder_sw_rise = '1' or btn0_rise = '1' then
                -- Write operation - start beep
                write_beep <= '1';
                manual_beep <= '1';
                beep_timer <= 10_000_000;  -- 100ms beep
                
            elsif btn1_rise = '1' and fifo_empty = '0' then
                -- Read operation (only if not empty) - start beep
                read_beep <= '1';
                manual_beep <= '1';
                beep_timer <= 5_000_000;  -- 50ms beep (shorter)
                
            elsif (encoder_sw_rise = '1' or btn0_rise = '1') and fifo_full = '1' then
                -- Read operation (only if not empty) - start beep
                read_beep <= '1';
                manual_beep <= '1';
                beep_timer <= 5_000_000;  -- 50ms beep (shorter)
                
            elsif beep_timer > 0 then
                -- Count down beep timer
                beep_timer <= beep_timer - 1;
            else
                -- Timer expired
                manual_beep <= '0';
            end if;
        end if;
    end process;
    
    -- FIFO control signals
    fifo_wr_en   <= encoder_sw_rise or btn0_rise ;  -- Write when encoder button pressed btn0_rise; --
    fifo_rd_en   <= btn1_rise;        -- Read on BTN1
    fifo_rst     <= btn2_rise;        -- Reset on BTN2
    fifo_data_in <= std_logic_vector(current_value);
    
    -- Instantiate 8-bit FIFO
    fifo_inst: fifo
        generic map (DATA_WIDTH => 8, FIFO_DEPTH => 16)
        port map (
            clk      => clk,
            rst      => fifo_rst,
            wr_en    => fifo_wr_en,
            data_in  => fifo_data_in,
            rd_en    => fifo_rd_en,
            data_out => fifo_data_out,
            full     => fifo_full,
            empty    => fifo_empty,
            count    => fifo_count
        );
    
    -- Instantiate buzzer controller
    buzzer_ctrl: buzzer_controller
        generic map (CLK_FREQ => 100_000_000)
        port map (
            clk    => clk,
            rst    => fifo_rst,
            empty  => fifo_empty,
            full   => fifo_full,
            count  => fifo_count,
            buzzer => open  -- Don't use directly, combine with manual beep below
        );
    
    -- Simple tone generator for manual beeps (1kHz tone)
    -- Generate square wave when manual_beep is active
    manual_tone_gen: process(clk)
        variable tone_counter : integer range 0 to 50000 := 0;  -- 100MHz / 50000 / 2 = 1kHz
        variable tone_output : std_logic := '0';
    begin
        if rising_edge(clk) then
            if manual_beep = '1' then
                if tone_counter < 50000 then
                    tone_counter := tone_counter + 1;
                else
                    tone_counter := 0;
                    tone_output := not tone_output;
                end if;
            else
                tone_counter := 0;
                tone_output := '0';
            end if;
            
            -- Output manual beep tone
            buzzer <= tone_output;
        end if;
    end process;

    
    -- Output assignments
    
    -- Onboard LEDs show lower 4 bits of current value
    led <= display_value(3 downto 0);
    
    -- External rainbow LEDs show full 8-bit display value
    -- This updates when reading from FIFO or when turning encoder
    led_ext <= display_value;
    
    -- RGB LED 0: Status
    led0_r <= fifo_full;                          -- Red when full
    led0_g <= fifo_empty;                         -- Green when empty
    led0_b <= not fifo_empty and not fifo_full;  -- Blue when partially filled
    
end Behavioral;