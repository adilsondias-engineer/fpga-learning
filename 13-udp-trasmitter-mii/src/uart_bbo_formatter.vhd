--------------------------------------------------------------------------------
-- Module: uart_bbo_formatter
-- Description: Simple UART formatter for BBO (Best Bid/Offer) display
--              Displays BBO updates in human-readable format
--
-- Output Format (enhanced for Project 9 integration):
--   Valid BBO:   [BBO:AAPL    ] Bid:0x12345678 (0x00000064) | Ask:0x12345678 (0x000000C8) | Spr:0x00000050
--   No BBO data: [BBO:NODATA  ]
--   Where: Symbol (8 chars), Bid price, (Bid shares), Ask price, (Ask shares), Spread
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.order_book_pkg.all;

entity uart_bbo_formatter is
    Port (
        clk : in std_logic;
        rst : in std_logic;

        -- BBO input
        bbo             : in  bbo_t;
        bbo_update      : in  std_logic;  -- Trigger to display BBO
        bbo_symbol      : in  std_logic_vector(63 downto 0);  -- Symbol name (for multi-symbol support)
        stats           : in  order_book_stats_t;

        -- UART TX interface
        uart_tx_data    : out std_logic_vector(7 downto 0);
        uart_tx_valid   : out std_logic;
        uart_tx_ready   : in  std_logic
    );
end uart_bbo_formatter;

architecture Behavioral of uart_bbo_formatter is

    type state_type is (IDLE, FORMAT_MSG, FORMAT_DONE, SEND_MESSAGE, WAIT_TX);
    signal state : state_type := IDLE;

    type byte_array is array (0 to 255) of std_logic_vector(7 downto 0);
    signal msg_buffer : byte_array := (others => (others => '0'));
    signal msg_length : integer range 0 to 256 := 0;
    signal byte_index : integer range 0 to 256 := 0;

    signal uart_tx_valid_int : std_logic := '0';

    -- Heartbeat counter (send message every ~5 seconds at 100 MHz)
    signal heartbeat_counter : unsigned(28 downto 0) := (others => '0');
    constant HEARTBEAT_MAX : unsigned(28 downto 0) := to_unsigned(500_000_000, 29);  -- 5 seconds
    signal heartbeat_trigger : std_logic := '0';
    signal sending_message : std_logic := '0';

    -- Captured BBO (registered on bbo_update)
    signal captured_bbo : bbo_t;
    signal captured_bbo_symbol : std_logic_vector(63 downto 0);
    signal captured_stats : order_book_stats_t;

    -- Edge detection for bbo_update (prevent continuous triggering)
    signal bbo_update_prev : std_logic := '0';
    
    -- Debug counters
    signal bbo_update_count : unsigned(15 downto 0) := (others => '0');
    

    -- Helper function: Convert nibble to hex ASCII
    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        case nibble is
            when x"0" => result := x"30";  -- '0'
            when x"1" => result := x"31";  -- '1'
            when x"2" => result := x"32";  -- '2'
            when x"3" => result := x"33";  -- '3'
            when x"4" => result := x"34";  -- '4'
            when x"5" => result := x"35";  -- '5'
            when x"6" => result := x"36";  -- '6'
            when x"7" => result := x"37";  -- '7'
            when x"8" => result := x"38";  -- '8'
            when x"9" => result := x"39";  -- '9'
            when x"A" => result := x"41";  -- 'A'
            when x"B" => result := x"42";  -- 'B'
            when x"C" => result := x"43";  -- 'C'
            when x"D" => result := x"44";  -- 'D'
            when x"E" => result := x"45";  -- 'E'
            when x"F" => result := x"46";  -- 'F'
            when others => result := x"3F"; -- '?'
        end case;
        return result;
    end function;

