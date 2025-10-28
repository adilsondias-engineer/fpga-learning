# Button Debouncer with Metastability Protection

A robust button handler demonstrating synchronization, debouncing, and edge detection - critical concepts for reliable FPGA designs.

## Overview

Physical buttons are electrically noisy - they "bounce" when pressed, creating multiple transitions instead of a clean on/off signal. Additionally, asynchronous signals crossing into the FPGA clock domain can cause metastability. This project implements a complete solution to both problems.

## Hardware

- **Board:** Xilinx Arty A7-100T
- **FPGA:** Artix-7 XC7A100T
- **Clock:** 100 MHz system clock
- **Input:** BTN0 (physical button)
- **Output:** LD0 (single LED)

## What It Does

Press the button → LED toggles ON/OFF

**Key Features:**

- One button press = One toggle (no multiple triggers from bouncing)
- Safe handling of asynchronous external signals
- Reliable operation regardless of press duration
- Production-ready debounce implementation

## Design Architecture

The design uses a 4-stage pipeline:
