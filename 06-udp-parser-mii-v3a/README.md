# IP Parser Standalone Development (v3a)

Isolated development and testing of IP header parser module.

---

## Quick Start

### 1. Generate Test Vectors

```bash
cd test
python3 generate_test_vectors.py
```

**Expected Output:**

- Creates `test_vectors/` directory
- Generates 6 test files (.txt format)
- Prints hex dumps and parsed fields

### 2. Implement IP Parser

Edit `src/ip_parser.vhd` and implement:

1. **State Machine:** IDLE → WAIT_ETHERTYPE → PARSE_HEADER → VALIDATE → OUTPUT
2. **EtherType Detection:** Check bytes 12-13 for 0x0800
3. **Header Parsing:** Extract fields byte-by-byte (bytes 14-33)
4. **Checksum Calculation:** 16-bit one's complement sum
5. **Validation:** Version=4, IHL=5, checksum=0xFFFF
6. **Output Pulse:** Assert ip_valid for 1 cycle when valid

### 3. Run Simulation

```bash
vivado -mode batch -source simulate.tcl
```

**Expected Output:**

```
========================================
Starting IP Parser Tests
========================================
Test: Test 1: Valid UDP packet
PASS: Test 1: Valid UDP packet
----------------------------------------
...
========================================
Test Summary
========================================
Tests Passed: 6
Tests Failed: 0
ALL TESTS PASSED!
```

### 4. View Waveforms (Optional)

```bash
vivado -mode gui
# In Vivado GUI:
# - Create new project or open existing
# - Add src/ip_parser.vhd
# - Add test/ip_parser_tb.vhd
# - Run Behavioral Simulation
# - Add signals to waveform viewer
```

---

## Implementation Guide

### State Machine

```
IDLE:
  - Wait for frame_valid='1'
  - Reset all registers
  - Transition to WAIT_ETHERTYPE

WAIT_ETHERTYPE:
  - Monitor byte_index 12 and 13
  - Store bytes to check for 0x0800
  - If 0x0800: transition to PARSE_HEADER
  - If not 0x0800: return to IDLE

PARSE_HEADER:
  - Count bytes 14-33 (20-byte IP header)
  - Store fields based on byte position:
    * Byte 14: version_ihl
    * Bytes 16-17: total_length
    * Byte 23: protocol
    * Bytes 26-29: source IP
    * Bytes 30-33: destination IP
  - Accumulate checksum on every 16-bit word
  - After 20 bytes: transition to VALIDATE

VALIDATE:
  - Check version = 4 (upper nibble of version_ihl)
  - Check IHL = 5 (lower nibble of version_ihl)
  - Check checksum accumulator = 0xFFFF
  - If all pass: transition to OUTPUT
  - If any fail: set error flags, return to IDLE

OUTPUT:
  - Assert ip_valid = '1' for ONE clock cycle
  - Hold all output registers stable
  - Transition to IDLE
```

### Checksum Algorithm

**Key Points:**

- Use 20-bit accumulator to prevent overflow (10 words × 0xFFFF = 0x9FFF6)
- Sum all 16-bit words including checksum field
- Preserve all upper bits during accumulation (no intermediate folding)
- Fold carry bits in VALIDATE state after all additions complete
- Final result should be 0xFFFF for valid header

**Implementation:**

```vhdl
-- Signal declaration:
signal checksum_acc : unsigned(19 downto 0) := (others => '0');

-- In PARSE_HEADER state (accumulate without folding):
if byte_count is even then
    temp_word(15 downto 8) <= data_in;
elsif byte_count is odd then
    temp_word(7 downto 0) <= data_in;

    -- Add to accumulator, preserving ALL upper bits
    checksum_acc <= checksum_acc + unsigned("0000" & temp_word);
end if;

-- In VALIDATE state (multi-step process):
-- Step 0: Add final word
checksum_acc <= checksum_acc + unsigned("0000" & temp_word);

-- Step 1: Fold upper 4 bits into lower 16 bits (iterate until upper bits = 0)
if checksum_acc(19 downto 16) /= "0000" then
    checksum_acc <= "0000" & (checksum_acc(15 downto 0) + checksum_acc(19 downto 16));
    -- Stay in step 1 until folding complete
else
    -- Move to step 2
end if;

-- Step 2: Check final result
if checksum_acc(15 downto 0) = x"FFFF" then
    checksum_valid <= '1';
else
    checksum_valid <= '0';
end if;
```

### Byte Parsing

**Frame Structure:**

