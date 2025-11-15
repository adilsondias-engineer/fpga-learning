----------------------------------------------------------------------------------
-- PWM Dimmer Module
-- Generates a PWM signal for LED brightness control
--
-- Configurable duty cycle from 0% to 100%
-- Default configuration provides 25% brightness
--
-- Parameters:
--   COUNTER_BITS - Width of PWM counter (default 8 = 256 steps)
--   DUTY_CYCLE   - Number of ON cycles out of 2^COUNTER_BITS (default 64 = 25%)
--
-- At 100 MHz clock with 8-bit counter:
--   PWM frequency = 100 MHz / 256 = 390.625 kHz (no visible flicker)
--
-- Usage example for 25% brightness:
--   pwm_inst: entity work.pwm_dimmer
--       generic map (
--           COUNTER_BITS => 8,    -- 256 steps
--           DUTY_CYCLE   => 64    -- 25% = 64/256
--       )
--       port map (
--           clk       => CLK,
--           reset     => reset,
--           pwm_out   => pwm_enable
--       );
--
--   led(0) <= led_signal and pwm_enable;
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_dimmer is
    generic (
        COUNTER_BITS : integer := 8;     -- PWM counter width (8 = 256 steps)
        DUTY_CYCLE   : integer := 64     -- ON cycles (64/256 = 25%)
    );
    port (
        clk       : in  std_logic;       -- System clock
        reset     : in  std_logic;       -- Synchronous reset
        pwm_out   : out std_logic        -- PWM output (1 = LED ON, 0 = LED OFF)
    );
end pwm_dimmer;

architecture Behavioral of pwm_dimmer is
    signal counter : unsigned(COUNTER_BITS-1 downto 0) := (others => '0');
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= (others => '0');
                pwm_out <= '0';
            else
                counter <= counter + 1;

                -- Generate PWM signal
                if counter < DUTY_CYCLE then
                    pwm_out <= '1';
                else
                    pwm_out <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
