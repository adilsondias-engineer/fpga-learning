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
        MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0) := x"000A3502AF9A"  -- Arty's A7 MAC address
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
    
    -- Pass through data for IP parser
    data_out <= rx_data;
    byte_counter <= global_byte_count;
    
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
                
            else
                
                -- Default
                frame_valid <= '0';
                
                case state is
                    
                    when IDLE_ST =>
                        byte_count <= (others => '0');
                        global_byte_count <= (others => '0');
                        
                        if frame_start = '1' then
                            state <= DEST_MAC_ST;
                        end if;
                    
                    when DEST_MAC_ST =>
                        if rx_valid = '1' then
                            -- Shift in destination MAC (MSB first)
                            dest_mac_buf <= dest_mac_buf(39 downto 0) & rx_data;
                            byte_count   <= byte_count + 1;
                            global_byte_count <= global_byte_count + 1;
                            
                            if byte_count = 5 then
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
                        if rx_valid = '1' then
                            global_byte_count <= global_byte_count + 1;
                        end if;
                        
                        if frame_end = '1' then
                            state <= FRAME_DONE_ST;
                        end if;
                    
                    when FRAME_DONE_ST =>
                        -- Check if frame is for us
                        if (dest_mac_buf = MAC_ADDR) or (dest_mac_buf = BROADCAST_MAC) then
                            -- Frame matched Arty's MAC or broadcast
                            frame_valid <= '1';
                            dest_mac    <= dest_mac_buf;
                            src_mac     <= src_mac_buf;
                            ethertype   <= ethertype_buf;
                            frame_cnt   <= frame_cnt + 1;
                        end if;
                        
                        state <= IDLE_ST;
                        
                end case;
                
            end if;
            
        end if;
    end process;

end Behavioral;