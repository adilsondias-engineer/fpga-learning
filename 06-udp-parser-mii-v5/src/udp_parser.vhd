--------------------------------------------------------------------------------
-- UDP Parser Module (Real-time Architecture)
-- Extracts UDP header fields and validates packet
-- Rewritten from 06-udp-parser-mii-3b to match IP parser architecture for reliability as there were hard to find CDC issues
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity udp_parser is
    Port (
        clk             : in  std_logic;
        reset           : in  std_logic;

        -- Input from IP parser
        ip_valid        : in  std_logic;              -- IP header validated (not used in new design)
        ip_protocol     : in  std_logic_vector(7 downto 0);  -- Must be 0x11 for UDP
        ip_total_length : in  std_logic_vector(15 downto 0); -- Total IP packet length
        data_in         : in  std_logic_vector(7 downto 0);  -- Byte stream
        byte_index      : in  integer range 0 to 1023;       -- Current byte position
        frame_valid     : in  std_logic;

        -- Outputs
        udp_valid       : out std_logic;              -- Pulsed when valid UDP parsed
        udp_src_port    : out std_logic_vector(15 downto 0);
        udp_dst_port    : out std_logic_vector(15 downto 0);
        udp_length      : out std_logic_vector(15 downto 0);
        udp_checksum_ok : out std_logic;              -- Checksum validation result
        udp_length_err  : out std_logic;              -- Length mismatch flag

        -- Payload access
        payload_valid   : out std_logic;              -- High during payload bytes
        payload_data    : out std_logic_vector(7 downto 0);
        payload_length  : out std_logic_vector(15 downto 0); -- Payload size

        -- Debug outputs
        udp_protocol_ok : out std_logic;              -- Debug: protocol check passed
        udp_length_ok   : out std_logic               -- Debug: length check passed
    );
end udp_parser;

architecture Behavioral of udp_parser is

    -- Simplified state machine
    type state_type is (IDLE, PARSE_HEADER, VALIDATE, OUTPUT);
    signal state : state_type := IDLE;

    -- UDP header fields
    signal src_port_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal dst_port_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal length_reg    : std_logic_vector(15 downto 0) := (others => '0');
    signal checksum_reg  : std_logic_vector(15 downto 0) := (others => '0');

    -- Parsing counter (tracks which byte of UDP header we're on: 0-7)
    signal header_byte_count : integer range 0 to 20 := 0;

    -- Validation flags
    signal protocol_ok_reg : std_logic := '0';
    signal length_ok_reg   : std_logic := '0';
    signal checksum_ok_reg : std_logic := '0';

    -- Constants
    constant UDP_PROTOCOL : std_logic_vector(7 downto 0) := x"11";  -- UDP = 17
    constant IP_HEADER_SIZE : integer := 20;  -- Standard IP header (no options)
    constant UDP_HEADER_SIZE : integer := 8;
    constant UDP_HEADER_START : integer := 34;  -- Byte 34 in full frame (14 MAC + 20 IP)

begin

    -- Main state machine - Real-time byte-by-byte parsing
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                udp_valid <= '0';
                udp_length_err <= '0';
                payload_valid <= '0';
                header_byte_count <= 0;
                protocol_ok_reg <= '0';
                length_ok_reg <= '0';

            else
                case state is

                    when IDLE =>
                        udp_valid <= '0';
                        udp_length_err <= '0';
                        payload_valid <= '0';
                        header_byte_count <= 0;
                        protocol_ok_reg <= '0';
                        length_ok_reg <= '0';

                        -- Start parsing when UDP header begins (byte 34)
                        -- Only parse if frame is valid
                        if frame_valid = '1' and byte_index = UDP_HEADER_START then
                            state <= PARSE_HEADER;
                        end if;

                    when PARSE_HEADER =>
                        udp_valid <= '0';

                        -- Return to IDLE if frame ends prematurely
                        if frame_valid = '0' then
                            state <= IDLE;
                        -- Parse bytes 34-41 (8 bytes of UDP header) in real-time
                        elsif byte_index = (UDP_HEADER_START + header_byte_count) then
                            case header_byte_count is
                                when 0 => src_port_reg(15 downto 8) <= data_in;
                                when 1 => src_port_reg(7 downto 0) <= data_in;
                                when 2 => dst_port_reg(15 downto 8) <= data_in;
                                when 3 => dst_port_reg(7 downto 0) <= data_in;
                                when 4 => length_reg(15 downto 8) <= data_in;
                                when 5 => length_reg(7 downto 0) <= data_in;
                                when 6 => checksum_reg(15 downto 8) <= data_in;
                                when 7 =>
                                    checksum_reg(7 downto 0) <= data_in;
                                    -- All 8 bytes captured, move to validation
                                    state <= VALIDATE;
                                when others => null;
                            end case;

                            header_byte_count <= header_byte_count + 1;
                        end if;

                    when VALIDATE =>
                        udp_valid <= '0';

                        -- Return to IDLE if frame ends
                        if frame_valid = '0' then
                            state <= IDLE;
                        else
                            -- Check 1: IP protocol must be UDP (0x11)
                            if ip_protocol = UDP_PROTOCOL then
                                protocol_ok_reg <= '1';
                            else
                                protocol_ok_reg <= '0';
                            end if;

                            -- Check 2: UDP length must match (IP total length - IP header)
                            if unsigned(length_reg) = (unsigned(ip_total_length) - IP_HEADER_SIZE) then
                                length_ok_reg <= '1';
                                udp_length_err <= '0';
                            else
                                length_ok_reg <= '0';
                                udp_length_err <= '1';
                            end if;

                            -- Check 3: Checksum (simplified - accept any)
                            checksum_ok_reg <= '1';

                            -- Move to output
                            state <= OUTPUT;
                        end if;

                    when OUTPUT =>
                        -- Pulse udp_valid for ONE cycle if all validations passed
                        if protocol_ok_reg = '1' and length_ok_reg = '1' then
                            udp_valid <= '1';
                            udp_src_port <= src_port_reg;
                            udp_dst_port <= dst_port_reg;
                            udp_length <= length_reg;
                            udp_checksum_ok <= checksum_ok_reg;
                        else
                            udp_valid <= '0';
                        end if;

                        -- Always return to IDLE after output
                        state <= IDLE;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Static outputs (not implemented in this phase)
    payload_valid <= '0';
    payload_data <= (others => '0');
    payload_length <= (others => '0');

    -- Debug outputs
    udp_protocol_ok <= protocol_ok_reg;
    udp_length_ok   <= length_ok_reg;

end Behavioral;
