----------------------------------------------------------------------------------
-- UART Echo System with FIFO Queue and Binary Protocol (Top Level for Project 5)
--
-- Functionality:
-- 1. Receives characters from PC via UART
-- 2. Displays received byte on LEDs
-- 3. Echoes character back to PC
-- 4. Queues unknown characters in FIFO (16-byte capacity)
-- 5. Buttons:
--    - BTN0: Manual reset (debounced)
--    - BTN1: Clear LED display and value counter
--    - BTN2: Send test character ('A' = 0x41)
--    - BTN3: Send "HELLO" (press multiple times)
-- 6. ASCII UART Commands (legacy):
--    - 'R': Reset value counter
--    - 'I': Increment value counter
--    - 'D': Decrement value counter
--    - 'Q': Query value counter (returns 2-char hex)
--    - 'S': Status - show FIFO count (returns 2-char hex)
--    - 'G': Get - transmit all queued FIFO data
--    - Other: Echo character and store in FIFO
-- 7. Binary Protocol (trading-style):
--    Format: [START_BYTE=0xAA][CMD][LENGTH][DATA...][CHECKSUM]
--    Checksum: XOR of CMD + LENGTH + all DATA bytes
--    Commands:
--      0x01: Set counter (LENGTH=1, DATA=value)
--      0x02: Add to counter (LENGTH=1, DATA=value)
--      0x03: Query counter (LENGTH=0, returns 2-byte hex)
--      0x04: Write to FIFO (LENGTH=N, DATA=bytes)
--      0x05: Read from FIFO (LENGTH=0, transmits all)
--    Example: Set counter to 0x42
--      Send: AA 01 01 42 42 (START, CMD=0x01, LEN=1, DATA=0x42, CSUM=0x01^0x01^0x42=0x42)
--
-- Trading Relevance: Binary protocols, checksum validation, message framing
--
-- This project became more complex than expected, as features were added incrementally.
-- The final design includes state machines for UART communication, binary protocol parsing,
-- FIFO buffering, and button interactions - similar to real trading system message handlers.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_echo_top is
    Port (
        -- Clock and reset
        clk : in STD_LOGIC;                      -- 100 MHz system clock

        -- Buttons (active low on Arty A7)
        btn : in STD_LOGIC_VECTOR(3 downto 0);   -- BTN0-BTN3

        -- LEDs
        led : out STD_LOGIC_VECTOR(3 downto 0);  -- Onboard LEDs (lower nibble)
        led0_r, led0_g, led0_b : out STD_LOGIC;  -- RGB LED 0

        -- UART
        uart_txd_in : in STD_LOGIC;              -- RX: PC -> FPGA (confusing naming!)
        uart_rxd_out : out STD_LOGIC             -- TX: FPGA -> PC
    );
end uart_echo_top;