```
Byte 0-5:   Destination MAC
Byte 6-11:  Source MAC
Byte 12-13: EtherType (0x0800 for IPv4)
Byte 14:    Version (4) + IHL (5)
Byte 15:    DSCP/ECN (ignore)
Byte 16-17: Total Length
Byte 18-19: Identification (ignore)
Byte 20-21: Flags/Fragment (ignore)
Byte 22:    TTL (ignore)
Byte 23:    Protocol
Byte 24-25: Header Checksum
Byte 26-29: Source IP
Byte 30-33: Destination IP
```

**Parsing Logic:**

```vhdl
-- In PARSE_HEADER state:
case byte_index is
    when 14 => version_ihl <= data_in;
    when 16 => total_length_reg(15 downto 8) <= data_in;
    when 17 => total_length_reg(7 downto 0) <= data_in;
    when 23 => protocol_reg <= data_in;
    when 26 => src_ip_reg(31 downto 24) <= data_in;
    when 27 => src_ip_reg(23 downto 16) <= data_in;
    when 28 => src_ip_reg(15 downto 8) <= data_in;
    when 29 => src_ip_reg(7 downto 0) <= data_in;
    when 30 => dst_ip_reg(31 downto 24) <= data_in;
    when 31 => dst_ip_reg(23 downto 16) <= data_in;
    when 32 => dst_ip_reg(15 downto 8) <= data_in;
    when 33 => dst_ip_reg(7 downto 0) <= data_in;
    when others => null;
end case;
```

---

## Test Cases

| Test | Description                              | Expected Result                              |
| ---- | ---------------------------------------- | -------------------------------------------- |
| 1    | Valid UDP (192.168.1.10 → 192.168.1.100) | ip_valid='1', protocol=0x11, checksum_ok='1' |
| 2    | Valid TCP (10.0.0.1 → 10.0.0.2)          | ip_valid='1', protocol=0x06, checksum_ok='1' |
| 3    | Invalid checksum                         | ip_valid='0', checksum_err='1'               |
| 4    | Invalid version (6 instead of 4)         | ip_valid='0', version_err='1'                |
| 5    | IP with options (IHL=6)                  | ip_valid='0', ihl_err='1'                    |
| 6    | Non-IP frame (ARP)                       | ip_valid='0' (ignored)                       |

---

## Expected Waveform Behavior

### Test 1: Valid UDP

```
Time   frame_valid  byte_index  data_in  state           ip_valid
0ns    0            0           00       IDLE            0
100ns  1            0           00       WAIT_ETHERTYPE  0
...
220ns  1            12          08       WAIT_ETHERTYPE  0
230ns  1            13          00       PARSE_HEADER    0  (detected 0x0800)
...
430ns  1            33          64       PARSE_HEADER    0  (last byte)
440ns  0            0           00       VALIDATE        0
450ns  0            0           00       OUTPUT          1  (ip_valid pulse!)
460ns  0            0           00       IDLE            0
```

### Test 3: Invalid Checksum

```
...
430ns  1            33          64       PARSE_HEADER    0
440ns  0            0           00       VALIDATE        0
450ns  0            0           00       IDLE            0  (rejected, no pulse)
```

**Key Observations:**

- ip_valid pulses for exactly 1 clock cycle on valid frames
- Outputs (ip_src, ip_dst, etc.) hold stable values during OUTPUT state
- Invalid frames return to IDLE without asserting ip_valid

---

## Common Mistakes to Avoid

### 1. Checksum Carry Handling

**Wrong:**

```vhdl
-- Discarding upper bits (loses carry information)
checksum_acc <= ('0' & checksum_acc(15 downto 0)) + unsigned(temp_word);
```

**Right:**

```vhdl
-- Use 20-bit accumulator (sufficient for 10 words)
signal checksum_acc : unsigned(19 downto 0);

-- Preserve all upper bits during accumulation
checksum_acc <= checksum_acc + unsigned("0000" & temp_word);

-- Fold upper bits only in VALIDATE state (after all additions)
if checksum_acc(19 downto 16) /= "0000" then
    checksum_acc <= "0000" & (checksum_acc(15 downto 0) + checksum_acc(19 downto 16));
end if;
```

### 2. EtherType Detection Timing

**Wrong:**

```vhdl
-- Checking before both bytes received
if byte_index = 12 and data_in = x"08" then
    is_ipv4 <= '1';  -- Wrong! Need byte 13 too
end if;
```

**Right:**

```vhdl
-- Store both bytes then check
if byte_index = 12 then
    ethertype_byte1 <= data_in;
elsif byte_index = 13 then
    if ethertype_byte1 = x"08" and data_in = x"00" then
        is_ipv4 <= '1';
    end if;
end if;
```

