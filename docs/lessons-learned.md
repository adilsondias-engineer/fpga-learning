## What I Learned so far
### FPGA Development Workflow

- Complete design → simulation → synthesis → implementation → hardware verification cycle
- Importance of setting correct top module for synthesis vs simulation (different "tops" for different purposes)
- Synthesis is for actual hardware designs only - testbenches cannot be synthesized
- Flash programming for autonomous boot on power-up
- Hardware verification is essential - testbenches complement but don't replace real testing

### Testbench Development

- Procedure placement: VHDL procedures must be declared in architecture declarative region (between architecture and begin), NOT inside processes
- Procedures declared in architecture can only be CALLED from processes, not DEFINED in them
- Self-checking testbenches with assert statements are more effective than manual waveform inspection
- Use shortened timing parameters (Generic mapping) for fast simulation vs hardware-accurate timing
- Reusable test procedures for common operations (encoder rotation, button presses)
- Test boundary conditions rather than exhaustive testing (test 0, 255, midpoint instead of all 256 values)

### Waveform Debugging Techniques

- Monitor multiple signals simultaneously to track data flow
- Use $monitor in testbenches for automatic change logging
- Identify metastability in waveforms (X or unknown states)
- Trace signal propagation through synchronizer chains
- Correlate simulation waveforms with hardware behavior

### Constraint Files (XDC)

- Single signal syntax: [get_ports signal_name]
- Vector syntax: [get_ports {vector_name[*]}] for all bits
- Individual vector bits: [get_ports {vector_name[0]}]
- Clock constraints with create_clock for timing analysis
- Pin mapping updates when changing physical connections (rotary encoder rewiring)

### Digital Design Fundamentals
#### Synchronous vs Asynchronous Reset

- Synchronous reset checked only on clock edge (safer for timing)
- Asynchronous reset responds immediately (better for emergency stops)
- Trade-off: timing closure vs responsiveness
- Most modern designs prefer synchronous reset

### Clock Domain Crossing (CDC)

- Critical: All asynchronous inputs MUST go through synchronizers
- Three-stage synchronizer is industry standard for metastability protection
- MTBF (Mean Time Between Failures) calculation depends on synchronizer stages
- CDC bugs can cause random, hard-to-reproduce failures in production

### Edge Detection

- Bug discovered: Order matters in sequential logic
- Must detect edge BEFORE updating previous state storage
- Ambiguous evaluation order can cause missed edges
- Correct pattern: read → compare → update

### Generic Parameters

- Design flexibility through configurable parameters
- DEBOUNCE_TIME for adjustable filtering periods
- FIFO_DEPTH for scalable buffer sizes
- Different values for simulation (fast) vs hardware (accurate)
- Enables IP reuse across different projects

### Component Design Patterns
#### Debouncing

- Mechanical switches bounce for 5-50ms typically
- 20ms debounce period filters all mechanical noise
- Counter-based implementation more reliable than sampling
- Must reset counter on any state change

### FIFO Buffers

- Circular buffer implementation with read/write pointers
- Full/empty flag generation from pointer comparison
- Careful handling of wrap-around conditions
- Synchronous read/write for predictable timing
- Critical for data flow control in streaming systems

### Rotary Encoder Decoding

- Quadrature encoding provides direction information
- Gray code sequence: only one bit changes at a time
- State machine decodes rotation direction
- Debouncing still required for mechanical encoders
- Edge detection on final stable state

### Bug Fixes During Development
#### Synthesis Attempting Testbench (Project 1)

- Error: [Synth 8-27] non-clocking wait statement not supported
- Cause: Testbench added to Design Sources instead of Simulation Sources
- Fix: Set design module as synthesis top, not testbench
- Lesson: Vivado's file organization matters - wrong placement causes cryptic errors

#### VHDL Procedure Syntax Errors (Project 4 Testbench)

- Error: syntax error near procedure and type error near ms
- Cause: Procedures defined inside process instead of architecture
- Fix: Move procedure declarations to architecture declarative region
- Lesson: VHDL has strict scoping rules for procedures

#### Edge Detection Timing (Project 2)

- Issue: LED toggle inconsistent, missed button presses
- Cause: Previous state updated before edge check
- Fix: Reorder to check edge first, then update state
- Lesson: Sequential statement order is critical in processes

#### Testbench Timing Failures (Project 2)

- Issue: Assertions failing despite correct logic
- Cause: Insufficient wait time after button release
- Fix: Increased wait times from 500ns to 5μs
- Lesson: Debouncer needs time to stabilize after input changes

### Hardware Integration Insights

- ChipKit headers provide flexible I/O expansion on Arty A7
- Pull-up resistors often needed for mechanical switches/encoders
- Breadboard connections can be unreliable - check continuity
- Color-coded wiring prevents confusion (red=power, black=ground, etc.)
- Current limiting resistors essential for LEDs (220Ω typical)

### Performance & Timing

- 100MHz system clock = 10ns period
- Timing closure becomes critical at high frequencies
- Setup/hold time violations cause intermittent failures
- Pipelining trades latency for throughput
- Register everything at module boundaries

### Vivado Tool Insights

- Behavioral simulation faster than post-implementation
- Synthesis optimizes away unused logic (can hide bugs)
- Implementation may fail even if synthesis succeeds (placement/routing)
- Critical warnings often indicate real problems
- ILA (Integrated Logic Analyzer) cores enable hardware debugging

### Documentation Best Practices

- Document bugs and fixes - shows learning mindset
- Include waveform screenshots with annotations
- Explain WHY not just WHAT in comments
- Create README with clear project structure
- Add interview talking points for portfolio projects

### Trading System Relevance

- FIFOs essential for packet buffering in network interfaces
- Metastability protection critical for asynchronous market data
- Low latency requires minimal logic levels
- Deterministic timing more important than average case
- Hardware timestamps need synchronized clocks
- Backpressure handling through full/empty flags

###  Key Conceptual Breakthroughs

- "You simulate signals, not physics" - Don't model LED photons or button mechanics
- "Synthesis is for hardware, simulation is for testing" - Testbenches are not synthesizable
- "Every async input is a potential failure point" - Never skip synchronizers
- "Edge detection is a pattern, not a primitive" - Must implement carefully
- "Timing is everything" - One clock cycle can make or break functionality
---
This document grows with each project. Latest update includes Projects 1-4.
