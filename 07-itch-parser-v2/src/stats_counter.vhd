--------------------------------------------------------------------------------
-- Statistics Counter with UDP Parsing
-- Multi-mode LED display: MAC stats, MDIO regs, IP stats, UDP ports
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

        -- UDP statistics (FIXED: removed "signal" keyword)
        udp_valid       : in  std_logic;
        udp_dst_port    : in  std_logic_vector(15 downto 0);
        udp_length_err  : in  std_logic;
        
        -- Display control
        debug_mode      : in  std_logic;
        mdio_reg_values : in  std_logic_vector(63 downto 0);
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
    
    -- UDP statistics (ADDED)
    signal udp_packet_count : unsigned(15 downto 0) := (others => '0');
    signal udp_port_80_count : unsigned(7 downto 0) := (others => '0');
    signal udp_port_53_count : unsigned(7 downto 0) := (others => '0');
    signal udp_length_errors : unsigned(7 downto 0) := (others => '0');
    signal udp_prev : std_logic := '0';
    
    -- Activity indicator
    signal activity_counter : unsigned(23 downto 0) := (others => '0');
    signal activity_flash   : std_logic := '0';
    
    -- Error indicator
    signal error_active : std_logic := '0';
    
    -- Display mode cycling (FIXED: removed MODE_PROTOCOL_DIST)
    type display_mode_type is (
        MODE_MAC_STATS,
        MODE_MDIO_REGS,
        MODE_IP_STATS,
        MODE_UDP_PORTS
    );
        
    signal display_mode : display_mode_type := MODE_MAC_STATS;
    signal mode_counter : unsigned(1 downto 0) := (others => '0');
    
    -- MDIO register cycling (2 seconds per register)
    constant CYCLE_TICKS : integer := CLK_FREQ * 2;
    signal cycle_counter : integer range 0 to CYCLE_TICKS-1 := 0;
    signal reg_index     : integer range 0 to 3 := 0;
    signal current_reg   : std_logic_vector(15 downto 0);
    
    -- UDP port display cycling
    signal udp_port_nibble : integer range 0 to 3 := 0;
    signal udp_display_port : std_logic_vector(15 downto 0) := (others => '0');
    signal udp_port_nibble_data : std_logic_vector(3 downto 0);

    -- Initialization guard to prevent false errors at power-up
    signal initialized : std_logic := '0';

    -- Error LED pulse stretcher (keep LED on for 0.5 seconds)
    constant ERROR_DISPLAY_TIME : integer := CLK_FREQ / 2;  -- 0.5 seconds
    signal error_timer : integer range 0 to ERROR_DISPLAY_TIME := 0;
    signal error_display : std_logic := '0';

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
    
    -- IP statistics (edge detection and protocol counting)
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
                
                if ip_valid = '1' and ip_prev = '0' then
                    ip_frame_count <= ip_frame_count + 1;
                    
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
                end if;
                
                if ip_checksum_err = '1' then
                    ip_checksum_errors <= ip_checksum_errors + 1;
                end if;
                
                if ip_version_err = '1' then
                    ip_version_errors <= ip_version_errors + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- UDP statistics (ADDED: edge detection and port-specific counting)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                udp_packet_count <= (others => '0');
                udp_port_80_count <= (others => '0');
                udp_port_53_count <= (others => '0');
                udp_length_errors <= (others => '0');
                udp_prev <= '0';
                udp_display_port <= (others => '0');
            else
                udp_prev <= udp_valid;
                
                -- Count UDP packets on rising edge
                if udp_valid = '1' and udp_prev = '0' then
                    udp_packet_count <= udp_packet_count + 1;
                    
                    -- Capture port for display
                    udp_display_port <= udp_dst_port;
                    
                    -- Count by destination port
                    case udp_dst_port is
                        when x"0050" =>  -- Port 80 (HTTP)
                            udp_port_80_count <= udp_port_80_count + 1;
                        when x"0035" =>  -- Port 53 (DNS)
                            udp_port_53_count <= udp_port_53_count + 1;
                        when others =>
                            null;
                    end case;
                end if;
                
                -- Count UDP length errors
                if udp_length_err = '1' then
                    udp_length_errors <= udp_length_errors + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- Activity flash (100ms pulse on frame received)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                activity_counter <= (others => '0');
                activity_flash <= '0';
            else
                if frame_valid = '1' and frame_prev = '0' then
                    activity_counter <= to_unsigned(10_000_000, 24);  -- 100ms at 100MHz
                    activity_flash <= '1';
                elsif activity_counter > 0 then
                    activity_counter <= activity_counter - 1;
                else
                    activity_flash <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Error pulse stretcher: Display errors for 0.5 seconds
    -- Makes brief error pulses visible to human eye
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                error_timer <= 0;
                error_display <= '0';
                initialized <= '1';  -- Mark as initialized after first reset
            else
                -- Only start monitoring errors after initialization
                if initialized = '1' then
                    -- Detect error pulse and start timer
                    if ip_checksum_err = '1' or ip_version_err = '1' or udp_length_err = '1' then
                        error_timer <= ERROR_DISPLAY_TIME;  -- Reset timer to 0.5 seconds
                        error_display <= '1';
                    elsif error_timer > 0 then
                        -- Count down timer
                        error_timer <= error_timer - 1;
                        error_display <= '1';
                    else
                        -- Timer expired
                        error_display <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Connect stretched pulse to output
    error_active <= error_display;
    
    -- Mode cycling (on debug_mode button press)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mode_counter <= (others => '0');
                display_mode <= MODE_MAC_STATS;
            else
                if debug_mode = '1' then
                    mode_counter <= mode_counter + 1;
                    
                    case mode_counter is
                        when "00" => display_mode <= MODE_MDIO_REGS;
                        when "01" => display_mode <= MODE_IP_STATS;
                        when "10" => display_mode <= MODE_UDP_PORTS;
                        when "11" => display_mode <= MODE_MAC_STATS;
                        when others => display_mode <= MODE_MAC_STATS;
                    end case;
                end if;
            end if;
        end if;
    end process;
    
    -- Cycle counter for register/protocol/port display
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                cycle_counter <= 0;
            else
                if cycle_counter = CYCLE_TICKS-1 then
                    cycle_counter <= 0;
                else
                    cycle_counter <= cycle_counter + 1;
                end if;
            end if;
        end if;
    end process;
    
    -- MDIO register cycling
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                reg_index <= 0;
            else
                if display_mode = MODE_MDIO_REGS and cycle_counter = 0 then
                    if reg_index < 3 then
                        reg_index <= reg_index + 1;
                    else
                        reg_index <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- UDP port nibble cycling (FIXED: moved to separate process)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                udp_port_nibble <= 0;
            else
                if display_mode = MODE_UDP_PORTS and cycle_counter = 0 then
                    if udp_port_nibble < 3 then
                        udp_port_nibble <= udp_port_nibble + 1;
                    else
                        udp_port_nibble <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Select current MDIO register to display
    with reg_index select current_reg <=
        mdio_reg_values(15 downto 0)   when 0,
        mdio_reg_values(31 downto 16)  when 1,
        mdio_reg_values(47 downto 32)  when 2,
        mdio_reg_values(63 downto 48)  when 3,
        (others => '0') when others;
    
    -- Select UDP port nibble (intermediate signal)
    with udp_port_nibble select udp_port_nibble_data <=
        std_logic_vector(udp_display_port(15 downto 12)) when 0,
        std_logic_vector(udp_display_port(11 downto 8))  when 1,
        std_logic_vector(udp_display_port(7 downto 4))   when 2,
        std_logic_vector(udp_display_port(3 downto 0))   when 3,
        (others => '0') when others;

    -- LED multiplexer (FIXED: use intermediate signal for complex conditions)
    with display_mode select led <=
        std_logic_vector(frame_count(3 downto 0))    when MODE_MAC_STATS,
        current_reg(3 downto 0)                      when MODE_MDIO_REGS,
        std_logic_vector(ip_frame_count(3 downto 0)) when MODE_IP_STATS,
        udp_port_nibble_data                         when MODE_UDP_PORTS,
        (others => '0') when others;
    
    -- Activity and error outputs
    led_activity <= activity_flash;
    led_error    <= error_active;

end Behavioral;