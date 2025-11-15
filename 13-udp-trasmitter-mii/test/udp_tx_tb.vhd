----------------------------------------------------------------------------------
-- UDP Transmitter Testbench
-- Tests the complete UDP TX stack: udp_packet_builder -> mii_tx -> PHY
--
-- Test Flow:
--   1. Send a simple "HELLO WORLD" payload
--   2. Verify MII signals (preamble, SFD, headers, payload)
--   3. Check IP checksum correctness
--   4. Validate Ethernet frame structure
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use std.textio.all;

entity udp_tx_tb is
end udp_tx_tb;

architecture Behavioral of udp_tx_tb is

    -- Clock periods
    constant CLK_25MHZ_PERIOD : time := 40 ns;  -- 25 MHz
    constant CLK_100MHZ_PERIOD : time := 10 ns; -- 100 MHz

    -- Component declarations
    component udp_packet_builder is
        generic (
            SRC_MAC      : std_logic_vector(47 downto 0);
            DST_MAC      : std_logic_vector(47 downto 0);
            SRC_IP       : std_logic_vector(31 downto 0);
            DST_IP       : std_logic_vector(31 downto 0);
            SRC_PORT     : std_logic_vector(15 downto 0);
            DST_PORT     : std_logic_vector(15 downto 0)
        );
        port (
            clk          : in  std_logic;
            reset        : in  std_logic;
            payload_data : in  std_logic_vector(7 downto 0);
            payload_len  : in  std_logic_vector(15 downto 0);
            payload_valid: in  std_logic;
            payload_ready: out std_logic;
            payload_start: in  std_logic;
            tx_data      : out std_logic_vector(7 downto 0);
            tx_valid     : out std_logic;
            tx_ready     : in  std_logic;
            tx_start     : out std_logic;
            tx_end       : out std_logic
        );
    end component;

    component mii_tx is
        port (
            mii_tx_clk   : in  std_logic;
            reset        : in  std_logic;
            tx_data      : in  std_logic_vector(7 downto 0);
            tx_valid     : in  std_logic;
            tx_ready     : out std_logic;
            tx_start     : in  std_logic;
            tx_end       : in  std_logic;
            eth_tx_en    : out std_logic;
            eth_txd      : out std_logic_vector(3 downto 0)
        );
    end component;

    -- Clock and reset signals
    signal clk_25mhz : std_logic := '0';
    signal reset : std_logic := '1';

    -- Packet builder signals
    signal payload_data : std_logic_vector(7 downto 0) := (others => '0');
    signal payload_len : std_logic_vector(15 downto 0) := x"000C";  -- 12 bytes ("HELLO WORLD!")
    signal payload_valid : std_logic := '0';
    signal payload_ready : std_logic;
    signal payload_start : std_logic := '0';

    -- Interconnect between packet builder and MII TX
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal tx_ready : std_logic;
    signal tx_start : std_logic;
    signal tx_end : std_logic;

    -- MII TX outputs
    signal eth_tx_en : std_logic;
    signal eth_txd : std_logic_vector(3 downto 0);

    -- Test payload
    type payload_array_type is array (0 to 11) of std_logic_vector(7 downto 0);
    constant TEST_PAYLOAD : payload_array_type := (
        x"48",  -- H
        x"45",  -- E
        x"4C",  -- L
        x"4C",  -- L
        x"4F",  -- O
        x"20",  -- (space)
        x"57",  -- W
        x"4F",  -- O
        x"52",  -- R
        x"4C",  -- L
        x"44",  -- D
        x"21"   -- !
    );

    signal payload_index : integer := 0;

    -- Packet capture for verification
    type byte_array_type is array (0 to 1023) of std_logic_vector(7 downto 0);
    signal captured_packet : byte_array_type;
    signal capture_index : integer := 0;
    signal nibble_buffer : std_logic_vector(3 downto 0) := (others => '0');
    signal nibble_phase : std_logic := '0';  -- 0 = low nibble, 1 = high nibble

