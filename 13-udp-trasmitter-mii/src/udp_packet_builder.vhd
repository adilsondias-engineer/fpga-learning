----------------------------------------------------------------------------------
-- UDP Packet Builder - SIMPLE VERSION
-- Builds UDP packets with Ethernet/IP/UDP headers
-- Runs at 25 MHz (same as MII TX) - NO clock domain crossing
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity udp_packet_builder is
    generic (
        SRC_MAC  : std_logic_vector(47 downto 0) := x"AABBCCDDEEFF";
        DST_MAC  : std_logic_vector(47 downto 0) := x"112233445566";
        SRC_IP   : std_logic_vector(31 downto 0) := x"C0A80140";  -- 192.168.1.64
        DST_IP   : std_logic_vector(31 downto 0) := x"C0A80120";  -- 192.168.1.32
        SRC_PORT : std_logic_vector(15 downto 0) := x"1388";  -- 5000
        DST_PORT : std_logic_vector(15 downto 0) := x"1391"   -- 5009
    );
    port (
        clk          : in  std_logic;  -- 25 MHz (same as MII TX)
        reset        : in  std_logic;

        -- Trigger interface
        payload_start: in  std_logic;  -- Start building packet
        payload_len  : in  std_logic_vector(15 downto 0);  -- Payload length

        -- Payload input (valid/ready handshake)
        payload_data : in  std_logic_vector(7 downto 0);
        payload_valid: in  std_logic;
        payload_ready: out std_logic;

        -- Output to MII TX (valid/ready handshake)
        tx_data      : out std_logic_vector(7 downto 0);
        tx_valid     : out std_logic;
        tx_ready     : in  std_logic;
        tx_start     : out std_logic;
        tx_end       : out std_logic
    );
end udp_packet_builder;

architecture Behavioral of udp_packet_builder is

    type state_type is (
        IDLE,
        CALC_CHECKSUM,
        SEND_START,
        ETH_HDR,
        IP_HDR,
        UDP_HDR,
        PAYLOAD_DATA_ST,
        FINISH
    );
    signal state : state_type := IDLE;

    -- Registered payload length
    signal payload_len_reg : unsigned(15 downto 0) := (others => '0');

    -- IP header fields
    signal ip_total_len : unsigned(15 downto 0) := (others => '0');
    signal udp_len      : unsigned(15 downto 0) := (others => '0');
    signal ip_checksum  : unsigned(15 downto 0) := (others => '0');

    -- Checksum calculation
    signal checksum_sum : unsigned(31 downto 0) := (others => '0');
    signal checksum_step : integer range 0 to 15 := 0;

    -- Byte counter for each header section
    signal byte_idx : integer range 0 to 1500 := 0;

    -- Payload byte counter
    signal payload_bytes_sent : unsigned(15 downto 0) := (others => '0');

    -- Internal signal for payload_ready (so we can read it)
    signal payload_ready_int : std_logic := '0';

