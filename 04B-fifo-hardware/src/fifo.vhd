library IEEE;
use IEEE.STD_LOGIC_1164.ALL; 
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo is
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
end fifo;


architecture Behavioral of fifo is

     -- Memory array( implemented as distributed RAM or BRAM)
     type memory_type is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
     signal memory : memory_type := (others => (others => '0'));

     -- Pointers (4 bits for 16 depth FIFO: 0 to 15)
     signal  wr_ptr : unsigned(3 downto 0) := (others => '0'); 
     signal  rd_ptr : unsigned(3 downto 0) := (others => '0');

     -- Counter to keep track of number of elements in FIFO
     signal fifo_count : unsigned(4 downto 0) := (others => '0');

     -- Interal flags
     signal full_i  : std_logic := '0';
     signal empty_i : std_logic := '1';

    
    begin
        -- full and empty detection
        full_i <= '1' when fifo_count = FIFO_DEPTH else '0';
        empty_i <= '1' when fifo_count = 0 else '0';

        -- Output assignments
        full <= full_i;
        empty <= empty_i;
        count <= std_logic_vector(fifo_count);

    --- Main FIFO operation
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                fifo_count <= (others => '0');
                data_out <= (others => '0'); -- Default output when not reading
            else
                -- Write operation
                if wr_en = '1' and full_i = '0' then
                    memory(to_integer(wr_ptr)) <= data_in;
                    wr_ptr <= wr_ptr + 1;
                    
                end if;

                -- Read operation
                if rd_en = '1' and empty_i = '0' then
                    data_out <= memory(to_integer(rd_ptr));
                    rd_ptr <= rd_ptr + 1;
                   
                end if;

                 --Update counter
                 if( wr_en = '1' and full_i = '0') and (rd_en = '0' or empty_i = '1') then
                    -- Only write
                    fifo_count <= fifo_count + 1;
                elsif (rd_en = '1' and empty_i = '0') and (wr_en = '0' or full_i = '1') then
                    -- Only read
                    fifo_count <= fifo_count -1;
                end if;
                --if both read and write are enabled and FIFO is neither full nor empty, count remains the same
            end if;
        end if;        
    end process;
        
    

end Behavioral;