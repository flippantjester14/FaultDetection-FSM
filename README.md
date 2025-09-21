# FaultDetection-FSM

## Overview

This project implements a comprehensive fault detection system for battery management applications, featuring a four-state FSM architecture with advanced safety mechanisms. The design is suitable for safety-critical applications including electric vehicles, energy storage systems, and industrial battery monitoring.

## Features

- **Four-State FSM Architecture**: Normal -> Warning -> Fault -> Shutdown progression
- **Multi-Parameter Monitoring**: Simultaneous monitoring of cell voltages, current, and temperature
- **Debounce Logic**: 8-cycle noise immunity for reliable fault detection
- **Persistence Mechanism**: 50-cycle threshold prevents false alarm escalation
- **Fault Priority System**: Temperature > Current > Voltage hierarchy
- **Selective Masking**: Individual fault type enable/disable for maintenance operations
- **Comprehensive Telemetry**: Fault counters, warning counters, and diagnostic logging
- **Safety Features**: Manual reset capability and fault latching mechanisms

## Technical Specifications

### FSM States
- **NORMAL (00)**: All parameters within safe operating limits
- **WARNING (01)**: Fault detected but not yet persistent
- **FAULT (10)**: Persistent fault confirmed and latched
- **SHUTDOWN (11)**: Critical temperature fault requiring manual intervention

### Monitoring Parameters
- **Cell Voltages**: 4 cells monitored with 330mV warning threshold
- **Current**: 150mA warning threshold with overcurrent protection
- **Temperature**: 60°C warning threshold with thermal shutdown capability

### Timing Parameters
- **Debounce Period**: 8 clock cycles minimum for fault recognition
- **Persistence Threshold**: 50 clock cycles for warning-to-fault escalation
- **ADC Resolution**: 12-bit precision for all measurements

## Prerequisites

### Software Requirements
```
sudo apt update
sudo apt install verilator gtkwave build-essential
```

### Hardware Requirements
- Linux-based system (Ubuntu 20.04+ recommended)
- Minimum 4GB RAM
- 1GB available storage space

## Quick Start Guide

### 1. Clone Repository
```bash
git clone https://github.com/flippantjester14/FaultDetection-FSM.git
cd FaultDetection-FSM
```

### 2. Build Project
```bash
# Clean any previous builds
rm -rf obj_dir

# Generate C++ model from SystemVerilog
verilator --cc src/fault_fsm.sv --exe sim/main.cpp -DASSERTIONS_ON --trace -Wno-fatal

# Compile executable
make -j -C obj_dir -f Vfault_fsm.mk Vfault_fsm
```

### 3. Run Simulation
```bash
# Create waveforms directory
mkdir -p waveforms

# Execute simulation
./obj_dir/Vfault_fsm
```

### 4. Analyze Results
```bash
# View waveforms in GTKWave
gtkwave waveforms/tb_fault_fsm.vcd
```

## Project Structure

```
FaultDetection-FSM/
├── src/
│   └── fault_fsm.sv          # Main SystemVerilog FSM implementation
├── sim/
│   └── main.cpp              # C++ testbench with comprehensive scenarios
├── waveforms/
│   └── tb_fault_fsm.vcd      # Generated VCD trace files
├── obj_dir/                  # Verilator build artifacts (auto-generated)
├── .gitignore                # Git ignore rules for build files
└── README.md                 # This file
```

## Test Scenarios

The testbench validates the following operational scenarios:

### Normal Operation Testing
- All parameters within safe limits
- Verification of stable NORMAL state operation
- Baseline telemetry counter validation

### Transient Spike Testing  
- Brief voltage drops below threshold
- Verification of debounce protection
- Confirmation that transient faults do not trigger state changes

### Persistent Fault Testing
- Long-duration undervoltage conditions  
- Warning-to-fault escalation timing validation
- Telemetry counter increment verification

### Priority Resolution Testing
- Multiple simultaneous fault conditions
- Temperature priority over current and voltage faults
- Correct fault code assignment validation