begin

    uart_tx_valid <= uart_tx_valid_int;

    -- Heartbeat generator (only trigger when not already sending)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                heartbeat_counter <= (others => '0');
                heartbeat_trigger <= '0';
            else
                heartbeat_trigger <= '0';
                if sending_message = '0' then
                    if heartbeat_counter >= HEARTBEAT_MAX then
                        heartbeat_counter <= (others => '0');
                        heartbeat_trigger <= '1';
                    else
                        heartbeat_counter <= heartbeat_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk)
        variable idx : integer;
        variable price_int : unsigned(31 downto 0);
        variable dollars : unsigned(15 downto 0);
        variable cents : unsigned(7 downto 0);
        variable shares_val : unsigned(31 downto 0);
        variable add_count_slv : std_logic_vector(31 downto 0);
        variable bid_level_slv : std_logic_vector(7 downto 0);
        variable ask_level_slv : std_logic_vector(7 downto 0);
        variable update_count_slv : std_logic_vector(15 downto 0);
        variable bid_order_slv : std_logic_vector(15 downto 0);
        variable ask_order_slv : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                uart_tx_valid_int <= '0';
                byte_index <= 0;
                msg_length <= 0;
                bbo_update_prev <= '0';
                bbo_update_count <= (others => '0');
            else
                case state is
                    when IDLE =>
                        uart_tx_valid_int <= '0';
                        sending_message <= '0';

                        -- Update edge detection
                        bbo_update_prev <= bbo_update;
                        
                        -- Count BBO update pulses (debug)
                        if bbo_update = '1' and bbo_update_prev = '0' then
                            bbo_update_count <= bbo_update_count + 1;
                        end if;

                        -- Trigger on BBO update edge (rising edge) only
                        -- Heartbeat disabled to avoid false updates in C++ gateway (Project 9)
                        -- Only trigger if UART is not busy
                        if (bbo_update = '1' and bbo_update_prev = '0') and uart_tx_ready = '1' then
                            -- Capture CURRENT BBO data (not stale cached data)
                            -- CRITICAL: Always capture live BBO to avoid sending stale prices
                            captured_bbo <= bbo;
                            captured_bbo_symbol <= bbo_symbol;
                            captured_stats <= stats;
                            sending_message <= '1';
                            state <= FORMAT_MSG;
                        end if;

                    when FORMAT_MSG =>
                        -- Convert statistics to std_logic_vector for indexing
                        add_count_slv := std_logic_vector(captured_stats.add_count);
                        bid_level_slv := std_logic_vector(captured_stats.bid_level_count);
                        ask_level_slv := std_logic_vector(captured_stats.ask_level_count);
                        update_count_slv := std_logic_vector(bbo_update_count);
                        bid_order_slv := std_logic_vector(captured_stats.bid_order_count);
                        ask_order_slv := std_logic_vector(captured_stats.ask_order_count);

                        -- Build message (all assignments happen in this cycle)
                        idx := 0;

                        -- "[BBO:SYMBOL] " - Symbol or NODATA status
                        msg_buffer(idx) <= x"5B"; idx := idx + 1;  -- '['
                        msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                        msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                        msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                        msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'

                        if captured_bbo.valid = '1' then
                            -- Symbol name (8 bytes from captured_bbo_symbol)
                            -- captured_bbo_symbol is provided by multi_symbol_order_book
                            -- Bit [63:56] = MSB, [55:48] = next byte, etc.
                            -- Extract MSB to LSB for correct symbol order
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= captured_bbo_symbol(i*8+7 downto i*8);
                                idx := idx + 1;
                            end loop;
                        else
                            -- No valid BBO - output "NODATA  " (8 chars, space-padded)
                            msg_buffer(idx) <= x"4E"; idx := idx + 1;  -- 'N'
                            msg_buffer(idx) <= x"4F"; idx := idx + 1;  -- 'O'
                            msg_buffer(idx) <= x"44"; idx := idx + 1;  -- 'D'
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"54"; idx := idx + 1;  -- 'T'
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' ' (padding)
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' ' (padding)
                        end if;
                        msg_buffer(idx) <= x"5D"; idx := idx + 1;  -- ']'

                        if captured_bbo.valid = '1' then
                            -- "Bid:0x"
                            msg_buffer(idx) <= x"42"; idx := idx + 1;  -- 'B'
                            msg_buffer(idx) <= x"69"; idx := idx + 1;  -- 'i'
                            msg_buffer(idx) <= x"64"; idx := idx + 1;  -- 'd'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'

                            -- Bid price (8 hex digits)
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= nibble_to_hex(captured_bbo.bid_price(i*4+3 downto i*4));
                                idx := idx + 1;
                            end loop;

                            -- " (0x" - Bid shares
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"28"; idx := idx + 1;  -- '('
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'

                            -- Bid shares (8 hex digits)
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= nibble_to_hex(captured_bbo.bid_shares(i*4+3 downto i*4));
                                idx := idx + 1;
                            end loop;

                            msg_buffer(idx) <= x"29"; idx := idx + 1;  -- ')'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"7C"; idx := idx + 1;  -- '|'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Ask:0x"
                            msg_buffer(idx) <= x"41"; idx := idx + 1;  -- 'A'
                            msg_buffer(idx) <= x"73"; idx := idx + 1;  -- 's'
                            msg_buffer(idx) <= x"6B"; idx := idx + 1;  -- 'k'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'

                            -- Ask price (8 hex digits)
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= nibble_to_hex(captured_bbo.ask_price(i*4+3 downto i*4));
                                idx := idx + 1;
                            end loop;

                            -- " (0x" - Ask shares
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"28"; idx := idx + 1;  -- '('
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'

                            -- Ask shares (8 hex digits)
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= nibble_to_hex(captured_bbo.ask_shares(i*4+3 downto i*4));
                                idx := idx + 1;
                            end loop;

                            msg_buffer(idx) <= x"29"; idx := idx + 1;  -- ')'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '
                            msg_buffer(idx) <= x"7C"; idx := idx + 1;  -- '|'
                            msg_buffer(idx) <= x"20"; idx := idx + 1;  -- ' '

                            -- "Spr:0x"
                            msg_buffer(idx) <= x"53"; idx := idx + 1;  -- 'S'
                            msg_buffer(idx) <= x"70"; idx := idx + 1;  -- 'p'
                            msg_buffer(idx) <= x"72"; idx := idx + 1;  -- 'r'
                            msg_buffer(idx) <= x"3A"; idx := idx + 1;  -- ':'
                            msg_buffer(idx) <= x"30"; idx := idx + 1;  -- '0'
                            msg_buffer(idx) <= x"78"; idx := idx + 1;  -- 'x'

                            -- Spread (8 hex digits)
                            for i in 7 downto 0 loop
                                msg_buffer(idx) <= nibble_to_hex(captured_bbo.spread(i*4+3 downto i*4));
                                idx := idx + 1;
                            end loop;

                        end if;

                        -- "\r\n"
                        msg_buffer(idx) <= x"0D"; idx := idx + 1;  -- CR
                        msg_buffer(idx) <= x"0A"; idx := idx + 1;  -- LF

                        msg_length <= idx;
                        byte_index <= 0;
                        -- Wait one cycle for signal assignments to complete
                        state <= FORMAT_DONE;

                    when FORMAT_DONE =>
                        -- Buffer formatting complete, ready to send
                        state <= SEND_MESSAGE;

                    when SEND_MESSAGE =>
                        -- Send bytes from buffer (matching ITCH formatter pattern)
                        if byte_index < msg_length then
                            if uart_tx_ready = '1' and uart_tx_valid_int = '0' then
                                -- UART is ready, send next byte
                                uart_tx_data <= msg_buffer(byte_index);
                                uart_tx_valid_int <= '1';
                            elsif uart_tx_valid_int = '1' then
                                -- Valid asserted, wait for UART to latch (goes to WAIT_TX)
                                uart_tx_valid_int <= '0';
                                state <= WAIT_TX;
                            end if;
                        else
                            -- Message complete
                            uart_tx_valid_int <= '0';
                            state <= IDLE;
                        end if;

                    when WAIT_TX =>
                        -- Wait for UART to finish transmitting current byte
                        uart_tx_valid_int <= '0';
                        
                        if uart_tx_ready = '1' then
                            -- UART is ready for next byte
                            byte_index <= byte_index + 1;
                            
                            if byte_index + 1 >= msg_length then
                                -- All bytes sent
                                state <= IDLE;
                            else
                                -- More bytes to send
                                state <= SEND_MESSAGE;
                            end if;
                        end if;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
