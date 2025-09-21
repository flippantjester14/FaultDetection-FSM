// src/fault_fsm.sv
// Production-ready Fault FSM with SVA + telemetry counters
module fault_fsm #(
    parameter int NUM_CELLS = 4,
    parameter int ADC_WIDTH = 12,
    parameter int V_WARN = 330,
    parameter int V_FAULT = 300,
    parameter int I_WARN = 150,
    parameter int I_FAULT = 200,
    parameter int T_WARN = 60,
    parameter int T_FAULT = 80,
    parameter int DEBOUNCE_CYCLES = 8,
    parameter int PERSIST_TO_FAULT = 50,
    
    // Local parameters for consistent widths
    localparam int DEBOUNCE_WIDTH = $clog2(DEBOUNCE_CYCLES+1)
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic [(NUM_CELLS*ADC_WIDTH)-1:0] cell_voltage_packed,
    input  logic [ADC_WIDTH-1:0]          current_raw,
    input  logic [ADC_WIDTH-1:0]          temp_raw,
    input  logic                          mask_voltage,
    input  logic                          mask_current,
    input  logic                          mask_temp,
    input  logic                          manual_reset,

    output logic [1:0]                    state_o,
    output logic                          fault_latched_o,
    output logic [1:0]                    active_fault_code_o,
    // telemetry
    output logic [31:0]                   fault_count_o,
    output logic [31:0]                   warning_count_o,
    output logic [31:0]                   last_fault_cycle_o
);

    localparam STATE_NORMAL   = 2'd0;
    localparam STATE_WARNING  = 2'd1;
    localparam STATE_FAULT    = 2'd2;
    localparam STATE_SHUTDOWN = 2'd3;

    // helper to extract cell
    function automatic logic [ADC_WIDTH-1:0] get_cell(input int idx);
        get_cell = cell_voltage_packed[(idx+1)*ADC_WIDTH-1 -: ADC_WIDTH];
    endfunction

    // resolve visible code (priority: TEMP>CURR>VOLT)
    function automatic logic [1:0] resolve_code(input logic v, input logic c, input logic t,
                                                 input logic m_v, input logic m_c, input logic m_t);
        if (t && !m_t) resolve_code = 2'd3;
        else if (c && !m_c) resolve_code = 2'd2;
        else if (v && !m_v) resolve_code = 2'd1;
        else resolve_code = 2'd0;
    endfunction

    // debounce counters & flags
    logic [DEBOUNCE_WIDTH-1:0] cell_cnt [NUM_CELLS];
    logic [DEBOUNCE_WIDTH-1:0] curr_cnt;
    logic [DEBOUNCE_WIDTH-1:0] temp_cnt;
    logic cell_debounced [NUM_CELLS];
    logic curr_debounced;
    logic temp_debounced;

    // FSM regs
    logic [1:0] state_reg, state_nxt;
    logic [31:0] warning_persist_cnt;
    logic fault_latched_reg;
    logic [1:0] active_fault_code_reg;

    // telemetry regs
    logic [31:0] fault_count_reg;
    logic [31:0] warning_count_reg;
    logic [31:0] last_fault_cycle_reg;
    logic [31:0] cycle_counter;

    // simple all-cells aggregate flag (module-scope)
    logic any_cell_deb;
    
    // Current fault code - moved outside always_ff block
    logic [1:0] cur_code;

    int i;
    // debounce synchronous and FSM update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0;i<NUM_CELLS;i=i+1) begin
                cell_cnt[i] <= '0;
                cell_debounced[i] <= 1'b0;
            end
            curr_cnt <= '0; temp_cnt <= '0;
            curr_debounced <= 1'b0; temp_debounced <= 1'b0;
            state_reg <= STATE_NORMAL;
            warning_persist_cnt <= 32'd0;
            fault_latched_reg <= 1'b0;
            active_fault_code_reg <= 2'd0;
            fault_count_reg <= 32'd0;
            warning_count_reg <= 32'd0;
            last_fault_cycle_reg <= 32'd0;
            cycle_counter <= 32'd0;
            any_cell_deb <= 1'b0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            // per-cell debounce
            for (i=0;i<NUM_CELLS;i=i+1) begin
                if (get_cell(i) < ADC_WIDTH'(V_WARN))
                    cell_cnt[i] <= (cell_cnt[i] == DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES)) ? cell_cnt[i] : cell_cnt[i] + 1;
                else
                    cell_cnt[i] <= '0;
                cell_debounced[i] <= (cell_cnt[i] >= DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES));
            end
            // current debounce
            if (current_raw > ADC_WIDTH'(I_WARN))
                curr_cnt <= (curr_cnt == DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES)) ? curr_cnt : curr_cnt + 1;
            else curr_cnt <= '0;
            curr_debounced <= (curr_cnt >= DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES));
            // temp debounce
            if (temp_raw > ADC_WIDTH'(T_WARN))
                temp_cnt <= (temp_cnt == DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES)) ? temp_cnt : temp_cnt + 1;
            else temp_cnt <= '0;
            temp_debounced <= (temp_cnt >= DEBOUNCE_WIDTH'(DEBOUNCE_CYCLES));

            // any_cell_deb computation
            any_cell_deb <= 1'b0;
            for (i=0;i<NUM_CELLS;i=i+1) any_cell_deb <= any_cell_deb | cell_debounced[i];

            // resolve visible code
            cur_code = resolve_code(any_cell_deb, curr_debounced, temp_debounced,
                                   mask_voltage, mask_current, mask_temp);

            // FSM next
            state_nxt = state_reg;
            case (state_reg)
                STATE_NORMAL: if (cur_code != 2'd0) begin state_nxt = STATE_WARNING; warning_count_reg <= warning_count_reg + 1; end
                STATE_WARNING: begin
                    if (cur_code == 2'd0) begin
                        if (warning_persist_cnt == 0) state_nxt = STATE_NORMAL;
                        else warning_persist_cnt <= warning_persist_cnt - 1;
                    end else begin
                        warning_persist_cnt <= warning_persist_cnt + 1;
                        if (warning_persist_cnt >= PERSIST_TO_FAULT) begin
                            state_nxt = STATE_FAULT;
                        end
                    end
                end
                STATE_FAULT: begin
                    if (manual_reset) begin
                        state_nxt = STATE_NORMAL;
                    end else if (temp_debounced && !mask_temp) begin
                        state_nxt = STATE_SHUTDOWN;
                    end
                end
                STATE_SHUTDOWN: if (manual_reset) state_nxt = STATE_NORMAL;
            endcase

            // latch and telemetry updates
            if (state_nxt == STATE_FAULT && state_reg != STATE_FAULT) begin
                fault_latched_reg <= 1'b1;
                active_fault_code_reg <= cur_code;
                fault_count_reg <= fault_count_reg + 1;
                last_fault_cycle_reg <= cycle_counter;
            end
            if (state_nxt == STATE_SHUTDOWN) begin
                fault_latched_reg <= 1'b1;
                active_fault_code_reg <= 2'd3;
                fault_count_reg <= fault_count_reg + 1;
                last_fault_cycle_reg <= cycle_counter;
            end
            if (manual_reset) begin
                fault_latched_reg <= 1'b0;
                active_fault_code_reg <= 2'd0;
                warning_persist_cnt <= 32'd0;
            end
            state_reg <= state_nxt;
        end
    end

    // outputs
    assign state_o = state_reg;
    assign fault_latched_o = fault_latched_reg;
    assign active_fault_code_o = active_fault_code_reg;
    assign fault_count_o = fault_count_reg;
    assign warning_count_o = warning_count_reg;
    assign last_fault_cycle_o = last_fault_cycle_reg;

    //-------------------------------------------------
    // Assertions - converted to simple checks for Verilator compatibility
    //-------------------------------------------------
`ifdef ASSERTIONS_ON
    // Check for direct NORMAL->SHUTDOWN transition
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if ($past(state_reg) == STATE_NORMAL && state_reg == STATE_SHUTDOWN) begin
                $error("Assertion failed: direct NORMAL->SHUTDOWN transition detected");
            end
        end
    end

    // Check temp priority
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (temp_debounced && !mask_temp && fault_latched_reg && active_fault_code_reg != 2'd3) begin
                $error("Assertion failed: temp priority violated");
            end
        end
    end

    // Check latch matches code
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (fault_latched_reg && (state_reg==STATE_FAULT || state_reg==STATE_SHUTDOWN) && active_fault_code_reg == 2'd0) begin
                $error("Assertion failed: latch without code");
            end
        end
    end
`endif

endmodule
