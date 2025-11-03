# Vivado build script for UART transmitter project

# Open the project
open_project 05-uart-transmitter.xpr

# Reset runs to ensure clean build
reset_run synth_1
reset_run impl_1

# Launch synthesis
puts "Starting synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis did not complete successfully!"
    exit 1
}

puts "Synthesis completed successfully!"

# Launch implementation
puts "Starting implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation did not complete successfully!"
    exit 1
}

puts "Implementation completed successfully!"

# Generate bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream generation complete!"
puts "Build finished successfully!"

# Close project
close_project
