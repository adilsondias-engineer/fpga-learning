----------------------------------------------------------------------------------
-- Ultra Simple Testbench
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity simple_tb is
end simple_tb;

architecture Behavioral of simple_tb is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal send_packet : std_logic := '0';
    signal packet_sent : std_logic;
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal tx_ready : std_logic := '1';  -- Always ready
    signal tx_start : std_logic;
    signal tx_end : std_logic;

    signal byte_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.udp_packet_builder_simple
        port map (
            clk => clk,
            reset => reset,
            send_packet => send_packet,
            packet_sent => packet_sent,
            tx_data => tx_data,
            tx_valid => tx_valid,
            tx_ready => tx_ready,
            tx_start => tx_start,
            tx_end => tx_end
        );

    stim_proc: process
    begin
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        wait for 100 ns;

        report "TEST: Triggering packet send";
        wait until rising_edge(clk);
        send_packet <= '1';
        wait until rising_edge(clk);
        send_packet <= '0';

        report "TEST: Waiting for packet_sent";
        wait until packet_sent = '1';
        report "TEST: Packet sent!";

        wait for 1 us;

        report "TEST: Total bytes = " & integer'image(byte_count);

        assert byte_count = 47 report "ERROR: Expected 47 bytes" severity error;

        if byte_count = 47 then
            report "TEST: PASS";
        else
            report "TEST: FAIL";
        end if;

        wait;
    end process;

    -- Count bytes
    count_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                byte_count <= 0;
            elsif tx_valid = '1' and tx_ready = '1' then
                byte_count <= byte_count + 1;
                report "Byte " & integer'image(byte_count) & " = 0x" &
                       integer'image(to_integer(unsigned(tx_data)));
            end if;
        end if;
    end process;

end Behavioral;
