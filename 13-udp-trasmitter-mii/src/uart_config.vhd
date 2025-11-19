----------------------------------------------------------------------------------
-- UART Configuration Module
-- Allows dynamic configuration of UDP destination IP, MAC, and port via UART
--
-- Command Protocol (ASCII, newline-terminated):
--   IP:192.168.0.93\n       - Set destination IP address
--   MAC:AA:BB:CC:DD:EE:FF\n - Set destination MAC address
--   PORT:5000\n             - Set destination UDP port
--   ?\n                     - Query current configuration
--
-- Examples:
--   IP:192.168.0.93\n
--   MAC:FF:FF:FF:FF:FF:FF\n
--   PORT:5000\n
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_config is
    Generic (
        DEFAULT_IP   : std_logic_vector(31 downto 0) := x"C0A8005D";  -- 192.168.0.93
        DEFAULT_MAC  : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";  -- Broadcast
        DEFAULT_PORT : std_logic_vector(15 downto 0) := x"1388"  -- 5000
    );
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;

        -- UART RX interface
        rx_data  : in STD_LOGIC_VECTOR(7 downto 0);
        rx_valid : in STD_LOGIC;

        -- Configuration outputs
        dst_ip   : out STD_LOGIC_VECTOR(31 downto 0);
        dst_mac  : out STD_LOGIC_VECTOR(47 downto 0);
        dst_port : out STD_LOGIC_VECTOR(15 downto 0);

        -- Status
        config_updated : out STD_LOGIC  -- Pulse when config changes
    );
end uart_config;

