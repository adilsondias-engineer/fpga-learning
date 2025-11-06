# UDP Parser Simulation Script
# Run in Vivado batch mode: vivado -mode batch -source simulate.tcl

# IP Parser Simulation Script
# Run in Vivado batch mode

# Create project in memory (no .xpr file)
#create_project -in_memory -part xc7a100tcsg324-1

# Add source files
#add_files -norecurse {
#    src/ip_parser.vhd
#}

# Add testbench
#add_files -fileset sim_1 -norecurse {
#    test/ip_parser_tb.vhd
#}

# Set testbench as top
#set_property top ip_parser_tb [get_filesets sim_1]
#set_property top_lib xil_defaultlib [get_filesets sim_1]

set project_dir [lindex $argv 0]

# Find .xpr file in the project directory
set xpr_files [glob -nocomplain -directory $project_dir *.xpr]
if { [llength $xpr_files] == 0 } {
    puts "ERROR: No .xpr file found in directory: $project_dir"
    exit 1
}

set project_file [lindex $xpr_files 0]
puts "=========================================="
puts "Building project: $project_file"
puts "=========================================="


# Open the project
open_project $project_file

# Set testbench as top
set_property top udp_parser_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch simulation
puts "Launching simulation..."
launch_simulation

# Run for sufficient time to complete all tests
#puts "Running simulation for 100 microseconds..."
restart
run 2500 ns

# Close simulation
close_sim

puts "========================================"
puts "Simulation Complete"
puts "========================================"
# puts ""
# puts "Check transcript above for test results"
# puts "Look for lines containing:"
# puts "  - 'PASS: <test_name>'"
# puts "  - 'FAIL: <test_name>'"
# puts "  - 'TEST SUMMARY'"
# puts ""
# puts "Expected results:"
# puts "  - Test 1: Valid UDP port 80       -> PASS"
# puts "  - Test 2: Valid UDP port 53       -> PASS"
# puts "  - Test 3: Checksum disabled       -> PASS"
# puts "  - Test 4: TCP packet ignored      -> PASS"
# puts "  - Test 5: Length mismatch         -> PASS (error detected)"
# puts "  - Test 6: Minimum UDP             -> PASS"
# puts ""
# puts "To view waveforms:"
# puts "  1. Open Vivado GUI: vivado"
# puts "  2. Open project (or File > New Project)"
# puts "  3. Add source files: src/udp_parser.vhd"
# puts "  4. Add testbench: test/udp_parser_tb.vhd"
# puts "  5. Flow > Run Simulation > Run Behavioral Simulation"
# puts "  6. Add signals to waveform window:"
# puts "     - state"
# puts "     - udp_valid"
# puts "     - udp_src_port"
# puts "     - udp_dst_port"
# puts "     - udp_length"
# puts "     - udp_checksum_ok"
# puts "     - udp_length_err"
# puts "     - payload_valid"
# puts "========================================"

exit