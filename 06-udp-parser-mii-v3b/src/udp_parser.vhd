--------------------------------------------------------------------------------
-- UDP Parser Module (Standalone)
-- Extracts UDP header fields and validates packet
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity udp_parser is
    Port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        
        -- Input from IP parser
        ip_valid        : in  std_logic;              -- IP header validated
        ip_protocol     : in  std_logic_vector(7 downto 0);  -- Must be 0x11 for UDP
        ip_total_length : in  std_logic_vector(15 downto 0); -- Total IP packet length
        data_in         : in  std_logic_vector(7 downto 0);  -- Byte stream
        byte_index      : in  integer range 0 to 1023;       -- Current byte position
        
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
        payload_length  : out std_logic_vector(15 downto 0)  -- Payload size
    );
end udp_parser;

architecture Behavioral of udp_parser is

    -- State machine
    type state_type is (IDLE, PARSE_HEADER, VALIDATE, OUTPUT, STREAM_PAYLOAD);
    signal state : state_type := IDLE;
    
    -- UDP header fields
    signal src_port_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal dst_port_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal length_reg    : std_logic_vector(15 downto 0) := (others => '0');
    signal checksum_reg  : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Byte parsing
    signal header_byte_count : integer range 0 to 7 := 0;
    signal payload_byte_count : integer range 0 to 1500 := 0;
    signal expected_byte : integer range 0 to 1023 := 0;
    
    -- Validation flags
    signal protocol_ok : std_logic := '0';
    signal length_ok   : std_logic := '0';
    signal checksum_ok_reg : std_logic := '0';
    
    -- Constants
    constant UDP_PROTOCOL : std_logic_vector(7 downto 0) := x"11";  -- UDP = 17
    constant IP_HEADER_SIZE : integer := 20;  -- Standard IP header (no options)
    constant UDP_HEADER_SIZE : integer := 8;
    constant UDP_HEADER_START : integer := 34;  -- Byte 34 in full frame (14 MAC + 20 IP)