architecture Behavioral of uart_echo_top is

    -- Component declarations
    component uart_tx is
        Generic (
            CLK_FREQ : integer := 100_000_000;
            BAUD_RATE : integer := 115_200
        );
        Port (
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            tx_data : in STD_LOGIC_VECTOR(7 downto 0);
            tx_start : in STD_LOGIC;
            tx_busy : out STD_LOGIC;
            tx_serial : out STD_LOGIC
        );
    end component;

    component uart_rx is
        Generic (
            CLK_FREQ : integer := 100_000_000;
            BAUD_RATE : integer := 115_200
        );
        Port (
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            rx_serial : in STD_LOGIC;
            rx_data : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid : out STD_LOGIC
        );
    end component;

    component button_debouncer is
        Generic (
            CLK_FREQ    : integer := 100_000_000;
            DEBOUNCE_MS : integer := 20
        );
        Port (
            clk       : in  STD_LOGIC;
            btn_in    : in  STD_LOGIC;
            btn_out   : out STD_LOGIC
        );
    end component;

    component edge_detector is
        Port (
            clk      : in  STD_LOGIC;
            sig_in   : in  STD_LOGIC;
            rising   : out STD_LOGIC;
            falling  : out STD_LOGIC
        );
    end component;

    component fifo is
        Generic (
            DATA_WIDTH : integer := 8; -- Width of the data bus
            FIFO_DEPTH : integer := 16 -- Number of entries in the FIFO (must be power of 2)
        );
        Port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            --Write Interface
            wr_en       : in  std_logic;
            data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            --Read Interface
            rd_en       : in  std_logic;
            data_out    : out std_logic_vector(DATA_WIDTH-1 downto 0);

            -- Status signals
            full        : out std_logic;
            empty       : out std_logic;
            count       : out std_logic_vector(4 downto 0)
        );
    end component;

    --fifo signals
    signal fifo_wr_en : std_logic := '0';
    signal fifo_rd_en : std_logic := '0';
    signal fifo_rst :  std_logic := '0';
    signal fifo_data_in : std_logic_vector(7 downto 0) := (others => '0');
    signal fifo_data_out : std_logic_vector(7 downto 0);
    signal fifo_full : std_logic;
    signal fifo_empty : std_logic;
    signal fifo_count : std_logic_vector(4 downto 0);

    -- Button signals
    signal btn0_db, btn1_db, btn2_db, btn3_db : STD_LOGIC;
    signal btn0_rise, btn1_rise, btn2_rise, btn3_rise : STD_LOGIC;
    signal btn0_fall, btn1_fall, btn2_fall, btn3_fall  : STD_LOGIC;

    -- Reset signal
    signal reset : STD_LOGIC := '0';
    
    -- UART signals
    signal rx_data : STD_LOGIC_VECTOR(7 downto 0);
    signal rx_valid : STD_LOGIC;
    signal tx_data : STD_LOGIC_VECTOR(7 downto 0);
    signal tx_start : STD_LOGIC;
    signal tx_busy : STD_LOGIC;
    
    -- Data storage
    signal last_received : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    
    -- Echo state machine
    type echo_state_type is (WAIT_RX, ECHO_TX, SEND_HEX_LOW, SEND_FIFO_DATA);
    signal echo_state : echo_state_type := WAIT_RX;

    signal msg_counter: integer range 0 to 4 := 0;

    -- value counter for 'R', 'I', 'D', 'Q' commands
    signal value_counter : unsigned(7 downto 0) := (others => '0');
    signal query_value : std_logic_vector(7 downto 0) := (others => '0');  -- Captured value for 'Q' command
    signal send_second_hex : std_logic := '0';  -- Flag: need to send second hex character
    signal tx_started : std_logic := '0';  -- Flag: transmission has started (tx_busy seen as '1')

    -- Binary protocol parser
    -- Protocol: [START_BYTE=0xAA][CMD][LENGTH][DATA...][CHECKSUM]
    type protocol_state_type is (IDLE, WAIT_CMD, WAIT_LENGTH, WAIT_DATA, WAIT_CHECKSUM, PROCESS_CMD);
    signal protocol_state : protocol_state_type := IDLE;
    signal protocol_cmd : std_logic_vector(7 downto 0) := (others => '0');
    signal protocol_length : unsigned(7 downto 0) := (others => '0');
    signal protocol_data_count : unsigned(7 downto 0) := (others => '0');
    signal protocol_checksum : unsigned(7 downto 0) := (others => '0');
    signal protocol_checksum_calc : unsigned(7 downto 0) := (others => '0');
    signal protocol_data_buffer : std_logic_vector(15 downto 0) := (others => '0'); -- Store up to 2 bytes
    signal protocol_cmd_ack : std_logic := '0';  -- Handshake from main state machine
    signal protocol_active : std_logic := '0';  -- Flag: protocol is actively parsing (not IDLE)
    constant START_BYTE : std_logic_vector(7 downto 0) := X"AA";

    -- Helper function to convert 4-bit nibble to ASCII hex character
    function nibble_to_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case nibble is
            when X"0" => return X"30";  -- '0'
            when X"1" => return X"31";  -- '1'
            when X"2" => return X"32";  -- '2'
            when X"3" => return X"33";  -- '3'
            when X"4" => return X"34";  -- '4'
            when X"5" => return X"35";  -- '5'
            when X"6" => return X"36";  -- '6'
            when X"7" => return X"37";  -- '7'
            when X"8" => return X"38";  -- '8'
            when X"9" => return X"39";  -- '9'
            when X"A" => return X"41";  -- 'A'
            when X"B" => return X"42";  -- 'B'
            when X"C" => return X"43";  -- 'C'
            when X"D" => return X"44";  -- 'D'
            when X"E" => return X"45";  -- 'E'
            when X"F" => return X"46";  -- 'F'
            when others => return X"3F";  -- '?'
        end case;
    end function;
    
