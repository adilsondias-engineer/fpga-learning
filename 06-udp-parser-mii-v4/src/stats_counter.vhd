--------------------------------------------------------------------------------
-- Statistics Counter with IP Parsing
-- Multi-mode LED display: MAC stats, MDIO regs, IP stats, Protocol distribution
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity stats_counter is
    Generic (
        CLK_FREQ : integer := 100_000_000
    );
    Port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        
        -- MAC frame statistics
        frame_valid : in  std_logic;
        
        -- IP statistics
        ip_valid        : in  std_logic;
        ip_protocol     : in  std_logic_vector(7 downto 0);
        ip_checksum_ok  : in  std_logic;
        ip_version_err  : in  std_logic;
        ip_checksum_err : in  std_logic;
        
        -- Display control
        debug_mode      : in  std_logic;
        mdio_reg_values : in  std_logic_vector(63 downto 0);  -- 4 registers
        mdio_seq_done   : in  std_logic;
        
        -- Outputs
        led         : out std_logic_vector(3 downto 0);
        led_activity : out std_logic;
        led_error   : out std_logic
    );
end stats_counter;

architecture Behavioral of stats_counter is
    
    -- MAC statistics
    signal frame_count : unsigned(15 downto 0) := (others => '0');
    signal frame_prev  : std_logic := '0';
    
    -- IP statistics
    signal ip_frame_count   : unsigned(15 downto 0) := (others => '0');
    signal ip_udp_count     : unsigned(7 downto 0) := (others => '0');
    signal ip_tcp_count     : unsigned(7 downto 0) := (others => '0');
    signal ip_icmp_count    : unsigned(7 downto 0) := (others => '0');
    signal ip_other_count   : unsigned(7 downto 0) := (others => '0');
    signal ip_checksum_errors : unsigned(7 downto 0) := (others => '0');
    signal ip_version_errors  : unsigned(7 downto 0) := (others => '0');
    signal ip_prev          : std_logic := '0';
    
    -- Activity indicator (flash on frame)
    signal activity_counter : unsigned(23 downto 0) := (others => '0');
    signal activity_flash   : std_logic := '0';
    
    -- Error indicator
    signal error_active : std_logic := '0';
    
    -- Display mode cycling
    type display_mode_type is (MODE_MAC_STATS, MODE_MDIO_REGS, MODE_IP_STATS, MODE_PROTOCOL_DIST);
    signal display_mode : display_mode_type := MODE_MAC_STATS;
    signal mode_counter : unsigned(1 downto 0) := (others => '0');
    
    -- MDIO register cycling (2 second per register)
    constant CYCLE_TICKS : integer := CLK_FREQ * 2;  -- 2 seconds
    signal cycle_counter : integer range 0 to CYCLE_TICKS-1 := 0;
    signal reg_index     : integer range 0 to 3 := 0;
    signal current_reg   : std_logic_vector(15 downto 0);
    
    -- Protocol display cycling (2 seconds per protocol)
    signal protocol_index : integer range 0 to 3 := 0;
    signal protocol_display : std_logic_vector(3 downto 0);
    
