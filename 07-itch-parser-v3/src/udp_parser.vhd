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
        payload_start   : out std_logic;              -- High on first byte of payload
        payload_end     : out std_logic;              -- High on last byte of payload

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

    -- Parsing counter (tracks current byte of UDP header: 0-7)
    signal header_byte_count : integer range 0 to 20 := 0;

    -- Validation flags
    signal protocol_ok_reg : std_logic := '0';
    signal length_ok_reg   : std_logic := '0';
    signal checksum_ok_reg : std_logic := '0';

    -- Payload tracking
    signal payload_start_byte : integer range 0 to 1023 := 0;
    signal payload_end_byte   : integer range 0 to 1023 := 0;
    signal payload_length_int : integer range 0 to 65535 := 0;
    signal udp_validated      : std_logic := '0';  -- Set when UDP validation passes

    -- Constants
    constant UDP_PROTOCOL : std_logic_vector(7 downto 0) := x"11";  -- UDP = 17
    constant IP_HEADER_SIZE : integer := 20;  -- Standard IP header (no options)
    constant UDP_HEADER_SIZE : integer := 8;
    constant UDP_HEADER_START : integer := 34;  -- Byte 34 in full frame (14 MAC + 20 IP)
    constant PAYLOAD_OFFSET : integer := 42;  -- Byte 42 (14 MAC + 20 IP + 8 UDP)

begin

    -- Main state machine - Real-time byte-by-byte parsing
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                udp_valid <= '0';
                udp_length_err <= '0';
                header_byte_count <= 0;
                protocol_ok_reg <= '0';
                length_ok_reg <= '0';
                udp_validated <= '0';

            else
                case state is

                    when IDLE =>
                        udp_valid <= '0';
                        udp_length_err <= '0';
                        header_byte_count <= 0;
                        protocol_ok_reg <= '0';
                        length_ok_reg <= '0';
                        -- Don't reset udp_validated here - keep it until frame ends
                        -- It will be reset by the payload extraction process when frame_valid = '0'
                        -- Keep port outputs stable even when not valid (for port filtering logic)
                        -- Ports are only updated in OUTPUT state, so they remain stable here

                        -- Start parsing when UDP header begins (byte 34)
                        -- Only parse if frame is valid
                        if frame_valid = '1' and byte_index = UDP_HEADER_START then
                            state <= PARSE_HEADER;
                        elsif frame_valid = '0' then
                            -- Frame ended, reset validation flag
                            udp_validated <= '0';
                        end if;

                    when PARSE_HEADER =>
                        udp_valid <= '0';
                        -- Keep port outputs stable during header parsing (from previous packet or zero)
                        -- Don't clear them here - they'll be updated in OUTPUT state

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
                        -- Keep port outputs stable during validation (from previous packet or zero)
                        -- Don't clear them here - they'll be updated in OUTPUT state if validation passes

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

                            -- CRITICAL FIX: Set udp_validated and payload boundaries HERE
                            -- Check conditions directly (not registers) since just set
                            if ip_protocol = UDP_PROTOCOL and 
                               unsigned(length_reg) = (unsigned(ip_total_length) - IP_HEADER_SIZE) then
                                udp_validated <= '1';
                                payload_length_int <= to_integer(unsigned(length_reg)) - UDP_HEADER_SIZE;
                                payload_start_byte <= PAYLOAD_OFFSET;
                                payload_end_byte <= PAYLOAD_OFFSET + to_integer(unsigned(length_reg)) - UDP_HEADER_SIZE - 1;
                            else
                                udp_validated <= '0';
                            end if;

                            -- Move to output
                            state <= OUTPUT;
                        end if;

                    when OUTPUT =>
                        -- Pulse udp_valid for ONE cycle if all validations passed
                        if protocol_ok_reg = '1' and length_ok_reg = '1' then
                            udp_valid <= '1';
                            -- CRITICAL: Set port outputs BEFORE pulsing udp_valid to ensure they're stable
                            -- Port outputs remain stable after udp_valid goes low (until next OUTPUT state)
                            udp_src_port <= src_port_reg;
                            udp_dst_port <= dst_port_reg;
                            udp_length <= length_reg;
                            udp_checksum_ok <= checksum_ok_reg;
                            -- udp_validated already set in VALIDATE state - keep it high for payload extraction
                            -- Don't reset udp_validated here - let it stay high until frame ends
                        else
                            udp_valid <= '0';
                            udp_validated <= '0';
                            -- Clear port outputs if validation failed
                            udp_src_port <= (others => '0');
                            udp_dst_port <= (others => '0');
                        end if;

                        -- Always return to IDLE after output
                        state <= IDLE;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Payload extraction process (real-time)
    -- payload_valid and payload_start/end are registered for stability
    -- payload_data is combinational to avoid 1-cycle pipeline delay
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                payload_valid <= '0';
                payload_start <= '0';
                payload_end <= '0';
                payload_length <= (others => '0');
            elsif frame_valid = '0' then
                -- Frame ended - clear outputs but don't reset between frames
                payload_valid <= '0';
                payload_start <= '0';
                payload_end <= '0';
            elsif udp_validated = '1' and frame_valid = '1' then
                -- Check if current byte is within payload region
                if byte_index >= payload_start_byte and byte_index <= payload_end_byte then
                    payload_valid <= '1';
                    payload_length <= std_logic_vector(to_unsigned(payload_length_int, 16));

                    -- Set start flag on first byte
                    if byte_index = payload_start_byte then
                        payload_start <= '1';
                    else
                        payload_start <= '0';
                    end if;

                    -- Set end flag on last byte
                    if byte_index = payload_end_byte then
                        payload_end <= '1';
                    else
                        payload_end <= '0';
                    end if;
                else
                    payload_valid <= '0';
                    payload_start <= '0';
                    payload_end <= '0';
                end if;
            else
                -- Not validated yet or frame not valid
                payload_valid <= '0';
                payload_start <= '0';
                payload_end <= '0';
            end if;
        end if;
    end process;
    
    -- Combinational assignment of payload_data
    -- CRITICAL: This must be combinational to align with byte_index and avoid pipeline delay
    -- data_in and byte_index are both registered from MAC parser on the same cycle,
    -- so making payload_data combinational ensures it reflects the current byte_index value
    payload_data <= data_in when (udp_validated = '1' and frame_valid = '1' and 
                                   byte_index >= payload_start_byte and byte_index <= payload_end_byte) 
                    else (others => '0');
    

    -- Debug outputs
    udp_protocol_ok <= protocol_ok_reg;
    udp_length_ok   <= length_ok_reg;

end Behavioral;
