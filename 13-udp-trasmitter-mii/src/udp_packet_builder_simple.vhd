----------------------------------------------------------------------------------
-- UDP Packet Builder - ULTRA SIMPLE VERSION
-- No handshaking - just trigger and it sends a fixed packet
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity udp_packet_builder_simple is
    generic (
        SRC_MAC  : std_logic_vector(47 downto 0) := x"AABBCCDDEEFF";
        DST_MAC  : std_logic_vector(47 downto 0) := x"112233445566";
        SRC_IP   : std_logic_vector(31 downto 0) := x"C0A80102";
        DST_IP   : std_logic_vector(31 downto 0) := x"C0A80164";
        SRC_PORT : std_logic_vector(15 downto 0) := x"1389";
        DST_PORT : std_logic_vector(15 downto 0) := x"1388"
    );
    port (
        clk          : in  std_logic;  -- 25 MHz (same as MII TX)
        reset        : in  std_logic;

        -- Simple trigger interface
        send_packet  : in  std_logic;  -- Pulse to send packet
        packet_sent  : out std_logic;  -- Pulse when done

        -- Output to MII TX (valid/ready handshake)
        tx_data      : out std_logic_vector(7 downto 0);
        tx_valid     : out std_logic;
        tx_ready     : in  std_logic;
        tx_start     : out std_logic;
        tx_end       : out std_logic
    );
end udp_packet_builder_simple;

architecture Behavioral of udp_packet_builder_simple is

    -- Fixed payload: "HELLO" (5 bytes)
    type payload_array_t is array(0 to 4) of std_logic_vector(7 downto 0);
    constant PAYLOAD : payload_array_t := (
        x"48", x"45", x"4C", x"4C", x"4F"  -- "HELLO"
    );

    constant PAYLOAD_LEN : integer := 5;
    constant IP_TOTAL_LEN : unsigned(15 downto 0) := to_unsigned(PAYLOAD_LEN + 28, 16);
    constant UDP_LEN : unsigned(15 downto 0) := to_unsigned(PAYLOAD_LEN + 8, 16);

    -- IP Checksum calculation (computed at elaboration time)
    -- Sum all 16-bit words in IP header (excluding checksum field)
    function calc_ip_checksum return std_logic_vector is
        variable sum : unsigned(31 downto 0);
        variable temp : unsigned(15 downto 0);
    begin
        sum := (others => '0');
        -- Add all 16-bit words from IP header (excluding checksum at bytes 10-11)
        sum := sum + to_unsigned(16#4500#, 16);  -- Version/IHL, ToS
        sum := sum + to_unsigned(16#0021#, 16);  -- Total length
        sum := sum + to_unsigned(16#0000#, 16);  -- ID
        sum := sum + to_unsigned(16#4000#, 16);  -- Flags/Fragment
        sum := sum + to_unsigned(16#4011#, 16);  -- TTL, Protocol
        -- Skip checksum field (bytes 10-11)
        sum := sum + unsigned(SRC_IP(31 downto 16));  -- Source IP high
        sum := sum + unsigned(SRC_IP(15 downto 0));   -- Source IP low
        sum := sum + unsigned(DST_IP(31 downto 16));  -- Dest IP high
        sum := sum + unsigned(DST_IP(15 downto 0));   -- Dest IP low

        -- Fold carries
        while sum(31 downto 16) /= 0 loop
            sum := resize(sum(15 downto 0), 32) + resize(sum(31 downto 16), 32);
        end loop;

        -- One's complement
        temp := not sum(15 downto 0);
        return std_logic_vector(temp);
    end function;

    constant IP_CHECKSUM : std_logic_vector(15 downto 0) := calc_ip_checksum;

    type state_type is (IDLE, START_TX, SEND_DATA, DONE);
    signal state : state_type := IDLE;

    -- Complete packet as constant array
    -- Minimum Ethernet frame: 60 bytes (before FCS)
    -- Current: 14 (Eth) + 20 (IP) + 8 (UDP) + 5 (payload) = 47 bytes
    -- Padding: 60 - 47 = 13 bytes
    type packet_array_t is array(0 to 59) of std_logic_vector(7 downto 0);
    constant PACKET : packet_array_t := (
        -- Ethernet header (14 bytes)
        DST_MAC(47 downto 40), DST_MAC(39 downto 32), DST_MAC(31 downto 24), DST_MAC(23 downto 16),
        DST_MAC(15 downto 8), DST_MAC(7 downto 0),
        SRC_MAC(47 downto 40), SRC_MAC(39 downto 32), SRC_MAC(31 downto 24), SRC_MAC(23 downto 16),
        SRC_MAC(15 downto 8), SRC_MAC(7 downto 0),
        x"08", x"00",  -- EtherType = IPv4

        -- IP header (20 bytes)
        x"45", x"00",  -- Version/IHL, ToS
        x"00", x"21",  -- Total length = 33 bytes (20 IP + 8 UDP + 5 payload)
        x"00", x"00",  -- ID
        x"40", x"00",  -- Flags/Fragment
        x"40", x"11",  -- TTL, Protocol (UDP)
        IP_CHECKSUM(15 downto 8), IP_CHECKSUM(7 downto 0),  -- Checksum
        SRC_IP(31 downto 24), SRC_IP(23 downto 16), SRC_IP(15 downto 8), SRC_IP(7 downto 0),
        DST_IP(31 downto 24), DST_IP(23 downto 16), DST_IP(15 downto 8), DST_IP(7 downto 0),

        -- UDP header (8 bytes)
        SRC_PORT(15 downto 8), SRC_PORT(7 downto 0),
        DST_PORT(15 downto 8), DST_PORT(7 downto 0),
        x"00", x"0D",  -- Length = 13 bytes (8 UDP + 5 payload)
        x"00", x"00",  -- Checksum (optional)

        -- Payload (5 bytes)
        x"48", x"45", x"4C", x"4C", x"4F",  -- "HELLO"

        -- Padding (13 bytes) to reach 60-byte minimum
        x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
        x"00", x"00", x"00", x"00", x"00"
    );

    signal byte_idx : integer range 0 to 60 := 0;

begin

    -- State machine to send packet
    -- CRITICAL: Use FALLING edge to match MII TX module
    -- Reference implementation runs entire TX state machine on negedge eth.tx_clk
    process(clk)
    begin
        if falling_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                tx_start <= '0';
                tx_end <= '0';
                tx_valid <= '0';
                tx_data <= (others => '0');
                packet_sent <= '0';
                byte_idx <= 0;

            else
                case state is
                    when IDLE =>
                        tx_start <= '0';
                        tx_end <= '0';
                        tx_valid <= '0';
                        packet_sent <= '0';
                        byte_idx <= 0;

                        if send_packet = '1' then
                            tx_start <= '1';
                            state <= START_TX;
                        end if;

                    when START_TX =>
                        tx_start <= '0';
                        state <= SEND_DATA;

                    when SEND_DATA =>
                        if tx_ready = '1' then
                            if byte_idx <= 59 then
                                tx_data <= PACKET(byte_idx);
                                tx_valid <= '1';
                                byte_idx <= byte_idx + 1;
                            else
                                -- All bytes sent, go to DONE
                                tx_valid <= '0';
                                state <= DONE;
                            end if;
                        else
                            tx_valid <= '0';
                        end if;

                    when DONE =>
                        tx_valid <= '0';
                        tx_end <= '1';
                        packet_sent <= '1';
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