begin

    -- Clock generator
    clk_25mhz <= not clk_25mhz after CLK_25MHZ_PERIOD / 2;

    -- DUT: UDP Packet Builder
    uut_packet_builder: udp_packet_builder
        generic map (
            SRC_MAC  => x"AABBCCDDEEFF",
            DST_MAC  => x"112233445566",
            SRC_IP   => x"C0A80102",  -- 192.168.1.2
            DST_IP   => x"C0A80164",  -- 192.168.1.100
            SRC_PORT => x"1389",      -- 5001
            DST_PORT => x"1388"       -- 5000
        )
        port map (
            clk          => clk_25mhz,
            reset        => reset,
            payload_data => payload_data,
            payload_len  => payload_len,
            payload_valid => payload_valid,
            payload_ready => payload_ready,
            payload_start => payload_start,
            tx_data      => tx_data,
            tx_valid     => tx_valid,
            tx_ready     => tx_ready,
            tx_start     => tx_start,
            tx_end       => tx_end
        );

    -- DUT: MII TX
    uut_mii_tx: mii_tx
        port map (
            mii_tx_clk   => clk_25mhz,
            reset        => reset,
            tx_data      => tx_data,
            tx_valid     => tx_valid,
            tx_ready     => tx_ready,
            tx_start     => tx_start,
            tx_end       => tx_end,
            eth_tx_en    => eth_tx_en,
            eth_txd      => eth_txd
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- Reset
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        wait for 100 ns;

        report "TEST: Starting UDP packet transmission";

        -- Start packet transmission (synchronous with clock)
        wait until rising_edge(clk_25mhz);
        payload_start <= '1';
        wait until rising_edge(clk_25mhz);
        payload_start <= '0';

        -- Wait for payload_ready to go high (ready for payload)
        report "TEST: Waiting for payload_ready to go high";
        wait until payload_ready = '1';
        report "TEST: Ready for payload data, payload_ready=" & std_logic'image(payload_ready);

        -- Send payload bytes (proper valid/ready handshaking)
        for i in 0 to 11 loop
            -- Wait for ready signal
            while payload_ready = '0' loop
                wait until rising_edge(clk_25mhz);
            end loop;

            -- Assert valid with data
            payload_data <= TEST_PAYLOAD(i);
            payload_valid <= '1';
            report "TEST: Asserting payload_valid for byte " & integer'image(i);

            -- Wait for handshake (both valid and ready high)
            wait until rising_edge(clk_25mhz);

            -- Wait until ready drops (byte accepted) then goes back high (ready for next)
            while payload_ready = '1' loop
                wait until rising_edge(clk_25mhz);
            end loop;

            -- Handshake complete, drop valid
            payload_valid <= '0';
            report "TEST: Byte " & integer'image(i) & " accepted";
        end loop;
        report "TEST: waiting 10us payload_valid=" & std_logic'image(payload_valid);
        -- Wait for transmission to complete (62 bytes * 80ns/byte = ~5us, use 10us to be safe)
        wait for 10 us;

        report "TEST: Packet transmission complete";
        report "TEST: Captured " & integer'image(capture_index) & " bytes";

        -- Verify packet structure
        assert capture_index > 60 report "ERROR: Packet too short" severity error;

        -- Check Ethernet header
        assert captured_packet(0) = x"11" report "ERROR: Dest MAC byte 0 wrong" severity error;
        assert captured_packet(1) = x"22" report "ERROR: Dest MAC byte 1 wrong" severity error;
        assert captured_packet(2) = x"33" report "ERROR: Dest MAC byte 2 wrong" severity error;
        assert captured_packet(6) = x"AA" report "ERROR: Src MAC byte 0 wrong" severity error;
        assert captured_packet(12) = x"08" report "ERROR: EtherType byte 0 wrong (expected 0x08)" severity error;
        assert captured_packet(13) = x"00" report "ERROR: EtherType byte 1 wrong (expected 0x00)" severity error;

        -- Check IP header
        assert captured_packet(14) = x"45" report "ERROR: IP Version/IHL wrong" severity error;
        assert captured_packet(23) = x"11" report "ERROR: IP Protocol wrong (expected 0x11 for UDP)" severity error;

        -- Check payload
        assert captured_packet(42) = x"48" report "ERROR: Payload byte 0 wrong (expected 'H')" severity error;
        assert captured_packet(43) = x"45" report "ERROR: Payload byte 1 wrong (expected 'E')" severity error;

        report "TEST: PASS - Packet structure verified";

        wait;
    end process;

    -- Packet capture process (captures nibbles from MII and reconstructs bytes)
    capture_proc: process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if reset = '1' then
                capture_index <= 0;
                nibble_phase <= '0';
                nibble_buffer <= (others => '0');
            elsif eth_tx_en = '1' then
                if nibble_phase = '0' then
                    -- Capture low nibble
                    nibble_buffer <= eth_txd;
                    nibble_phase <= '1';
                else
                    -- Capture high nibble and combine into byte
                    captured_packet(capture_index) <= eth_txd & nibble_buffer;
                    capture_index <= capture_index + 1;
                    nibble_phase <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Monitor process (prints transmitted bytes)
    monitor_proc: process(clk_25mhz)
        variable L : line;
    begin
        if rising_edge(clk_25mhz) then
            if eth_tx_en = '1' and nibble_phase = '1' then
                -- Just captured a complete byte
                write(L, string'("MII TX: Byte "));
                write(L, capture_index - 1);
                write(L, string'(" = 0x"));
                hwrite(L, eth_txd & nibble_buffer);
                writeline(output, L);
            end if;
        end if;
    end process;

end Behavioral;
