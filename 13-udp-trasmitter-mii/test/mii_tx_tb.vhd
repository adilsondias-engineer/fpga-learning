----------------------------------------------------------------------------------
-- MII TX Testbench (Standalone)
-- Tests only the MII TX transmitter in isolation
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mii_tx_tb is
end mii_tx_tb;

architecture Behavioral of mii_tx_tb is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz

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

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_valid : std_logic := '0';
    signal tx_ready : std_logic;
    signal tx_start : std_logic := '0';
    signal tx_end : std_logic := '0';
    signal eth_tx_en : std_logic;
    signal eth_txd : std_logic_vector(3 downto 0);

    -- Test data: "HELLO" (5 bytes)
    type test_data_array_type is array (0 to 4) of std_logic_vector(7 downto 0);
    constant TEST_DATA : test_data_array_type := (
        x"48",  -- H
        x"45",  -- E
        x"4C",  -- L
        x"4C",  -- L
        x"4F"   -- O
    );

    -- Capture for verification
    type byte_array_type is array (0 to 255) of std_logic_vector(7 downto 0);
    signal captured_bytes : byte_array_type;
    signal capture_index : integer := 0;
    signal nibble_buffer : std_logic_vector(3 downto 0) := (others => '0');
    signal nibble_phase : std_logic := '0';  -- 0 = low nibble, 1 = high nibble

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: mii_tx
        port map (
            mii_tx_clk   => clk,
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
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        wait for 100 ns;

        report "TEST: Starting MII TX test";

        -- Pulse tx_start
        wait until rising_edge(clk);
        tx_start <= '1';
        wait until rising_edge(clk);
        tx_start <= '0';

        report "TEST: tx_start pulsed, waiting for tx_ready";

        -- Send 5 bytes using valid/ready handshaking
        for i in 0 to 4 loop
            -- Wait for ready
            while tx_ready = '0' loop
                wait until rising_edge(clk);
            end loop;

            -- Send byte
            tx_data <= TEST_DATA(i);
            tx_valid <= '1';
            report "TEST: Sending byte " & integer'image(i) & " = 0x" &
                   integer'image(to_integer(unsigned(TEST_DATA(i))));

            wait until rising_edge(clk);
            tx_valid <= '0';
        end loop;

        report "TEST: All 5 bytes sent, pulsing tx_end";

        -- Wait a bit, then pulse tx_end
        wait for 200 ns;
        wait until rising_edge(clk);
        tx_end <= '1';
        wait until rising_edge(clk);
        tx_end <= '0';

        report "TEST: tx_end pulsed";

        -- Wait for transmission to complete
        wait for 2 us;

        report "TEST: Transmission complete";
        report "TEST: Captured " & integer'image(capture_index) & " bytes";

        -- Print captured bytes for debugging
        for i in 0 to capture_index-1 loop
            report "Captured byte " & integer'image(i) & " = 0x" &
                   integer'image(to_integer(unsigned(captured_bytes(i))));
        end loop;

        -- Verify preamble + SFD (8 bytes)
        assert captured_bytes(0) = x"55" report "ERROR: Preamble byte 0 wrong" severity error;
        assert captured_bytes(1) = x"55" report "ERROR: Preamble byte 1 wrong" severity error;
        assert captured_bytes(6) = x"D5" report "ERROR: SFD wrong (expected 0xD5)" severity error;

        -- Verify payload (5 bytes starting at index 7)
        assert captured_bytes(7) = x"48" report "ERROR: Payload byte 0 wrong (expected 'H')" severity error;
        assert captured_bytes(8) = x"45" report "ERROR: Payload byte 1 wrong (expected 'E')" severity error;
        assert captured_bytes(9) = x"4C" report "ERROR: Payload byte 2 wrong (expected 'L')" severity error;
        assert captured_bytes(10) = x"4C" report "ERROR: Payload byte 3 wrong (expected 'L')" severity error;
        assert captured_bytes(11) = x"4F" report "ERROR: Payload byte 4 wrong (expected 'O')" severity error;

        report "TEST: PASS - MII TX transmitted correctly";

        wait;
    end process;

    -- Capture process (captures nibbles from MII and reconstructs bytes)
    capture_proc: process(clk)
    begin
        if rising_edge(clk) then
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
                    captured_bytes(capture_index) <= eth_txd & nibble_buffer;
                    capture_index <= capture_index + 1;
                    nibble_phase <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
