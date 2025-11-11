--------------------------------------------------------------------------------
-- Module: price_level_table
-- Description: BRAM-based price level aggregation table
--
-- Storage: 256 entries × 66 bits = ~2 KB (1 BRAM36 block)
-- Organization: [0-127] = Bids (descending), [128-255] = Asks (ascending)
--
-- Operations:
--   ADD_SHARES    : Increment shares at price level
--   REMOVE_SHARES : Decrement shares at price level
--   LOOKUP_LEVEL  : Read price level data
--   CLEAR_LEVEL   : Set level to zero (when no orders remain)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.order_book_pkg.all;

entity price_level_table is
    Port (
        clk     : in  std_logic;
        rst     : in  std_logic;

        -- Command interface
        cmd_valid   : in  std_logic;
        cmd_type    : in  std_logic_vector(1 downto 0);  -- 00=ADD, 01=REMOVE, 10=LOOKUP, 11=CLEAR
        cmd_addr    : in  std_logic_vector(PRICE_ADDR_WIDTH-1 downto 0);
        cmd_price   : in  std_logic_vector(31 downto 0);
        cmd_shares  : in  std_logic_vector(31 downto 0);
        cmd_side    : in  std_logic;  -- 0=Buy, 1=Sell

        -- Read result (2-cycle latency)
        rd_level    : out price_level_t;
        rd_valid    : out std_logic;

        -- Statistics
        bid_level_count : out unsigned(7 downto 0);  -- Active bid levels
        ask_level_count : out unsigned(7 downto 0)   -- Active ask levels
    );
end price_level_table;

architecture Behavioral of price_level_table is

    -- Command type constants
    constant CMD_ADD    : std_logic_vector(1 downto 0) := "00";
    constant CMD_REMOVE : std_logic_vector(1 downto 0) := "01";
    constant CMD_LOOKUP : std_logic_vector(1 downto 0) := "10";
    constant CMD_CLEAR  : std_logic_vector(1 downto 0) := "11";

    -- BRAM storage (expanded to 82 bits for full 32-bit price)
    type bram_t is array (0 to MAX_PRICE_LEVELS-1) of std_logic_vector(81 downto 0);
    signal bram : bram_t := (others => (others => '0'));

    -- Read pipeline
    signal rd_data_stage1 : std_logic_vector(81 downto 0) := (others => '0');
    signal rd_data_stage2 : std_logic_vector(81 downto 0) := (others => '0');
    signal rd_valid_stage1 : std_logic := '0';
    signal rd_valid_stage2 : std_logic := '0';
    signal rd_valid_counter : integer range 0 to 3 := 0;  -- Track valid duration

    -- Level count tracking
    signal bid_count : unsigned(7 downto 0) := (others => '0');
    signal ask_count : unsigned(7 downto 0) := (others => '0');

    -- Xilinx BRAM inference
    attribute ram_style : string;
    attribute ram_style of bram : signal is "block";

