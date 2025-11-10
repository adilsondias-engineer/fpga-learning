--------------------------------------------------------------------------------
-- Module: async_fifo
-- Description: Asynchronous FIFO with gray code pointers for clock domain crossing
--              Parameterized width and depth
--
-- Features:
--   - Dual-clock operation (independent read/write clocks)
--   - Gray code pointer synchronization for CDC
--   - Configurable data width and depth
--   - Full and empty flags
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity async_fifo is
    Generic (
        DATA_WIDTH : integer := 128;
        FIFO_DEPTH : integer := 256  -- Must be power of 2
    );
    Port (
        -- Write clock domain
        wr_clk   : in  std_logic;
        wr_rst   : in  std_logic;
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_full  : out std_logic;

        -- Read clock domain
        rd_clk   : in  std_logic;
        rd_rst   : in  std_logic;
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_empty : out std_logic
    );
end async_fifo;

architecture Behavioral of async_fifo is

    -- Calculate address width from depth
    constant ADDR_WIDTH : integer := integer(ceil(log2(real(FIFO_DEPTH))));

    -- FIFO memory
    type fifo_mem_type is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_mem : fifo_mem_type := (others => (others => '0'));

    -- Write domain signals
    signal wr_ptr : unsigned(ADDR_WIDTH downto 0) := (others => '0');  -- Extra bit for full/empty distinction
    signal wr_ptr_gray : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_ptr_gray_sync1 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_ptr_gray_sync2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_ptr_gray_wr : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_ptr_gray_wr_sync1 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_ptr_gray_wr_sync2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');

    -- Read domain signals
    signal rd_ptr : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_ptr_gray : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_ptr_gray_rd : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_ptr_gray_rd_sync1 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_ptr_gray_rd_sync2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');

    signal wr_full_int : std_logic := '0';
    signal rd_empty_int : std_logic := '1';
    -- Function to convert binary to gray code
    function bin_to_gray(bin : unsigned) return unsigned is
        variable gray : unsigned(bin'range);
    begin
        gray := bin xor shift_right(bin, 1);
        return gray;
    end function;

begin

    -- Write clock domain
    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_rst = '1' then
                wr_ptr <= (others => '0');
                wr_ptr_gray <= (others => '0');
            else
                -- Synchronize read pointer from read domain (2FF synchronizer)
                rd_ptr_gray_wr_sync1 <= rd_ptr_gray;
                rd_ptr_gray_wr_sync2 <= rd_ptr_gray_wr_sync1;
                rd_ptr_gray_wr <= rd_ptr_gray_wr_sync2;

                -- Write to FIFO
                if wr_en = '1' and wr_full_int = '0' then
                    fifo_mem(to_integer(wr_ptr(ADDR_WIDTH-1 downto 0))) <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                    wr_ptr_gray <= bin_to_gray(wr_ptr + 1);
                end if;
            end if;
        end if;
    end process;

    -- Full flag generation (in write clock domain)
    -- FIFO is full when write pointer catches up to read pointer
    wr_full_int <= '1' when (wr_ptr_gray = (rd_ptr_gray_wr xor
                                         (to_unsigned(1, ADDR_WIDTH+1) sll ADDR_WIDTH) xor
                                         (to_unsigned(1, ADDR_WIDTH+1) sll (ADDR_WIDTH-1)))) else '0';
    wr_full <= wr_full_int;
    -- Read clock domain
    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_rst = '1' then
                rd_ptr <= (others => '0');
                rd_ptr_gray <= (others => '0');
                rd_data <= (others => '0');
            else
                -- Synchronize write pointer from write domain (2FF synchronizer)
                wr_ptr_gray_rd_sync1 <= wr_ptr_gray;
                wr_ptr_gray_rd_sync2 <= wr_ptr_gray_rd_sync1;
                wr_ptr_gray_rd <= wr_ptr_gray_rd_sync2;

                -- Read from FIFO
                if rd_en = '1' and rd_empty_int = '0' then
                    rd_data <= fifo_mem(to_integer(rd_ptr(ADDR_WIDTH-1 downto 0)));
                    rd_ptr <= rd_ptr + 1;
                    rd_ptr_gray <= bin_to_gray(rd_ptr + 1);
                end if;
            end if;
        end if;
    end process;

    -- Empty flag generation (in read clock domain)
    -- FIFO is empty when read pointer catches up to write pointer
    rd_empty_int <= '1' when (rd_ptr_gray = wr_ptr_gray_rd) else '0';
    rd_empty <= rd_empty_int;

end Behavioral;
