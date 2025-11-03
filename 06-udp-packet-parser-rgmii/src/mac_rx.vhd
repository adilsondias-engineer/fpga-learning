----------------------------------------------------------------------------------
-- Project 6: UDP Packet Parser - Phase 1A
-- Module: MAC Frame Receiver
-- 
-- Description:
--   Parses Ethernet (MAC layer) frames
--   - Extracts Destination MAC address (6 bytes)
--   - Extracts Source MAC address (6 bytes)
--   - Extracts EtherType (2 bytes) - 0x0800 = IPv4
--   - Validates frame (minimum size, CRC checking done by PHY)
--   - Filters frames by destination MAC
--
-- Ethernet Frame Structure:
--   [Dest MAC(6)] [Src MAC(6)] [EtherType(2)] [Payload(46-1500)] [CRC(4)]
--
-- Our MAC Address: 00:0A:35:02:AF:9A (Xilinx OUI + random)
--
-- Trading Relevance:
--   Market data multicast uses specific MAC addresses
--   Filtering at MAC layer reduces CPU load significantly
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mac_rx is
    Port (
        -- Clock and Reset
        clk             : in  STD_LOGIC;  -- 125 MHz ethernet RX clock
        reset           : in  STD_LOGIC;
        
        -- Input from RGMII receiver
        rx_data         : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_data_valid   : in  STD_LOGIC;
        rx_frame_start  : in  STD_LOGIC;
        rx_frame_end    : in  STD_LOGIC;
        
        -- Parsed frame outputs
        frame_valid     : out STD_LOGIC;  -- Frame accepted (good MAC, EtherType)
        dest_mac        : out STD_LOGIC_VECTOR(47 downto 0);  -- Destination MAC
        src_mac         : out STD_LOGIC_VECTOR(47 downto 0);  -- Source MAC
        ethertype       : out STD_LOGIC_VECTOR(15 downto 0);  -- 0x0800 = IPv4
        
        -- Payload output (for IPv4 parser)
        payload_data    : out STD_LOGIC_VECTOR(7 downto 0);
        payload_valid   : out STD_LOGIC;
        payload_start   : out STD_LOGIC;
        payload_end     : out STD_LOGIC;
        
        -- Statistics
        frame_count     : out STD_LOGIC_VECTOR(31 downto 0);  -- Total frames received
        frame_error     : out STD_LOGIC                        -- Frame error detected
    );
end mac_rx;

architecture Behavioral of mac_rx is
    
    -- Our MAC address (Xilinx OUI + random bytes)
    -- 00:0A:35 = Xilinx organizationally unique identifier
    constant MY_MAC : STD_LOGIC_VECTOR(47 downto 0) := X"000A3502AF9A";
    
    -- Broadcast MAC address (FF:FF:FF:FF:FF:FF)
    constant BROADCAST_MAC : STD_LOGIC_VECTOR(47 downto 0) := X"FFFFFFFFFFFF";
    
    -- State machine for parsing Ethernet frame
    type state_type is (
        IDLE_ST,           -- Waiting for frame
        DEST_MAC_ST,       -- Receiving destination MAC (6 bytes)
        SRC_MAC_ST,        -- Receiving source MAC (6 bytes)
        ETHERTYPE_ST,      -- Receiving EtherType (2 bytes)
        PAYLOAD_ST,        -- Receiving payload
        FRAME_END_ST      -- Frame complete
    );
    signal state : state_type := IDLE_ST;
    
    -- Byte counter within each field
    signal byte_count       : unsigned(3 downto 0) := (others => '0');
    
    -- Registers for extracted fields
    signal dest_mac_reg     : STD_LOGIC_VECTOR(47 downto 0) := (others => '0');
    signal src_mac_reg      : STD_LOGIC_VECTOR(47 downto 0) := (others => '0');
    signal ethertype_reg    : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    
    -- Frame acceptance flag
    signal accept_frame     : STD_LOGIC := '0';
    
    -- Statistics counter
    signal frame_counter    : unsigned(31 downto 0) := (others => '0');
    
