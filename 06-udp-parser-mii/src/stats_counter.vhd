----------------------------------------------------------------------------------
-- Statistics Counter
-- Counts received frames and displays on LEDs
-- Provides activity indicator on RGB LED
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity stats_counter is
    Port (
        clk          : in  STD_LOGIC;                      -- System clock (100 MHz)
        reset        : in  STD_LOGIC;
        
        -- Input from MAC parser
        frame_valid  : in  STD_LOGIC;                      -- Pulse on valid frame
        
        -- LED outputs
        led          : out STD_LOGIC_VECTOR(3 downto 0);  -- 4-bit counter display
        led_activity : out STD_LOGIC                       -- Activity blink
    );
end stats_counter;

architecture Behavioral of stats_counter is
    
    signal frame_count      : unsigned(3 downto 0) := (others => '0');
    signal activity_counter : unsigned(23 downto 0) := (others => '0');
    signal activity_blink   : STD_LOGIC := '0';
    
    -- Edge detection for frame_valid
    signal frame_valid_prev : STD_LOGIC := '0';
    signal frame_valid_edge : STD_LOGIC := '0';
    
begin

    -- Output frame count to LEDs
    led <= STD_LOGIC_VECTOR(frame_count);
    led_activity <= activity_blink;
    
    ----------------------------------------------------------------------------------
    -- Edge Detector for frame_valid
    ----------------------------------------------------------------------------------
    
    frame_valid_edge <= '1' when (frame_valid = '1' and frame_valid_prev = '0') else '0';
    
    ----------------------------------------------------------------------------------
    -- Frame Counter Process
    ----------------------------------------------------------------------------------
    
    process(clk)
    begin
        if rising_edge(clk) then
            
            if reset = '1' then
                frame_count      <= (others => '0');
                frame_valid_prev <= '0';
                activity_blink   <= '0';
                activity_counter <= (others => '0');
                
            else
                
                -- Update previous state
                frame_valid_prev <= frame_valid;
                
                -- Increment counter on frame received
                if frame_valid_edge = '1' then
                    frame_count    <= frame_count + 1;
                    activity_blink <= '1';  -- Turn on activity LED
                    activity_counter <= (others => '0');
                end if;
                
                -- Activity LED blink timer (100ms)
                if activity_blink = '1' then
                    activity_counter <= activity_counter + 1;
                    
                    -- 100ms at 100 MHz = 10,000,000 clocks
                    if activity_counter = 10_000_000 then
                        activity_blink   <= '0';
                        activity_counter <= (others => '0');
                    end if;
                end if;
                
            end if;
            
        end if;
    end process;

    

end Behavioral;