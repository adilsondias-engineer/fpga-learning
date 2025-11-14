--------------------------------------------------------------------------------
-- Simple testbench to verify mac_parser byte_counter timing
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity test_byte_counter is
end test_byte_counter;

architecture tb of test_byte_counter is

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

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD/2;

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

    -- Test stimulus
    process
    begin
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;

        -- Start frame
        frame_start <= '1';
        wait for CLK_PERIOD;
        frame_start <= '0';

        -- Send 20 bytes and check byte_counter matches
        for i in 0 to 19 loop
            rx_data <= std_logic_vector(to_unsigned(i, 8));
            rx_valid <= '1';
            wait for CLK_PERIOD;

            -- CHECK: On the clock that byte i arrives, byte_counter should be i
            assert to_integer(byte_counter) = i
                report "FAIL: byte " & integer'image(i) &
                       " arrived but byte_counter = " & integer'image(to_integer(byte_counter))
                severity error;

            if to_integer(byte_counter) = i then
                report "PASS: byte " & integer'image(i) & " has correct byte_counter = " & integer'image(i);
            end if;
        end loop;

        rx_valid <= '0';
        frame_end <= '1';
        wait for CLK_PERIOD;
        frame_end <= '0';

        wait for 500 ns;

        report "Test complete!";
        std.env.stop;

    end process;

end tb;
