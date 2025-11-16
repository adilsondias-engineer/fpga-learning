----------------------------------------------------------------------------------
-- BBO UDP Formatter (Timing-Optimized Version)
-- Converts BBO updates to UDP payload format and writes nibbles to UDP TX
--
-- Packet format (binary, little-endian):
-- - Symbol (8 bytes, padded)
-- - BID Price (4 bytes, unsigned 32-bit)
-- - BID Shares (4 bytes, unsigned 32-bit)
-- - ASK Price (4 bytes, unsigned 32-bit)
-- - ASK Shares (4 bytes, unsigned 32-bit)
-- - Spread (4 bytes, unsigned 32-bit)
-- Total: 28 bytes minimum, padded to 256 bytes to match eth_udp_send MIN_DATA_BYTES
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.order_book_pkg.all;

entity bbo_udp_formatter is
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;

        -- BBO input (from multi_symbol_order_book, synchronized to 100 MHz)
        bbo : in bbo_t;
        bbo_update : in STD_LOGIC;  -- Pulse when BBO changes
        bbo_symbol : in STD_LOGIC_VECTOR(63 downto 0);  -- Symbol name

        -- UDP TX FIFO interface (nibble write)
        wr_en : out STD_LOGIC;
        wr_d : out STD_LOGIC_VECTOR(3 downto 0);
        wr_busy : in STD_LOGIC;  -- When '1', FIFO is full or module is busy

        -- Status
        packets_sent : out STD_LOGIC_VECTOR(31 downto 0)
    );
end bbo_udp_formatter;

architecture Behavioral of bbo_udp_formatter is

    -- Packet data (28 bytes of actual data, pad to 256 bytes)
    constant DATA_BYTES : integer := 256;

    -- Packed as single vector for simpler nibble extraction
    signal packet_vector : std_logic_vector(8*DATA_BYTES-1 downto 0) := (others => '0');

    -- State machine
    type state_type is (IDLE, PREPARE, CALC_NIBBLE, WRITE_NIBBLE, DONE);
    signal state : state_type := IDLE;

    -- Nibble write counter (counts DOWN like reference implementation)
    signal wr_i : integer range -1 to 2*DATA_BYTES-1 := -1;
    signal packet_counter : unsigned(31 downto 0) := (others => '0');

    -- Pre-registered nibble to improve timing (pipelined)
    signal nibble_to_write : std_logic_vector(3 downto 0) := (others => '0');

begin

    packets_sent <= std_logic_vector(packet_counter);

    -- State machine to format BBO and write to UDP FIFO
    process(clk)
        variable byte_index : integer;
        variable is_lower_nibble : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                wr_en <= '0';
                wr_d <= (others => '0');
                wr_i <= -1;
                packet_counter <= (others => '0');
                packet_vector <= (others => '0');
                nibble_to_write <= (others => '0');

            else
                -- Default: no write
                wr_en <= '0';

                case state is
                    when IDLE =>
                        -- Wait for BBO update
                        if bbo_update = '1' and bbo.valid = '1' then
                            state <= PREPARE;
                        end if;

                    when PREPARE =>
                        -- Pack BBO data into vector (little-endian byte order)
                        -- Symbol (8 bytes) - bytes 0-7
                        packet_vector(63 downto 0) <= bbo_symbol;

                        -- BID Price (4 bytes) - bytes 8-11
                        packet_vector(95 downto 64) <= bbo.bid_price;

                        -- BID Shares (4 bytes) - bytes 12-15
                        packet_vector(127 downto 96) <= bbo.bid_shares;

                        -- ASK Price (4 bytes) - bytes 16-19
                        packet_vector(159 downto 128) <= bbo.ask_price;

                        -- ASK Shares (4 bytes) - bytes 20-23
                        packet_vector(191 downto 160) <= bbo.ask_shares;

                        -- Spread (4 bytes) - bytes 24-27
                        packet_vector(223 downto 192) <= bbo.spread;

                        -- Padding (bytes 28-255) - already zero
                        -- packet_vector(8*DATA_BYTES-1 downto 224) stays at '0'

                        wr_i <= 2 * DATA_BYTES - 1;  -- Start from last nibble (511)
                        state <= CALC_NIBBLE;

                    when CALC_NIBBLE =>
                        -- Pipeline stage 1: Calculate nibble index and extract to register
                        -- Extract nibble using reference implementation pattern:
                        -- wr_d <= eth_d[8 * (wr_i >> 1) + 4 * ((~wr_i) & 1)+:4];
                        -- This means: lower nibble first (odd wr_i), then upper nibble (even wr_i)

                        if wr_i >= 0 then
                            -- Calculate byte index and nibble position
                            byte_index := wr_i / 2;
                            is_lower_nibble := (wr_i mod 2) = 1;

                            -- Extract nibble (lower first for odd index, upper for even)
                            if is_lower_nibble then
                                nibble_to_write <= packet_vector(8*byte_index + 3 downto 8*byte_index);
                            else
                                nibble_to_write <= packet_vector(8*byte_index + 7 downto 8*byte_index + 4);
                            end if;

                            state <= WRITE_NIBBLE;
                        else
                            -- All nibbles written
                            state <= DONE;
                        end if;

                    when WRITE_NIBBLE =>
                        -- Pipeline stage 2: Write pre-registered nibble if FIFO not busy
                        if wr_busy = '0' then
                            wr_d <= nibble_to_write;
                            wr_en <= '1';
                            wr_i <= wr_i - 1;
                            state <= CALC_NIBBLE;  -- Calculate next nibble
                        end if;

                    when DONE =>
                        packet_counter <= packet_counter + 1;
                        wr_i <= -1;
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
