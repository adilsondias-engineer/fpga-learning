# FPGA Learning Resources

Comprehensive list of documentation, datasheets, specifications, and tools used throughout this learning journey.

---

## Hardware Documentation

### Xilinx Arty A7-100T

**Official Documentation:**

- [Arty A7 Reference Manual](https://digilent.com/reference/programmable-logic/arty-a7/reference-manual)

  - Pin assignments for all peripherals
  - Schematic diagrams
  - Memory layout
  - Power specifications

- [Arty A7 Master XDC File](https://github.com/Digilent/digilent-xdc)
  - Complete pin constraints
  - All peripheral mappings
  - PMOD connector pinouts

**Board Features:**

- FPGA: Xilinx Artix-7 XC7A100T-1CSG324C
- Clock: 100 MHz oscillator
- Memory: 256 MB DDR3, 16 MB Quad-SPI Flash
- USB: UART bridge (FTDI FT2232HQ)
- Ethernet: 10/100 PHY (TI DP83848J)
- Peripherals: 4 buttons, 4 switches, 4 LEDs, 2 RGB LEDs

### Xilinx FPGA

**User Guides:**

- [UG470: 7 Series FPGAs Configuration User Guide](https://docs.xilinx.com/v/u/en-US/ug470_7Series_Config)

  - Configuration modes
  - Bitstream generation
  - Flash programming

- [UG471: 7 Series FPGAs SelectIO Resources User Guide](https://docs.xilinx.com/v/u/en-US/ug471_7Series_SelectIO)

  - I/O standards (LVCMOS33, LVDS, etc.)
  - Termination requirements
  - Timing parameters

- [UG472: 7 Series FPGAs Clocking Resources User Guide](https://docs.xilinx.com/v/u/en-US/ug472_7Series_Clocking)

  - PLL configuration (PLLE2_BASE)
  - MMCM configuration (MMCME2_BASE)
  - Clock distribution networks (BUFG, BUFR)
  - Jitter specifications

- [UG473: 7 Series FPGAs Memory Resources User Guide](https://docs.xilinx.com/v/u/en-US/ug473_7Series_Memory_Resources)

  - Block RAM architecture
  - FIFO implementation
  - Distributed RAM

- [UG953: Vivado Design Suite 7 Series FPGA and Zynq Libraries Guide](https://docs.xilinx.com/v/u/en-US/ug953-vivado-7series-libraries)
  - Primitive component specifications
  - Generic parameter requirements (STRING vs boolean!)
  - Port descriptions

**Datasheets:**

- [DS181: Artix-7 FPGAs Data Sheet](https://docs.xilinx.com/v/u/en-US/ds181_Artix_7_Data_Sheet)
  - DC/AC characteristics
  - Maximum frequencies
  - Power consumption
  - Package pinouts

---

## Ethernet PHY Documentation

### TI DP83848J (Arty A7 Ethernet PHY)

**Datasheet:**

- [DP83848J 10/100 Ethernet Physical Layer Transceiver](https://www.ti.com/product/DP83848J)
  - MII interface specification
  - Reset timing requirements (10ms minimum)
  - Register map (MDIO)
  - LED configuration modes

**Key Specifications:**

- Interface: MII (Media Independent Interface)
- Speed: 10/100 Mbps (NOT Gigabit)
- Clock: Requires 25 MHz reference from FPGA
- Pins: 18 MII signals + PHY management
- Auto-negotiation: IEEE 802.3u compliant

**Critical Notes:**

- Does NOT support RGMII
- Requires external 25 MHz reference clock
- PHY provides eth_rx_clk and eth_tx_clk to FPGA
- Minimum 10ms reset pulse required

---

## Protocol Specifications

### IEEE 802.3 - Ethernet

**Official Specification:**

- [IEEE 802.3-2018: Ethernet Standard](https://standards.ieee.org/ieee/802.3/7071/)
  - MAC frame format
  - Preamble/SFD structure
  - MII interface timing
  - CSMA/CD operation

**Frame Structure:**

```
Preamble (7 bytes):  0x55 0x55 0x55 0x55 0x55 0x55 0x55
SFD (1 byte):        0xD5
Dest MAC (6 bytes):  Target address
Src MAC (6 bytes):   Source address
Type/Length (2):     EtherType or payload length
Payload (46-1500):   Data
FCS (4 bytes):       CRC32 checksum
```

**MII Interface:**

- Data width: 4 bits (nibbles)
- Clock: 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
- Preamble: Passed to FPGA (must strip in logic)
- Control signals: RX_DV, RX_ER, TX_EN, TX_ER

### UART Communication

**Standard:** RS-232 compatible (LVCMOS levels)

- Format: 8N1 (8 data bits, no parity, 1 stop bit)
- Baud rate: 115200 bps
- Voltage: 3.3V CMOS levels
- Mid-bit sampling for noise immunity

---

## Software Tools

### AMD Vivado Design Suite

**Version Used:** Vivado 2025.1

**Documentation:**

- [UG835: Vivado Design Suite Tcl Command Reference Guide](https://docs.xilinx.com/r/en-US/ug835-vivado-tcl-commands)
- [UG888: Vivado Design Suite Tutorial](https://docs.xilinx.com/v/u/en-US/ug888-vivado-design-tutorials-getting-started)
- [UG893: Using the Vivado Logic Analyzer](https://docs.xilinx.com/v/u/en-US/ug893-vivado-logic-analyzer)
- [UG904: Vivado Implementation](https://docs.xilinx.com/v/u/en-US/ug904-vivado-implementation)
- [UG906: Vivado Design Analysis and Closure](https://docs.xilinx.com/v/u/en-US/ug906-vivado-design-analysis)

**Key Features Used:**

- Behavioral simulation
- Synthesis (out-of-context and project modes)
- Implementation (place & route)
- Timing analysis
- Bitstream generation
- Hardware manager (programming)

### Python Testing Tools

**PySerial (UART Testing):**

```bash
pip install pyserial
```

- Serial port communication
- Binary protocol testing
- Automated test scripts

**Scapy (Ethernet Testing):**

```bash
pip install scapy
```

- Raw Ethernet frame construction
- Layer 2 packet injection
- MAC address manipulation
- Wireshark-compatible captures

**Wireshark:**

- Packet capture and analysis
- Protocol dissection
- Timing measurements
- Filter expressions for debugging

---

## Learning Resources

### VHDL Language

**Books:**

- "VHDL for Engineers" by Kenneth Short
- "RTL Hardware Design Using VHDL" by Pong P. Chu

**Online References:**

- [VHDL Quick Reference](http://www.ics.uci.edu/~jmoorkan/vhdlref/)
- [VHDL Tutorial (UNSW)](http://web.eece.maine.edu/~vweaver/classes/ece412_2005s/vhdl_tutorial.pdf)

**Key Concepts Learned:**

- Signal vs variable timing
- Process evaluation order
- Sequential vs concurrent statements
- Clock domain crossing
- Synchronizer patterns
- State machine design

### Digital Design Fundamentals

**Metastability:**

- [Metastability in FPGA Design (Altera/Intel)](https://www.intel.com/content/www/us/en/docs/programmable/683082/current/metastability.html)
- 2FF synchronizers for CDC
- 3FF synchronizers for asynchronous inputs
- MTBF calculations

**Clock Domain Crossing:**

- Gray code counters
- Handshake protocols
- FIFO-based crossing
- Timing constraints (set_max_delay, set_false_path)

**Protocol Design:**

- Binary vs ASCII protocols
- Framing strategies (START_BYTE, length-prefixed)
- Error detection (checksums, CRC)
- State machine parsers

---

## Development Tools Configuration

### Git Repository Structure

```
fpga-learning/
├── .gitignore           # Vivado files, temp files
├── README.md            # Portfolio overview
├── context.txt          # Context restoration (git ignored)
├── resources.md         # This file
├── docs/
│   └── lessons-learned.md
├── 01-project/
│   ├── src/
│   ├── test/
│   ├── constraints/
│   └── README.md
└── ...
```

**.gitignore Patterns:**

```
*.jou
*.log
*.str
*.xpr
*.cache/
*.hw/
*.runs/
*.sim/
*.tmp/
.Xil/
*.wdb
*.vcd
```

### Vivado Project Management

**TCL Scripts:**

- `build.tcl` - Batch synthesis/implementation
- `program.tcl` - FPGA programming
- Automated workflow for consistent builds

**Constraints Best Practices:**

- Separate timing from physical constraints
- Use variables for reusable values
- Comment all non-obvious constraints
- Include clock domain crossing constraints

---

## Community & Forums

**Xilinx Forums:**

- [AMD Support Community](https://support.xilinx.com/s/)
- Active community for tool issues
- Hardware-specific questions

**Stack Overflow:**

- Tag: [fpga], [vhdl], [xilinx]
- Good for language questions

**Reddit:**

- r/FPGA - Community discussions
- r/ECE - Electronics engineering

**GitHub:**

- Digilent reference designs
- Open-source IP cores
- Example projects

---

## Hardware Debugging Tools

**Integrated Logic Analyzer (ILA):**

- Xilinx IP core for on-chip debugging
- Real-time signal capture
- Trigger conditions
- Waveform export to Vivado

**Virtual I/O (VIO):**

- Runtime signal manipulation
- Interactive debugging
- Register inspection

**JTAG:**

- Programming interface
- Boundary scan
- ChipScope debugging

---

## Reference Designs

**Digilent GitHub:**

- [Arty A7 Reference Designs](https://github.com/Digilent/Arty-A7-100-Master-XDC)
- Example constraints
- Peripheral interfaces
- Complete working projects

**Xilinx Example Designs:**

- AXI interface examples
- Clock management examples
- High-speed serial transceivers
- Memory controller examples

---

## Next Learning Topics

**Phase 1B (Immediate):**

- IP header parsing (IPv4)
- UDP packet extraction
- Hardware timestamping
- MDIO interface for PHY management

**Phase 2 (Future):**

- AXI4 interfaces
- DMA controllers
- High-speed serial (GTX transceivers)
- DDR3 memory controller
- Order book implementation
- Market data parser (ITCH protocol)

---

## Lessons on Tool Usage

**Vivado Best Practices:**

- Always check critical warnings
- Timing must close (WNS > 0)
- Use IP Integrator for complex systems
- Out-of-context synthesis for IP
- Incremental compilation for faster iterations

**Simulation Best Practices:**

- Use reduced timing for fast simulation
- Self-checking testbenches save time
- Procedures for reusable test patterns
- Assert statements catch bugs early
- Simulate edge cases, not just happy path

**Hardware Verification:**

- LED debugging is surprisingly effective
- Wireshark for network protocol validation
- Scapy for controllable test traffic
- Oscilloscope for timing verification
- Always test on real hardware

---

_This resource list grows with each project. Last updated: Project 06 (MII Ethernet Receiver)_