begin

    -- Connect internal signal to output
    payload_ready <= payload_ready_int;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                tx_start <= '0';
                tx_end <= '0';
                tx_valid <= '0';
                tx_data <= (others => '0');
                payload_ready_int <= '0';
                byte_idx <= 0;
                payload_bytes_sent <= (others => '0');
                checksum_sum <= (others => '0');
                checksum_step <= 0;

            else
                case state is
                    ------------------------------------------------------------
                    when IDLE =>
                        tx_start <= '0';
                        tx_end <= '0';
                        tx_valid <= '0';
                        payload_ready_int <= '0';
                        byte_idx <= 0;
                        payload_bytes_sent <= (others => '0');

                        if payload_start = '1' then
                            -- Capture payload length
                            payload_len_reg <= unsigned(payload_len);
                            ip_total_len <= unsigned(payload_len) + 28;  -- IP(20) + UDP(8) + payload
                            udp_len <= unsigned(payload_len) + 8;  -- UDP(8) + payload

                            state <= CALC_CHECKSUM;
                            checksum_step <= 0;
                            checksum_sum <= (others => '0');
                        end if;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when CALC_CHECKSUM =>
                        -- Calculate IP header checksum step by step
                        case checksum_step is
                            when 0 =>
                                checksum_sum <= x"00004500";  -- Version/IHL + ToS
                                checksum_step <= 1;
                            when 1 =>
                                checksum_sum <= checksum_sum + ip_total_len;
                                checksum_step <= 2;
                            when 2 =>
                                checksum_sum <= checksum_sum + x"00000000";  -- ID + Flags
                                checksum_step <= 3;
                            when 3 =>
                                checksum_sum <= checksum_sum + x"00004011";  -- TTL + Protocol (UDP=17)
                                checksum_step <= 4;
                            when 4 =>
                                checksum_sum <= checksum_sum + unsigned(SRC_IP(31 downto 16));
                                checksum_step <= 5;
                            when 5 =>
                                checksum_sum <= checksum_sum + unsigned(SRC_IP(15 downto 0));
                                checksum_step <= 6;
                            when 6 =>
                                checksum_sum <= checksum_sum + unsigned(DST_IP(31 downto 16));
                                checksum_step <= 7;
                            when 7 =>
                                checksum_sum <= checksum_sum + unsigned(DST_IP(15 downto 0));
                                checksum_step <= 8;
                            when 8 =>
                                -- Add carry (resize to 32 bits)
                                checksum_sum <= resize(checksum_sum(15 downto 0) + checksum_sum(31 downto 16), 32);
                                checksum_step <= 9;
                            when 9 =>
                                -- One's complement
                                ip_checksum <= not checksum_sum(15 downto 0);
                                state <= SEND_START;
                            when others =>
                                state <= SEND_START;
                        end case;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when SEND_START =>
                        tx_start <= '1';
                        state <= ETH_HDR;
                        byte_idx <= 0;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when ETH_HDR =>
                        tx_start <= '0';  -- Pulse tx_start for 1 cycle only

                        if tx_ready = '1' then
                            tx_valid <= '1';

                            -- Send Ethernet header (14 bytes)
                            case byte_idx is
                                when 0 => tx_data <= DST_MAC(47 downto 40);
                                when 1 => tx_data <= DST_MAC(39 downto 32);
                                when 2 => tx_data <= DST_MAC(31 downto 24);
                                when 3 => tx_data <= DST_MAC(23 downto 16);
                                when 4 => tx_data <= DST_MAC(15 downto 8);
                                when 5 => tx_data <= DST_MAC(7 downto 0);
                                when 6 => tx_data <= SRC_MAC(47 downto 40);
                                when 7 => tx_data <= SRC_MAC(39 downto 32);
                                when 8 => tx_data <= SRC_MAC(31 downto 24);
                                when 9 => tx_data <= SRC_MAC(23 downto 16);
                                when 10 => tx_data <= SRC_MAC(15 downto 8);
                                when 11 => tx_data <= SRC_MAC(7 downto 0);
                                when 12 => tx_data <= x"08";  -- EtherType = IPv4 (0x0800)
                                when 13 => tx_data <= x"00";
                                when others => tx_data <= x"00";
                            end case;

                            if byte_idx < 13 then
                                byte_idx <= byte_idx + 1;
                            else
                                byte_idx <= 0;
                                state <= IP_HDR;
                            end if;
                        else
                            tx_valid <= '0';
                        end if;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when IP_HDR =>
                        if tx_ready = '1' then
                            tx_valid <= '1';

                            -- Send IP header (20 bytes)
                            case byte_idx is
                                when 0 => tx_data <= x"45";  -- Version 4, IHL 5
                                when 1 => tx_data <= x"00";  -- ToS
                                when 2 => tx_data <= std_logic_vector(ip_total_len(15 downto 8));
                                when 3 => tx_data <= std_logic_vector(ip_total_len(7 downto 0));
                                when 4 => tx_data <= x"00";  -- ID
                                when 5 => tx_data <= x"00";
                                when 6 => tx_data <= x"40";  -- Flags: Don't fragment
                                when 7 => tx_data <= x"00";  -- Fragment offset
                                when 8 => tx_data <= x"40";  -- TTL = 64
                                when 9 => tx_data <= x"11";  -- Protocol = UDP (17)
                                when 10 => tx_data <= std_logic_vector(ip_checksum(15 downto 8));
                                when 11 => tx_data <= std_logic_vector(ip_checksum(7 downto 0));
                                when 12 => tx_data <= SRC_IP(31 downto 24);
                                when 13 => tx_data <= SRC_IP(23 downto 16);
                                when 14 => tx_data <= SRC_IP(15 downto 8);
                                when 15 => tx_data <= SRC_IP(7 downto 0);
                                when 16 => tx_data <= DST_IP(31 downto 24);
                                when 17 => tx_data <= DST_IP(23 downto 16);
                                when 18 => tx_data <= DST_IP(15 downto 8);
                                when 19 => tx_data <= DST_IP(7 downto 0);
                                when others => tx_data <= x"00";
                            end case;

                            if byte_idx < 19 then
                                byte_idx <= byte_idx + 1;
                            else
                                byte_idx <= 0;
                                state <= UDP_HDR;
                            end if;
                        else
                            tx_valid <= '0';
                        end if;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when UDP_HDR =>
                        if tx_ready = '1' then
                            tx_valid <= '1';

                            -- Send UDP header (8 bytes)
                            case byte_idx is
                                when 0 => tx_data <= SRC_PORT(15 downto 8);
                                when 1 => tx_data <= SRC_PORT(7 downto 0);
                                when 2 => tx_data <= DST_PORT(15 downto 8);
                                when 3 => tx_data <= DST_PORT(7 downto 0);
                                when 4 => tx_data <= std_logic_vector(udp_len(15 downto 8));
                                when 5 => tx_data <= std_logic_vector(udp_len(7 downto 0));
                                when 6 => tx_data <= x"00";  -- Checksum (optional, 0 = no checksum)
                                when 7 => tx_data <= x"00";
                                when others => tx_data <= x"00";
                            end case;

                            if byte_idx < 7 then
                                byte_idx <= byte_idx + 1;
                            else
                                byte_idx <= 0;
                                state <= PAYLOAD_DATA_ST;
                                payload_ready_int <= '1';  -- Ready for payload
                                payload_bytes_sent <= (others => '0');
                            end if;
                        else
                            tx_valid <= '0';
                        end if;
                    report "UDP PACKET BUILDER: state =" & state_type'image(state);
                    ------------------------------------------------------------
                    when PAYLOAD_DATA_ST =>
                        -- Handle payload input and MII TX output together
                        -- Only accept payload when MII TX is ready to transmit it
                        if payload_valid = '1' and payload_ready_int = '1' and tx_ready = '1' then
                            -- Accept the byte and send to MII TX
                            tx_data <= payload_data;
                            tx_valid <= '1';
                            payload_bytes_sent <= payload_bytes_sent + 1;

                            -- After accepting, drop ready for 1 cycle
                            payload_ready_int <= '0';

                            -- Check if this was the last byte
                            report "PAYLOAD CHECK: payload_bytes_sent=" & integer'image(to_integer(payload_bytes_sent)) &
                                   " payload_len_reg=" & integer'image(to_integer(payload_len_reg)) &
                                   " check=" & boolean'image(payload_bytes_sent + 1 >= payload_len_reg);
                            if payload_bytes_sent + 1 >= payload_len_reg then
                                state <= FINISH;
                                report "TRANSITIONING TO FINISH";
                            end if;
                        else
                            -- Not accepting a byte this cycle
                            tx_valid <= '0';

                            -- Manage ready signal based on tx_ready
                            if tx_ready = '1' then
                                -- MII TX is ready, so we can accept payload
                                if payload_bytes_sent < payload_len_reg then
                                    payload_ready_int <= '1';
                                else
                                    payload_ready_int <= '0';
                                    state <= FINISH;
                                end if;
                            else
                                -- MII TX is busy, we can't accept payload
                                payload_ready_int <= '0';
                            end if;
                        end if;
                     --tx_ready='1' payload_valid='0' payload_ready_int='1'
                    report "UDP PACKET BUILDER: state =" & state_type'image(state) & " tx_ready=" & std_logic'image(tx_ready) & " payload_valid=" & std_logic'image( payload_valid)  & " payload_ready_int=" & std_logic'image(payload_ready_int);
                    ------------------------------------------------------------
                    when FINISH =>
                    
                        tx_valid <= '0';
                        payload_ready_int <= '0';
                        tx_end <= '1';
                        state <= IDLE;
                        report "UDP PACKET BUILDER: state =" & state_type'image(state);
                end case;
            end if;
        end if;
    end process;

end Behavioral;