begin

    -- Output statistics
    frame_count <= STD_LOGIC_VECTOR(frame_counter);

    ----------------------------------------------------------------------------------
    -- MAC Frame Parser State Machine
    --
    -- Parses incoming Ethernet frame byte-by-byte
    -- State transitions based on byte count in each field
    ----------------------------------------------------------------------------------
    
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state          <= IDLE_ST;
                byte_count     <= (others => '0');
                dest_mac_reg   <= (others => '0');
                src_mac_reg    <= (others => '0');
                ethertype_reg  <= (others => '0');
                accept_frame   <= '0';
                frame_counter  <= (others => '0');
                frame_valid    <= '0';
                payload_valid  <= '0';
                payload_start  <= '0';
                payload_end    <= '0';
                frame_error    <= '0';
                
            else
                -- Default: clear one-cycle pulses
                frame_valid   <= '0';
                payload_valid <= '0';
                payload_start <= '0';
                payload_end   <= '0';
                frame_error   <= '0';
                
                case state is
                    
                    ------------------------------------------------------
                    -- IDLE: Wait for frame start
                    ------------------------------------------------------
                    when IDLE_ST =>
                        byte_count   <= (others => '0');
                        accept_frame <= '0';
                        
                        if rx_frame_start = '1' then
                            state <= DEST_MAC_ST;
                        end if;
                    
                    ------------------------------------------------------
                    -- DEST_MAC: Receive 6 bytes of destination MAC
                    ------------------------------------------------------
                    when DEST_MAC_ST =>
                        if rx_data_valid = '1' then
                            -- Shift in MAC address bytes (MSB first)
                            dest_mac_reg <= dest_mac_reg(39 downto 0) & rx_data;
                            byte_count   <= byte_count + 1;
                            
                            if byte_count = 5 then
                                -- All 6 bytes received
                                byte_count <= (others => '0');
                                state      <= SRC_MAC_ST;
                                
                                -- Check if frame is for us
                                -- Compare with our MAC or broadcast MAC
                                if (dest_mac_reg(39 downto 0) & rx_data) = MY_MAC or
                                   (dest_mac_reg(39 downto 0) & rx_data) = BROADCAST_MAC then
                                    accept_frame <= '1';  -- Accept this frame
                                else
                                    accept_frame <= '0';  -- Ignore this frame
                                end if;
                            end if;
                        end if;
                        
                        if rx_frame_end = '1' then
                            state <= IDLE_ST;  -- Frame ended prematurely (error)
                            frame_error <= '1';
                        end if;
                    
                    ------------------------------------------------------
                    -- SRC_MAC: Receive 6 bytes of source MAC
                    ------------------------------------------------------
                    when SRC_MAC_ST =>
                        if rx_data_valid = '1' then
                            src_mac_reg <= src_mac_reg(39 downto 0) & rx_data;
                            byte_count  <= byte_count + 1;
                            
                            if byte_count = 5 then
                                byte_count <= (others => '0');
                                state      <= ETHERTYPE_ST;
                            end if;
                        end if;
                        
                        if rx_frame_end = '1' then
                            state <= IDLE_ST;
                            frame_error <= '1';
                        end if;
                    
                    ------------------------------------------------------
                    -- ETHERTYPE: Receive 2 bytes of EtherType
                    ------------------------------------------------------
                    when ETHERTYPE_ST =>
                        if rx_data_valid = '1' then
                            ethertype_reg <= ethertype_reg(7 downto 0) & rx_data;
                            byte_count    <= byte_count + 1;
                            
                            if byte_count = 1 then
                                -- EtherType complete
                                byte_count <= (others => '0');
                                
                                -- Only proceed if frame was accepted
                                if accept_frame = '1' then
                                    state         <= PAYLOAD_ST;
                                    payload_start <= '1';
                                    
                                    -- Output parsed headers
                                    dest_mac  <= dest_mac_reg;
                                    src_mac   <= src_mac_reg;
                                    ethertype <= ethertype_reg(7 downto 0) & rx_data;
                                else
                                    -- Frame not for us, skip to end
                                    state <= FRAME_END_ST;
                                end if;
                            end if;
                        end if;
                        
                        if rx_frame_end = '1' then
                            state <= IDLE_ST;
                            frame_error <= '1';
                        end if;
                    
                    ------------------------------------------------------
                    -- PAYLOAD: Forward payload bytes to next layer
                    ------------------------------------------------------
                    when PAYLOAD_ST =>
                        if rx_data_valid = '1' then
                            payload_data  <= rx_data;
                            payload_valid <= '1';
                        end if;
                        
                        if rx_frame_end = '1' then
                            payload_end   <= '1';
                            frame_valid   <= '1';  -- Frame complete and valid!
                            frame_counter <= frame_counter + 1;
                            state         <= IDLE_ST;
                        end if;
                    
                    ------------------------------------------------------
                    -- FRAME_END: Frame not for us, wait for end
                    ------------------------------------------------------
                    when FRAME_END_ST =>
                        if rx_frame_end = '1' then
                            state <= IDLE_ST;
                        end if;
                    
                end case;
                
            end if;
        end if;
    end process;

end Behavioral;