--------------------------------------------------------------------------------
-- UDP Parser Testbench
-- Comprehensive verification with multiple test cases
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity udp_parser_tb is
end udp_parser_tb;

architecture Behavioral of udp_parser_tb is

    -- Component declaration
    component udp_parser is
        Port (
            clk             : in  std_logic;
            reset           : in  std_logic;
            
            -- Input from IP parser
            ip_valid        : in  std_logic;
            ip_protocol     : in  std_logic_vector(7 downto 0);
            ip_total_length : in  std_logic_vector(15 downto 0);
            data_in         : in  std_logic_vector(7 downto 0);
            byte_index      : in  integer range 0 to 1023;
            
            -- Outputs
            udp_valid       : out std_logic;
            udp_src_port    : out std_logic_vector(15 downto 0);
            udp_dst_port    : out std_logic_vector(15 downto 0);
            udp_length      : out std_logic_vector(15 downto 0);
            udp_checksum_ok : out std_logic;
            udp_length_err  : out std_logic;
            
            -- Payload access
            payload_valid   : out std_logic;
            payload_data    : out std_logic_vector(7 downto 0);
            payload_length  : out std_logic_vector(15 downto 0)
        );
    end component;

    -- Clock and reset
    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    
    -- Inputs
    signal ip_valid        : std_logic := '0';
    signal ip_protocol     : std_logic_vector(7 downto 0) := x"00";
    signal ip_total_length : std_logic_vector(15 downto 0) := x"0000";
    signal data_in         : std_logic_vector(7 downto 0) := x"00";
    signal byte_index      : integer range 0 to 1023 := 0;
    
    -- Outputs
    signal udp_valid       : std_logic;
    signal udp_src_port    : std_logic_vector(15 downto 0);
    signal udp_dst_port    : std_logic_vector(15 downto 0);
    signal udp_length      : std_logic_vector(15 downto 0);
    signal udp_checksum_ok : std_logic;
    signal udp_length_err  : std_logic;
    signal payload_valid   : std_logic;
    signal payload_data    : std_logic_vector(7 downto 0);
    signal payload_length  : std_logic_vector(15 downto 0);
    
    -- Test control
    signal test_running : boolean := true;
    signal tests_passed : integer := 0;
    signal tests_failed : integer := 0;
    
    -- Clock period
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    
begin

    -- Clock generation
    clk_process: process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- DUT instantiation
    dut: udp_parser
        port map (
            clk             => clk,
            reset           => reset,
            ip_valid        => ip_valid,
            ip_protocol     => ip_protocol,
            ip_total_length => ip_total_length,
            data_in         => data_in,
            byte_index      => byte_index,
            udp_valid       => udp_valid,
            udp_src_port    => udp_src_port,
            udp_dst_port    => udp_dst_port,
            udp_length      => udp_length,
            udp_checksum_ok => udp_checksum_ok,
            udp_length_err  => udp_length_err,
            payload_valid   => payload_valid,
            payload_data    => payload_data,
            payload_length  => payload_length
        );

    -- Main test process
    stimulus: process
        
        -- Helper procedure to send UDP packet
        procedure send_udp_packet(
            constant protocol     : in std_logic_vector(7 downto 0);
            constant total_len    : in std_logic_vector(15 downto 0);
            constant src_port     : in std_logic_vector(15 downto 0);
            constant dst_port     : in std_logic_vector(15 downto 0);
            constant udp_len      : in std_logic_vector(15 downto 0);
            constant checksum     : in std_logic_vector(15 downto 0);
            constant payload_bytes: in integer
        ) is
        begin
            -- Simulate IP parser asserting ip_valid
            ip_protocol     <= protocol;
            ip_total_length <= total_len;
            ip_valid        <= '1';
            wait for CLK_PERIOD;
            
            -- Start of UDP header (byte_index 34 = end of IP header)
            byte_index <= 34;
            
            -- Source port (2 bytes)
            data_in <= src_port(15 downto 8);
            wait for CLK_PERIOD;
            byte_index <= 35;
            data_in <= src_port(7 downto 0);
            wait for CLK_PERIOD;
            
            -- Destination port (2 bytes)
            byte_index <= 36;
            data_in <= dst_port(15 downto 8);
            wait for CLK_PERIOD;
            byte_index <= 37;
            data_in <= dst_port(7 downto 0);
            wait for CLK_PERIOD;
            
            -- Length (2 bytes)
            byte_index <= 38;
            data_in <= udp_len(15 downto 8);
            wait for CLK_PERIOD;
            byte_index <= 39;
            data_in <= udp_len(7 downto 0);
            wait for CLK_PERIOD;
            
            -- Checksum (2 bytes)
            byte_index <= 40;
            data_in <= checksum(15 downto 8);
            wait for CLK_PERIOD;
            byte_index <= 41;
            data_in <= checksum(7 downto 0);
            wait for CLK_PERIOD;
            
            -- Payload (if any)
            for i in 0 to payload_bytes-1 loop
                byte_index <= 42 + i;
                data_in <= std_logic_vector(to_unsigned(i mod 256, 8));
                wait for CLK_PERIOD;
            end loop;
            
            -- End of packet
            ip_valid <= '0';
            wait for CLK_PERIOD * 2;
        end procedure;
        
        -- Helper procedure to check results
        procedure check_result(
            constant test_name      : in string;
            constant exp_valid      : in std_logic;
            constant exp_src_port   : in std_logic_vector(15 downto 0);
            constant exp_dst_port   : in std_logic_vector(15 downto 0);
            constant exp_length     : in std_logic_vector(15 downto 0);
            constant exp_chksum_ok  : in std_logic;
            constant exp_len_err    : in std_logic
        ) is
            variable valid_captured : std_logic := '0';
            variable src_captured : std_logic_vector(15 downto 0) := (others => '0');
            variable dst_captured : std_logic_vector(15 downto 0) := (others => '0');
            variable len_captured : std_logic_vector(15 downto 0) := (others => '0');
            variable chk_captured : std_logic := '0';
            variable err_captured : std_logic := '0';
        begin
            -- Wait and capture outputs when udp_valid pulses
            -- Parser needs ~11 clocks: 1(IDLE->PARSE) + 8(parse) + 1(VALIDATE) + 1(OUTPUT)
            for i in 0 to 20 loop  -- Wait up to 20 clocks to catch the pulse
                wait for CLK_PERIOD;
                if udp_valid = '1' then
                    -- Capture outputs when valid asserts
                    valid_captured := '1';
                    src_captured := udp_src_port;
                    dst_captured := udp_dst_port;
                    len_captured := udp_length;
                    chk_captured := udp_checksum_ok;
                end if;
                if udp_length_err = '1' then
                    err_captured := '1';
                end if;
            end loop;

            if valid_captured = exp_valid and
               src_captured = exp_src_port and
               dst_captured = exp_dst_port and
               len_captured = exp_length and
               chk_captured = exp_chksum_ok and
               err_captured = exp_len_err then
                report "PASS: " & test_name severity note;
                tests_passed <= tests_passed + 1;
            else
                report "FAIL: " & test_name severity error;
                report "  Expected: valid=" & std_logic'image(exp_valid) &
                       " src=" & integer'image(to_integer(unsigned(exp_src_port))) &
                       " dst=" & integer'image(to_integer(unsigned(exp_dst_port))) &
                       " len=" & integer'image(to_integer(unsigned(exp_length))) &
                       " chksum=" & std_logic'image(exp_chksum_ok) &
                       " len_err=" & std_logic'image(exp_len_err) severity error;
                report "  Got:      valid=" & std_logic'image(valid_captured) &
                       " src=" & integer'image(to_integer(unsigned(src_captured))) &
                       " dst=" & integer'image(to_integer(unsigned(dst_captured))) &
                       " len=" & integer'image(to_integer(unsigned(len_captured))) &
                       " chksum=" & std_logic'image(chk_captured) &
                       " len_err=" & std_logic'image(err_captured) severity error;
                tests_failed <= tests_failed + 1;
            end if;
        end procedure;
        
    begin
        -- Initial reset
        reset <= '1';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;
        
        report "========================================" severity note;
        report "UDP PARSER TESTBENCH" severity note;
        report "========================================" severity note;
        
        -- Test 1: Valid UDP to port 80 (HTTP)
        report "Test 1: Valid UDP to port 80" severity note;

        -- Start monitoring for output BEFORE sending full packet
        -- The parser will output after header (not payload)

        -- Send header only first
        ip_protocol     <= x"11";
        ip_total_length <= x"002C";
        ip_valid        <= '1';
        wait for CLK_PERIOD;

        -- UDP header bytes
        byte_index <= 34; data_in <= x"30"; wait for CLK_PERIOD; -- src port MSB
        byte_index <= 35; data_in <= x"39"; wait for CLK_PERIOD; -- src port LSB (12345)
        byte_index <= 36; data_in <= x"00"; wait for CLK_PERIOD; -- dst port MSB
        byte_index <= 37; data_in <= x"50"; wait for CLK_PERIOD; -- dst port LSB (80)
        byte_index <= 38; data_in <= x"00"; wait for CLK_PERIOD; -- length MSB
        byte_index <= 39; data_in <= x"18"; wait for CLK_PERIOD; -- length LSB (24)
        byte_index <= 40; data_in <= x"A5"; wait for CLK_PERIOD; -- checksum MSB
        byte_index <= 41; data_in <= x"B3"; wait for CLK_PERIOD; -- checksum LSB

        -- Now check result (pulse should occur within next few clocks)
        check_result(
            test_name     => "Valid UDP port 80",
            exp_valid     => '1',
            exp_src_port  => x"3039",
            exp_dst_port  => x"0050",
            exp_length    => x"0018",
            exp_chksum_ok => '1',
            exp_len_err   => '0'
        );

        -- Clean up
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 2: Valid UDP to port 53 (DNS)
        report "Test 2: Valid UDP to port 53 (DNS)" severity note;
        ip_protocol     <= x"11";
        ip_total_length <= x"0024";
        ip_valid        <= '1';
        wait for CLK_PERIOD;
        byte_index <= 34; data_in <= x"C0"; wait for CLK_PERIOD;
        byte_index <= 35; data_in <= x"A8"; wait for CLK_PERIOD;
        byte_index <= 36; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 37; data_in <= x"35"; wait for CLK_PERIOD;
        byte_index <= 38; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 39; data_in <= x"10"; wait for CLK_PERIOD;
        byte_index <= 40; data_in <= x"12"; wait for CLK_PERIOD;
        byte_index <= 41; data_in <= x"34"; wait for CLK_PERIOD;
        check_result(
            test_name     => "Valid UDP port 53",
            exp_valid     => '1',
            exp_src_port  => x"C0A8",
            exp_dst_port  => x"0035",
            exp_length    => x"0010",
            exp_chksum_ok => '1',
            exp_len_err   => '0'
        );
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 3: UDP with checksum disabled (0x0000)
        report "Test 3: UDP with checksum=0 (disabled)" severity note;
        ip_protocol     <= x"11";
        ip_total_length <= x"001C";
        ip_valid        <= '1';
        wait for CLK_PERIOD;
        byte_index <= 34; data_in <= x"12"; wait for CLK_PERIOD;
        byte_index <= 35; data_in <= x"34"; wait for CLK_PERIOD;
        byte_index <= 36; data_in <= x"56"; wait for CLK_PERIOD;
        byte_index <= 37; data_in <= x"78"; wait for CLK_PERIOD;
        byte_index <= 38; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 39; data_in <= x"08"; wait for CLK_PERIOD;
        byte_index <= 40; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 41; data_in <= x"00"; wait for CLK_PERIOD;
        check_result(
            test_name     => "UDP checksum disabled",
            exp_valid     => '1',
            exp_src_port  => x"1234",
            exp_dst_port  => x"5678",
            exp_length    => x"0008",
            exp_chksum_ok => '1',       -- Checksum disabled = OK
            exp_len_err   => '0'
        );
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 4: TCP packet (should be ignored)
        report "Test 4: TCP packet (should ignore)" severity note;
        ip_protocol     <= x"06";  -- TCP, not UDP
        ip_total_length <= x"0028";
        ip_valid        <= '1';
        wait for CLK_PERIOD;
        byte_index <= 34; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 35; data_in <= x"50"; wait for CLK_PERIOD;
        byte_index <= 36; data_in <= x"12"; wait for CLK_PERIOD;
        byte_index <= 37; data_in <= x"34"; wait for CLK_PERIOD;
        byte_index <= 38; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 39; data_in <= x"08"; wait for CLK_PERIOD;
        byte_index <= 40; data_in <= x"FF"; wait for CLK_PERIOD;
        byte_index <= 41; data_in <= x"FF"; wait for CLK_PERIOD;
        check_result(
            test_name     => "TCP packet ignored",
            exp_valid     => '0',       -- Should not validate
            exp_src_port  => x"0000",   -- Don't care
            exp_dst_port  => x"0000",
            exp_length    => x"0000",
            exp_chksum_ok => '0',
            exp_len_err   => '0'
        );
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 5: Length mismatch (UDP length > IP payload)
        report "Test 5: Length mismatch error" severity note;
        ip_protocol     <= x"11";
        ip_total_length <= x"001C";
        ip_valid        <= '1';
        wait for CLK_PERIOD;
        byte_index <= 34; data_in <= x"AB"; wait for CLK_PERIOD;
        byte_index <= 35; data_in <= x"CD"; wait for CLK_PERIOD;
        byte_index <= 36; data_in <= x"EF"; wait for CLK_PERIOD;
        byte_index <= 37; data_in <= x"01"; wait for CLK_PERIOD;
        byte_index <= 38; data_in <= x"01"; wait for CLK_PERIOD;
        byte_index <= 39; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 40; data_in <= x"55"; wait for CLK_PERIOD;
        byte_index <= 41; data_in <= x"55"; wait for CLK_PERIOD;
        check_result(
            test_name     => "Length mismatch",
            exp_valid     => '0',
            exp_src_port  => x"0000",
            exp_dst_port  => x"0000",
            exp_length    => x"0000",
            exp_chksum_ok => '0',
            exp_len_err   => '1'        -- Length error flag
        );
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 6: Minimum valid UDP (8-byte header only)
        report "Test 6: Minimum UDP packet" severity note;
        ip_protocol     <= x"11";
        ip_total_length <= x"001C";
        ip_valid        <= '1';
        wait for CLK_PERIOD;
        byte_index <= 34; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 35; data_in <= x"01"; wait for CLK_PERIOD;
        byte_index <= 36; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 37; data_in <= x"02"; wait for CLK_PERIOD;
        byte_index <= 38; data_in <= x"00"; wait for CLK_PERIOD;
        byte_index <= 39; data_in <= x"08"; wait for CLK_PERIOD;
        byte_index <= 40; data_in <= x"AB"; wait for CLK_PERIOD;
        byte_index <= 41; data_in <= x"CD"; wait for CLK_PERIOD;
        check_result(
            test_name     => "Minimum UDP",
            exp_valid     => '1',
            exp_src_port  => x"0001",
            exp_dst_port  => x"0002",
            exp_length    => x"0008",
            exp_chksum_ok => '1',
            exp_len_err   => '0'
        );
        ip_valid <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test Summary
        wait for CLK_PERIOD * 10;
        report "========================================" severity note;
        report "TEST SUMMARY" severity note;
        report "========================================" severity note;
        report "Tests Passed: " & integer'image(tests_passed) severity note;
        report "Tests Failed: " & integer'image(tests_failed) severity note;
        
        if tests_failed = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;
        
        report "========================================" severity note;
        
        test_running <= false;
        wait;
    end process;

end Behavioral;