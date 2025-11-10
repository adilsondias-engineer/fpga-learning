--------------------------------------------------------------------------------
-- Module: uart_itch_formatter
-- Description: Formats parsed ITCH messages for UART debug output
--              Reads from async FIFO (no CDC needed - decoder handles it)
--              V4 architecture: clean separation, no race conditions
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.itch_msg_pkg.all;

entity uart_itch_formatter is
    Generic (
        BUILD_VERSION : integer := 0
    );
    Port (
        clk : in std_logic;
        rst : in std_logic;

        -- From async FIFO (via decoder)
        fifo_rd_en : out std_logic;
        fifo_rd_data : in std_logic_vector(MSG_FIFO_WIDTH-1 downto 0);
        fifo_rd_empty : in std_logic;

        -- Decoded message data (from decoder)
        msg_type : in msg_type_t;
        order_ref : in std_logic_vector(63 downto 0);
        buy_sell : in std_logic;
        shares : in std_logic_vector(31 downto 0);
        stock_symbol : in std_logic_vector(63 downto 0);
        price : in std_logic_vector(31 downto 0);
        stock_locate : in std_logic_vector(15 downto 0);
        tracking_number : in std_logic_vector(15 downto 0);
        timestamp : in std_logic_vector(47 downto 0);
        match_number : in std_logic_vector(63 downto 0);
        event_code : in std_logic_vector(7 downto 0);
        market_category : in std_logic_vector(7 downto 0);
        financial_status : in std_logic_vector(7 downto 0);
        round_lot_size : in std_logic_vector(31 downto 0);

        -- New message type fields
        original_order_ref : in std_logic_vector(63 downto 0);
        new_order_ref : in std_logic_vector(63 downto 0);
        new_shares : in std_logic_vector(31 downto 0);
        new_price : in std_logic_vector(31 downto 0);
        trade_price : in std_logic_vector(31 downto 0);
        cross_shares : in std_logic_vector(63 downto 0);
        cross_price : in std_logic_vector(31 downto 0);
        cross_type : in std_logic_vector(7 downto 0);

        -- UART TX interface
        uart_tx_data : out std_logic_vector(7 downto 0);
        uart_tx_valid : out std_logic;
        uart_tx_ready : in std_logic
    );
end uart_itch_formatter;

architecture Behavioral of uart_itch_formatter is

    type state_type is (SEND_BANNER, IDLE, WAIT_FIFO, WAIT_DECODE, FORMAT_MSG, SEND_MESSAGE, WAIT_TX);
    signal state : state_type := SEND_BANNER;

    signal uart_tx_valid_int : std_logic := '0';

    type byte_array is array (0 to 255) of std_logic_vector(7 downto 0);
    signal msg_buffer : byte_array := (others => (others => '0'));
    signal msg_length : integer range 0 to 256 := 0;
    signal byte_index : integer range 0 to 256 := 0;

    signal msg_counter : unsigned(31 downto 0) := (others => '0');
    signal banner_sent : std_logic := '0';

    -- Captured message data (registered on FIFO read)
    signal captured_msg_type : msg_type_t := MSG_NONE;
    signal captured_order_ref : std_logic_vector(63 downto 0);
    signal captured_buy_sell : std_logic;
    signal captured_shares : std_logic_vector(31 downto 0);
    signal captured_stock_symbol : std_logic_vector(63 downto 0);
    signal captured_price : std_logic_vector(31 downto 0);
    signal captured_match_number : std_logic_vector(63 downto 0);
    signal captured_event_code : std_logic_vector(7 downto 0);
    signal captured_market_category : std_logic_vector(7 downto 0);
    signal captured_financial_status : std_logic_vector(7 downto 0);
    signal captured_round_lot_size : std_logic_vector(31 downto 0);

    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        case nibble is
            when x"0" => result := x"30";
            when x"1" => result := x"31";
            when x"2" => result := x"32";
            when x"3" => result := x"33";
            when x"4" => result := x"34";
            when x"5" => result := x"35";
            when x"6" => result := x"36";
            when x"7" => result := x"37";
            when x"8" => result := x"38";
            when x"9" => result := x"39";
            when x"A" => result := x"41";
            when x"B" => result := x"42";
            when x"C" => result := x"43";
            when x"D" => result := x"44";
            when x"E" => result := x"45";
            when x"F" => result := x"46";
            when others => result := x"3F";
        end case;
        return result;
    end function;

