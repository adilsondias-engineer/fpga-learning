# Program FPGA script

# Open hardware manager
open_hw_manager

# Connect to hardware server
connect_hw_server -allow_non_jtag

# Get the first available hardware target
set hw_target [lindex [get_hw_targets] 0]
if {$hw_target == ""} {
    puts "ERROR: No hardware targets found!"
    exit 1
}

puts "Found hardware target: $hw_target"
current_hw_target $hw_target
open_hw_target

# Get the first device
set hw_device [lindex [get_hw_devices] 0]
if {$hw_device == ""} {
    puts "ERROR: No hardware devices found!"
    exit 1
}

puts "Found hardware device: $hw_device"
current_hw_device $hw_device

# Program the device with the bitstream
set bitstream "05-uart-transmitter.runs/impl_1/uart_echo_top.bit"
puts "Programming device with: $bitstream"
set_property PROGRAM.FILE $bitstream $hw_device
program_hw_devices $hw_device

puts "Programming completed!"

# Close connections
close_hw_target
disconnect_hw_server
close_hw_manager

puts "FPGA programmed successfully!"
