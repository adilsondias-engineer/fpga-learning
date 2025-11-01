library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rotary_encoder is
    Port (
        clk         : in  STD_LOGIC;
        rst         : in  STD_LOGIC;
        
        -- Encoder inputs
        encoder_a   : in  STD_LOGIC;  -- CLK pin
        encoder_b   : in  STD_LOGIC;  -- DT pin
        
        -- Outputs
        cw_pulse    : out STD_LOGIC;  -- Clockwise rotation detected
        ccw_pulse   : out STD_LOGIC   -- Counter-clockwise rotation detected
    );
end rotary_encoder;

architecture Behavioral of rotary_encoder is
    
    -- Synchronizer for metastability protection (3-stage shift register)
    signal a_sync : STD_LOGIC_VECTOR(2 downto 0) := "000";
    signal b_sync : STD_LOGIC_VECTOR(2 downto 0) := "000";
    
    -- Edge detection
    signal a_prev : STD_LOGIC := '0';
    signal b_prev : STD_LOGIC := '0';
    
    -- State machine for quadrature decoding
    type state_type is (IDLE, CW_1, CW_2, CW_3, CCW_1, CCW_2, CCW_3);
    signal state : state_type := IDLE;
    
begin
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset synchronizers and state
                a_sync <= "000";
                b_sync <= "000";
                a_prev <= '0';
                b_prev <= '0';
                state <= IDLE;
                cw_pulse <= '0';
                ccw_pulse <= '0';
                
            else
                -- Default: no pulses
                cw_pulse <= '0';
                ccw_pulse <= '0';
                
                -- 3-stage synchronizer for metastability protection
                -- This is critical for asynchronous inputs!
                a_sync <= a_sync(1 downto 0) & encoder_a;
                b_sync <= b_sync(1 downto 0) & encoder_b;
                
                -- Store previous values for edge detection
                a_prev <= a_sync(2);
                b_prev <= b_sync(2);
                
                -- Quadrature decoding state machine
                -- Detects the sequence of transitions to determine direction
                case state is
                    when IDLE =>
                        -- Wait for either signal to rise
                        if a_sync(2) = '1' and a_prev = '0' then
                            -- A rose first -> might be clockwise
                            if b_sync(2) = '0' then
                                state <= CW_1;
                            end if;
                        elsif b_sync(2) = '1' and b_prev = '0' then
                            -- B rose first -> might be counter-clockwise
                            if a_sync(2) = '0' then
                                state <= CCW_1;
                            end if;
                        end if;
                    
                    when CW_1 =>
                        -- In CW sequence, waiting for B to rise
                        if b_sync(2) = '1' and b_prev = '0' then
                            state <= CW_2;
                        elsif a_sync(2) = '0' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                    when CW_2 =>
                        -- Waiting for A to fall
                        if a_sync(2) = '0' and a_prev = '1' then
                            state <= CW_3;
                        elsif b_sync(2) = '0' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                    when CW_3 =>
                        -- Waiting for B to fall (complete CW rotation)
                        if b_sync(2) = '0' and b_prev = '1' then
                            cw_pulse <= '1';  -- Valid CW click detected!
                            state <= IDLE;
                        elsif a_sync(2) = '1' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                    when CCW_1 =>
                        -- In CCW sequence, waiting for A to rise
                        if a_sync(2) = '1' and a_prev = '0' then
                            state <= CCW_2;
                        elsif b_sync(2) = '0' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                    when CCW_2 =>
                        -- Waiting for B to fall
                        if b_sync(2) = '0' and b_prev = '1' then
                            state <= CCW_3;
                        elsif a_sync(2) = '0' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                    when CCW_3 =>
                        -- Waiting for A to fall (complete CCW rotation)
                        if a_sync(2) = '0' and a_prev = '1' then
                            ccw_pulse <= '1';  -- Valid CCW click detected!
                            state <= IDLE;
                        elsif b_sync(2) = '1' then
                            state <= IDLE;  -- Lost sequence
                        end if;
                        
                end case;
            end if;
        end if;
    end process;
    
end Behavioral;