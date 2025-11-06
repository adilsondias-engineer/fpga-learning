--------------------------------------------------------------------------------
-- MAC Parser byte_counter Timing Verification Testbench
-- Tests that byte_counter outputs the CURRENT byte position (not next)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sim_mac_byte_counter is
end sim_mac_byte_counter;

architecture tb of sim_mac_byte_counter is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz (MII RX clock)

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal rx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid : std_logic := '0';
    signal frame_start : std_logic := '0';
    signal frame_end : std_logic := '0';

    signal frame_valid : std_logic;
    signal byte_counter : unsigned(10 downto 0);
    signal data_out : std_logic_vector(7 downto 0);

    signal test_failed : boolean := false;

begin

    -- Clock generation
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- MAC parser instance
    dut: entity work.mac_parser
        generic map (
            MAC_ADDR => x"000A3502AF9A"
        )
        port map (
            clk => clk,
            reset => reset,
            rx_data => rx_data,
            rx_valid => rx_valid,
            frame_start => frame_start,
            frame_end => frame_end,
            frame_valid => frame_valid,
            dest_mac => open,
            src_mac => open,
            ethertype => open,
            frame_count => open,
            data_out => data_out,
            byte_counter => byte_counter
        );

    -- Test stimulus and checker
    test_process: process
        variable expected_counter : integer;
    begin
        report "========================================";
        report "MAC Parser byte_counter Timing Test";
        report "========================================";

        -- Reset
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        wait for 100 ns;

        -- Start frame
        report "Starting Ethernet frame...";
        frame_start <= '1';
        wait until rising_edge(clk);
        frame_start <= '0';
        wait until rising_edge(clk);

        -- Send 30 bytes and check byte_counter synchronization
        -- The CRITICAL check: On clock N when byte i arrives,
        -- byte_counter should equal i (the current byte position)
        report "Sending 30 bytes and checking byte_counter timing...";

        for i in 0 to 29 loop
            -- Set data for this byte
            rx_data <= std_logic_vector(to_unsigned(i, 8));
            rx_valid <= '1';

            -- Wait for clock edge
            wait until rising_edge(clk);

            -- CRITICAL CHECK: After rising edge, byte_counter should show CURRENT byte (i)
            -- This is because byte_counter <= global_byte_count is combinational
            -- and global_byte_count gets incremented on this clock
            wait for 1 ns;  -- Small delay for signals to settle

            expected_counter := i;

            if to_integer(byte_counter) /= expected_counter then
                report "FAIL at byte " & integer'image(i) &
                       ": byte_counter = " & integer'image(to_integer(byte_counter)) &
                       ", expected = " & integer'image(expected_counter)
                    severity error;
                test_failed <= true;
            else
                report "PASS byte " & integer'image(i) &
                       ": byte_counter = " & integer'image(to_integer(byte_counter));
            end if;
        end loop;

        -- End frame
        rx_valid <= '0';
        frame_end <= '1';
        wait until rising_edge(clk);
        frame_end <= '0';
        wait for 500 ns;

        report "========================================";
        if test_failed then
            report "TEST FAILED: byte_counter timing is incorrect!" severity error;
        else
            report "TEST PASSED: byte_counter shows current byte position correctly!";
        end if;
        report "========================================";

        wait for 1 us;
        std.env.stop;

    end process;

end tb;
