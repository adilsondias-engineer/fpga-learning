----------------------------------------------------------------------------------
-- UDP Packet Builder Testbench (Standalone)
-- Tests only the packet builder without MII TX
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity packet_builder_tb is
end packet_builder_tb;

architecture Behavioral of packet_builder_tb is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz

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

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal payload_data : std_logic_vector(7 downto 0) := (others => '0');
    signal payload_len : std_logic_vector(15 downto 0) := x"0005";  -- 5 bytes
    signal payload_valid : std_logic := '0';
    signal payload_ready : std_logic;
    signal payload_start : std_logic := '0';
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal tx_ready : std_logic := '1';  -- Always ready for now
    signal tx_start : std_logic;
    signal tx_end : std_logic;

    type payload_array_type is array (0 to 4) of std_logic_vector(7 downto 0);
    constant TEST_PAYLOAD : payload_array_type := (
        x"48",  -- H
        x"45",  -- E
        x"4C",  -- L
        x"4C",  -- L
        x"4F"   -- O
    );

    signal byte_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: udp_packet_builder
        generic map (
            SRC_MAC  => x"AABBCCDDEEFF",
            DST_MAC  => x"112233445566",
            SRC_IP   => x"C0A80102",
            DST_IP   => x"C0A80164",
            SRC_PORT => x"1389",
            DST_PORT => x"1388"
        )
        port map (
            clk          => clk,
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

    stim_proc: process
    begin
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 50 ns;

        report "TEST: Starting packet build";

        -- Start packet
        wait until rising_edge(clk);
        payload_start <= '1';
        wait until rising_edge(clk);
        payload_start <= '0';

        report "TEST: Waiting for payload_ready to go high, currently=" & std_logic'image(payload_ready);

        -- Wait for payload_ready with timeout check
        for j in 0 to 1000 loop
            wait until rising_edge(clk);
            if payload_ready = '1' then
                report "TEST: Ready for payload after " & integer'image(j) & " clocks";
                exit;
            end if;
        end loop;

        -- Send 5 payload bytes using proper valid/ready handshake
        for i in 0 to 4 loop
            -- Wait for ready
            while payload_ready = '0' loop
                wait until rising_edge(clk);
            end loop;

            -- Assert valid with data and HOLD until accepted
            payload_data <= TEST_PAYLOAD(i);
            payload_valid <= '1';
            report "TEST: Asserting payload_valid for byte " & integer'image(i) & " = 0x" &
                   integer'image(to_integer(unsigned(TEST_PAYLOAD(i))));

            -- Wait for handshake (both valid and ready high)
            wait until rising_edge(clk);
            while payload_ready = '0' loop
                wait until rising_edge(clk);
            end loop;

            -- Handshake complete, drop valid
            payload_valid <= '0';
            report "TEST: Byte " & integer'image(i) & " accepted";
        end loop;
        report "TEST: All 5 payload bytes sent";

        report "TEST: waiting on  tx_end = 1 -> " & std_logic'image(tx_end);
        -- Wait for completion (synchronized with clock to catch single-cycle pulse)
        loop
            wait until rising_edge(clk);
            exit when tx_end = '1';
        end loop;
        report "TEST: Packet complete (tx_end asserted)";

        wait for 1 us;

        report "TEST: Total bytes sent = " & integer'image(byte_count);

        assert byte_count = 47 report "ERROR: Expected 47 bytes (14 ETH + 20 IP + 8 UDP + 5 payload)" severity error;

        if byte_count = 47 then
            report "TEST: PASS";
        else
            report "TEST: FAIL";
        end if;

        wait;
    end process;

    -- Count transmitted bytes
    count_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                byte_count <= 0;
            elsif tx_valid = '1' and tx_ready = '1' then
                byte_count <= byte_count + 1;
                report "TX Byte " & integer'image(byte_count) & " = 0x" &
                       integer'image(to_integer(unsigned(tx_data)));
            end if;
        end if;
    end process;

end Behavioral;
