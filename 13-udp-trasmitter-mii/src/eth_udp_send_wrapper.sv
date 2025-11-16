// VHDL-compatible wrapper for eth_udp_send module
// Flattens SystemVerilog interfaces to individual ports

`timescale 1ns / 1ps

module eth_udp_send_wrapper #(
    parameter int unsigned CLK_RATIO = 4,
    parameter int unsigned MAX_DATA_BYTES = 548,
    parameter int unsigned MIN_DATA_BYTES = 256,
    parameter int unsigned POWER_UP_CYCLES = 5_000_000,
    parameter int unsigned WORD_SIZE_BYTES = 1
) (
    // Standard
    input logic clk,
    input logic rst,

    // Writing data
    input logic wr_en,
    input logic [3:0] wr_d,
    output logic wr_rst_busy,
    output logic wr_full,

    // Clocks
    input logic clk25,

    // Ethernet PHY interface (flattened from IEthPhy)
    output logic eth_ref_clk,
    output logic eth_rstn,
    input logic eth_tx_clk,
    output logic eth_tx_en,
    output logic [3:0] eth_txd,

    // IP/MAC info (flattened from IIpInfo)
    input logic [31:0] ip_src,
    input logic [47:0] mac_src,
    input logic [15:0] udp_src_port,
    input logic [31:0] ip_dst,
    input logic [47:0] mac_dst,
    input logic [15:0] udp_dst_port,

    // Control
    input logic flush,

    // Status
    output logic mac_busy,
    output logic rdy
);

    // Instantiate SystemVerilog interfaces
    IEthPhy eth();
    IIpInfo ip_info();

    // Connect flattened ports to interface
    assign eth.ref_clk = clk25;  // Drive ref_clk from clk25
    assign eth.rstn = ~rst;       // Active low reset
    assign eth.tx_clk = eth_tx_clk;

    // Drive outputs from interface
    assign eth_ref_clk = eth.ref_clk;
    assign eth_rstn = eth.rstn;
    assign eth_tx_en = eth.tx_en;
    assign eth_txd = eth.tx_d;

    // Connect IP info
    assign ip_info.src_ip = ip_src;
    assign ip_info.src_mac = mac_src;
    assign ip_info.src_port = udp_src_port;
    assign ip_info.dst_ip = ip_dst;
    assign ip_info.dst_mac = mac_dst;
    assign ip_info.dst_port = udp_dst_port;

    // Instantiate eth_udp_send with interfaces
    eth_udp_send #(
        .CLK_RATIO(CLK_RATIO),
        .MAX_DATA_BYTES(MAX_DATA_BYTES),
        .MIN_DATA_BYTES(MIN_DATA_BYTES),
        .POWER_UP_CYCLES(POWER_UP_CYCLES),
        .WORD_SIZE_BYTES(WORD_SIZE_BYTES)
    ) eth_udp_send_inst (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_d(wr_d),
        .wr_rst_busy(wr_rst_busy),
        .wr_full(wr_full),
        .clk25(clk25),
        .eth(eth),
        .flush(flush),
        .ip_info(ip_info),
        .mac_busy(mac_busy),
        .rdy(rdy)
    );

endmodule
