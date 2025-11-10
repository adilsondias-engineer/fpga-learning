--------------------------------------------------------------------------------
-- Package: hex_string_pkg
-- Description: Helper package for converting std_logic_vector to hex strings
--              Provides to_hex_string function for testbenches
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package hex_string_pkg is
    function to_hex_string(slv : std_logic_vector) return string;
end package hex_string_pkg;

package body hex_string_pkg is

    function to_hex_string(slv : std_logic_vector) return string is
        variable result_len : integer := (slv'length + 3) / 4;
        variable result : string(1 to result_len);
        variable vec_norm : std_logic_vector(slv'length - 1 downto 0);
        variable int_val : unsigned(63 downto 0);
        variable temp_int : integer;
        variable hex_chars : string(1 to 16) := "0123456789ABCDEF";
    begin
        vec_norm := slv;
        
        -- Handle vectors up to 64 bits
        if slv'length <= 64 then
            -- Convert to unsigned integer
            int_val := resize(unsigned(vec_norm), 64);
            
            -- Extract hex digits from LSB to MSB
            for i in 0 to result_len - 1 loop
                temp_int := to_integer(int_val mod 16);
                int_val := int_val / 16;
                -- Store in reverse order (MSB first in result string)
                result(result_len - i) := hex_chars(temp_int + 1);
            end loop;
        else
            -- For very large vectors, return placeholder
            for i in 1 to result_len loop
                result(i) := '?';
            end loop;
        end if;
        
        return result;
    end function;

end package body hex_string_pkg;