### Masking Functionality Testing
- Individual fault type disable verification
- Masked fault ignore confirmation
- Selective monitoring capability validation

### Recovery Testing  
- Manual reset functionality
- Fault latch clearing verification
- Return to normal operation confirmation

## Key Verification Points

### State Transition Validation
- NORMAL -> WARNING: Fault detection and debounce completion
- WARNING -> FAULT: Persistence threshold exceeded
- WARNING -> NORMAL: Fault clearance before persistence threshold
- FAULT -> SHUTDOWN: Critical temperature conditions
- Any State -> NORMAL: Manual reset activation

### Timing Verification
- Debounce delays: 8-cycle minimum before fault recognition
- Persistence timing: 50-cycle accumulation before escalation  
- Reset response: Immediate state transition on manual reset

### Telemetry Accuracy
- Fault count increments on each fault state entry
- Warning count increments on each warning state entry
- Last fault cycle timestamp accuracy
- Cycle counter progression validation

## Expected Simulation Output

```
Starting simulation...
Running normal operation cycles...
Testing transient spike...
Testing persistent undervoltage...
Testing temperature priority...
Testing current fault...
Testing voltage masking...
Testing manual reset...

=== SIMULATION COMPLETE ===
Simulation ended at cycle 1024 (time=15360)
Final state:
  state_o = 0
  fault_latched_o = 0
  active_fault_code_o = 0
  fault_count_o = 3
  warning_count_o = 5
  last_fault_cycle_o = 890
  State decoded: NORMAL
  Fault code decoded: NONE
VCD trace written to waveforms/tb_fault_fsm.vcd
Simulation completed successfully!
```

## Waveform Analysis

### Essential Signals for Analysis
- **clk, rst_n**: Basic timing and reset verification
- **state_o[1:0]**: FSM state progression (00=NORMAL, 01=WARNING, 10=FAULT, 11=SHUTDOWN)
- **fault_latched_o**: Fault latch status indication
- **active_fault_code_o[1:0]**: Active fault type (00=NONE, 01=VOLTAGE, 10=CURRENT, 11=TEMPERATURE)
- **cell_voltage_packed[47:0]**: Input cell voltage monitoring
- **current_raw[11:0], temp_raw[11:0]**: Current and temperature measurements
- **warning_persist_cnt[31:0]**: Persistence counter for escalation timing

### Key Time Periods
- **Reset Period**: Initial cycles showing proper reset behavior
- **Normal Operation**: Stable state with no fault conditions
- **Fault Detection**: Debounce completion and state transition
- **Fault Escalation**: Warning-to-fault progression timing
- **Priority Resolution**: Multiple fault handling with correct priority
- **Manual Reset**: Emergency recovery mechanism operation

## Troubleshooting

### Compilation Issues
- Ensure Verilator is properly installed and in PATH
- Check SystemVerilog syntax if compilation fails
- Verify all source files are present in correct directories
- Use -Wno-fatal flag to treat warnings as non-fatal

### Simulation Issues  
- Confirm executable permissions on generated binary
- Check available disk space for VCD file generation
- Verify waveforms directory exists and is writable
- Review console output for assertion failures

### Waveform Viewing Issues
- Install GTKWave if not available
- Check VCD file was generated successfully
- Verify file permissions on waveform files
- Try alternative waveform viewers if GTKWave unavailable

## Academic Context

This project was developed as part of Digital System Design coursework, demonstrating:

- Advanced SystemVerilog finite state machine design
- Comprehensive verification methodology using C++ testbenches
- Industry-standard EDA tool usage and workflow
- Safety-critical system design principles
- Real-world battery management system requirements



## Performance Characteristics

- **Resource Utilization**: Minimal logic overhead with efficient state encoding
- **Response Time**: Single clock cycle fault detection and state transitions  
- **Throughput**: Real-time monitoring capability for multiple parameters
- **Reliability**: Comprehensive fault coverage with fail-safe operation
- **Maintainability**: Modular design with configurable parameters


## License

This project is developed for educational purposes as part of academic coursework. All code and documentation are provided for learning and evaluation purposes.
