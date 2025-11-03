----------------------------------------------------------------------------------
-- Project 6: UDP Packet Parser - Phase 1A
-- Module: Statistics Counter
-- 
-- Description:
--   Counts received Ethernet frames and displays statistics
--   - Total frames received
--   - IPv4 packets (Phase 2)
--   - UDP packets (Phase 2)
--   - Error count
--   - Displays count on LEDs (binary)
--
-- LED Display (8 LEDs showing frame count in binary):
--   LED[7:0] = frame_count[7:0]  (lower 8 bits)
--
-- Trading Relevance:
--   Real trading systems track packet rates, drops, errors
--   This is my first "monitoring dashboard" in hardware!
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity stats_counter is
    Port (
        -- Clock and Reset
        clk             : in  STD_LOGIC;  -- 100 MHz system clock
        reset           : in  STD_LOGIC;  -- Reset button
        
        -- Input events (from parsers, crossing clock domain)
        frame_received  : in  STD_LOGIC;  -- Pulse on each frame
        ipv4_received   : in  STD_LOGIC;  -- Pulse on each IPv4 packet (Phase 2)
        udp_received    : in  STD_LOGIC;  -- Pulse on each UDP packet (Phase 2)
        error_detected  : in  STD_LOGIC;  -- Pulse on error
        
        -- Statistics outputs
        total_frames    : out STD_LOGIC_VECTOR(31 downto 0);
        ipv4_packets    : out STD_LOGIC_VECTOR(31 downto 0);
        udp_packets     : out STD_LOGIC_VECTOR(31 downto 0);
        error_count     : out STD_LOGIC_VECTOR(31 downto 0);
        
        -- LED display (binary count)
        led_display     : out STD_LOGIC_VECTOR(7 downto 0)
    );
end stats_counter;

architecture Behavioral of stats_counter is
    
    -- Counters (32-bit for large counts)
    signal frame_counter : unsigned(31 downto 0) := (others => '0');
    signal ipv4_counter  : unsigned(31 downto 0) := (others => '0');
    signal udp_counter   : unsigned(31 downto 0) := (others => '0');
    signal error_counter : unsigned(31 downto 0) := (others => '0');
    
    -- Edge detection for input events
    signal frame_received_prev : STD_LOGIC := '0';
    signal ipv4_received_prev  : STD_LOGIC := '0';
    signal udp_received_prev   : STD_LOGIC := '0';
    signal error_detected_prev : STD_LOGIC := '0';
    
    -- Blink LED on activity (visual feedback)
    signal activity_blink : STD_LOGIC := '0';
    signal blink_counter  : unsigned(23 downto 0) := (others => '0');  -- ~100ms at 100MHz
    
begin

    -- Output statistics
    total_frames <= STD_LOGIC_VECTOR(frame_counter);
    ipv4_packets <= STD_LOGIC_VECTOR(ipv4_counter);
    udp_packets  <= STD_LOGIC_VECTOR(udp_counter);
    error_count  <= STD_LOGIC_VECTOR(error_counter);
    
    -- LED display: Show frame count in binary
    -- LED7 will also blink on activity for visual feedback
    led_display <= STD_LOGIC_VECTOR(frame_counter(7 downto 1)) & (activity_blink or frame_counter(0));
    
    ----------------------------------------------------------------------------------
    -- Statistics Counter Process
    --
    -- Increments counters on rising edge of event signals
    -- Uses edge detection to count pulses
    ----------------------------------------------------------------------------------
    
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Reset all counters
                frame_counter <= (others => '0');
                ipv4_counter  <= (others => '0');
                udp_counter   <= (others => '0');
                error_counter <= (others => '0');
                
                frame_received_prev <= '0';
                ipv4_received_prev  <= '0';
                udp_received_prev   <= '0';
                error_detected_prev <= '0';
                
                activity_blink <= '0';
                blink_counter  <= (others => '0');
                
            else
                -- Edge detection and counting
                frame_received_prev <= frame_received;
                ipv4_received_prev  <= ipv4_received;
                udp_received_prev   <= udp_received;
                error_detected_prev <= error_detected;
                
                -- Count frame on rising edge
                if frame_received = '1' and frame_received_prev = '0' then
                    frame_counter <= frame_counter + 1;
                    activity_blink <= '1';  -- Turn on activity LED
                    blink_counter <= (others => '0');
                end if;
                
                -- Count IPv4 packet on rising edge
                if ipv4_received = '1' and ipv4_received_prev = '0' then
                    ipv4_counter <= ipv4_counter + 1;
                end if;
                
                -- Count UDP packet on rising edge
                if udp_received = '1' and udp_received_prev = '0' then
                    udp_counter <= udp_counter + 1;
                end if;
                
                -- Count error on rising edge
                if error_detected = '1' and error_detected_prev = '0' then
                    error_counter <= error_counter + 1;
                end if;
                
                -- Activity blink timer (~100ms)
                if activity_blink = '1' then
                    blink_counter <= blink_counter + 1;
                    if blink_counter = 10_000_000 then  -- 100ms at 100 MHz
                        activity_blink <= '0';
                    end if;
                end if;
                
            end if;
        end if;
    end process;

end Behavioral;