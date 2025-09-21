// sim/main.cpp
// Verilator C++ harness to drive fault_fsm (verilator --build supports --trace)
#include <iostream>
#include <vector>
#include "Vfault_fsm.h"
#include "verilated.h"
#if VM_TRACE
# include "verilated_vcd_c.h"
#endif

// Global time counter for VCD tracing
vluint64_t main_time = 0;

// Called by $time in Verilog
double sc_time_stamp() {
    return main_time;
}

// helper: pack cells into vector-width integer (matches ADC_WIDTH)
static uint64_t pack_cells(const std::vector<int>& vals, int ADC_WIDTH) {
    uint64_t packed = 0;
    for (size_t i=0;i<vals.size();++i) {
        uint64_t v = (uint64_t) (vals[i] & ((1u<<ADC_WIDTH)-1));
        packed |= (v << (i*ADC_WIDTH));
    }
    return packed;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vfault_fsm* dut = new Vfault_fsm;
    
#if VM_TRACE
    VerilatedVcdC* tfp = NULL;
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("waveforms/tb_fault_fsm.vcd");
#endif

    // parameters (match the SV TB expectations)
    const int ADC_WIDTH = 12;
    const int NUM_CELLS = 4;
    
    // reset
    dut->clk = 0;
    dut->rst_n = 0;
    dut->manual_reset = 0;
    
    // default inputs
    uint64_t packed = pack_cells({360,360,360,360}, ADC_WIDTH);
    dut->cell_voltage_packed = packed;
    dut->current_raw = 100;
    dut->temp_raw = 40;
    dut->mask_voltage = 0;
    dut->mask_current = 0;
    dut->mask_temp = 0;
    
    // run for N cycles with clk toggle every step (half-cycle semantics)
    const uint64_t MAX_CYCLES = 20000; // adjust if you need longer sim
    uint64_t cycle = 0;
    
    // timeline convenience lambdas
    auto apply_cells = [&](std::initializer_list<int> list){ 
        dut->cell_voltage_packed = pack_cells(std::vector<int>(list), ADC_WIDTH); 
    };
    
    auto tick = [&](){
        // posedge
        dut->clk = 0;
        dut->eval();
#if VM_TRACE
        if (tfp) tfp->dump(main_time);
#endif
        main_time += 5;
        
        dut->clk = 1;
        dut->eval();
#if VM_TRACE
        if (tfp) tfp->dump(main_time);
#endif
        main_time += 5;
        
        // negedge
        dut->clk = 0;
        dut->eval();
#if VM_TRACE
        if (tfp) tfp->dump(main_time);
#endif
        main_time += 5;
        cycle++;
    };
    
    // reset for first 4 cycles
    std::cout << "Starting simulation..." << std::endl;
    for (int i=0;i<4;i++) tick();
    dut->rst_n = 1;
    
    // normal 0..99
    std::cout << "Running normal operation cycles..." << std::endl;
    for (int i=0;i<100;i++) tick();
    
    // transient spike shorter than debounce (4 cycles)
    std::cout << "Testing transient spike..." << std::endl;
    apply_cells({360,290,360,360});
    for (int i=0;i<4;i++) tick();
    apply_cells({360,360,360,360});
    for (int i=0;i<40;i++) tick();
    
    // persistent undervolt -> escalate
    std::cout << "Testing persistent undervolt..." << std::endl;
    apply_cells({360,360,280,360});
    for (int i=0;i<300;i++) tick();
    
    // temp priority event
    std::cout << "Testing temperature priority..." << std::endl;
    dut->temp_raw = 90;
    for (int i=0;i<60;i++) tick();
    dut->temp_raw = 40;
    for (int i=0;i<60;i++) tick();
    
    // current persistent
    std::cout << "Testing current fault..." << std::endl;
    dut->current_raw = 220;
    for (int i=0;i<120;i++) tick();
    dut->current_raw = 100;
    for (int i=0;i<40;i++) tick();
    
    // mask voltage and sustain undervolt
    std::cout << "Testing voltage masking..." << std::endl;
    dut->mask_voltage = 1;
    apply_cells({360,360,270,360});
    for (int i=0;i<200;i++) tick();
    
    // manual reset
    std::cout << "Testing manual reset..." << std::endl;
    dut->manual_reset = 1;
    for (int i=0;i<2;i++) tick();
    dut->manual_reset = 0;
    for (int i=0;i<40;i++) tick();
    
    // print telemetry outputs at end
    std::cout << "\n=== SIMULATION COMPLETE ===" << std::endl;
    std::cout << "Simulation ended at cycle " << cycle << " (time=" << main_time << ")" << std::endl;
    std::cout << "Final state:" << std::endl;
    std::cout << "  state_o = " << (int)dut->state_o << std::endl;
    std::cout << "  fault_latched_o = " << (int)dut->fault_latched_o << std::endl;
    std::cout << "  active_fault_code_o = " << (int)dut->active_fault_code_o << std::endl;
    std::cout << "  fault_count_o = " << dut->fault_count_o << std::endl;
    std::cout << "  warning_count_o = " << dut->warning_count_o << std::endl;
    std::cout << "  last_fault_cycle_o = " << dut->last_fault_cycle_o << std::endl;
    
    // State decode for readability
    const char* state_names[] = {"NORMAL", "WARNING", "FAULT", "SHUTDOWN"};
    std::cout << "  State decoded: " << state_names[dut->state_o & 0x3] << std::endl;
    
    const char* fault_code_names[] = {"NONE", "VOLTAGE", "CURRENT", "TEMPERATURE"};
    std::cout << "  Fault code decoded: " << fault_code_names[dut->active_fault_code_o & 0x3] << std::endl;

#if VM_TRACE
    if (tfp) {
        tfp->close();
        delete tfp;
        std::cout << "VCD trace written to waveforms/tb_fault_fsm.vcd" << std::endl;
    }
#endif

    dut->final();
    delete dut;
    
    std::cout << "Simulation completed successfully!" << std::endl;
    return 0;
}