begin

    -- =========================================================================
    -- Button Debouncing and Edge Detection
    -- =========================================================================

    -- BTN0: Reset button
    btn0_debouncer: button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => btn(0),
            btn_out => btn0_db
        );

    btn0_edge: edge_detector
        port map (
            clk => clk,
            sig_in => btn0_db,
            rising => btn0_rise,
            falling => btn0_fall
        );

    -- BTN1: Clear display button
    btn1_debouncer: button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => btn(1),
            btn_out => btn1_db
        );

    btn1_edge: edge_detector
        port map (
            clk => clk,
            sig_in => btn1_db,
            rising => btn1_rise,
            falling => btn1_fall
        );

    -- BTN2: Test character button
    btn2_debouncer: button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => btn(2),
            btn_out => btn2_db
        );

    btn2_edge: edge_detector
        port map (
            clk => clk,
            sig_in => btn2_db,
            rising => btn2_rise,
            falling => btn2_fall
        );

      -- BTN3: SEND "HELLO" button
    btn3_debouncer: button_debouncer
        generic map (
            CLK_FREQ => 100_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk => clk,
            btn_in => btn(3),
            btn_out => btn3_db
        );

    btn3_edge: edge_detector
        port map (
            clk => clk,
            sig_in => btn3_db,
            rising => btn3_rise,
            falling => btn3_fall
        );
    -- =========================================================================
  -- Reset control: Pulse on BTN0 press
    process(clk)
    begin
        if rising_edge(clk) then
            if btn0_rise = '1' then
                reset <= '1';  -- Assert reset for one cycle
            else
                reset <= '0';
            end if;
        end if;
    end process;

    -- =========================================================================
    -- UART Module Instantiation
    -- =========================================================================

    -- Instantiate UART receiver
    uart_rx_inst : uart_rx
        port map (
            clk => clk,
            reset => reset,
            rx_serial => uart_txd_in,      -- Note: confusing Xilinx naming!
            rx_data => rx_data,
            rx_valid => rx_valid
        );
    
    -- Instantiate UART transmitter
    uart_tx_inst : uart_tx
        port map (
            clk => clk,
            reset => reset,
            tx_data => tx_data,
            tx_start => tx_start,
            tx_busy => tx_busy,
            tx_serial => uart_rxd_out      -- Note: confusing Xilinx naming!
        );

    -- Instantiate FIFO for data queuing
    fifo_inst : fifo
        generic map (
            DATA_WIDTH => 8,
            FIFO_DEPTH => 16
        )
        port map (
            clk => clk,
            rst => fifo_rst,
            wr_en => fifo_wr_en,
            data_in => fifo_data_in,
            rd_en => fifo_rd_en,
            data_out => fifo_data_out,
            full => fifo_full,
            empty => fifo_empty,
            count => fifo_count
        );

    -- =========================================================================
    -- Binary Protocol Parser
    -- =========================================================================
    -- Protocol: [START_BYTE=0xAA][CMD][LENGTH][DATA...][CHECKSUM]
    -- Checksum: XOR of CMD + LENGTH + all DATA bytes
    -- Commands:
    --   0x01: Set counter (DATA: 1 byte value)
    --   0x02: Add to counter (DATA: 1 byte value)
    --   0x03: Query counter (DATA: none)
    --   0x04: Write to FIFO (DATA: N bytes)
    --   0x05: Read from FIFO (DATA: 1 byte count)
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                protocol_state <= IDLE;
                protocol_active <= '0';
            else
                case protocol_state is
                    when IDLE =>
                        -- Don't reset protocol_active here - it causes race condition
                        -- Only set it when START_BYTE is detected
                        if rx_valid = '1' then
                            if rx_data = START_BYTE then
                                protocol_state <= WAIT_CMD;
                                protocol_checksum_calc <= (others => '0');
                                protocol_active <= '1';  -- Signal that protocol is now active
                            end if;
                        end if;

                    when WAIT_CMD =>
                        protocol_active <= '1';
                        if rx_valid = '1' then
                            protocol_cmd <= rx_data;
                            protocol_checksum_calc <= unsigned(rx_data);
                            protocol_state <= WAIT_LENGTH;
                        end if;

                    when WAIT_LENGTH =>
                        protocol_active <= '1';
                        if rx_valid = '1' then
                            protocol_length <= unsigned(rx_data);
                            protocol_data_count <= (others => '0');
                            protocol_checksum_calc <= protocol_checksum_calc xor unsigned(rx_data);
                            if unsigned(rx_data) = 0 then
                                protocol_state <= WAIT_CHECKSUM; -- No data bytes
                            else
                                protocol_state <= WAIT_DATA;
                            end if;
                        end if;

                    when WAIT_DATA =>
                        protocol_active <= '1';
                        if rx_valid = '1' then
                            -- Store data in buffer (up to 2 bytes)
                            if protocol_data_count = 0 then
                                protocol_data_buffer(7 downto 0) <= rx_data;
                            elsif protocol_data_count = 1 then
                                protocol_data_buffer(15 downto 8) <= rx_data;
                            end if;

                            protocol_checksum_calc <= protocol_checksum_calc xor unsigned(rx_data);
                            protocol_data_count <= protocol_data_count + 1;

                            if protocol_data_count + 1 = protocol_length then
                                protocol_state <= WAIT_CHECKSUM;
                            end if;
                        end if;

                    when WAIT_CHECKSUM =>
                        protocol_active <= '1';
                        if rx_valid = '1' then
                            protocol_checksum <= unsigned(rx_data);
                            if unsigned(rx_data) = protocol_checksum_calc then
                                protocol_state <= PROCESS_CMD; -- Checksum valid
                            else
                                protocol_state <= IDLE; -- Checksum error, discard
                                protocol_active <= '0';
                            end if;
                        end if;

                    when PROCESS_CMD =>
                        protocol_active <= '1';
                        -- Wait for acknowledgment from main state machine
                        if protocol_cmd_ack = '1' then
                            protocol_state <= IDLE;
                            protocol_data_buffer <= (others => '0');  -- Clear buffer
                            protocol_active <= '0';
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Echo State Machine with Button Control
    -- =========================================================================
    -- Handles UART echo, test character transmission, and LED display
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                echo_state <= WAIT_RX;
                tx_start <= '0';
                last_received <= (others => '0');
                value_counter <= (others => '0');
                query_value <= (others => '0');
                send_second_hex <= '0';
                tx_started <= '0';
                msg_counter <= 0;
                fifo_rst <= '1';
                fifo_wr_en <= '0';
                fifo_rd_en <= '0';
                -- Reset protocol parser
                protocol_state <= IDLE;
                protocol_cmd <= (others => '0');
                protocol_length <= (others => '0');
                protocol_data_count <= (others => '0');
                protocol_checksum <= (others => '0');
                protocol_checksum_calc <= (others => '0');
                protocol_cmd_ack <= '0';
                protocol_active <= '0';

            else
                -- Default: no transmission
                tx_start <= '0';
                fifo_rst <= '0';
                fifo_wr_en <= '0';
                fifo_rd_en <= '0';
                protocol_cmd_ack <= '0';  -- Clear ack by default

                case echo_state is

                    when WAIT_RX =>

                        -- Priority 1: Binary protocol command ready
                        if protocol_state = PROCESS_CMD then
                            protocol_cmd_ack <= '1';  -- Acknowledge protocol command processing
                            -- Process binary protocol commands
                            case protocol_cmd is
                                when X"01" =>  -- Set counter
                                    value_counter <= unsigned(protocol_data_buffer(7 downto 0));
                                    last_received <= protocol_data_buffer(7 downto 0);

                                when X"02" =>  -- Add to counter
                                    value_counter <= value_counter + unsigned(protocol_data_buffer(7 downto 0));
                                    last_received <= std_logic_vector(value_counter + unsigned(protocol_data_buffer(7 downto 0)));

                                when X"03" =>  -- Query counter (return as hex)
                                    query_value <= std_logic_vector(value_counter);
                                    send_second_hex <= '1';
                                    tx_data <= nibble_to_hex(std_logic_vector(value_counter(7 downto 4)));
                                    tx_start <= '1';
                                    echo_state <= ECHO_TX;

                                when X"04" =>  -- Write to FIFO (up to 2 bytes)
                                    if protocol_length >= 1 and fifo_full = '0' then
                                        fifo_data_in <= protocol_data_buffer(7 downto 0);
                                        fifo_wr_en <= '1';
                                    end if;
                                    -- Could write second byte too if length = 2

                                when X"05" =>  -- Read from FIFO
                                    if fifo_empty = '0' then
                                        fifo_rd_en <= '1';
                                        echo_state <= SEND_FIFO_DATA;
                                    end if;

                                when others =>
                                    null; -- Unknown binary command
                            end case;

                        -- Priority 2: BTN1 pressed (clear display and counter)
                        elsif btn1_rise = '1' then
                            last_received <= (others => '0');
                            value_counter <= (others => '0');

                        -- Priority 3: UART received character (ASCII commands or echo)
                        -- Don't process if protocol is parsing (check both state and flag)
                        elsif rx_valid = '1' and protocol_state = IDLE and protocol_active = '0' and rx_data /= START_BYTE then

                            if msg_counter /= 0 then
                                msg_counter <= 0; -- Reset message counter if in middle of sending "HELLO"
                            end if;
                            
                            -- Parse received command
                            case rx_data is
                                
                                when X"52" =>  -- 'R' = Reset
                                    value_counter <= (others => '0');
                                    last_received <= (others => '0');
                                when X"49" =>  -- 'I' = Increment
                                    if(value_counter = X"FF") then
                                        value_counter <= (others => '0'); -- Wrap around
                                        last_received <= (others => '0');
                                    else
                                        value_counter <= value_counter + 1;
                                        last_received <= std_logic_vector(value_counter + 1);
                                    end if;

                                when X"44" =>  -- 'D' = Decrement
                                    if(value_counter = X"00") then
                                        value_counter <= X"FF"; -- Wrap around
                                        last_received <= X"FF";
                                    else
                                        value_counter <= value_counter - 1;
                                        last_received <= std_logic_vector(value_counter - 1);
                                    end if;
                                    
                                when X"51" =>  -- 'Q' = Query (send value back as hex ASCII)
                                    last_received <= std_logic_vector(value_counter);
                                    query_value <= std_logic_vector(value_counter);  -- Capture the value
                                    send_second_hex <= '1';  -- Flag to indicate to send low nibble next
                                    -- Send high nibble first (e.g., for 0x5A, send '5' then 'A')
                                    tx_data <= nibble_to_hex(std_logic_vector(value_counter(7 downto 4)));
                                    tx_start <= '1';
                                    echo_state <= ECHO_TX;  -- Wait for high nibble to transmit first

                                when X"53" =>  -- 'S' = Status (show FIFO count as hex)
                                    -- Send FIFO count as 2-character hex (5-bit count: 0-16)
                                    query_value <= "000" & fifo_count;  -- Convert 5-bit count to 8-bit
                                    send_second_hex <= '1';
                                    -- High nibble: bit 4 of count (will be '0' or '1')
                                    tx_data <= nibble_to_hex("000" & fifo_count(4));
                                    tx_start <= '1';
                                    echo_state <= ECHO_TX;

                                when X"47" =>  -- 'G' = Get (transmit all queued data)
                                    if fifo_empty = '0' then
                                        -- FIFO has data, start transmitting
                                        fifo_rd_en <= '1';  -- Request first byte
                                        echo_state <= SEND_FIFO_DATA;
                                    end if;
                                    -- If FIFO empty, do nothing (stay in WAIT_RX)

                                when others =>
                                    -- Unknown command: store in FIFO if not full, then echo
                                    if fifo_full = '0' then
                                        fifo_data_in <= rx_data;
                                        fifo_wr_en <= '1';
                                    end if;
                                    last_received <= rx_data;  -- Store for LED display
                                    tx_data <= rx_data;
                                    tx_start <= '1';
                                    echo_state <= ECHO_TX;
                            end case;


                        -- Priority 4: BTN2 pressed (send test character 'A' = 0x41)
                        elsif btn2_rise = '1' then

                             if msg_counter /= 0 then
                                msg_counter <= 0; -- Reset message counter if in middle of sending "HELLO"
                            end if;

                            tx_data <= X"41";          -- Send 'A'
                            tx_start <= '1';           -- Start transmission
                            last_received <= X"41";    -- Show on LEDs
                            echo_state <= ECHO_TX;

                        -- Priority 5: BTN3 pressed (transmit "HELLO")
                        elsif btn3_rise = '1' then
                            case msg_counter is
                                when 0 => tx_data <= X"48"; -- 'H'
                                when 1 => tx_data <= X"45"; -- 'E'
                                when 2 => tx_data <= X"4C"; -- 'L'
                                when 3 => tx_data <= X"4C"; -- 'L'
                                when 4 => tx_data <= X"4F"; -- 'O'
                                when  others => tx_data <= X"00"; -- Should not occur
                            end case;
                            tx_start <= '1';
                            echo_state <= ECHO_TX;
                            if(msg_counter >= 4) then
                                msg_counter <= 0;
                            else
                                msg_counter <= msg_counter + 1;
                            end if;                            
                        end if;
                    when ECHO_TX =>
                        -- Wait for transmission to start, then wait for it to complete
                        if tx_busy = '1' then
                            tx_started <= '1';  -- Mark that  I've seen transmission start
                        elsif tx_started = '1' and tx_busy = '0' then
                            -- Transmission has completed
                            tx_started <= '0';  -- Clear flag
                            -- Check if need to send the second hex character (for 'Q' command)
                            if send_second_hex = '1' then
                                -- Send low nibble
                                tx_data <= nibble_to_hex(query_value(3 downto 0));
                                tx_start <= '1';
                                send_second_hex <= '0';  -- Clear flag
                                echo_state <= SEND_HEX_LOW;
                            else
                                echo_state <= WAIT_RX;
                            end if;
                        end if;

                    when SEND_HEX_LOW =>
                        -- Wait for low nibble transmission to start and complete
                        if tx_busy = '1' then
                            tx_started <= '1';  -- Mark that  I've seen transmission start
                        elsif tx_started = '1' and tx_busy = '0' then
                            -- Transmission has completed
                            tx_started <= '0';  -- Clear flag
                            echo_state <= WAIT_RX;
                        end if;

                    when SEND_FIFO_DATA =>
                        -- Transmit all data from FIFO
                        if tx_busy = '1' then
                            tx_started <= '1';  -- Mark that  I've seen transmission start
                        elsif tx_started = '1' and tx_busy = '0' then
                            -- Previous transmission completed
                            tx_started <= '0';

                            -- Check if more data in FIFO
                            if fifo_empty = '0' then
                                -- More data available, send next byte
                                tx_data <= fifo_data_out;  -- Send current FIFO output
                                tx_start <= '1';
                                fifo_rd_en <= '1';  -- Request next byte
                                last_received <= fifo_data_out;  -- Update LEDs
                            else
                                -- FIFO empty, done transmitting
                                echo_state <= WAIT_RX;
                            end if;
                        elsif fifo_rd_en = '1' then
                            -- Just issued read request, now start transmission
                            fifo_rd_en <= '0';
                            tx_data <= fifo_data_out;
                            tx_start <= '1';
                            last_received <= fifo_data_out;
                        end if;

                end case;
            end if;
        end if;
    end process;
    
    -- =========================================================================
    -- LED Display
    -- =========================================================================

    -- Standard LEDs: Show lower nibble of last received/sent character
    led <= last_received(3 downto 0);

    -- RGB LED 0: Status indicators
    led0_r <= '1' when rx_valid = '1' else '0';        -- Red: Flash on receive
    led0_g <= '1' when tx_busy = '1' else '0';         -- Green: Transmitting
    led0_b <= '1' when echo_state = WAIT_RX else '0';  -- Blue: Idle/waiting

end Behavioral;
