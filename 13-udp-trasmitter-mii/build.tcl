# Build script for UDP Transmitter Project 13
# Runs synthesis, implementation, and bitstream generation

# Open the project
open_project j:/work/projects/fpga-trading-systems/13-udp-trasmitter-mii/13-udp-trasmitter-mii.xpr

# Reset runs to ensure clean build
reset_run synth_1
reset_run impl_1

# Run synthesis
puts "=========================================="
puts "Starting Synthesis..."
puts "=========================================="
launch_runs synth_1
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "Synthesis complete!"

# Run implementation
puts "=========================================="
puts "Starting Implementation..."
puts "=========================================="
launch_runs impl_1
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation complete!"

# Generate bitstream
puts "=========================================="
puts "Generating Bitstream..."
puts "=========================================="
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# Check bitstream generation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Bitstream generation failed!"
    exit 1
}

puts "=========================================="
puts "Build Complete!"
puts "=========================================="
puts "Bitstream: 13-udp-trasmitter-mii.runs/impl_1/udp_tx_top.bit"

# Close project
close_project

exit 0
