# Add all source files to Project 7
#
# Usage: vivado -mode batch -source add_sources.tcl

# Open the project
open_project "j:/work/projects/fpga-learning/07-itch-parser/07-itch-parser.xpr"

# Remove all existing source files (clean slate)
remove_files [get_files]

# Add all VHDL source files
add_files -fileset sources_1 [glob j:/work/projects/fpga-learning/07-itch-parser/src/*.vhd]

# Add constraint file
add_files -fileset constrs_1 j:/work/projects/fpga-learning/07-itch-parser/constraints/arty_a7_100t_mii.xdc

# Set mii_eth_top as the top-level entity
set_property top mii_eth_top [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

# Save project
save_project_as -force 07-itch-parser j:/work/projects/fpga-learning/07-itch-parser

puts "=========================================="
puts "All source files added to project!"
puts "Top-level set to: mii_eth_top"
puts "=========================================="

close_project