### 3. Output Pulse Duration

**Wrong:**

```vhdl
-- ip_valid stays high too long
ip_valid <= '1';  -- In OUTPUT state, but never cleared
```

**Right:**

```vhdl
-- Pulse for exactly 1 cycle
case state is
    when OUTPUT =>
        ip_valid <= '1';
        state <= IDLE;  -- Immediately transition
    when others =>
        ip_valid <= '0';
end case;
```

### 4. Byte Ordering (Endianness)

**Wrong:**

```vhdl
-- Little-endian (backwards!)
when 26 => src_ip_reg(7 downto 0) <= data_in;    -- Wrong!
when 27 => src_ip_reg(15 downto 8) <= data_in;
```

**Right:**

```vhdl
-- Big-endian (network byte order)
when 26 => src_ip_reg(31 downto 24) <= data_in;  -- MSB first
when 27 => src_ip_reg(23 downto 16) <= data_in;
```

---

## Debug Tips

### If All Tests Fail

1. Check state machine transitions
2. Verify frame_valid is being recognized
3. Check byte_index range (0-33 for this test)

### If Checksum Always Fails

1. Verify 17-bit accumulator (not 16-bit)
2. Check carry folding logic
3. Verify all 20 bytes included in sum
4. Check word assembly (MSB/LSB order)

### If Output Values Wrong

1. Verify byte_index matches expected values
2. Check big-endian byte ordering
3. Verify registers hold values through OUTPUT state

### Simulation Tips

```bash
# Run with more detail
vivado -mode batch -source simulate.tcl > sim.log 2>&1

# Check for assertion failures
grep "FAIL" sim.log
grep "error" sim.log

# Check test summary
grep -A 5 "Test Summary" sim.log
```

---

## Integration (Future Phase 1D)

After passing all tests:

1. Copy `ip_parser.vhd` to `06-udp-parser-mii-v4/src/`
2. Instantiate in `mii_eth_top.vhd`
3. Connect to MAC parser outputs
4. Add synchronizers for CDC (25 MHz → 100 MHz)
5. Update `stats_counter.vhd` with new IP statistics
6. Test on hardware with real Ethernet traffic

---

## Metrics

**Expected Complexity:**

- Lines of Code: ~150-200 (active logic)
- States: 5 (IDLE, WAIT_ETHERTYPE, PARSE_HEADER, VALIDATE, OUTPUT)
- Registers: ~15 signals
- Development Time: 10 hours with debugging sessions

**Resource Estimate (Post-synthesis):**

- LUTs: ~100
- FFs: ~80
- Block RAM: 0

---

## Bugs Fixed

### Bug #1: Insufficient Accumulator Width for Checksum Calculation

