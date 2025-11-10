--------------------------------------------------------------------------------
-- UART Message Formatter
-- Formats and sends debug messages for MAC/IP/UDP packets
-- Uses simple uart_tx.vhd as byte transmitter
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_formatter is
    Generic (
        CLK_FREQ : integer := 100_000_000
    );
    Port (
        clk   : in  std_logic;
        reset : in  std_logic;
        
        -- Packet triggers
        frame_valid     : in  std_logic;
        ip_valid        : in  std_logic;
        udp_valid       : in  std_logic;
        
        -- IP packet info
        ip_protocol     : in  std_logic_vector(7 downto 0);
        ip_src          : in  std_logic_vector(31 downto 0);
        ip_dst          : in  std_logic_vector(31 downto 0);
        ip_total_length : in  std_logic_vector(15 downto 0);
        ip_checksum_ok  : in  std_logic;

        -- IP error signals (for debugging)
        ip_version_err  : in  std_logic;
        ip_ihl_err      : in  std_logic;
        ip_checksum_err : in  std_logic;
        ip_version_ihl_byte : in  std_logic_vector(7 downto 0);

        -- UDP packet info
        udp_src_port    : in  std_logic_vector(15 downto 0);
        udp_dst_port    : in  std_logic_vector(15 downto 0);
        udp_length      : in  std_logic_vector(15 downto 0);
        udp_checksum_ok : in  std_logic;
        udp_length_err  : in  std_logic;
        udp_protocol_ok : in  std_logic;  -- Debug
        udp_length_ok   : in  std_logic;  -- Debug
        in_frame_at_ip_valid : in std_logic; -- Debug: was frame valid when ip_valid pulsed?
        
        -- Payload capture for debug (first 16 bytes)
        payload_capture : in  std_logic_vector(127 downto 0);  -- 16 bytes packed
        payload_capture_valid : in std_logic;  -- Pulse when capture ready

        -- UART byte transmitter interface
        tx_data  : out std_logic_vector(7 downto 0);
        tx_start : out std_logic;
        tx_busy  : in  std_logic
    );
end uart_formatter;

architecture Behavioral of uart_formatter is

    -- State machine for message transmission
    type state_type is (
        IDLE,
        SEND_MAC_MSG,
        SEND_IP_MSG,
        SEND_UDP_MSG,
        WAIT_TX
    );
    signal state : state_type := IDLE;
    signal current_msg_state : state_type := IDLE;  -- Tracks current message being sent
    
    -- Message buffer (increased to 256 bytes to accommodate payload display)
    type msg_buffer_type is array (0 to 255) of std_logic_vector(7 downto 0);
    signal msg_buffer : msg_buffer_type := (others => (others => '0'));
    signal msg_length : integer range 0 to 255 := 0;
    signal msg_index  : integer range 0 to 255 := 0;
    
    -- Edge detection for triggers
    signal frame_prev : std_logic := '0';
    signal ip_prev    : std_logic := '0';
    signal udp_prev   : std_logic := '0';

    -- Pending message flags (set when edge detected while busy)
    signal udp_msg_pending  : std_logic := '0';
    signal ip_msg_pending   : std_logic := '0';
    signal mac_msg_pending  : std_logic := '0';

    -- Debug: capture signal values at edge detection time
    signal frame_valid_latch : std_logic := '0';
    signal ip_valid_latch_dbg : std_logic := '0';
    signal udp_valid_latch_dbg : std_logic := '0';
    
    -- Payload capture
    signal payload_capture_latch : std_logic_vector(127 downto 0) := (others => '0');
    signal payload_capture_prev : std_logic := '0';

    -- Internal signal for tx_start (can be read, unlike output port)
    signal tx_start_int : std_logic := '0';
    
    -- Captured packet data (latched on trigger)
    signal ip_protocol_latch     : std_logic_vector(7 downto 0);
    signal ip_src_latch          : std_logic_vector(31 downto 0);
    signal ip_dst_latch          : std_logic_vector(31 downto 0);
    signal ip_total_length_latch : std_logic_vector(15 downto 0);
    signal ip_checksum_ok_latch  : std_logic;
    
    signal udp_src_port_latch    : std_logic_vector(15 downto 0);
    signal udp_dst_port_latch    : std_logic_vector(15 downto 0);
    signal udp_length_latch      : std_logic_vector(15 downto 0);
    signal udp_checksum_ok_latch : std_logic;
    signal udp_length_err_latch  : std_logic;
    
    -- ASCII constants
    constant CHAR_CR    : std_logic_vector(7 downto 0) := x"0D";  -- \r
    constant CHAR_LF    : std_logic_vector(7 downto 0) := x"0A";  -- \n
    constant CHAR_SPACE : std_logic_vector(7 downto 0) := x"20";  -- space
    constant CHAR_COLON : std_logic_vector(7 downto 0) := x"3A";  -- :
    constant CHAR_EQUAL : std_logic_vector(7 downto 0) := x"3D";  -- =
    constant CHAR_DOT   : std_logic_vector(7 downto 0) := x"2E";  -- .
    
    -- Helper functions
    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        case nibble is
            when x"0" => result := x"30";  -- '0'
            when x"1" => result := x"31";  -- '1'
            when x"2" => result := x"32";  -- '2'
            when x"3" => result := x"33";  -- '3'
            when x"4" => result := x"34";  -- '4'
            when x"5" => result := x"35";  -- '5'
            when x"6" => result := x"36";  -- '6'
            when x"7" => result := x"37";  -- '7'
            when x"8" => result := x"38";  -- '8'
            when x"9" => result := x"39";  -- '9'
            when x"A" => result := x"41";  -- 'A'
            when x"B" => result := x"42";  -- 'B'
            when x"C" => result := x"43";  -- 'C'
            when x"D" => result := x"44";  -- 'D'
            when x"E" => result := x"45";  -- 'E'
            when x"F" => result := x"46";  -- 'F'
            when others => result := x"3F";  -- '?'
        end case;
        return result;
    end function;
    
    function byte_to_decimal(byte_val : std_logic_vector(7 downto 0)) return string is
        variable val : integer;
        variable result : string(1 to 3);
    begin
        val := to_integer(unsigned(byte_val));
        result(1) := character'val(48 + (val / 100));
        result(2) := character'val(48 + ((val / 10) mod 10));
        result(3) := character'val(48 + (val mod 10));
        return result;
    end function;

