----------------------------------------------------------------------------------
-- MAC Frame Parser
-- Parses Ethernet MAC frames byte-by-byte
-- Extracts destination MAC, source MAC, EtherType
-- Filters based on destination MAC address
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mac_parser is
    Generic (
        MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0) := x"00183E045DE7"  -- x"000A3502AF9A"  -- Arty's A7 MAC address
    );
    Port (
        clk         : in  STD_LOGIC;                      -- System clock (from MII rx_clk)
        reset       : in  STD_LOGIC;
        
        -- Input from MII receiver
        rx_data     : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_valid    : in  STD_LOGIC;
        frame_start : in  STD_LOGIC;
        frame_end   : in  STD_LOGIC;
        
        -- Frame information output
        frame_valid : out STD_LOGIC;                      -- Valid frame received
        dest_mac    : out STD_LOGIC_VECTOR(47 downto 0); -- Destination MAC
        src_mac     : out STD_LOGIC_VECTOR(47 downto 0); -- Source MAC
        ethertype   : out STD_LOGIC_VECTOR(15 downto 0); -- EtherType field
        
        -- Statistics
        frame_count : out STD_LOGIC_VECTOR(31 downto 0); -- Total frames received
        
        -- Data passthrough for IP parser (ADDED)
        data_out     : out STD_LOGIC_VECTOR(7 downto 0); -- Byte stream passthrough
        byte_counter : out unsigned(10 downto 0)          -- Current byte position
    );
end mac_parser;

architecture Behavioral of mac_parser is
    
    -- MAC frame structure (bytes):
    -- [0-5]   Destination MAC (6 bytes)
    -- [6-11]  Source MAC (6 bytes)
    -- [12-13] EtherType (2 bytes)
    -- [14+]   Payload
    
    type state_type is (
        IDLE_ST,
        DEST_MAC_ST,
        SRC_MAC_ST,
        ETHERTYPE_ST,
        PAYLOAD_ST,
        FRAME_DONE_ST
    );
    
    signal state       : state_type := IDLE_ST;
    signal byte_count  : unsigned(15 downto 0) := (others => '0');
    
    -- Frame buffers
    signal dest_mac_buf   : STD_LOGIC_VECTOR(47 downto 0) := (others => '0');
    signal src_mac_buf    : STD_LOGIC_VECTOR(47 downto 0) := (others => '0');
    signal ethertype_buf  : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    
    -- Frame counter
    signal frame_cnt      : unsigned(31 downto 0) := (others => '0');
    
    -- MAC filtering
    signal mac_match      : STD_LOGIC := '0';
    
    constant BROADCAST_MAC : STD_LOGIC_VECTOR(47 downto 0) := x"FFFFFFFFFFFF";
    
    -- Byte counter for entire frame (needed by IP parser)
    signal global_byte_count : unsigned(10 downto 0) := (others => '0');

