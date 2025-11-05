--------------------------------------------------------------------------------
-- IP Parser Testbench
-- Comprehensive verification with multiple test cases
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity ip_parser_tb is
end ip_parser_tb;

architecture Behavioral of ip_parser_tb is

    -- Component declaration
    component ip_parser is
        Port (
            clk             : in  std_logic;
            reset           : in  std_logic;
            frame_valid     : in  std_logic;
            data_in         : in  std_logic_vector(7 downto 0);
            byte_index      : in  integer range 0 to 1023;
            ip_valid        : out std_logic;
            ip_src          : out std_logic_vector(31 downto 0);
            ip_dst          : out std_logic_vector(31 downto 0);
            ip_protocol     : out std_logic_vector(7 downto 0);
            ip_total_length : out std_logic_vector(15 downto 0);
            ip_checksum_ok  : out std_logic;
            ip_version_err  : out std_logic;
            ip_ihl_err      : out std_logic;
            ip_checksum_err : out std_logic
        );
    end component;

    -- Clock and reset
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    -- DUT inputs
    signal frame_valid : std_logic := '0';
    signal data_in : std_logic_vector(7 downto 0) := (others => '0');
    signal byte_index : integer range 0 to 1023 := 0;

    -- DUT outputs
    signal ip_valid : std_logic;
    signal ip_src : std_logic_vector(31 downto 0);
    signal ip_dst : std_logic_vector(31 downto 0);
    signal ip_protocol : std_logic_vector(7 downto 0);
    signal ip_total_length : std_logic_vector(15 downto 0);
    signal ip_checksum_ok : std_logic;
    signal ip_version_err : std_logic;
    signal ip_ihl_err : std_logic;
    signal ip_checksum_err : std_logic;

    -- Test control
    signal test_running : boolean := true;
    signal test_passed : integer := 0;
    signal test_failed : integer := 0;

    -- Test vectors (Ethernet frame format)
    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
    
    -- Valid UDP packet: 192.168.1.10 -> 192.168.1.100, protocol=17
    constant VALID_UDP_FRAME : byte_array(0 to 33) := (
        -- Destination MAC (6 bytes)
        x"00", x"0A", x"35", x"02", x"AF", x"9A",
        -- Source MAC (6 bytes)
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",
        -- EtherType: 0x0800 = IPv4 (2 bytes)
        x"08", x"00",
        -- IP Header (20 bytes)
        x"45",              -- Version=4, IHL=5
        x"00",              -- DSCP/ECN
        x"00", x"14",       -- Total length = 20 (header only, no payload for test)
        x"00", x"00",       -- Identification
        x"00", x"00",       -- Flags/Fragment offset
        x"40",              -- TTL = 64
        x"11",              -- Protocol = 17 (UDP)
        x"F7", x"1A",       -- Checksum (corrected - was E7 1A)
        x"C0", x"A8", x"01", x"0A",  -- Source: 192.168.1.10
        x"C0", x"A8", x"01", x"64"   -- Dest: 192.168.1.100
    );

    -- Valid TCP packet: 10.0.0.1 -> 10.0.0.2, protocol=6
    constant VALID_TCP_FRAME : byte_array(0 to 33) := (
        x"00", x"0A", x"35", x"02", x"AF", x"9A",  -- Dest MAC
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",  -- Src MAC
        x"08", x"00",                               -- EtherType
        -- IP Header
        x"45", x"00", x"00", x"14",
        x"00", x"00", x"00", x"00",
        x"40", x"06",       -- Protocol = 6 (TCP)
        x"66", x"E2",       -- Checksum (corrected)
        x"0A", x"00", x"00", x"01",  -- Src: 10.0.0.1
        x"0A", x"00", x"00", x"02"   -- Dst: 10.0.0.2
    );

    -- Invalid checksum packet (checksum field corrupted)
    constant INVALID_CHECKSUM_FRAME : byte_array(0 to 33) := (
        x"00", x"0A", x"35", x"02", x"AF", x"9A",
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",
        x"08", x"00",
        -- IP Header with wrong checksum
        x"45", x"00", x"00", x"14",
        x"00", x"00", x"00", x"00",
        x"40", x"11",
        x"FF", x"FF",       -- Wrong checksum (should be F7 1A)
        x"C0", x"A8", x"01", x"0A",
        x"C0", x"A8", x"01", x"64"
    );

    -- Invalid version (IPv6 indicated by version=6)
    constant INVALID_VERSION_FRAME : byte_array(0 to 33) := (
        x"00", x"0A", x"35", x"02", x"AF", x"9A",
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",
        x"08", x"00",
        -- IP Header
        x"65",              -- Version=6 (WRONG), IHL=5
        x"00", x"00", x"14",
        x"00", x"00", x"00", x"00",
        x"40", x"11",
        x"61", x"1B",       -- Checksum corrected for version=6
        x"C0", x"A8", x"01", x"0A",
        x"C0", x"A8", x"01", x"64"
    );

    -- IP with options (IHL=6, indicating 24-byte header)
    constant IP_WITH_OPTIONS_FRAME : byte_array(0 to 33) := (
        x"00", x"0A", x"35", x"02", x"AF", x"9A",
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",
        x"08", x"00",
        -- IP Header
        x"46",              -- Version=4, IHL=6 (has options)
        x"00", x"00", x"18",  -- Total length = 24
        x"00", x"00", x"00", x"00",
        x"40", x"11",
        x"AA", x"17",       -- Checksum corrected for IHL=6
        x"C0", x"A8", x"01", x"0A",
        x"C0", x"A8", x"01", x"64"
    );

    -- Non-IP frame (ARP: EtherType 0x0806)
    constant ARP_FRAME : byte_array(0 to 13) := (
        x"00", x"0A", x"35", x"02", x"AF", x"9A",
        x"AA", x"BB", x"CC", x"DD", x"EE", x"FF",
        x"08", x"06"        -- EtherType = ARP (should be ignored)
    );

    -- Helper procedures
    procedure send_frame(
        constant frame_data : in byte_array;
        signal clk : in std_logic;
        signal frame_valid : out std_logic;
        signal data_in : out std_logic_vector(7 downto 0);
        signal byte_index : out integer
    ) is
    begin
        wait until rising_edge(clk);
        frame_valid <= '1';
        
        for i in frame_data'range loop
            data_in <= frame_data(i);
            byte_index <= i;
            wait until rising_edge(clk);
        end loop;
        
        frame_valid <= '0';
        data_in <= (others => '0');
        byte_index <= 0;
        wait until rising_edge(clk);
    end procedure;

    procedure check_result(
        constant test_name : in string;
        constant expected_valid : in std_logic;
        constant expected_src : in std_logic_vector(31 downto 0);
        constant expected_dst : in std_logic_vector(31 downto 0);
        constant expected_protocol : in std_logic_vector(7 downto 0);
        constant expected_checksum_ok : in std_logic;
        signal ip_valid : in std_logic;
        signal ip_src : in std_logic_vector(31 downto 0);
        signal ip_dst : in std_logic_vector(31 downto 0);
        signal ip_protocol : in std_logic_vector(7 downto 0);
        signal ip_checksum_ok : in std_logic;
        signal test_passed : inout integer;
        signal test_failed : inout integer
    ) is
        variable passed : boolean := true;
        variable found_pulse : boolean := false;
        variable captured_valid : std_logic := '0';
        variable captured_src : std_logic_vector(31 downto 0) := (others => '0');
        variable captured_dst : std_logic_vector(31 downto 0) := (others => '0');
        variable captured_protocol : std_logic_vector(7 downto 0) := (others => '0');
        variable captured_checksum_ok : std_logic := '0';

    begin
        -- Wait for ip_valid pulse (with timeout)
        -- Monitor for up to 1000 clock cycles (10 microseconds at 100 MHz)
        for i in 0 to 1000 loop
            wait until rising_edge(clk);

            if ip_valid = '1' then
                -- Capture all outputs synchronously with pulse
                found_pulse := true;
                captured_valid := ip_valid;
                captured_src := ip_src;
                captured_dst := ip_dst;
                captured_protocol := ip_protocol;
                captured_checksum_ok := ip_checksum_ok;
                exit;  -- Exit loop once pulse found
            end if;
        end loop;

        report "========================================";
        report "Test: " & test_name;
        report "========================================";

        -- Check if we found the expected pulse
        if expected_valid = '1' then
            if not found_pulse then
                report "FAIL: ip_valid pulse never occurred (timeout after 10us)" severity error;
                passed := false;
            else
                report "INFO: ip_valid pulse detected" severity note;

                -- Check captured values
                if captured_src /= expected_src then
                    report "FAIL: ip_src = " & integer'image(to_integer(unsigned(captured_src))) &
                           ", expected " & integer'image(to_integer(unsigned(expected_src))) severity error;
                    passed := false;
                end if;

                if captured_dst /= expected_dst then
                    report "FAIL: ip_dst = " & integer'image(to_integer(unsigned(captured_dst))) &
                           ", expected " & integer'image(to_integer(unsigned(expected_dst))) severity error;
                    passed := false;
                end if;

                if captured_protocol /= expected_protocol then
                    report "FAIL: ip_protocol = " & integer'image(to_integer(unsigned(captured_protocol))) &
                           ", expected " & integer'image(to_integer(unsigned(expected_protocol))) severity error;
                    passed := false;
                end if;

                if captured_checksum_ok /= expected_checksum_ok then
                    report "FAIL: ip_checksum_ok = " & std_logic'image(captured_checksum_ok) &
                           ", expected " & std_logic'image(expected_checksum_ok) severity error;
                    passed := false;
                end if;
            end if;
        else
            -- Expect no pulse for invalid frames
            if found_pulse then
                report "FAIL: unexpected ip_valid pulse occurred" severity error;
                passed := false;
            else
                report "INFO: No ip_valid pulse (as expected for invalid frame)" severity note;
            end if;
        end if;
        
        if passed then
            report "PASS: " & test_name severity note;
            test_passed <= test_passed + 1;
        else
            report "FAIL: " & test_name severity error;
            test_failed <= test_failed + 1;
        end if;
        
        report "----------------------------------------";
    end procedure;

