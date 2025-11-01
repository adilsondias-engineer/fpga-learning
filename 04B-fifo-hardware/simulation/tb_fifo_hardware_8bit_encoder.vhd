library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fifo_hardware_8bit_encoder is
end tb_fifo_hardware_8bit_encoder;

architecture Behavioral of tb_fifo_hardware_8bit_encoder is
    
    component fifo_hardware_8bit_encoder is
        Port (
            clk        : in  STD_LOGIC;
            btn        : in  STD_LOGIC_VECTOR(3 downto 0);
            encoder_a  : in  STD_LOGIC;
            encoder_b  : in  STD_LOGIC;
            encoder_sw : in  STD_LOGIC;
            led        : out STD_LOGIC_VECTOR(3 downto 0);
            led_ext    : out STD_LOGIC_VECTOR(7 downto 0);
            buzzer     : out STD_LOGIC;
            led0_r     : out STD_LOGIC;
            led0_g     : out STD_LOGIC;
            led0_b     : out STD_LOGIC
        );
    end component;
    
    constant CLK_PERIOD : time := 10 ns;
    
    signal clk        : STD_LOGIC := '0';
    signal btn        : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal encoder_a  : STD_LOGIC := '0';
    signal encoder_b  : STD_LOGIC := '0';
    signal encoder_sw : STD_LOGIC := '0';
    signal led        : STD_LOGIC_VECTOR(3 downto 0);
    signal led_ext    : STD_LOGIC_VECTOR(7 downto 0);
    signal buzzer     : STD_LOGIC;
    signal led0_r     : STD_LOGIC;
    signal led0_g     : STD_LOGIC;
    signal led0_b     : STD_LOGIC;
    
    signal sim_done : boolean := false;

    
    -- Simplified encoder rotation procedure
    procedure rotate_cw(
        signal encoder_a : out std_logic;
        signal encoder_b : out std_logic;
        count : integer) is
    begin
        for i in 1 to count loop
            encoder_a <= '0'; encoder_b <= '0'; wait for 1 ms;
            encoder_a <= '1'; encoder_b <= '0'; wait for 1 ms;
            encoder_a <= '1'; encoder_b <= '1'; wait for 1 ms;
            encoder_a <= '0'; encoder_b <= '1'; wait for 1 ms;
            encoder_a <= '0'; encoder_b <= '0'; wait for 1 ms;
        end loop;
    end procedure;
    
    -- Press encoder button
    procedure press_encoder(
        signal encoder_sw : out std_logic) is
    begin
        encoder_sw <= '1';
        wait for 100 ms;  -- Hold for debounce time
        encoder_sw <= '0';
        wait for 50 ms;
    end procedure;
    -- Press BTN1 (read)
    procedure press_btn1(
        signal btn : out std_logic_vector(3 downto 0)) is
    begin
        btn(1) <= '1';
        wait for 100 ms;
        btn(1) <= '0';
        wait for 50 ms;
    end procedure;
  
    
begin
    
    DUT: fifo_hardware_8bit_encoder
        port map (
            clk        => clk,
            btn        => btn,
            encoder_a  => encoder_a,
            encoder_b  => encoder_b,
            encoder_sw => encoder_sw,
            led        => led,
            led_ext    => led_ext,
            buzzer     => buzzer,
            led0_r     => led0_r,
            led0_g     => led0_g,
            led0_b     => led0_b
        );
    
    -- Clock generation
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    -- Test stimulus
    stimulus: process
    begin
        -- Reset
        btn(2) <= '1';
        wait for 200 ms;
        btn(2) <= '0';
        wait for 100 ms;
        
        assert led0_g = '1' report "ERROR: Should be empty (green)" severity error;
        rotate_cw(encoder_a, encoder_b, 5);  -- Rotate to value 5
        -- Scenario: Write two values
        report "TEST: Write 0x05";
        assert led_ext = x"05" report "ERROR: LED should show 0x05" severity error;
        
        press_encoder(encoder_sw);  -- Write to FIFO
        rotate_cw(encoder_a, encoder_b, 5);  -- Rotate to value 10
        press_encoder(encoder_sw);  -- Write to FIFO
        rotate_cw(encoder_a, encoder_b, 5);  -- Rotate to value 10
        
        report "TEST: Write 0x0A";
        assert led_ext = x"0A" report "ERROR: LED should show 0x0A" severity error;
        
        press_encoder(encoder_sw);  -- Write to FIFO
        wait for 100 ms;
        press_encoder(encoder_sw);  -- Write to FIFO
        -- Read values back
        report "TEST: Read first value";
        press_btn1(btn);
        wait for 100 ms;
        press_btn1(btn);
        wait for 100 ms;
        report "TEST: Read second value";
        press_btn1(btn);
        wait for 100 ms;
        press_btn1(btn);
        wait for 100 ms;
        assert led_ext = x"0A" report "ERROR: Should read 0x0A" severity error;
        
        report "All tests run successfully!";
        sim_done <= true;
        wait;
    end process;
    
end Behavioral;