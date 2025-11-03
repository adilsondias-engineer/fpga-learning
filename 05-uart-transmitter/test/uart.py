import serial
import time

ser = serial.Serial('COM7', 115200, parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE, bytesize=serial.EIGHTBITS, timeout=1)

# Clear any pending data
ser.reset_input_buffer()
ser.reset_output_buffer()

print("Testing binary protocol...")

# Set counter to 0x10
print("\n1. Setting counter to 0x10")
msg = bytes([0xAA, 0x01, 0x01, 0x10, 0x10])
print(f"   Sending: {' '.join(f'{b:02X}' for b in msg)}")
ser.write(msg)
time.sleep(0.2)  # Wait longer for FPGA to process

# Check if any unexpected echo
leftover = ser.read(10)
if leftover:
    print(f"   WARNING - Unexpected echo: {' '.join(f'{b:02X}' for b in leftover)}")

# Query counter (should return "10")
print("\n2. Querying counter value")
msg = bytes([0xAA, 0x03, 0x00, 0x03])
print(f"   Sending: {' '.join(f'{b:02X}' for b in msg)}")
ser.write(msg)
time.sleep(0.2)  # Wait for response

response = ser.read(2)
print(f"   Response: {' '.join(f'{b:02X}' for b in response)} = {response}")
print(f"   Expected: 31 30 = b'10'")
if response == b'10':
    print("   PASS")
else:
    print(f"   FAIL")

# Test Add command
print("\n3. Adding 0x05 to counter")
msg = bytes([0xAA, 0x02, 0x01, 0x05, 0x06])
print(f"   Sending: {' '.join(f'{b:02X}' for b in msg)}")
ser.write(msg)
time.sleep(0.1)

# Query again
print("\n4. Querying counter after add")
msg = bytes([0xAA, 0x03, 0x00, 0x03])
print(f"   Sending: {' '.join(f'{b:02X}' for b in msg)}")
ser.write(msg)
time.sleep(0.1)

response = ser.read(2)
print(f"   Response: {response}")
print(f"   Expected: b'15' (0x10 + 0x05 = 0x15)")
if response == b'15':
    print("   PASS")
else:
    print(f"   FAIL - Got {response}")

print("\n5. Testing ASCII commands")
ser.write(b'Q')  # Query using ASCII
time.sleep(0.1)
response = ser.read(2)
print(f"   ASCII 'Q' response: {response}")

ser.close()