begin

    -- Outputs
    rd_level <= slv_to_price_level(rd_data_stage2);
    rd_valid <= rd_valid_stage2;
    bid_level_count <= bid_count;
    ask_level_count <= ask_count;

    ------------------------------------------------------------------------
    -- BRAM Access Process (Read-Modify-Write)
    ------------------------------------------------------------------------
    process(clk)
        variable addr : integer;
        variable level_slv : std_logic_vector(81 downto 0);  -- Updated to 82 bits
        variable level : price_level_t;
        variable new_level : price_level_t;
        variable new_shares : unsigned(31 downto 0);
        variable new_count : unsigned(15 downto 0);
        variable prev_valid : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset level counts only
                -- BRAM is initialized to all zeros via signal initialization
                bid_count <= (others => '0');
                ask_count <= (others => '0');
            elsif cmd_valid = '1' then
                addr := to_integer(unsigned(cmd_addr));

                -- Read current level
                level_slv := bram(addr);
                level := slv_to_price_level(level_slv);
                prev_valid := level.valid;

                case cmd_type is
                    when CMD_ADD =>
                        -- Add shares to level
                        if level.valid = '0' then
                            -- Create new level
                            new_level.price := cmd_price;
                            new_level.total_shares := cmd_shares;
                            new_level.order_count := x"0001";
                            new_level.side := cmd_side;
                            new_level.valid := '1';
                            
                            -- Update level count (new level created)
                            if cmd_side = '0' then
                                bid_count <= bid_count + 1;
                            else
                                ask_count <= ask_count + 1;
                            end if;
                        else
                            -- Add to existing level
                            -- Check if side matches (if not, treat as new level - stale data cleanup)
                            if level.side /= cmd_side then
                                -- Side mismatch - stale data at this address, overwrite it
                                -- This should never happen in normal operation (addresses are side-specific)
                                -- But handle gracefully for stale data cleanup
                                new_level.price := cmd_price;
                                new_level.total_shares := cmd_shares;
                                new_level.order_count := x"0001";
                                new_level.side := cmd_side;
                                new_level.valid := '1';
                                
                                -- Only increment new side count if it's currently 0
                                -- Don't decrement old side - we can't trust stale data's count state
                                if cmd_side = '0' and bid_count = 0 then
                                    bid_count <= bid_count + 1;
                                elsif cmd_side = '1' and ask_count = 0 then
                                    ask_count <= ask_count + 1;
                                end if;
                            else
                                -- Side matches - add to existing level
                                -- Check if this level is actually counted (safety check for stale data)
                                -- If count is 0 but level exists, it's stale data - create new level
                                if (cmd_side = '0' and bid_count = 0) or (cmd_side = '1' and ask_count = 0) then
                                    -- Stale data: level exists but not counted, treat as new level
                                    new_level.price := cmd_price;
                                    new_level.total_shares := cmd_shares;
                                    new_level.order_count := x"0001";
                                    new_level.side := cmd_side;
                                    new_level.valid := '1';
                                    
                                    -- Increment count (this is actually a new level)
                                    if cmd_side = '0' then
                                        bid_count <= bid_count + 1;
                                    else
                                        ask_count <= ask_count + 1;
                                    end if;
                                else
                                    -- Normal case: add to existing counted level
                                    new_level.side := level.side;
                                    new_shares := unsigned(level.total_shares) + unsigned(cmd_shares);
                                    new_count := unsigned(level.order_count) + 1;

                                    new_level.price := level.price;
                                    new_level.total_shares := std_logic_vector(new_shares);
                                    new_level.order_count := std_logic_vector(new_count);
                                    new_level.valid := '1';
                                    -- No count update - level already exists and is counted
                                end if;
                            end if;
                        end if;

                        -- Write back
                        bram(addr) <= price_level_to_slv(new_level);

                    when CMD_REMOVE =>
                        -- Remove shares from level
                        if level.valid = '1' then
                            new_shares := unsigned(level.total_shares);
                            if new_shares >= unsigned(cmd_shares) then
                                new_shares := new_shares - unsigned(cmd_shares);
                            else
                                new_shares := (others => '0');
                            end if;

                            new_count := unsigned(level.order_count);
                            if new_count > 0 then
                                new_count := new_count - 1;
                            end if;

                            -- If no shares or orders remain, invalidate level
                            if new_shares = 0 or new_count = 0 then
                                new_level.valid := '0';
                                new_level.total_shares := (others => '0');
                                new_level.order_count := (others => '0');
                            else
                                new_level.valid := '1';
                                new_level.total_shares := std_logic_vector(new_shares);
                                new_level.order_count := std_logic_vector(new_count);
                            end if;

                            new_level.price := level.price;
                            new_level.side := level.side;

                            -- Write back
                            bram(addr) <= price_level_to_slv(new_level);
                        end if;

                    when CMD_LOOKUP =>
                        -- Read-only, no write
                        null;

                    when CMD_CLEAR =>
                        -- Clear level
                        bram(addr) <= (others => '0');

                    when others =>
                        null;
                end case;

                -- Update level counts based on the NEW level state (after command processing)
                -- Note: CMD_ADD level count update is now handled inside the CMD_ADD case
                if cmd_type = CMD_REMOVE or cmd_type = CMD_CLEAR then
                    -- Use prev_valid (old state) and new_level.valid (new state) to detect changes
                    -- Don't re-read from BRAM - use the level we just modified
                    if cmd_type = CMD_REMOVE then
                        -- CMD_REMOVE may invalidate a level
                        if prev_valid = '1' and new_level.valid = '0' then
                            -- Level removed
                            if cmd_side = '0' then
                                if bid_count > 0 then
                                    bid_count <= bid_count - 1;
                                end if;
                            else
                                if ask_count > 0 then
                                    ask_count <= ask_count - 1;
                                end if;
                            end if;
                        end if;
                    elsif cmd_type = CMD_CLEAR then
                        -- CMD_CLEAR always removes a level if it existed
                        if prev_valid = '1' then
                            -- Level removed
                            if cmd_side = '0' then
                                if bid_count > 0 then
                                    bid_count <= bid_count - 1;
                                end if;
                            else
                                if ask_count > 0 then
                                    ask_count <= ask_count - 1;
                                end if;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- Read Pipeline (for LOOKUP commands)
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rd_data_stage1 <= (others => '0');
                rd_data_stage2 <= (others => '0');
                rd_valid_stage1 <= '0';
                rd_valid_stage2 <= '0';
                rd_valid_counter <= 0;
            else
                -- BRAM read on LOOKUP command
                if cmd_valid = '1' and cmd_type = CMD_LOOKUP then
                    rd_data_stage1 <= bram(to_integer(unsigned(cmd_addr)));
                    rd_valid_counter <= 2;  -- Hold valid for 2 cycles
                end if;

                -- Pipeline stage 2
                rd_data_stage2 <= rd_data_stage1;

                -- Manage rd_valid with counter for precise 2-cycle pulse
                if rd_valid_counter > 0 then
                    rd_valid_stage1 <= '1';
                    rd_valid_stage2 <= '1';
                    rd_valid_counter <= rd_valid_counter - 1;
                else
                    rd_valid_stage1 <= '0';
                    rd_valid_stage2 <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