begin

    -- Frame counting (edge detection)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                frame_count <= (others => '0');
                frame_prev <= '0';
            else
                frame_prev <= frame_valid;
                if frame_valid = '1' and frame_prev = '0' then
                    frame_count <= frame_count + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- IP statistics counting
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ip_frame_count <= (others => '0');
                ip_udp_count <= (others => '0');
                ip_tcp_count <= (others => '0');
                ip_icmp_count <= (others => '0');
                ip_other_count <= (others => '0');
                ip_checksum_errors <= (others => '0');
                ip_version_errors <= (others => '0');
                ip_prev <= '0';
            else
                ip_prev <= ip_valid;
                
                -- Count valid IP frames
                if ip_valid = '1' and ip_prev = '0' then
                    if ip_checksum_ok = '1' then
                        ip_frame_count <= ip_frame_count + 1;
                        
                        -- Count by protocol
                        case ip_protocol is
                            when x"11" =>  -- UDP
                                ip_udp_count <= ip_udp_count + 1;
                            when x"06" =>  -- TCP
                                ip_tcp_count <= ip_tcp_count + 1;
                            when x"01" =>  -- ICMP
                                ip_icmp_count <= ip_icmp_count + 1;
                            when others =>
                                ip_other_count <= ip_other_count + 1;
                        end case;
                    else
                        -- Checksum failed
                        ip_checksum_errors <= ip_checksum_errors + 1;
                    end if;
                end if;
                
                -- Count version errors
                if ip_version_err = '1' then
                    ip_version_errors <= ip_version_errors + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- Activity flash (100ms on frame reception)
    process(clk)
        constant FLASH_TICKS : integer := CLK_FREQ / 10;  -- 100ms
    begin
        if rising_edge(clk) then
            if reset = '1' then
                activity_counter <= (others => '0');
                activity_flash <= '0';
            else
                if frame_valid = '1' and frame_prev = '0' then
                    activity_counter <= to_unsigned(FLASH_TICKS, 24);
                    activity_flash <= '1';
                elsif activity_counter > 0 then
                    activity_counter <= activity_counter - 1;
                else
                    activity_flash <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Error indicator (set on any error)
    error_active <= '1' when ip_checksum_errors > 0 or ip_version_errors > 0 else '0';
    
    -- Display mode selection (cycles with debug_mode)
    -- debug_mode='0': MODE_MAC_STATS
    -- debug_mode='1': Cycles through MDIO_REGS -> IP_STATS -> PROTOCOL_DIST
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mode_counter <= (others => '0');
                display_mode <= MODE_MAC_STATS;
            else
                if debug_mode = '0' then
                    display_mode <= MODE_MAC_STATS;
                    mode_counter <= (others => '0');
                else
                    -- Cycle through modes every 3 seconds in debug mode
                    if cycle_counter = 0 then
                        mode_counter <= mode_counter + 1;
                        case mode_counter is
                            when "00" => display_mode <= MODE_MDIO_REGS;
                            when "01" => display_mode <= MODE_IP_STATS;
                            when "10" => display_mode <= MODE_PROTOCOL_DIST;
                            when "11" => display_mode <= MODE_MDIO_REGS;
                            when others => display_mode <= MODE_MAC_STATS;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- MDIO register cycling
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                cycle_counter <= 0;
                reg_index <= 0;
            else
                if cycle_counter < CYCLE_TICKS - 1 then
                    cycle_counter <= cycle_counter + 1;
                else
                    cycle_counter <= 0;
                    if reg_index < 3 then
                        reg_index <= reg_index + 1;
                    else
                        reg_index <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Select current MDIO register nibble
    with reg_index select current_reg <=
        mdio_reg_values(15 downto 0)  when 0,
        mdio_reg_values(31 downto 16) when 1,
        mdio_reg_values(47 downto 32) when 2,
        mdio_reg_values(63 downto 48) when 3,
        (others => '0') when others;
    
    -- Protocol display cycling
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                protocol_index <= 0;
            else
                if display_mode = MODE_PROTOCOL_DIST and cycle_counter = 0 then
                    if protocol_index < 3 then
                        protocol_index <= protocol_index + 1;
                    else
                        protocol_index <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Select protocol count for display
    with protocol_index select protocol_display <=
        std_logic_vector(ip_udp_count(3 downto 0))   when 0,  -- UDP
        std_logic_vector(ip_tcp_count(3 downto 0))   when 1,  -- TCP
        std_logic_vector(ip_icmp_count(3 downto 0))  when 2,  -- ICMP
        std_logic_vector(ip_checksum_errors(3 downto 0)) when 3,  -- Errors
        (others => '0') when others;
    
    -- LED multiplexer based on display mode
    with display_mode select led <=
        std_logic_vector(frame_count(3 downto 0))    when MODE_MAC_STATS,
        current_reg(3 downto 0)                       when MODE_MDIO_REGS,
        std_logic_vector(ip_frame_count(3 downto 0)) when MODE_IP_STATS,
        protocol_display                              when MODE_PROTOCOL_DIST,
        (others => '0') when others;
    
    -- Activity and error outputs
    led_activity <= activity_flash;
    led_error    <= error_active;

end Behavioral;