begin

    -- Main state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                udp_valid <= '0';
                udp_length_err <= '0';
                payload_valid <= '0';
                header_byte_count <= 0;
                payload_byte_count <= 0;
                
            else
                case state is
                    
                    when IDLE =>
                        udp_valid <= '0';
                        udp_length_err <= '0';
                        payload_valid <= '0';
                        header_byte_count <= 0;
                        payload_byte_count <= 0;
                        protocol_ok <= '0';
                        length_ok <= '0';

                        -- Check if IP parser indicates valid IP with UDP protocol
                        if ip_valid = '1' and ip_protocol = UDP_PROTOCOL then
                            protocol_ok <= '1';
                            expected_byte <= UDP_HEADER_START;  -- BUG FIX #6: Initialize when transitioning
                            state <= PARSE_HEADER;
                        end if;

                    when PARSE_HEADER =>
                        udp_valid <= '0';

                        -- Parse UDP header bytes as they arrive
                        if byte_index >= UDP_HEADER_START and
                           byte_index < UDP_HEADER_START + UDP_HEADER_SIZE then

                            -- Extract header fields based on byte position within UDP header
                            case (byte_index - UDP_HEADER_START) is
                                when 0 => src_port_reg(15 downto 8) <= data_in; -- Source port MSB
                                when 1 => src_port_reg(7 downto 0) <= data_in;  -- Source port LSB
                                when 2 => dst_port_reg(15 downto 8) <= data_in; -- Dest port MSB
                                when 3 => dst_port_reg(7 downto 0) <= data_in; -- Dest port LSB
                                when 4 => length_reg(15 downto 8) <= data_in; -- Length MSB
                                when 5 => length_reg(7 downto 0) <= data_in; -- Length LSB
                                when 6 => checksum_reg(15 downto 8) <= data_in; -- Checksum MSB
                                when 7 =>
                                    checksum_reg(7 downto 0) <= data_in; -- Checksum LSB
                                    -- BUG FIX #1: Transition to VALIDATE after last byte
                                    state <= VALIDATE;
                                when others => null;
                            end case;

                            header_byte_count <= header_byte_count + 1;
                        elsif header_byte_count = 8 then
                            -- All 8 bytes received, transition to VALIDATE
                            state <= VALIDATE;
                        end if;

                        -- If frame ends before header complete, return to IDLE
                        if ip_valid = '0' and header_byte_count < 8 then
                            udp_valid <= '0';
                            udp_length_err <= '0';
                            payload_valid <= '0';
                            header_byte_count <= 0;
                            payload_byte_count <= 0;
                            protocol_ok <= '0';
                            length_ok <= '0';
                            state <= IDLE;
                        end if;
                    
                    when VALIDATE =>
                        udp_valid <= '0';

                        -- BUG FIX #3: First verify complete header received
                        if header_byte_count /= 8 then
 
                            udp_length_err <= '1';
                            length_ok <= '0';

                        -- BUG FIX #7: reset all flags and state to IDLE to prevent garbage data
                            udp_valid <= '0';
                            udp_length_err <= '0';
                            payload_valid <= '0';
                            header_byte_count <= 0;
                            payload_byte_count <= 0;
                            protocol_ok <= '0';
                            length_ok <= '0';

                            state <= IDLE;
 
                       else
                            -- Validate UDP length field
                            -- UDP length includes header (8 bytes) + payload
                            -- Must match: ip_total_length - IP_HEADER_SIZE = length_reg

                            if unsigned(length_reg) = (unsigned(ip_total_length) - IP_HEADER_SIZE) then
                                length_ok <= '1';
                                udp_length_err <= '0';
                            else
                                length_ok <= '0';
                                udp_length_err <= '1';
                            end if;
                                
                            -- Checksum validation (simplified)
                            -- For Phase 1E: Accept checksum = 0x0000 (disabled) as valid
                            -- TODO: Implement full UDP checksum calculation in future phase
                            if checksum_reg = x"0000" then
                                checksum_ok_reg <= '1';  -- Checksum disabled = OK
                            else
                                checksum_ok_reg <= '1';  -- Assume valid for now
                            end if;
                            -- report "BUG FIX #3 -> state: " & to_string(state) severity note;
                            -- report "BUG FIX #3 -> length_ok: " & to_string(length_ok) severity note;
                            -- report "BUG FIX #3 -> protocol_ok: " & to_string(protocol_ok) severity note;
                            state <= OUTPUT;
                        end if;

                        

                    when OUTPUT =>
                        -- Output results for exactly ONE clock cycle
                        if length_ok = '1' and protocol_ok = '1' then
                            udp_valid <= '1';  -- BUG FIX #5: Single-cycle pulse
                            udp_src_port <= src_port_reg;
                            udp_dst_port <= dst_port_reg;
                            udp_length <= length_reg;
                            udp_checksum_ok <= checksum_ok_reg;

                            -- Calculate payload length
                            payload_length <= std_logic_vector(unsigned(length_reg) - UDP_HEADER_SIZE);


                            -- If there's payload data, start streaming it
                            if unsigned(length_reg) > UDP_HEADER_SIZE then
                                state <= STREAM_PAYLOAD;
                            else
                                state <= IDLE;
                            end if;

                        else
                            -- Validation failed
                            udp_valid <= '0';
                            -- BUG FIX #7: reset all flags and state to IDLE to prevent garbage data
                            udp_length_err <= '0';
                            payload_valid <= '0';
                            header_byte_count <= 0;
                            payload_byte_count <= 0;
                            protocol_ok <= '0';
                            length_ok <= '0';
                            state <= IDLE;
                        end if;
                    
                    when STREAM_PAYLOAD =>
                        udp_valid <= '0';  -- BUG FIX #5: Clear pulse from OUTPUT state

                        -- BUG FIX #4: Stream payload bytes sequentially
                        -- Only process when byte_index matches expected position
                        if byte_index = (UDP_HEADER_START + UDP_HEADER_SIZE + payload_byte_count) then
                            if payload_byte_count < to_integer(unsigned(length_reg) - UDP_HEADER_SIZE) then
                                payload_valid <= '1';
                                payload_data <= data_in;
                                payload_byte_count <= payload_byte_count + 1;
                            else
                                -- Payload complete
                                payload_valid <= '0';
                                -- BUG FIX #7: reset all flags and state to IDLE to prevent garbage data
                                udp_valid <= '0';
                                udp_length_err <= '0';
                                header_byte_count <= 0;
                                payload_byte_count <= 0;
                                protocol_ok <= '0';
                                length_ok <= '0';
                                state <= IDLE;
                            end if;
                        end if;

                        -- If frame ends prematurely, return to IDLE
                        if ip_valid = '0' then
                            payload_valid <= '0';
                            -- BUG FIX #7: reset all flags and state to IDLE to prevent garbage data
                            udp_length_err <= '0';
                            header_byte_count <= 0;
                            payload_byte_count <= 0;
                            protocol_ok <= '0';
                            length_ok <= '0';
                            state <= IDLE;
                        end if;
                    
                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;