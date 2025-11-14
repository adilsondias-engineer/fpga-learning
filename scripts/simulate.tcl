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

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation

# Run for sufficient time to complete all tests
run 50 us

# Close simulation
close_sim

# puts "=========================================="
# puts "Simulation Complete"
# puts "=========================================="
# puts "Check transcript for test results"
# puts "Look for 'Test Summary' section"
# puts ""
# puts "To view waveforms:"
# puts "  1. Open Vivado GUI"
# puts "  2. Open project (or create new)"
# puts "  3. Add source/testbench files"
# puts "  4. Run behavioral simulation"
# puts "  5. Add signals to waveform window"
# puts "=========================================="

exit