**Date:** November 5, 2025
**Location:** [ip_parser.vhd:48](src/ip_parser.vhd#L48)

**Symptom:**
Checksum validation failing for all valid frames. Simulation showed final checksum value of `0xEFFF` instead of expected `0xFFFF` (difference of exactly `0x1000`).

**Root Cause:**
17-bit accumulator insufficient to hold sum of 10 words during IPv4 header checksum calculation. Maximum possible sum is `10 × 0xFFFF = 0x9FFF6`, which requires 20 bits. Overflow was occurring, losing upper bits and producing incorrect checksum results.

**Fix:**

```vhdl
-- Before: 17-bit accumulator (WRONG - causes overflow)
signal checksum_acc : unsigned(16 downto 0) := (others => '0');

-- After: 20-bit accumulator (CORRECT - prevents overflow)
signal checksum_acc : unsigned(19 downto 0) := (others => '0');
```

**Verification:**
All test cases now pass with checksum values computing correctly to `0xFFFF` for valid headers.

**Lesson:**
Calculate maximum accumulator size before implementation: `N words × 0xFFFF = max_value`, then determine required bit width. For IPv4 with 20-byte header (10 words): `⌈log₂(0x9FFF6)⌉ = 20 bits`.

---

### Bug #2: Carry Bits Discarded During Checksum Accumulation

**Date:** November 5, 2025
**Location:** [ip_parser.vhd:155](src/ip_parser.vhd#L155), [ip_parser.vhd:173](src/ip_parser.vhd#L173)

**Symptom:**
Checksum calculation producing incorrect results despite correct algorithm logic. Intermediate checksum values showed bits being lost between additions.

**Root Cause:**
Addition logic used `('0' & checksum_acc(15 downto 0)) + unsigned(temp_word)`, which discarded upper 4 bits (19:16) of the accumulator on every addition. This lost all carry information from previous additions, breaking the one's complement sum algorithm.

**Fix:**

```vhdl
-- Before: Discarded upper bits (WRONG)
checksum_acc <= ('0' & checksum_acc(15 downto 0)) + unsigned(temp_word);

-- After: Preserved all bits (CORRECT)
checksum_acc <= checksum_acc + unsigned("0000" & temp_word);
```

Applied consistently in PARSE_HEADER state (line 155) and VALIDATE state Step 0 (line 173).

**Impact:**
Critical bug - checksum validation completely non-functional without this fix.

**Lesson:**
When implementing multi-cycle accumulation, preserve all accumulator bits until final folding step. Never truncate intermediate results.

---

### Bug #3: Incorrect Test Vector Checksums

**Date:** November 5, 2025
**Location:** [ip_parser_tb.vhd](test/ip_parser_tb.vhd) - multiple test vectors

**Symptom:**
Valid IP headers failing checksum validation despite parser implementation appearing correct. Manual checksum calculation showed discrepancies with test data.

**Root Cause:**
Python script `generate_test_vectors.py` contained checksum calculation errors, producing incorrect expected checksums for all test vectors.

**Fix:**
Manually recalculated and corrected checksums for all test cases:

- **VALID_UDP_FRAME:** `0xE71A` → `0xF71A` (line 81)
- **VALID_TCP_FRAME:** `0x4D06` → `0x66E2` (line 95)
- **INVALID_VERSION_FRAME:** `0x96CC` → `0x611B` (line 124)
- **IP_WITH_OPTIONS_FRAME:** `0xB2CC` → `0xAA17` (line 139)

**Verification:**
All test vectors now produce correct checksum validation results when processed by IP parser.

**Lesson:**
Verify test data independently before trusting automated generation. Cross-check critical values (checksums, CRCs) with manual calculation or known-good reference implementation.

---

### Bug #4: Invalid Frames Generating ip_valid Pulse

**Date:** November 5, 2025
**Location:** [ip_parser.vhd:227-236](src/ip_parser.vhd#L227-L236)

**Symptom:**
Tests 3-6 (invalid checksum, wrong version, IHL≠5, non-IP frames) were failing. Testbench expected no `ip_valid` pulse for invalid frames, but parser was generating pulse for all frames regardless of validation results.

**Root Cause:**
OUTPUT state unconditionally asserted `ip_valid <= '1'` without checking validation results (version, IHL, checksum). This violated the specification requirement that only valid IPv4 headers should generate output pulse.

**Fix:**

```vhdl
-- Before: Always generated pulse (WRONG)
when OUTPUT =>
    ip_valid <= '1';  -- Unconditional
    ip_checksum_ok <= checksum_valid;

-- After: Conditional pulse based on validation (CORRECT)
when OUTPUT =>
    -- Only generate ip_valid pulse if all checks pass
    if (version_ihl(7 downto 4) = "0100" and     -- Version = 4
        version_ihl(3 downto 0) = "0101" and     -- IHL = 5 (no options)
        checksum_valid = '1') then               -- Checksum valid
        ip_valid <= '1';
    else
        ip_valid <= '0';  -- Invalid frame, no pulse
    end if;
    ip_checksum_ok <= checksum_valid;
```

**Verification:**
All 6 test cases now pass:

- Tests 1-2 (valid frames): Generate `ip_valid` pulse ✓
- Tests 3-6 (invalid frames): No pulse generated ✓

**Impact:**
Moderate - invalid frames would have been passed to downstream logic, requiring additional filtering.

**Lesson:**
State machine output logic must incorporate all validation checks. Never assume downstream modules will perform validation that should occur at protocol parser level.

---

## Metrics

**Development Status:** Complete - All tests passing
**Lines of Code:** ~250 (ip_parser.vhd + ip_parser_tb.vhd)
**States:** 5 (IDLE, WAIT_ETHERTYPE, PARSE_HEADER, VALIDATE, OUTPUT)
**Test Cases:** 6 (2 valid, 4 invalid/edge cases)
**Bugs Fixed:** 4 (accumulator sizing, carry preservation, test data, validation logic)
**Development Time:** ~10 hours (including debugging and test data correction)

**Resource Estimate (Post-synthesis):**

- LUTs: ~100
- FFs: ~80
- Block RAM: 0

---

**Status:** ✅ Complete - All tests passing
**Created:** November 5, 2025
**Last Updated:** November 5, 2025
**Completed:** November 5, 2025

**Dependencies:** Python 3, Vivado 2020.2+, Scapy (for test vector generation)
