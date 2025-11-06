# Standalone simulation script
# Compile source files directly

# Compile UDP parser
exec xvhdl -work xil_defaultlib "../src/udp_parser.vhd"

# Compile testbench
exec xvhdl -work xil_defaultlib "../test/udp_parser_tb.vhd"

# Elaborate
exec xelab -debug typical -top udp_parser_tb -snapshot udp_parser_tb_snap

# Simulate
exec xsim udp_parser_tb_snap -runall

quit