begin

    process(clk)
        variable idx : integer;
        variable plen_temp : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                tx_start_int <= '0';
                msg_length <= 0;
                msg_index <= 0;
                frame_prev <= '0';
                ip_prev <= '0';
                udp_prev <= '0';
                payload_capture_prev <= '0';
                udp_msg_pending <= '0';
                ip_msg_pending <= '0';
                mac_msg_pending <= '0';
                payload_capture_latch <= (others => '0');

            else
                -- Edge detection (always, regardless of state)
                frame_prev <= frame_valid;
                ip_prev <= ip_valid;
                udp_prev <= udp_valid;
                payload_capture_prev <= payload_capture_valid;

                -- Capture payload when payload_capture_valid pulses
                if payload_capture_valid = '1' and payload_capture_prev = '0' then
                    -- Latch payload data on rising edge
                    payload_capture_latch <= payload_capture;
                end if;

                -- Capture edge events even when busy
                if udp_valid = '1' and udp_prev = '0' then
                    udp_msg_pending <= '1';
                    udp_valid_latch_dbg <= '1';  -- Debug: signal detected
                    -- Latch UDP data immediately
                    udp_src_port_latch <= udp_src_port;
                    udp_dst_port_latch <= udp_dst_port;
                    udp_length_latch <= udp_length;
                    udp_checksum_ok_latch <= udp_checksum_ok;
                    udp_length_err_latch <= udp_length_err;
                    -- Also latch IP addresses when UDP is valid (they're stable)
                    ip_src_latch <= ip_src;
                    ip_dst_latch <= ip_dst;
                end if;

                if ip_valid = '1' and ip_prev = '0' then
                    ip_msg_pending <= '1';
                    ip_valid_latch_dbg <= '1';  -- Debug: signal detected
                    -- Latch IP data immediately
                    ip_protocol_latch <= ip_protocol;
                    ip_src_latch <= ip_src;
                    ip_dst_latch <= ip_dst;
                    ip_total_length_latch <= ip_total_length;
                    ip_checksum_ok_latch <= ip_checksum_ok;
                end if;

                if frame_valid = '1' and frame_prev = '0' then
                    mac_msg_pending <= '1';
                    frame_valid_latch <= '1';  -- Debug: signal detected
                end if;

                case state is

                    when IDLE =>
                        tx_start_int <= '0';
                        msg_index <= 0;

                        -- Priority: UDP > IP > MAC (most detailed first)
                        -- Check pending flags (set when edges detected while busy)
                        if udp_msg_pending = '1' then
                            udp_msg_pending <= '0';  -- Clear flag

                            -- Build UDP message using latched data
                            idx := 0;
                            
                            -- "UDP: "
                            msg_buffer(idx) <= x"55"; idx := idx + 1;  -- 'U'
                            msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            msg_buffer(idx) <= CHAR_COLON; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "src="
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Source port (decimal, up to 5 digits)
                            -- Simplified: show as hex
                            msg_buffer(idx) <= nibble_to_hex(udp_src_port(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_src_port(11 downto 8));  idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_src_port(7 downto 4));   idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_src_port(3 downto 0));   idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "dst="
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Destination port (hex)
                            msg_buffer(idx) <= nibble_to_hex(udp_dst_port(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_dst_port(11 downto 8));  idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_dst_port(7 downto 4));   idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_dst_port(3 downto 0));   idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "len="
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Length (hex)
                            msg_buffer(idx) <= nibble_to_hex(udp_length(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_length(11 downto 8));  idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_length(7 downto 4));   idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(udp_length(3 downto 0));   idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "plen=" (payload length = UDP length - 8)
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Calculate payload length (UDP length - 8 byte header) - show as hex
                            -- Use latched UDP length
                            plen_temp := std_logic_vector(unsigned(udp_length_latch) - 8);
                            msg_buffer(idx) <= nibble_to_hex(plen_temp(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(plen_temp(11 downto 8));  idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(plen_temp(7 downto 4));   idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(plen_temp(3 downto 0));   idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "ipsrc=" (IP source address in hex format for timing)
                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- IP source address (hex format: 8 hex digits, e.g., C0A8005D)
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_src_latch(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "ipdst=" (IP destination address in hex format for timing)
                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- IP destination address (hex format: 8 hex digits, e.g., C0A800C9)
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(31 downto 28)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(27 downto 24)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(23 downto 20)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(19 downto 16)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(11 downto 8)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_dst_latch(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- Error flags
                            if udp_length_err_latch = '1' then
                                msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            elsif udp_checksum_ok_latch = '1' then
                                msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                                msg_buffer(idx) <= x"4B"; idx := idx + 1;  -- 'K'
                            else
                                msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                                msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                                msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            end if;
                            
                            -- "\r\n"
                            msg_buffer(idx) <= CHAR_CR; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_LF; idx := idx + 1;
                            
                            msg_length <= idx;
                            state <= SEND_UDP_MSG;
                            current_msg_state <= SEND_UDP_MSG;  -- Track message type

                        elsif ip_msg_pending = '1' then
                            ip_msg_pending <= '0';  -- Clear flag

                            -- Build IP message using latched data
                            idx := 0;
                            
                            -- "IP: "
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            msg_buffer(idx) <= CHAR_COLON; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "proto="
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Protocol (hex)
                            msg_buffer(idx) <= nibble_to_hex(ip_protocol(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_protocol(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- "len="
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            
                            -- Length (hex)
                            msg_buffer(idx) <= nibble_to_hex(ip_total_length(15 downto 12)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_total_length(11 downto 8));  idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_total_length(7 downto 4));   idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_total_length(3 downto 0));   idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- Checksum status
                            if ip_checksum_ok = '1' then
                                msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                                msg_buffer(idx) <= x"4B"; idx := idx + 1;  -- 'K'
                            else
                                msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            end if;
                            
                            -- "\r\n"
                            msg_buffer(idx) <= CHAR_CR; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_LF; idx := idx + 1;
                            
                            msg_length <= idx;
                            state <= SEND_IP_MSG;
                            current_msg_state <= SEND_IP_MSG;  -- Track message type

                        elsif mac_msg_pending = '1' then
                            mac_msg_pending <= '0';  -- Clear flag

                            -- Build MAC message with debug values
                            idx := 0;

                            msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= CHAR_COLON; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug info: LATCHED values (captured at edge time)
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if frame_valid_latch = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if ip_valid_latch_dbg = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if udp_valid_latch_dbg = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug info: pending flags
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if ip_msg_pending = '1' then
                                msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            else
                                msg_buffer(idx) <= x"2D"; idx := idx + 1;  -- '-'
                            end if;
                            if udp_msg_pending = '1' then
                                msg_buffer(idx) <= x"55"; idx := idx + 1;  -- 'U'
                            else
                                msg_buffer(idx) <= x"2D"; idx := idx + 1;  -- '-'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add IP error signals (critical debug info!)
                            msg_buffer(idx) <= x"76"; idx := idx + 1;  -- 'v'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if ip_version_err = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if ip_ihl_err = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if ip_checksum_err = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug: actual version/IHL byte read (byte 14)
                            msg_buffer(idx) <= x"62"; idx := idx + 1;  -- 'b'
                            msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            msg_buffer(idx) <= x"34"; idx := idx + 1;  -- '4'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_version_ihl_byte(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_version_ihl_byte(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug: IP protocol value
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_protocol_latch(7 downto 4)); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(ip_protocol_latch(3 downto 0)); idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug: UDP flags
                            msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"6B"; idx := idx + 1;  -- 'k'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if udp_protocol_ok = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"6B"; idx := idx + 1;  -- 'k'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if udp_length_ok = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add debug: in_frame status when ip_valid pulsed
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= CHAR_EQUAL; idx := idx + 1;
                            if in_frame_at_ip_valid = '1' then
                                msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            else
                                msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            end if;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;

                            -- Add payload bytes (first 16 bytes in hex)
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= CHAR_COLON; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                            
                            -- Display first 16 bytes of payload in hex
                            -- Bytes are packed as: byte0=127:120, byte1=119:112, ..., byte15=7:0
                            -- Extract each byte and display as hex
                            for i in 0 to 15 loop
                                -- Byte i is at bits (127-i*8) downto (120-i*8)
                                -- High nibble: bits (127-i*8) downto (124-i*8) = 4 bits
                                -- Low nibble: bits (123-i*8) downto (120-i*8) = 4 bits
                                case i is
                                    when 0 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(127 downto 124)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(123 downto 120)); idx := idx + 1;
                                    when 1 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(119 downto 116)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(115 downto 112)); idx := idx + 1;
                                    when 2 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(111 downto 108)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(107 downto 104)); idx := idx + 1;
                                    when 3 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(103 downto 100)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(99 downto 96)); idx := idx + 1;
                                    when 4 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(95 downto 92)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(91 downto 88)); idx := idx + 1;
                                    when 5 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(87 downto 84)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(83 downto 80)); idx := idx + 1;
                                    when 6 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(79 downto 76)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(75 downto 72)); idx := idx + 1;
                                    when 7 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(71 downto 68)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(67 downto 64)); idx := idx + 1;
                                    when 8 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(63 downto 60)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(59 downto 56)); idx := idx + 1;
                                    when 9 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(55 downto 52)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(51 downto 48)); idx := idx + 1;
                                    when 10 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(47 downto 44)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(43 downto 40)); idx := idx + 1;
                                    when 11 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(39 downto 36)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(35 downto 32)); idx := idx + 1;
                                    when 12 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(31 downto 28)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(27 downto 24)); idx := idx + 1;
                                    when 13 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(23 downto 20)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(19 downto 16)); idx := idx + 1;
                                    when 14 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(15 downto 12)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(11 downto 8)); idx := idx + 1;
                                    when 15 =>
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(7 downto 4)); idx := idx + 1;
                                        msg_buffer(idx) <= nibble_to_hex(payload_capture_latch(3 downto 0)); idx := idx + 1;
                                    when others =>
                                        null;
                                end case;
                                if i < 15 then
                                    msg_buffer(idx) <= CHAR_SPACE; idx := idx + 1;
                                end if;
                            end loop;

                            -- Clear latched debug values for next frame
                            frame_valid_latch <= '0';
                            ip_valid_latch_dbg <= '0';
                            udp_valid_latch_dbg <= '0';

                            msg_buffer(idx) <= CHAR_CR; idx := idx + 1;
                            msg_buffer(idx) <= CHAR_LF; idx := idx + 1;
                            
                            msg_length <= idx;
                            state <= SEND_MAC_MSG;
                            current_msg_state <= SEND_MAC_MSG;  -- Track message type
                        end if;
                    
                    when SEND_MAC_MSG | SEND_IP_MSG | SEND_UDP_MSG =>
                        if tx_busy = '0' and tx_start_int = '0' then
                            if msg_index < msg_length then
                                -- Send next byte
                                tx_data <= msg_buffer(msg_index);
                                tx_start_int <= '1';
                                msg_index <= msg_index + 1;
                            else
                                -- Message complete
                                state <= IDLE;
                            end if;
                        elsif tx_start_int = '1' then
                            -- Wait for tx_busy to assert
                            tx_start_int <= '0';
                            state <= WAIT_TX;
                        end if;
                    
                    when WAIT_TX =>
                        -- Wait for current byte transmission to complete
                        if tx_busy = '0' then
                            if msg_index < msg_length then
                                state <= current_msg_state;  -- Return to correct message state
                            else
                                state <= IDLE;
                            end if;
                        end if;
                    
                    when others =>
                        state <= IDLE;

                end case;

            end if;
        end if;
    end process;

    -- Connect internal signal to output port
    tx_start <= tx_start_int;

end Behavioral;