architecture Behavioral of uart_config is

    -- Command buffer (max command: "MAC:AA:BB:CC:DD:EE:FF\n" = 24 chars)
    constant BUF_SIZE : integer := 32;
    type char_array_t is array (0 to BUF_SIZE-1) of std_logic_vector(7 downto 0);
    signal cmd_buffer : char_array_t := (others => (others => '0'));
    signal buf_index : integer range 0 to BUF_SIZE-1 := 0;

    -- Configuration registers
    signal dst_ip_reg   : std_logic_vector(31 downto 0) := DEFAULT_IP;
    signal dst_mac_reg  : std_logic_vector(47 downto 0) := DEFAULT_MAC;
    signal dst_port_reg : std_logic_vector(15 downto 0) := DEFAULT_PORT;

    -- State machine
    type state_type is (IDLE, RECEIVE_CMD, PARSE_CMD);
    signal state : state_type := IDLE;

    -- ASCII constants
    constant CHAR_LF      : std_logic_vector(7 downto 0) := x"0A";  -- '\n' Line Feed
    constant CHAR_CR      : std_logic_vector(7 downto 0) := x"0D";  -- '\r' Carriage Return
    constant CHAR_COLON   : std_logic_vector(7 downto 0) := x"3A";  -- ':'
    constant CHAR_DOT     : std_logic_vector(7 downto 0) := x"2E";  -- '.'
    constant CHAR_QUESTION: std_logic_vector(7 downto 0) := x"3F";  -- '?'

    -- Helper function: ASCII hex digit to 4-bit value
    function hex_char_to_nibble(c : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        case c is
            when x"30" => return x"0";  -- '0'
            when x"31" => return x"1";  -- '1'
            when x"32" => return x"2";  -- '2'
            when x"33" => return x"3";  -- '3'
            when x"34" => return x"4";  -- '4'
            when x"35" => return x"5";  -- '5'
            when x"36" => return x"6";  -- '6'
            when x"37" => return x"7";  -- '7'
            when x"38" => return x"8";  -- '8'
            when x"39" => return x"9";  -- '9'
            when x"41" | x"61" => return x"A";  -- 'A' or 'a'
            when x"42" | x"62" => return x"B";  -- 'B' or 'b'
            when x"43" | x"63" => return x"C";  -- 'C' or 'c'
            when x"44" | x"64" => return x"D";  -- 'D' or 'd'
            when x"45" | x"65" => return x"E";  -- 'E' or 'e'
            when x"46" | x"66" => return x"F";  -- 'F' or 'f'
            when others => return x"0";
        end case;
    end function;

    -- Helper function: ASCII decimal digit to 4-bit value
    function dec_char_to_nibble(c : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable temp : unsigned(7 downto 0);
    begin
        if c >= x"30" and c <= x"39" then  -- '0' to '9'
            temp := unsigned(c) - 48;  -- c - '0'
            return std_logic_vector(temp(3 downto 0));  -- Return only lower 4 bits
        else
            return x"0";
        end if;
    end function;

begin

    -- Output current configuration
    dst_ip <= dst_ip_reg;
    dst_mac <= dst_mac_reg;
    dst_port <= dst_port_reg;

    -- Main process
    process(clk)
        variable cmd_type : std_logic_vector(7 downto 0);
        variable temp_ip : std_logic_vector(31 downto 0);
        variable temp_mac : std_logic_vector(47 downto 0);
        variable temp_port : std_logic_vector(15 downto 0);
        variable octet_val : unsigned(7 downto 0);
        variable port_val : unsigned(15 downto 0);
        variable idx : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                buf_index <= 0;
                cmd_buffer <= (others => (others => '0'));
                dst_ip_reg <= DEFAULT_IP;
                dst_mac_reg <= DEFAULT_MAC;
                dst_port_reg <= DEFAULT_PORT;
                config_updated <= '0';

            else
                config_updated <= '0';  -- Default

                case state is

                    when IDLE =>
                        buf_index <= 0;
                        if rx_valid = '1' then
                            -- Ignore stray CR/LF characters (e.g., if terminal sends CRLF)
                            if rx_data /= CHAR_CR and rx_data /= CHAR_LF then
                                cmd_buffer(0) <= rx_data;
                                buf_index <= 1;
                                state <= RECEIVE_CMD;
                            end if;
                        end if;

                    when RECEIVE_CMD =>
                        if rx_valid = '1' then
                            -- Accept both CR ('\r') and LF ('\n') as command terminators
                            if rx_data = CHAR_LF or rx_data = CHAR_CR then
                                -- Command complete, parse it
                                state <= PARSE_CMD;
                            elsif buf_index < BUF_SIZE-1 then
                                cmd_buffer(buf_index) <= rx_data;
                                buf_index <= buf_index + 1;
                            else
                                -- Buffer overflow, reset
                                state <= IDLE;
                            end if;
                        end if;

                    when PARSE_CMD =>
                        -- Parse command based on first 3 characters
                        -- Check for "IP:", "MAC:", "PORT:", or "?"

                        if buf_index >= 3 and
                           cmd_buffer(0) = x"49" and  -- 'I'
                           cmd_buffer(1) = x"50" and  -- 'P'
                           cmd_buffer(2) = CHAR_COLON then

                            -- Parse IP address: "IP:192.168.0.93"
                            -- Format: AAA.BBB.CCC.DDD (max 3 digits per octet)
                            idx := 3;  -- Start after "IP:"
                            temp_ip := (others => '0');

                            -- Parse first octet (max 3 digits)
                            octet_val := (others => '0');
                            for i in 0 to 2 loop
                                exit when idx >= buf_index or cmd_buffer(idx) = CHAR_DOT;
                                -- x*10 = x*8 + x*2 (shift-and-add is faster than multiply)
                                octet_val := resize(shift_left(octet_val, 3) + shift_left(octet_val, 1) + resize(unsigned(dec_char_to_nibble(cmd_buffer(idx))), 8), 8);
                                idx := idx + 1;
                            end loop;
                            temp_ip(31 downto 24) := std_logic_vector(octet_val);
                            idx := idx + 1;  -- Skip dot

                            -- Parse second octet (max 3 digits)
                            octet_val := (others => '0');
                            for i in 0 to 2 loop
                                exit when idx >= buf_index or cmd_buffer(idx) = CHAR_DOT;
                                octet_val := resize(shift_left(octet_val, 3) + shift_left(octet_val, 1) + resize(unsigned(dec_char_to_nibble(cmd_buffer(idx))), 8), 8);
                                idx := idx + 1;
                            end loop;
                            temp_ip(23 downto 16) := std_logic_vector(octet_val);
                            idx := idx + 1;  -- Skip dot

                            -- Parse third octet (max 3 digits)
                            octet_val := (others => '0');
                            for i in 0 to 2 loop
                                exit when idx >= buf_index or cmd_buffer(idx) = CHAR_DOT;
                                octet_val := resize(shift_left(octet_val, 3) + shift_left(octet_val, 1) + resize(unsigned(dec_char_to_nibble(cmd_buffer(idx))), 8), 8);
                                idx := idx + 1;
                            end loop;
                            temp_ip(15 downto 8) := std_logic_vector(octet_val);
                            idx := idx + 1;  -- Skip dot

                            -- Parse fourth octet (max 3 digits)
                            octet_val := (others => '0');
                            for i in 0 to 2 loop
                                exit when idx >= buf_index;
                                octet_val := resize(shift_left(octet_val, 3) + shift_left(octet_val, 1) + resize(unsigned(dec_char_to_nibble(cmd_buffer(idx))), 8), 8);
                                idx := idx + 1;
                            end loop;
                            temp_ip(7 downto 0) := std_logic_vector(octet_val);

                            -- Update register
                            dst_ip_reg <= temp_ip;
                            config_updated <= '1';

                        elsif buf_index >= 4 and
                              cmd_buffer(0) = x"4D" and  -- 'M'
                              cmd_buffer(1) = x"41" and  -- 'A'
                              cmd_buffer(2) = x"43" and  -- 'C'
                              cmd_buffer(3) = CHAR_COLON then

                            -- Parse MAC address: "MAC:AA:BB:CC:DD:EE:FF"
                            -- Format: HH:HH:HH:HH:HH:HH (17 chars after colon)
                            temp_mac := (others => '0');
                            idx := 4;  -- Start after "MAC:"

                            -- Parse 6 octets (AA, BB, CC, DD, EE, FF)
                            for i in 0 to 5 loop
                                if idx < buf_index-1 then
                                    temp_mac(47 - i*8 downto 47 - i*8 - 3) := hex_char_to_nibble(cmd_buffer(idx));
                                    temp_mac(47 - i*8 - 4 downto 47 - i*8 - 7) := hex_char_to_nibble(cmd_buffer(idx+1));
                                    idx := idx + 3;  -- Skip 2 hex chars + colon (or end)
                                end if;
                            end loop;

                            dst_mac_reg <= temp_mac;
                            config_updated <= '1';

                        elsif buf_index >= 5 and
                              cmd_buffer(0) = x"50" and  -- 'P'
                              cmd_buffer(1) = x"4F" and  -- 'O'
                              cmd_buffer(2) = x"52" and  -- 'R'
                              cmd_buffer(3) = x"54" and  -- 'T'
                              cmd_buffer(4) = CHAR_COLON then

                            -- Parse port: "PORT:5000"
                            idx := 5;  -- Start after "PORT:"
                            port_val := (others => '0');

                            -- Parse port number (max 5 digits for 0-65535)
                            for i in 0 to 4 loop
                                exit when idx >= buf_index;
                                -- x*10 = x*8 + x*2 (shift-and-add is faster than multiply)
                                port_val := resize(shift_left(port_val, 3) + shift_left(port_val, 1) + resize(unsigned(dec_char_to_nibble(cmd_buffer(idx))), 16), 16);
                                idx := idx + 1;
                            end loop;

                            dst_port_reg <= std_logic_vector(port_val);
                            config_updated <= '1';

                        end if;

                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