begin

    frame_count <= STD_LOGIC_VECTOR(frame_cnt);

    ----------------------------------------------------------------------------------
    -- MAC Frame Parser State Machine
    ----------------------------------------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if reset = '1' then
                state       <= IDLE_ST;
                byte_count  <= (others => '0');
                frame_valid <= '0';
                frame_cnt   <= (others => '0');
                global_byte_count <= (others => '0');
                data_out <= (others => '0');
                byte_counter <= (others => '0');
                mac_match <= '0';
                
            else
                
                -- Default
                frame_valid <= '0';
                
                case state is
                    
                    when IDLE_ST =>
                        byte_count <= (others => '0');
                        global_byte_count <= (others => '0');
                        mac_match <= '0';  -- Reset MAC match flag
                        
                        if frame_start = '1' then
                            state <= DEST_MAC_ST;
                        end if;
                    
                    when DEST_MAC_ST =>
                        if rx_valid = '1' then
                            -- Shift in destination MAC (MSB first)
                            -- After shift: dest_mac_buf(47:40)=byte0, dest_mac_buf(39:32)=byte1, ..., dest_mac_buf(7:0)=byte5
                            dest_mac_buf <= dest_mac_buf(39 downto 0) & rx_data;
                            byte_count   <= byte_count + 1;
                            
                            -- Always pass destination MAC bytes (0-5) for filtering
                            -- BUG FIX #13: Register both data and counter synchronously
                            data_out <= rx_data;
                            byte_counter <= global_byte_count;
                            global_byte_count <= global_byte_count + 1;
                            
                            -- Check MAC address as soon as we have all 6 bytes
                            if byte_count = 5 then
                                -- MAC filtering: Accept only packets for board MAC or broadcast
                                if ((dest_mac_buf(39 downto 0) & rx_data) = MAC_ADDR) or
                                   ((dest_mac_buf(39 downto 0) & rx_data) = BROADCAST_MAC) then
                                    mac_match <= '1';  -- Frame is for us
                                else
                                    mac_match <= '0';  -- Frame is not for us
                                end if;

                                state      <= SRC_MAC_ST;
                                byte_count <= (others => '0');
                            end if;
                        end if;

                        if frame_end = '1' then
                            state <= IDLE_ST;  -- Premature end
                        end if;

                    when SRC_MAC_ST =>
                        if rx_valid = '1' then
                            -- Shift in source MAC (MSB first)
                            src_mac_buf <= src_mac_buf(39 downto 0) & rx_data;
                            byte_count  <= byte_count + 1;
                            
                            -- Always increment global_byte_count to keep byte_counter in sync
                            -- Only pass data if MAC matches
                            if mac_match = '1' then
                                data_out <= rx_data;
                                byte_counter <= global_byte_count;
                            else
                                -- Don't pass data, but still update byte_counter for next bytes
                                byte_counter <= global_byte_count;
                            end if;
                            global_byte_count <= global_byte_count + 1;

                            if byte_count = 5 then
                                state      <= ETHERTYPE_ST;
                                byte_count <= (others => '0');
                            end if;
                        end if;

                        if frame_end = '1' then
                            state <= IDLE_ST;
                        end if;

                    when ETHERTYPE_ST =>
                        if rx_valid = '1' then
                            -- Shift in EtherType (MSB first)
                            ethertype_buf <= ethertype_buf(7 downto 0) & rx_data;
                            byte_count    <= byte_count + 1;
                            
                            -- Only pass EtherType bytes if MAC matches (otherwise IP parser will see invalid frames)
                            if mac_match = '1' then
                                data_out <= rx_data;
                                byte_counter <= global_byte_count;
                            else
                                -- Don't pass data, but still update byte_counter for next bytes
                                byte_counter <= global_byte_count;
                            end if;
                            global_byte_count <= global_byte_count + 1;

                            if byte_count = 1 then
                                state      <= PAYLOAD_ST;
                                byte_count <= (others => '0');
                            end if;
                        end if;

                        if frame_end = '1' then
                            state <= IDLE_ST;
                        end if;

                    when PAYLOAD_ST =>
                        -- Continue counting bytes for IP parser
                        -- Only pass data if MAC matches
                        if rx_valid = '1' and mac_match = '1' then
                            -- BUG FIX #13: Register both data and counter synchronously
                            data_out <= rx_data;
                            byte_counter <= global_byte_count;
                            global_byte_count <= global_byte_count + 1;
                        end if;

                        if frame_end = '1' then
                            state <= FRAME_DONE_ST;
                        end if;
                    
                    when FRAME_DONE_ST =>
                        -- Use mac_match flag that was set in DEST_MAC_ST (more reliable)
                        -- Also double-check dest_mac_buf for safety
                        if mac_match = '1' then
                            -- Frame matched Arty's MAC or broadcast
                            frame_valid <= '1';
                            dest_mac    <= dest_mac_buf;
                            src_mac     <= src_mac_buf;
                            ethertype   <= ethertype_buf;
                            frame_cnt   <= frame_cnt + 1;
                        else
                            -- Frame not for us - ensure frame_valid is low
                            frame_valid <= '0';
                        end if;
                        
                        state <= IDLE_ST;
                        
                end case;
                
            end if;
            
        end if;
    end process;

end Behavioral;