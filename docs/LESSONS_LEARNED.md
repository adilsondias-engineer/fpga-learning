# FPGA Development - Key Lessons Learned

Critical insights from FPGA development for trading systems, organized by category.

---

## VHDL Language Gotchas

### 1. `with...select` - Single Signal Only
**Bug:** stats_counter.vhd compound condition syntax error
```vhdl
-- WRONG: Cannot use 'and' in when clause
with mode select led <= nibble when MODE_UDP and counter = 0,

-- RIGHT: Use intermediate signal
with counter select temp <= nibble_data(15 downto 12) when 0,
with mode select led <= temp when MODE_UDP,
```
**Lesson:** VHDL `with...select` limited to one signal. Use intermediate signals for complex logic.

### 2. Signal Assignment Timing
**Bug:** UDP parser state contamination (v3b)
- All assignments take effect on **next** clock edge
- Transitioning to IDLE with old `byte_count` value caused spurious errors
**Fix:** Explicitly clear ALL state variables in IDLE state entry
**Lesson:** State transitions need complete cleanup to prevent residual state contamination

### 3. Xilinx Primitive Generic Types
**Bug:** PLLE2_BASE type error
```vhdl
-- WRONG: STARTUP_WAIT => FALSE
-- RIGHT: STARTUP_WAIT => "FALSE"  -- String literal required
```
**Lesson:** Xilinx primitives require string literals for parameters (check UG953)

---

## Hardware & Timing

### 4. Power-Up Initialization Glitches
**Bug:** LED error indicator stuck ON at power-up
- Combinational error signals assert when registers initialize to '0'
- `ip_checksum_err <= '1' when checksum_valid = '0'` → asserts immediately at startup
**Fix:** Gate error detection with `initialized` flag set after first reset
**Lesson:** Always protect error latches from power-up glitches

### 5. Human-Visible Timing
**Bug:** Error LED pulses too brief to see
- Hardware events: 10ns (1 clock @ 100MHz)
- Human eye persistence: 100ms
- **Ratio: 10,000,000× too fast!**
**Fix:** Pulse stretcher with 0.5-second timer
```vhdl
constant ERROR_DISPLAY_TIME : integer := CLK_FREQ / 2;  -- 0.5 sec
if error_pulse = '1' then
    error_timer <= ERROR_DISPLAY_TIME;
    led_on <= '1';
elsif error_timer > 0 then
    error_timer <= error_timer - 1;
end if;
```
**Lesson:** Use 100ms-1sec pulse stretchers for visual indicators

### 6. MII Preamble Stripping
**Bug:** Zero frames counted despite traffic
- MII PHY sends preamble (7×0x55) + SFD (0xD5) before frame
- MAC parser saw 0x55 instead of destination MAC
**Fix:** State machine to detect SFD and skip preamble
**Lesson:** PHY interface behavior varies (MII vs RGMII). Check IEEE 802.3 spec.

---

## Debug Strategies

### 7. Testbench Timing for Transient Signals
**Bug:** UDP parser tests failing (v3b)
- Hardware generated 1-cycle `udp_valid` pulse at 175ns
- Testbench checked at 390ns (pulse long gone)
**Fix:** Active monitoring with capture variables
```vhdl
for i in 0 to 20 loop
    wait for CLK_PERIOD;
    if udp_valid = '1' then
        valid_captured := '1';  -- Capture occurrence
        port_captured := udp_dst_port;  -- Sample data
    end if;
end loop;
assert valid_captured = '1';
```
**Lesson:** Actively monitor for transient pulses, don't just check at fixed time

### 8. Waveform Analysis Essential
- Transcript shows "what failed"
- Waveforms show "why it failed" and **when**
- UDP parser case: Waveform revealed timing mismatch (not logic error)
**Lesson:** Always generate waveforms for failing tests

### 9. Synthesis Warnings Judgment
**Examples:**
- "Unused register removed" → Check if intentional (future use) vs broken
- "Unconnected port" → Likely real issue if port should be used
**Lesson:** Review all warnings, verify functionality, check timing

---

## Design Patterns

### 10. State Machine for Protocols
```vhdl
type state_type is (IDLE, PREAMBLE, HEADER, VALIDATE, PAYLOAD);
```
Benefits: Clear structure, easy to extend, self-documenting

### 11. Clock Domain Crossing Checklist
1. Identify all signals crossing boundary
2. Single-bit → 2FF synchronizer
3. Multi-bit → Sample on valid pulse
4. Add timing constraints
**Lesson:** Systematically synchronize EVERY signal (don't forget status/error signals!)

### 12. Error Detection with Pulse Stretcher
For human-visible indicators:
1. Detect brief error pulse (1 cycle)
2. Set timer (e.g., 50M clocks = 0.5 sec)
3. Keep LED ON while timer > 0
4. New errors restart timer
**Lesson:** Makes transient hardware events visible to operators

---

## Development Workflow

### 13. Documentation First
**Mistake:** Coded RGMII interface without reading docs
- Wasted 4 hours implementing wrong interface
**Correct:** 30 min reading Arty A7 manual → found MII interface
**Savings:** 3.5 hours
**Lesson:** Read hardware docs before coding

### 14. Incremental Integration
1. Phase 1A: MII + MAC → Verify
2. Phase 1D: + IP → Verify
3. Phase 1F: + UDP → Verify
**Anti-pattern:** Build entire stack, debug all layers at once
**Lesson:** Verify each layer before adding next

### 15. Component Interface Management
**Bug:** Port map mismatch after entity redesign
**Solutions:**
- Direct entity instantiation (recommended - single source of truth)
- Auto-generate component from entity
- Avoid manual component declarations
**Lesson:** Use direct `entity work.module` instantiation

---

## Trading System Relevance

**Skills from Bug Fixes:**

1. **Nanosecond Timing** (Pulse stretcher) → Timestamp precision
2. **Clean Initialization** (Power-up glitches) → Production robustness
3. **State Management** (Contamination) → Order book updates
4. **Synthesis Mastery** (Warnings) → Resource optimization
5. **Observable Events** (LED visibility) → System monitoring
6. **Direct PHY Interface** (MII preamble) → Ultra-low latency

---

**Projects:** 6 phases, 15 bugs documented
**Last Updated:** November 6, 2025
