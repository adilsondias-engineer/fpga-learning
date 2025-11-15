# Create ILA IP for debugging MII TX
# Run this in Vivado TCL console or via batch mode

# Open project
open_project j:/work/projects/fpga-trading-systems/13-udp-trasmitter-mii/13-udp-trasmitter-mii.xpr

# Create ILA IP
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_0

# Configure ILA
set_property -dict [list \
    CONFIG.C_PROBE7_WIDTH {8} \
    CONFIG.C_PROBE6_WIDTH {4} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_NUM_OF_PROBES {8} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_TRIGIN_EN {false} \
    CONFIG.C_TRIGOUT_EN {false} \
] [get_ips ila_0]

# Generate IP
generate_target all [get_ips ila_0]
create_ip_run [get_ips ila_0]
launch_runs ila_0_synth_1
wait_on_run ila_0_synth_1

puts "ILA IP created successfully"

close_project
