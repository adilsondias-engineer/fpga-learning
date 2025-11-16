`timescale 1ns / 1ps

// NOTE: Technical language generally uses the term "octet" to describe a group
// of 8 bits. This is because the term "bytes" is not actually well defined.
// There is no reason that a byte must be 8 bits. A byte is the smallest
// addressable unit in a system, which historically and practically has been
// designated 8 bits. There is no reason that a byte couldn't be 16, 32, 5,
// 19, or any other number of bits. However, in the implementation of this
// module, it will be assumed that octects and bytes are equivalent and
// interchangeable.

// NOTE: In the specification of the Internet protocols (RFCs), the terminalogy
// is a bit confusing. The RFCs use big-endian format, but the bit labelling is
// different than usual. The RFCs label the MSB as 0, whereas typically the LSB
// is 0. The code uses the format where the LSBs are 0, but the comments which
// reference RFCs use the MSB as 0 to be consistent with them.

/// This is the header of an Ethernet frame.
///
/// # Fields
///
/// *   [dst_mac] is the destination MAC address.
/// *   [src_mac] is the source MAC address.
/// *   [ether_type] indicates the protocol of the packet being sent.
typedef struct packed {
    logic [47:0] dst_mac;
    logic [47:0] src_mac;
    logic [15:0] ether_type;
} MacHeader;

/// According to RFC 791, an IP header has the following format
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +---------------+---------------+---------------+---------------+
/// |Version|  IHL  |     Type      |          Total Length         |
/// +---------------+---------------+---------------+---------------+
/// |         Identification        |Flags|     Fragment Offset     |
/// +---------------+---------------+---------------+---------------+
/// | Time to Live  |    Protocol   |        Header Checksum        |
/// +---------------+---------------+---------------+---------------+
/// |                       Source IP Address                       |
/// +---------------+---------------+---------------+---------------+
/// |                    Destination IP Address                     |
/// +---------------+---------------+---------------+---------------+
///
/// # Fields
///
/// *   [version] indicates the format of internet header.
/// *   [ihl] is the internet header length. This must be at least 5.
/// *   [type_of_service] is the type and quality of service desired.
/// *   [total_length] is the total length of packet including the header and
///     data.
/// *   [identification] is  assigned to help with assembling fragments.
/// *   [flags] is a set of control flags.
/// *   [fragment_offset] indicates where in a datagram the fragment belongs.
/// *   [time_to_live] the time (formally in seconds, practically in hops) that
///     the datagram is allowed to live.
/// *   [protocol] the next level protocol to use.
/// *   [header_checksum] is the checksum that verifies the validity of the
///     IP header.
/// *   [src_ip] is the source IPv4 address.
/// *   [dst_ip] is the destination IPv4 address.
typedef struct packed {
    logic [3:0] version;
    logic [3:0] ihl;
    logic [7:0] type_of_service;
    logic [15:0] total_length;
    logic [15:0] identification;
    logic [2:0] flags;
    logic [12:0] fragment_offset;
    logic [7:0] time_to_live;
    logic [7:0] protocol;
    logic [15:0] header_checksum;
    logic [31:0] src_ip;
    logic [31:0] dst_ip;
} IpHeader;

/// According to RFC 768, the UDP header has the following format
///
///  0      7 8     15 16    23 24    31
/// +--------+--------+--------+--------+
/// |   Source Port   |    Dest Port    |
/// +--------+--------+--------+--------+
/// |     Length      |    Checksum     |
/// +--------+--------+--------+--------+
///
/// # Fields
///
/// *   [src_port] is the number of the source port.
/// *   [dst_port] is the number of the destination port.
/// *   [length] is the length of the packet in bytes inclufing this header.
/// *   [checksum] is the UDP checksum.
typedef struct packed {
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic [15:0] length;
    logic [15:0] checksum;
} UdpHeader;

/// Holds the values needed to describe the source and destination of an IP
/// packet.
///
/// # Ports
///
/// *   [src_ip] is the source IP address.
/// *   [src_mac] is the source MAC address.
/// *   [src_port] is the source port number.
/// *   [dst_ip] is the destination IP address.
/// *   [dst_mac] is the destination MAC address.
/// *   [dst_port] is the destination port number.
///
/// # Mod Ports
///
/// *   [in] is an input port.
interface IIpInfo;
    logic [31:0] src_ip;
    logic [47:0] src_mac;
    logic [15:0] src_port;
    logic [31:0] dst_ip;
    logic [47:0] dst_mac;
    logic [15:0] dst_port;

    modport in(
        input src_ip,
        input src_mac,
        input src_port,
        input dst_ip,
        input dst_mac,
        input dst_port);
endinterface

/// Holds the signals that control the Ethernet PHY.
///
/// # Ports
///
/// *   [eth_ref_clk] is the reference clock input. This must be connected to a
///     25MHz clock source.
/// *   [eth_rstn] is an active low reset. This signal must be asserted for at
///     least 1 µs for a reset event to get triggered.
/// *   [eth_tx_clk] is the clock to transmit data on. This will have two
///     values depending on the mode. In the 10 Mb/s mode, this will be
///     2.5 MHz.In the 100 Mb/s mode, this will be 25 MHz.
/// *   [eth_tx_en] is the transmit enable. This is an active high indicator
///     that the value on [eth_rx_d] is valid.
/// *   [eth_tx_d] is the data to transmit.
///
/// # Mod Ports
///
/// *   [fwd] forwards the ports while preserving the port directions to
///     communicate with the PHY.
interface IEthPhy;
    logic ref_clk;
    logic rstn;
    logic tx_clk;
    logic tx_en;
    logic [3:0] tx_d;

    modport fwd(
        output ref_clk,
        output rstn,
        input tx_clk,
        output tx_en,
        output tx_d);
endinterface

/// This module implements a transmitter for an Ethernet port. This is used to
/// send UDP packets using IPv4.
///
/// This module is optimal for streaming fixed width data. It offers a number
/// guarantees.
///
/// *   The packet alwaus contains an integer number of data points.
/// *   The packet will always have a number of data points between a specified
///     minimum and maximum value so as to not add overhead on small packets or
///     produce packets too large for a network to handle.
///     *   However, this is not true when the module is flushed, which causes
///         all data to be sent.
///
/// Data is written into a FIFO queue as nibbles, and the packets are
/// constructed based on that data. The MAC, IP, and UDP headers and the MAC
/// FCS are automatically generated. The data in the queue is read as nibbles,
/// where one data point is equal to the number of nibbles required to make
/// data of width WORD_SIZE_BYTES (in bytes).
///
/// When a data point is written to the queue, it must be written from most
/// significant byte to least significant byte, with the lower nibble of each
/// byte first. For example, suppose (in hex) 1A2B3C4D is to be written, it
/// should be written as the following nibbles: A1B2C3D4.
///
/// The MAX_DATA_BYTES should not exceeed 548 (though this is not enforced)
/// based on the following reasoning.
///
/// *   RFC 768: a UDP header is 8 bytes.
/// *   RFC 791: the maximum sized internet header is 60 bytes, though only 20
/// *   are used by this module.
/// *   RFC 791: every host must be able to receive a datagram of at least 576
///     bytes.
///
/// These specifications imply that the safest maximum size of a UDP payload is
/// 576 - 20 - 8 = 548 bytes.
///
/// # Notes
///
/// *   Make sure that the [eth.tx_clk] input is constrained as a 25 MHz
///     clock.
///
/// # Parameters
///
/// *   [CLK_RATIO] is the ratio of the rate of [clk] to the rate of [clk25].
///     This value is always rounded up, so formally the value is
///
///         CLK_RATIO = ceil(rate(clk) / rate(clk25))
///
///     This implies a minimum value of 1.
/// *   [MAX_DATA_BYTES] is the maximum number of payload bytes that will be
///     sent in a packet.
/// *   [MIN_DATA_BYTES] is the minimum number of bytes that must exist in the
///     queue before a packet is automatically sent. This is also the minimum
///     number of payload bytes that will be sent in a packet.
/// *   [POWER_UP_CYCLES] is the number of clock cycles to wait at power up
///     before the PHY is ready. This must be at least 167 ms worth of time.
///     The default value is set appropriately for a 25 MHz [clk]. Setting
///     this to 0 disables the wait at powerup, but the PHY will not be
///     initialized properly. Disabling the startup sequence is only really
///     useful in simulation.
/// *   [WORD_SIZE_BYTES] is the number of bytes in a word of data. It is
///     guaranteed that the payload is multiple of this number of bytes. This
///     is also the size of one data point in the payload.
///
/// # Ports
///
/// *   [clk] is the system clock.
/// *   [rst] is the system reset signal.
/// *   [wr_en] indicates that the data on [wr_d] is valid and should be
///     written. While this is asserted high data on [wr_d] is read in on the
///     rising edge of [clk].
/// *   [wr_d] is the input data bus for the payload data.
/// *   [wr_rst_busy] indicates that the queue is in a reset state when asserted
///     high.
/// *   [wr_full] means that the input queue is full when asserted high and no
///     data can be written until more packets are sent out.
/// *   [clk25] is a 25 MHz clock signal used to write to the PHY.
/// *   [eth] contains the signals used to write to the Ethernet PHY.
/// *   [flush] causes any data in the queue to be sent even if it is less than
///     [MIN_DATA_BYTES] long. This will only send a multiple of two bytes so
///     this may not send all data. It is read on the falling edge of
///     [eth.tx_clk].
/// *   [ip_info] is the source and destination data that is needed to
///     transmit. It is read on the falling edge of [eth.tx_clk].
/// *   [mac_busy] indicates that packet is currently being sent. Note that the
///     queue can still be written to when this is asserted. When this signal
///     falls a packet has finished sending.
/// *   [rdy] indicates that the module is powered up and ready to communicate
///     with the PHY when asserted high.
module eth_udp_send #(
    parameter int unsigned CLK_RATIO = 0,
    parameter int unsigned MAX_DATA_BYTES = 548,
    parameter int unsigned MIN_DATA_BYTES = 256,
    parameter int unsigned POWER_UP_CYCLES = 5_000_000,
    parameter int unsigned WORD_SIZE_BYTES = 0) (
    // Standard
    input logic clk,
    input logic rst,
    // Writing data
    input logic wr_en,
    input logic [3:0] wr_d,
    output logic wr_rst_busy,
    output logic wr_full,
    // Ethernet
    input logic clk25,
    IEthPhy.fwd eth,
    input logic flush,
    IIpInfo.in ip_info,
    output logic mac_busy,
    output logic rdy);

    // Assert that the parameters are appropriate
    initial begin
        // Check that the clock ratio is set appropriately
        if (CLK_RATIO < 2) begin
            $error("CLK_RATIO must be set to at least 1.");
        end
        // Check that the word size is set appropriately
        if (WORD_SIZE_BYTES <= 0) begin
            $error("WORD_SIZE_BYTES must be positive");
        end
        // Check that the min and max data byte counts are set appropriately
        if (MIN_DATA_BYTES > MAX_DATA_BYTES) begin
            $error("MIN_DATA_BYTES must be less than MAX_DATA_BYTES");
        end
        if (MIN_DATA_BYTES % WORD_SIZE_BYTES != 0 ||
            MIN_DATA_BYTES < WORD_SIZE_BYTES) begin
            $error("MIN_DATA_BYTES must be a multiple of WORD_SIZE_BYTES");
        end
        if (MAX_DATA_BYTES % WORD_SIZE_BYTES != 0) begin
            $error("MAX_DATA_BYTES must be a multiple of the WORD_SIZE_BYTES");
        end
    end

    // The parameters in nibbles
    localparam int unsigned MIN_DATA_NIBBLES  = 2 * MIN_DATA_BYTES;
    localparam int unsigned MAX_DATA_NIBBLES  = 2 * MAX_DATA_BYTES;
    localparam int unsigned WORD_SIZE_NIBBLES = 2 * WORD_SIZE_BYTES;

    // The number of bytes in parts of the frame.
    localparam int unsigned PREAMBLE_SFD_BYTES = 8;
    localparam int unsigned MAC_HEADER_BYTES   = 14;
    localparam int unsigned IP_HEADER_BYTES    = 20;
    localparam int unsigned UDP_HEADER_BYTES   = 8;
    localparam int unsigned FCS_BYTES          = 4;

    // The number of nibbles in parts of the frame
    localparam int unsigned PREAMBLE_SFD_NIBBLES = 2 * PREAMBLE_SFD_BYTES;
    localparam int unsigned MAC_HEADER_NIBBLES   = 2 * MAC_HEADER_BYTES;
    localparam int unsigned IP_HEADER_NIBBLES    = 2 * IP_HEADER_BYTES;
    localparam int unsigned UDP_HEADER_NIBBLES   = 2 * UDP_HEADER_BYTES;
    localparam int unsigned FCS_NIBBLES          = 2 * FCS_BYTES;

    // The minimum number of nibbles allowed in an Ethernet frame. An Ethernet
    // must be at least 64 bytes.
    localparam int unsigned MIN_FRAME_NIBBLES = 128;

    // The number of write cycles to wait after writing data to the PHY. This
    // must be at least 12 bytes worth of time.
    localparam int unsigned GAP_NIBBLES = 24;

    // The Ethernet type for the Ethernet header. This value indicates that
    // IPv4 is used.
    localparam int unsigned ETHER_TYPE = 16'h0800;

    // The IP version to use.
    localparam int unsigned IP_VERSION = 4;

    // The IP header length.
    localparam int unsigned IP_IHL = IP_HEADER_BYTES / 4;

    // The IP type of service.
    localparam int unsigned IP_TOS = 8'h00;

    // The IP fragment identification.
    localparam int unsigned IP_ID = 0;

    // The IP flags.
    localparam int unsigned IP_FLAGS = 0;

    // The IP fragmentation offset.
    localparam int unsigned IP_FRAG_OFFSET = 0;

    // The IP time to live.
    localparam int unsigned IP_TTL = 8'hFF;

    // The IP next level protocol to use. This is the User Datagram Protocol.
    localparam int unsigned IP_PROTOCOL = 8'h11;

    // Forward the 25 MHz clock to the PHY
    assign eth.ref_clk = clk25;

    // Computes one step of the CRC-32 algorithm from the previous CRC value.
    //
    // # Arguments
    //
    // * [crc] is the previous CRC value.
    // * [data] is the data to contribute to the CRC.
    //
    // # Returns
    //
    // The next CRC value.
    function logic [31:0] compute_crc(
        input logic [31:0] crc,
        input logic [3:0] data);

        localparam int unsigned POLYNOMIAL = 32'h04C11DB7;

        compute_crc = crc;
        for (int j = 0; j < 4; j++) begin
            compute_crc = {compute_crc[30:0], 1'b0} ^
                (data[j] == compute_crc[31] ? '0 : POLYNOMIAL);
        end
    endfunction

    // Swaps the nibbles in each byte of a value.
    //
    // # Arguments
    //
    // * [data] is the data to swap nibbles.
    //
    // # Returns
    //
    // The data with swapped nibbles.
    function logic [31:0] swap_nibbles(input logic [31:0] data);
        swap_nibbles[28+:4] = data[24+:4];
        swap_nibbles[24+:4] = data[28+:4];
        swap_nibbles[20+:4] = data[16+:4];
        swap_nibbles[16+:4] = data[20+:4];
        swap_nibbles[12+:4] = data[8+:4];
        swap_nibbles[8+:4]  = data[12+:4];
        swap_nibbles[4+:4]  = data[0+:4];
        swap_nibbles[0+:4]  = data[4+:4];
    endfunction

    // Compute the number of payload nibbles from the number of nibbles in
    // the queue.
    //
    // # Arguments
    //
    // * [fifo_nibbles] is the number of nibbles in the queue.
    //
    // # Returns
    //
    // The number of payload nibbles.
    function int compute_payload_nibbles(int fifo_nibbles);
        automatic int temp = fifo_nibbles > MAX_DATA_NIBBLES ?
            MAX_DATA_NIBBLES : fifo_nibbles;
        compute_payload_nibbles =
            {temp[31:1], 1'b0} - ({temp[31:1], 1'b0} % WORD_SIZE_NIBBLES);
    endfunction

    // Compute the number of padding nibbles from the number of nibbles in
    // the payload.
    //
    // # Arguments
    //
    // * [payload_nibbles] is the number of nibbles in the payload.
    //
    // # Returns
    //
    // The number of padding nibbles that are required.
    function int compute_padding_nibbles(int payload_nibbles);
        // The payload must be at least 64 bytes, so padding is added to
        // inflate the size if necessary.
        automatic int nibbles = MAC_HEADER_NIBBLES + IP_HEADER_NIBBLES +
            UDP_HEADER_NIBBLES + payload_nibbles + FCS_NIBBLES;
        compute_padding_nibbles = nibbles < MIN_FRAME_NIBBLES ?
            MIN_FRAME_NIBBLES - nibbles : 0;
    endfunction

    // FIFO read signals
    logic [3:0] fifo_dout;
    logic [11:0] fifo_rd_data_count;
    logic fifo_rd_en;
    logic fifo_rd_rst_busy;

    // The FIFO that allows data to cross clock domains to write data to the
    // PHY on a different clock.
    eth_udp_fifo_async fifo(
        .rst(rst),
        // Write
        .din(wr_d),
        .full(wr_full),
        .wr_clk(clk),
        .wr_en(wr_en),
        .wr_rst_busy(wr_rst_busy),
        // Read
        .dout(fifo_dout),
        .empty(/* Unused */),
        .rd_clk(eth.tx_clk),
        .rd_data_count(fifo_rd_data_count),
        .rd_en(fifo_rd_en),
        .rd_rst_busy(fifo_rd_rst_busy)
    );


    // This enum is used to track the progress of a state machine that writes
    // the data to the PHY.
    enum {
        POWER_UP,
        READY,
        PREPARE,
        LENGTHS,
        IP_CHECKSUM,
        SEND_PREAMBLE_SFD,
        SEND_MAC_HEADER,
        SEND_IP_HEADER,
        SEND_UDP_HEADER,
        SEND_PAYLOAD,
        SEND_PADDING,
        SEND_FCS,
        WAIT
    } state;

    // This is used as a general purpose counter. Note that this is signed
    // because it is used to count up and down.
    int i;

    // This value is used as a temporary value in an intermediate step for
    // computing the IP header checksum and UDP checksum.
    int unsigned checksum_temp;

    // The headers that are to be sent
    MacHeader mac_header;
    IpHeader ip_header;
    UdpHeader udp_header;

    // The frame check (CRC) sequence for the Ethernet packet
    logic [31:0] fcs;

    // The number of data nibbles that will be sent in the current packet
    int payload_nibbles;

    // The number of nibbles that need to be sent to pad the packet length
    int padding_nibbles;

    // From a [vector] grab a nibble at the given index. The order of the
    // nibbles in each byte that are selected is reversed.
    `define SLICE(vector, index) \
        vector[8 * (index >> 1) + 4 * ((~index) & 1)+:4]

    // Run the state machine that sends that data to the PHY against the
    // transmit clock.
    always_ff @(negedge eth.tx_clk) begin
        if (rst) begin
            eth.rstn        <= 0;
            eth.tx_d        <= '0;
            eth.tx_en       <= 0;
            mac_header      <= '0;
            ip_header       <= '0;
            udp_header      <= '0;
            fcs             <= '0;
            i               <= '0;
            mac_busy        <= 0;
            padding_nibbles <= '0;
            payload_nibbles <= '0;
            rdy             <= 0;
            state           <= POWER_UP;
        end else begin
            // No longer need to reset
            eth.rstn <= 1;
            // Run the state machine for what to send
            case (state)
            // Wait for the PHY to properly power up
            POWER_UP: if (i < POWER_UP_CYCLES) begin
                i <= i + 1;
            end else begin
                i     <= '0;
                rdy   <= 1;
                state <= READY;
            end
            // Send as soon as there is enough data in the FIFO
            READY: if (!fifo_rd_rst_busy &&
                    (flush || fifo_rd_data_count >= MIN_DATA_NIBBLES)) begin
                // Construct the Ethernet header
                mac_header.dst_mac    <= ip_info.dst_mac;
                mac_header.src_mac    <= ip_info.src_mac;
                mac_header.ether_type <= ETHER_TYPE;
                // Construct the IP header
                ip_header.version         <= IP_VERSION;
                ip_header.ihl             <= IP_IHL;
                ip_header.type_of_service <= IP_TOS;
                ip_header.total_length    <= '0; // Computed later
                ip_header.identification  <= IP_ID;
                ip_header.flags           <= IP_FLAGS;
                ip_header.fragment_offset <= IP_FRAG_OFFSET;
                ip_header.time_to_live    <= IP_TTL;
                ip_header.protocol        <= IP_PROTOCOL;
                ip_header.header_checksum <= '0; // Computed later
                ip_header.src_ip          <= ip_info.src_ip;
                ip_header.dst_ip          <= ip_info.dst_ip;
                // Construct the UDP header
                udp_header.src_port <= ip_info.src_port;
                udp_header.dst_port <= ip_info.dst_port;
                udp_header.length   <= '0; // Computed later
                udp_header.checksum <= '0; // Optional, left as 0
                // The CRC starts as all 1's
                fcs <= 32'hFFFFFFFF;
                // The number of nibbles to send in the payload
                payload_nibbles <= compute_payload_nibbles(fifo_rd_data_count);
                // Others
                mac_busy <= 1;
                state    <= PREPARE;
            end
            // Compute the nimber of padding nibbles to add
            PREPARE: begin
                padding_nibbles <= compute_padding_nibbles(payload_nibbles);
                state           <= LENGTHS;
            end
            // Compute the IP and UDP lengths
            LENGTHS: begin
                ip_header.total_length <=
                    IP_HEADER_BYTES + UDP_HEADER_BYTES + (payload_nibbles / 2);
                udp_header.length <= UDP_HEADER_BYTES + (payload_nibbles / 2);
                // Others
                i     <= 1;
                state <= IP_CHECKSUM;
            end
            // Compute the IP header checksum
            IP_CHECKSUM: if (i == 1) begin
                // Note that the header checksum field `ip_header[64+:16]` is
                // not included.
                checksum_temp <=
                    ip_header[144+:16] + // Version, IHL, ToS
                    ip_header[128+:16] + // Total length
                    ip_header[112+:16] + // Identification
                    ip_header[ 96+:16] + // Flags, Fragmentation offset
                    ip_header[ 80+:16] + // TTL, Protocol
                    ip_header[ 48+:16] + // Source IP Upper
                    ip_header[ 32+:16] + // Source IP Lower
                    ip_header[ 16+:16] + // Destination IP Upper
                    ip_header[  0+:16];  // Destination IP Lower
                // Others
                i <= 0;
            end else begin
                ip_header.header_checksum <=
                    ~(checksum_temp[31:16] + checksum_temp[15:0]);
                // Others
                i     <= '0;
                state <= SEND_PREAMBLE_SFD;
            end
            // Send the preamble and SFD to the PHY
            SEND_PREAMBLE_SFD: begin
                eth.tx_d <= (i < PREAMBLE_SFD_NIBBLES - 1) ?
                    4'b0101 : 4'b1101;
                eth.tx_en <= 1;
                if (i < PREAMBLE_SFD_NIBBLES - 1) begin
                    i <= i + 1;
                end else begin
                    i     <= MAC_HEADER_NIBBLES - 1;
                    state <= SEND_MAC_HEADER;
                end
            end
            SEND_MAC_HEADER: begin
                eth.tx_d <= `SLICE(mac_header, i);
                fcs      <= compute_crc(fcs, `SLICE(mac_header, i));
                if (i > 0) begin
                    i <= i - 1;
                end else begin
                    i     <= IP_HEADER_NIBBLES - 1;
                    state <= SEND_IP_HEADER;
                end
            end
            SEND_IP_HEADER: begin
                eth.tx_d <= `SLICE(ip_header, i);
                fcs      <= compute_crc(fcs, `SLICE(ip_header, i));
                if (i > 0) begin
                    i <= i - 1;
                end else begin
                    i     <= UDP_HEADER_NIBBLES - 1;
                    state <= SEND_UDP_HEADER;
                end
            end
            SEND_UDP_HEADER: begin
                eth.tx_d <= `SLICE(udp_header, i);
                fcs      <= compute_crc(fcs, `SLICE(udp_header, i));
                if (i > 0) begin
                    i <= i - 1;
                end else begin
                    // If there is no payload skip straight to sending the
                    // padding
                    if (payload_nibbles != 0) begin
                        fifo_rd_en <= 1;
                        i          <= payload_nibbles - 1;
                        state      <= SEND_PAYLOAD;
                    end else begin
                        i     <= padding_nibbles - 1;
                        state <= SEND_PADDING;
                    end
                end
            end
            SEND_PAYLOAD: begin
                eth.tx_d <= fifo_dout;
                if (i > 0) begin
                    fcs <= compute_crc(fcs, fifo_dout);
                    i   <= i - 1;
                end else begin
                    if (padding_nibbles != 0) begin
                        fcs        <= compute_crc(fcs, fifo_dout);
                        fifo_rd_en <= 0;
                        i          <= padding_nibbles - 1;
                        state      <= SEND_PADDING;
                    end else begin
                        fcs <=
                            swap_nibbles(compute_crc(fcs, fifo_dout));
                        fifo_rd_en <= 0;
                        i          <= FCS_NIBBLES - 1;
                        state      <= SEND_FCS;
                    end
                end
            end
            SEND_PADDING: if (i > 0) begin
                fcs      <= compute_crc(fcs, '0);
                eth.tx_d <= '0;
                i        <= i - 1;
            end else begin
                fcs   <= swap_nibbles(compute_crc(fcs, '0));
                i     <= FCS_NIBBLES - 1;
                state <= SEND_FCS;
            end
            SEND_FCS: begin
                // Get the current nibble and take the one's complement, then
                // reverse the order of the bits, then send the new nibble.
                eth.tx_d <= {<<bit{~`SLICE(fcs, i)}};
                if (i > 0) begin
                    i <= i - 1;
                end else begin
                    i         <= '0;
                    state     <= WAIT;
                end
            end
            // Wait the appropriate time for the Ethernet interframe gap
            WAIT: if (i < GAP_NIBBLES) begin
                eth.tx_d  <= '0;
                eth.tx_en <= 0;
                i         <= i + 1;
            end else begin
                i        <= '0;
                mac_busy <= 0;
                state    <= READY;
            end
            endcase
        end
    end

endmodule