begin

    -- Instantiate DUT
    dut: ip_parser
        port map (
            clk => clk,
            reset => reset,
            frame_valid => frame_valid,
            data_in => data_in,
            byte_index => byte_index,
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_total_length => ip_total_length,
            ip_checksum_ok => ip_checksum_ok,
            ip_version_err => ip_version_err,
            ip_ihl_err => ip_ihl_err,
            ip_checksum_err => ip_checksum_err
        );

    -- Clock generation
    clk_process: process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    stimulus: process
    begin
        -- Reset
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 50 ns;
        
        report "========================================";
        report "Starting IP Parser Tests";
        report "========================================";
        
        -- Test 1: Valid UDP packet
        send_frame(VALID_UDP_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 1: Valid UDP packet",
            expected_valid => '1',
            expected_src => x"C0A8010A",      -- 192.168.1.10
            expected_dst => x"C0A80164",      -- 192.168.1.100
            expected_protocol => x"11",       -- UDP
            expected_checksum_ok => '1',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
		wait for 1 us;
        
        -- Test 2: Valid TCP packet
        send_frame(VALID_TCP_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 2: Valid TCP packet",
            expected_valid => '1',
            expected_src => x"0A000001",      -- 10.0.0.1
            expected_dst => x"0A000002",      -- 10.0.0.2
            expected_protocol => x"06",       -- TCP
            expected_checksum_ok => '1',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
        wait for 1 us;
        
        -- Test 3: Invalid checksum
        send_frame(INVALID_CHECKSUM_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 3: Invalid checksum",
            expected_valid => '0',            -- Should reject
            expected_src => x"00000000",
            expected_dst => x"00000000",
            expected_protocol => x"00",
            expected_checksum_ok => '0',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
        wait for 1 us;
        
        -- Test 4: Invalid version
        send_frame(INVALID_VERSION_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 4: Invalid version (IPv6)",
            expected_valid => '0',            -- Should reject
            expected_src => x"00000000",
            expected_dst => x"00000000",
            expected_protocol => x"00",
            expected_checksum_ok => '0',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
        wait for 1 us;
        
        -- Test 5: IP with options
        send_frame(IP_WITH_OPTIONS_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 5: IP with options (IHL=6)",
            expected_valid => '0',            -- Should reject
            expected_src => x"00000000",
            expected_dst => x"00000000",
            expected_protocol => x"00",
            expected_checksum_ok => '0',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
        wait for 1 us;
        
        -- Test 6: Non-IP frame (ARP)
        send_frame(ARP_FRAME, clk, frame_valid, data_in, byte_index);
        check_result(
            "Test 6: Non-IP frame (ARP)",
            expected_valid => '0',            -- Should ignore
            expected_src => x"00000000",
            expected_dst => x"00000000",
            expected_protocol => x"00",
            expected_checksum_ok => '0',
            ip_valid => ip_valid,
            ip_src => ip_src,
            ip_dst => ip_dst,
            ip_protocol => ip_protocol,
            ip_checksum_ok => ip_checksum_ok,
            test_passed => test_passed,
            test_failed => test_failed
        );
        
        wait for 1 us;
        -- Summary
        report "========================================";
        report "Test Summary";
        report "========================================";
        report "Tests Passed: " & integer'image(test_passed);
        report "Tests Failed: " & integer'image(test_failed);
        
        if test_failed = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;
        
        test_running <= false;
        wait;
    end process;

end Behavioral;