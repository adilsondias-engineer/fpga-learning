--------------------------------------------------------------------------------
-- IP Header Parser
-- Extracts IPv4 header fields and validates checksum
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ip_parser is
    Port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        
        -- Input from MAC parser (or testbench)
        frame_valid     : in  std_logic;
        data_in         : in  std_logic_vector(7 downto 0);
        byte_index      : in  integer range 0 to 1023;  -- Current byte position
        
        -- Outputs
        ip_valid        : out std_logic;  -- Pulsed when valid IP header parsed
        ip_src          : out std_logic_vector(31 downto 0);
        ip_dst          : out std_logic_vector(31 downto 0);
        ip_protocol     : out std_logic_vector(7 downto 0);
        ip_total_length : out std_logic_vector(15 downto 0);
        ip_checksum_ok  : out std_logic;
        
        -- Error flags
        ip_version_err  : out std_logic;  -- Version != 4
        ip_ihl_err      : out std_logic;  -- IHL != 5 (has options)
        ip_checksum_err : out std_logic;  -- Checksum validation failed

        -- Debug output
        ip_version_ihl_byte : out std_logic_vector(7 downto 0)  -- Raw version/IHL byte for debug
    );
end ip_parser;

architecture Behavioral of ip_parser is
    
    -- State machine
    type state_type is (IDLE, WAIT_ETHERTYPE, PARSE_HEADER, VALIDATE, OUTPUT);
    signal state : state_type := IDLE;
    
    -- Header storage registers
    signal version_ihl      : std_logic_vector(7 downto 0) := (others => '0');
    signal total_length_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal protocol_reg     : std_logic_vector(7 downto 0) := (others => '0');
    signal src_ip_reg       : std_logic_vector(31 downto 0) := (others => '0');
    signal dst_ip_reg       : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Checksum calculation
    signal checksum_acc     : unsigned(19 downto 0) := (others => '0');
    signal temp_word        : std_logic_vector(15 downto 0) := (others => '0');
    signal checksum_valid   : std_logic := '0';
    
    -- Byte counter for header parsing
    signal header_byte_count : integer range 0 to 31 := 0;

    -- EtherType detection
    signal ethertype_byte1  : std_logic_vector(7 downto 0) := (others => '0');
    signal is_ipv4          : std_logic := '0';

    -- Validation step tracking
    signal validate_step : integer range 0 to 2 := 0;
    