begin

    process(clk)
        variable idx : integer range 0 to 256;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= SEND_BANNER;
                uart_tx_valid_int <= '0';
                fifo_rd_en <= '0';
                byte_index <= 0;
                msg_counter <= (others => '0');
                banner_sent <= '0';

            else
                fifo_rd_en <= '0';  -- Default

                case state is
                    when SEND_BANNER =>
                        -- Format startup banner on first entry
                        if banner_sent = '0' then
                            idx := 0;
                            -- "\r\n"
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "========================================\r\n"
                            for i in 0 to 39 loop
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            end loop;
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "  ITCH 5.0 Parser v5 - Arty A7-100T\r\n"
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"35"; idx := idx + 1;  -- '5'
                            msg_buffer(idx) <= x"2E"; idx := idx + 1;  -- '.'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"76"; idx := idx + 1;  -- 'v'
                            msg_buffer(idx) <= x"35"; idx := idx + 1;  -- '5'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"2D"; idx := idx + 1;  -- '-'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"37"; idx := idx + 1;  -- '7'
                            msg_buffer(idx) <= x"2D"; idx := idx + 1;  -- '-'
                            msg_buffer(idx) <= x"31"; idx := idx + 1;  -- '1'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "  Build: vXXX\r\n"
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                            msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"76"; idx := idx + 1;  -- 'v'
                            -- Build version (3 digits)
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(to_unsigned(BUILD_VERSION / 100 mod 10, 4))); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(to_unsigned(BUILD_VERSION / 10 mod 10, 4))); idx := idx + 1;
                            msg_buffer(idx) <= nibble_to_hex(std_logic_vector(to_unsigned(BUILD_VERSION mod 10, 4))); idx := idx + 1;
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "  Message Types: S R A E X D U P Q\r\n"
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"67"; idx := idx + 1;  -- 'g'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"58"; idx := idx + 1;  -- 'X'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"55"; idx := idx + 1;  -- 'U'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"51"; idx := idx + 1;  -- 'Q'
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "  Symbol Filter: ENABLED (8 symbols)\r\n"
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= x"62"; idx := idx + 1;  -- 'b'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"46"; idx := idx + 1;  -- 'F'
                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            msg_buffer(idx) <= x"4E"; idx := idx + 1;  -- 'N'
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                            msg_buffer(idx) <= x"4C"; idx := idx + 1;  -- 'L'
                            msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"28"; idx := idx + 1;  -- '('
                            msg_buffer(idx) <= x"38"; idx := idx + 1;  -- '8'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= x"62"; idx := idx + 1;  -- 'b'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"29"; idx := idx + 1;  -- ')'
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "========================================\r\n"
                            for i in 0 to 39 loop
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                            end loop;
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            -- "Ready for ITCH messages...\r\n\r\n"
                            msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                            msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                            msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                            msg_buffer(idx) <= x"67"; idx := idx + 1;  -- 'g'
                            msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"2E"; idx := idx + 1;  -- '.'
                            msg_buffer(idx) <= x"2E"; idx := idx + 1;  -- '.'
                            msg_buffer(idx) <= x"2E"; idx := idx + 1;  -- '.'
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;
                            msg_buffer(idx) <= x"0D"; idx := idx + 1;
                            msg_buffer(idx) <= x"0A"; idx := idx + 1;

                            msg_length <= idx;
                            byte_index <= 0;
                            banner_sent <= '1';
                            state <= SEND_MESSAGE;
                        else
                            -- Banner already sent, go to normal operation
                            state <= IDLE;
                        end if;

                    when IDLE =>
                        uart_tx_valid_int <= '0';
                        byte_index <= 0;

                        -- Read from FIFO when available
                        if fifo_rd_empty = '0' then
                            fifo_rd_en <= '1';
                            state <= WAIT_FIFO;
                        end if;

                    when WAIT_FIFO =>
                        -- FIFO updates rd_data on cycle when rd_en is '1'
                        -- Wait one cycle for FIFO data to be valid
                        fifo_rd_en <= '0';
                        state <= WAIT_DECODE;

                    when WAIT_DECODE =>
                        -- Decoder decodes on cycle after fifo_rd_en was '1' (fifo_rd_en_prev = '1')
                        -- Wait one cycle for decoder outputs to stabilize
                        state <= FORMAT_MSG;

                    when FORMAT_MSG =>
                        -- Capture decoded message data (now stable after decoder registration)
                        captured_msg_type <= msg_type;
                        captured_order_ref <= order_ref;
                        captured_buy_sell <= buy_sell;
                        captured_shares <= shares;
                        captured_stock_symbol <= stock_symbol;
                        captured_price <= price;
                        captured_match_number <= match_number;
                        captured_event_code <= event_code;
                        captured_market_category <= market_category;
                        captured_financial_status <= financial_status;
                        captured_round_lot_size <= round_lot_size;

                        msg_counter <= msg_counter + 1;

                        -- Build message buffer
                        idx := 0;

                        -- Prefix: "[#XX.vYY] [ITCH] Type=X "
                        msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                        msg_buffer(idx) <= x"23"; idx := idx + 1;  -- '#'
                        msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(7 downto 4))); idx := idx + 1;
                        msg_buffer(idx) <= nibble_to_hex(std_logic_vector(msg_counter(3 downto 0))); idx := idx + 1;
                        msg_buffer(idx) <= x"2E"; idx := idx + 1;  -- '.'
                        msg_buffer(idx) <= x"76"; idx := idx + 1;  -- 'v'
                        msg_buffer(idx) <= nibble_to_hex(std_logic_vector(to_unsigned(BUILD_VERSION, 8)(7 downto 4))); idx := idx + 1;
                        msg_buffer(idx) <= nibble_to_hex(std_logic_vector(to_unsigned(BUILD_VERSION, 8)(3 downto 0))); idx := idx + 1;
                        msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                        msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                        msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                        msg_buffer(idx) <= x"49"; idx := idx + 1;  -- 'I'
                        msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                        msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                        msg_buffer(idx) <= x"48"; idx := idx + 1;  -- 'H'
                        msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'
                        msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                        msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                        msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                        msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                        msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                        msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='

                        -- Message type character
                        case msg_type is
                            when MSG_ADD_ORDER => msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            when MSG_ORDER_EXECUTED => msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                            when MSG_ORDER_CANCEL => msg_buffer(idx) <= x"58"; idx := idx + 1;  -- 'X'
                            when MSG_SYSTEM_EVENT => msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            when MSG_STOCK_DIRECTORY => msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                            when MSG_ORDER_DELETE => msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            when MSG_ORDER_REPLACE => msg_buffer(idx) <= x"55"; idx := idx + 1;  -- 'U'
                            when MSG_TRADE_NON_CROSS => msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                            when MSG_TRADE_CROSS => msg_buffer(idx) <= x"51"; idx := idx + 1;  -- 'Q'
                            when others => msg_buffer(idx) <= x"3F"; idx := idx + 1;  -- '?'
                        end case;
                        msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                        -- Message-specific fields
                        case msg_type is
                            when MSG_ADD_ORDER =>
                                -- "Ref=XXXXXXXXXXXXXXXX B/S=X Shr=XXXXXXXX Sym=XXXXXXXXXXXXXXXX Px=XXXXXXXX\r\n"
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                                msg_buffer(idx) <= x"2F"; idx := idx + 1;  -- '/'
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                if buy_sell = '1' then
                                    msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                                else
                                    msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                end if;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                                msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                -- Output symbol bytes in correct order (byte 0 = bits 63:56, byte 7 = bits 7:0)
                                for i in 0 to 7 loop
                                    msg_buffer(idx) <= stock_symbol((7-i)*8+7 downto (7-i)*8); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(price(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_ORDER_EXECUTED =>
                                -- "Ref=XXXXXXXXXXXXXXXX ExecShr=XXXXXXXX Match=XXXXXXXXXXXXXXXX\r\n"
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(match_number(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_ORDER_CANCEL =>
                                -- "Ref=XXXXXXXXXXXXXXXX CxlShr=XXXXXXXX\r\n"
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_SYSTEM_EVENT =>
                                -- "EventCode=XX\r\n"
                                msg_buffer(idx) <= x"45"; idx := idx + 1;  -- 'E'
                                msg_buffer(idx) <= x"76"; idx := idx + 1;  -- 'v'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"43"; idx := idx + 1;  -- 'C'
                                msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                                msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                msg_buffer(idx) <= nibble_to_hex(event_code(7 downto 4)); idx := idx + 1;
                                msg_buffer(idx) <= nibble_to_hex(event_code(3 downto 0)); idx := idx + 1;

                            when MSG_STOCK_DIRECTORY =>
                                -- "Market=XX FinStat=XX Roundlot=XXXXXXXX Symboles=XXXXXXXXXXXXXXXX\r\n"
                                msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"6B"; idx := idx + 1;  -- 'k'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                msg_buffer(idx) <= nibble_to_hex(market_category(7 downto 4)); idx := idx + 1;
                                msg_buffer(idx) <= nibble_to_hex(market_category(3 downto 0)); idx := idx + 1;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"46"; idx := idx + 1;  -- 'F'
                                msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                                msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                msg_buffer(idx) <= nibble_to_hex(financial_status(7 downto 4)); idx := idx + 1;
                                msg_buffer(idx) <= nibble_to_hex(financial_status(3 downto 0)); idx := idx + 1;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                                msg_buffer(idx) <= x"75"; idx := idx + 1;  -- 'u'
                                msg_buffer(idx) <= x"6E"; idx := idx + 1;  -- 'n'
                                msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                                msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                                msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(round_lot_size(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                                msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                                msg_buffer(idx) <= x"62"; idx := idx + 1;  -- 'b'
                                msg_buffer(idx) <= x"6F"; idx := idx + 1;  -- 'o'
                                msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                -- Output symbol bytes in correct order (byte 0 = bits 63:56, byte 7 = bits 7:0)
                                for i in 0 to 7 loop
                                    msg_buffer(idx) <= stock_symbol((7-i)*8+7 downto (7-i)*8); idx := idx + 1;
                                end loop;

                            when MSG_ORDER_DELETE =>
                                -- "Ref=XXXXXXXXXXXXXXXX\r\n"
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_ORDER_REPLACE =>
                                -- "OldRef=XXXXXXXXXXXXXXXX NewRef=XXXXXXXXXXXXXXXX Shr=XXXXXXXX Px=XXXXXXXX\r\n"
                                msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                                msg_buffer(idx) <= x"6C"; idx := idx + 1;  -- 'l'
                                msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(original_order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"4E"; idx := idx + 1;  -- 'N'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"77"; idx := idx + 1;  -- 'w'
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(new_order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(new_shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(new_price(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_TRADE_NON_CROSS =>
                                -- "Ref=XXXXXXXXXXXXXXXX B/S=X Shr=XXXXXXXX Sym=XXXXXXXXXXXXXXXX Px=XXXXXXXX Match=XXXXXXXXXXXXXXXX\r\n"
                                msg_buffer(idx) <= x"52"; idx := idx + 1;  -- 'R'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"66"; idx := idx + 1;  -- 'f'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(order_ref(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                                msg_buffer(idx) <= x"2F"; idx := idx + 1;  -- '/'
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                if buy_sell = '1' then
                                    msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                                else
                                    msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                end if;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                                msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 0 to 7 loop
                                    msg_buffer(idx) <= stock_symbol((7-i)*8+7 downto (7-i)*8); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(trade_price(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(match_number(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;

                            when MSG_TRADE_CROSS =>
                                -- "Shr=XXXXXXXXXXXXXXXX Sym=XXXXXXXXXXXXXXXX Px=XXXXXXXX Match=XXXXXXXXXXXXXXXX Type=XX\r\n"
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(cross_shares(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                                msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                                msg_buffer(idx) <= x"6D"; idx := idx + 1;  -- 'm'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 0 to 7 loop
                                    msg_buffer(idx) <= stock_symbol((7-i)*8+7 downto (7-i)*8); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"50"; idx := idx + 1;  -- 'P'
                                msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 7 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(cross_price(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"4D"; idx := idx + 1;  -- 'M'
                                msg_buffer(idx) <= x"61"; idx := idx + 1;  -- 'a'
                                msg_buffer(idx) <= x"74"; idx := idx + 1;  -- 't'
                                msg_buffer(idx) <= x"63"; idx := idx + 1;  -- 'c'
                                msg_buffer(idx) <= x"68"; idx := idx + 1;  -- 'h'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                for i in 15 downto 0 loop
                                    msg_buffer(idx) <= nibble_to_hex(match_number(i*4+3 downto i*4)); idx := idx + 1;
                                end loop;
                                msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                                msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                                msg_buffer(idx) <= x"79"; idx := idx + 1;  -- 'y'
                                msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                                msg_buffer(idx) <= x"65"; idx := idx + 1;  -- 'e'
                                msg_buffer(idx) <= x"3D"; idx := idx + 1;  -- '='
                                msg_buffer(idx) <= nibble_to_hex(cross_type(7 downto 4)); idx := idx + 1;
                                msg_buffer(idx) <= nibble_to_hex(cross_type(3 downto 0)); idx := idx + 1;

                            when others =>
                                null;
                        end case;

                        -- Add CRLF
                        msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- '\r'
                        msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- '\n'

                        msg_length <= idx;
                        state <= SEND_MESSAGE;

                    when SEND_MESSAGE =>
                        -- Send bytes from buffer
                        if byte_index < msg_length then
                            if uart_tx_ready = '1' and uart_tx_valid_int = '0' then
                                uart_tx_data <= msg_buffer(byte_index);
                                uart_tx_valid_int <= '1';
                            elsif uart_tx_valid_int = '1' then
                                uart_tx_valid_int <= '0';
                                state <= WAIT_TX;
                            end if;
                        else
                            uart_tx_valid_int <= '0';
                            state <= IDLE;
                        end if;

                    when WAIT_TX =>
                        uart_tx_valid_int <= '0';

                        if uart_tx_ready = '1' then
                            byte_index <= byte_index + 1;

                            if byte_index + 1 >= msg_length then
                                state <= IDLE;
                            else
                                state <= SEND_MESSAGE;
                            end if;
                        end if;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    uart_tx_valid <= uart_tx_valid_int;

end Behavioral;
