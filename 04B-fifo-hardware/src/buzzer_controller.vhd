library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity buzzer_controller is
    Generic (
        CLK_FREQ : integer := 100_000_000  -- 100 MHz
    );
    Port (
        clk          : in  STD_LOGIC;
        rst          : in  STD_LOGIC;
        
        -- Status inputs
        empty        : in  STD_LOGIC;
        full         : in  STD_LOGIC;
        count        : in  STD_LOGIC_VECTOR(4 downto 0);
        
        -- Buzzer output
        buzzer       : out STD_LOGIC
    );
end buzzer_controller;

architecture Behavioral of buzzer_controller is
    
    -- Tone frequencies (musical notes)
    constant EMPTY_FREQ   : integer := 880;  -- A5 - High pitch
    constant PARTIAL_FREQ : integer := 523;  -- C5 - Mid pitch
    constant FULL_FREQ    : integer := 262;  -- C4 - Low pitch
    
    -- Calculate periods
    constant EMPTY_PERIOD   : integer := CLK_FREQ / EMPTY_FREQ;
    constant PARTIAL_PERIOD : integer := CLK_FREQ / PARTIAL_FREQ;
    constant FULL_PERIOD    : integer := CLK_FREQ / FULL_FREQ;
    
    -- Beep durations (in clock cycles)
    constant EMPTY_DURATION   : integer := CLK_FREQ / 10;     -- 100ms
    constant PARTIAL_DURATION : integer := CLK_FREQ / 10;     -- 100ms
    constant FULL_DURATION    : integer := CLK_FREQ / 5;      -- 200ms
    
    -- State machine
    type state_type is (IDLE, BEEPING);
    signal state : state_type := IDLE;
    
    -- Signals
    signal prev_count     : unsigned(4 downto 0) := (others => '0');
    signal tone_counter   : unsigned(31 downto 0) := (others => '0');
    signal beep_counter   : integer range 0 to FULL_DURATION := 0;
    signal tone_period    : integer := 0;
    signal beep_duration  : integer := 0;
    signal buzzer_toggle  : STD_LOGIC := '0';
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                prev_count <= (others => '0');
                tone_counter <= (others => '0');
                beep_counter <= 0;
                buzzer_toggle <= '0';
                
            else
                case state is
                    when IDLE =>
                        buzzer_toggle <= '0';
                        
                        -- Detect status transitions
                        if unsigned(count) /= prev_count then
                            
                            -- Transition TO empty (count becomes 0)
                            if unsigned(count) = 0 and prev_count = 1 then
                                tone_period <= EMPTY_PERIOD;
                                beep_duration <= EMPTY_DURATION;
                                state <= BEEPING;
                                
                            -- Transition FROM empty (count becomes 1)
                            elsif unsigned(count) = 1 and prev_count = 0 then
                                tone_period <= EMPTY_PERIOD;
                                beep_duration <= EMPTY_DURATION;
                                state <= BEEPING;
                                
                            -- Transition TO full (count becomes 16)
                            elsif unsigned(count) = 16 and prev_count = 15 then
                                tone_period <= FULL_PERIOD;
                                beep_duration <= FULL_DURATION;
                                state <= BEEPING;
                                
                            -- Transition FROM full (count becomes 15)
                            elsif unsigned(count) = 15 and prev_count = 16 then
                                tone_period <= PARTIAL_PERIOD;
                                beep_duration <= PARTIAL_DURATION;
                                state <= BEEPING;
                            end if;
                            
                            prev_count <= unsigned(count);
                        end if;
                        
                    when BEEPING =>
                        -- Generate tone
                        if tone_counter >= tone_period / 2 then
                            buzzer_toggle <= not buzzer_toggle;
                            tone_counter <= (others => '0');
                        else
                            tone_counter <= tone_counter + 1;
                        end if;
                        
                        -- Count beep duration
                        if beep_counter < beep_duration then
                            beep_counter <= beep_counter + 1;
                        else
                            beep_counter <= 0;
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    buzzer <= buzzer_toggle when state = BEEPING else '0';
    
end Behavioral;