begin

    -- 1. State machine logic (IDLE -> WAIT_ETHERTYPE -> PARSE_HEADER -> VALIDATE -> OUTPUT)
    process (clk) is
    begin
        if rising_edge(clk) then

            if reset = '1' then
                state <= IDLE;
                header_byte_count <= 0;
                checksum_acc <= (others => '0');
                is_ipv4 <= '0';
                validate_step <= 0;
            else
                case state is

                    when IDLE =>

                        if frame_valid = '1' then
                            state <= WAIT_ETHERTYPE;
                        end if;

                    -- 2. EtherType detection (bytes at index 12-13 should be 0x0800 for IPv4)
                    when WAIT_ETHERTYPE =>

                        if byte_index = 12 then
                            ethertype_byte1 <= data_in;
                        elsif byte_index = 13 then
                            if ethertype_byte1 = x"08" and data_in = x"00" then
                                is_ipv4 <= '1';
                                state <= PARSE_HEADER;
                                header_byte_count <= 0;
                                checksum_acc <= (others => '0');
                            else
                                state <= IDLE;  -- Not IPv4, go back to IDLE
                            end if;
                        end if;

                    when PARSE_HEADER =>
                        -- Wait for the next expected header byte; only act on matching index
                        if byte_index = 14 + header_byte_count then

                            -- Latch fields by absolute byte index
                            if (byte_index = 14) then
                                version_ihl <= data_in;
                            elsif (byte_index = 16) then
                                total_length_reg(15 downto 8) <= data_in;
                            elsif (byte_index = 17) then
                                total_length_reg(7 downto 0) <= data_in;
                            elsif (byte_index = 23) then
                                protocol_reg <= data_in;
                            elsif (byte_index = 26) then
                                src_ip_reg(31 downto 24) <= data_in;
                            elsif (byte_index = 27) then
                                src_ip_reg(23 downto 16) <= data_in;
                            elsif (byte_index = 28) then
                                src_ip_reg(15 downto 8) <= data_in;
                            elsif (byte_index = 29) then
                                src_ip_reg(7 downto 0) <= data_in;
                            elsif (byte_index = 30) then
                                dst_ip_reg(31 downto 24) <= data_in;
                            elsif (byte_index = 31) then
                                dst_ip_reg(23 downto 16) <= data_in;
                            elsif (byte_index = 32) then
                                dst_ip_reg(15 downto 8) <= data_in;
                            elsif (byte_index = 33) then
                                dst_ip_reg(7 downto 0) <= data_in;
                            end if;

                            -- Checksum accumulation as you have today
                            if header_byte_count mod 2 = 0 then
                                if header_byte_count > 0 then
                                    checksum_acc <= checksum_acc + unsigned("0000" & temp_word);
                                end if;
                                temp_word(15 downto 8) <= data_in;
                            else
                                temp_word(7 downto 0) <= data_in;
                            end if;

                            header_byte_count <= header_byte_count + 1;

                            -- After consuming all 20 header bytes (14..33), move to VALIDATE
                            if header_byte_count = 19 then
                                state <= VALIDATE;
                                validate_step <= 0;
                            end if;

                        else
                            -- No match this cycle: stay in PARSE_HEADER and wait
                            null;
                        end if;

                    when VALIDATE =>

                         -- 5. Validation logic (version=4, IHL=5, checksum=0xFFFF)
                         -- Step 0: Add final word
                         -- Step 1: Fold upper bits (bits 19:16) into lower 16 bits repeatedly
                         -- Step 2: Check result

                        case validate_step is
                            when 0 =>
                                -- Add the final word (10th word)
                                -- report "VALIDATE Step 0: Adding final word=" & to_hstring(temp_word) &
                                --        " to checksum_acc=" & to_hstring(std_logic_vector(checksum_acc));
                                checksum_acc <= checksum_acc + unsigned("0000" & temp_word);
                                validate_step <= 1;

                            when 1 =>
                                -- Fold upper bits (19:16) into lower 16 bits
                                -- report "VALIDATE Step 1: checksum_acc=" & to_hstring(std_logic_vector(checksum_acc)) &
                                --        " upper_bits=" & to_hstring(std_logic_vector(checksum_acc(19 downto 16)));
                                if checksum_acc(19 downto 16) /= "0000" then
                                    -- Fold: add upper 4 bits to lower 16 bits
                                    checksum_acc <= "0000" & (checksum_acc(15 downto 0) + checksum_acc(19 downto 16));
                                    -- Stay in step 1 until upper bits are all 0
                                else
                                    -- All upper bits folded, move to validation
                                    validate_step <= 2;
                                end if;

                            when 2 =>
                                -- Check final result (should be 0xFFFF for valid checksum)
                                -- report "VALIDATE Step 2: Final checksum_acc=" & to_hstring(std_logic_vector(checksum_acc(15 downto 0)));
                                if checksum_acc(15 downto 0) = x"FFFF" then
                                    checksum_valid <= '1';
                                    report "Checksum VALID!";
                                else
                                    checksum_valid <= '0';
                                    report "Checksum INVALID!";
                                end if;
                                state <= OUTPUT;

                            when others =>
                                state <= OUTPUT;
                        end case;

                    when OUTPUT =>
                        state <= IDLE;  -- Immediately transition
                end case;
            end if;
        end if;

    end process;

process (clk) is
    begin
    if rising_edge(clk) then
        case state is
            
            when IDLE =>
                ip_valid <= '0';  -- Clear outputs
                ip_checksum_ok <= '0';
            when WAIT_ETHERTYPE =>
                ip_valid <= '0';  -- Keep cleared
            when PARSE_HEADER =>
                ip_valid <= '0';  -- Still cleared
            when VALIDATE =>
                ip_valid <= '0';  -- Still cleared
            when OUTPUT =>
                -- Only generate ip_valid pulse if all checks pass
                if (version_ihl(7 downto 4) = "0100" and     -- Version = 4
                    version_ihl(3 downto 0) = "0101" and     -- IHL = 5 (no options)
                    checksum_valid = '1') then               -- Checksum valid
                    ip_valid <= '1';
                else
                    ip_valid <= '0';  -- Invalid frame, no pulse
                end if;
                ip_checksum_ok <= checksum_valid;
    end case;
    end if;
end process;

    -- 6. Output pulse generation (ip_valid for 1 clock cycle)
    ip_src          <= src_ip_reg;
    ip_dst          <= dst_ip_reg;
    ip_protocol     <= protocol_reg;
    ip_total_length <= total_length_reg;

  --  ip_valid        <= '1' when state = OUTPUT else '0';
    ip_version_err  <= '1' when version_ihl(7 downto 4) /= "0100" else '0';
    ip_ihl_err      <= '1' when version_ihl(3 downto 0) /= "0101" else '0';
    ip_checksum_err <= '1' when checksum_valid = '0' else '0';

    -- Debug output
    ip_version_ihl_byte <= version_ihl;

end Behavioral;