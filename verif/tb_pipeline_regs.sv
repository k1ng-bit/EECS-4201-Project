/*
 * Testbench: tb_pipeline_regs
 *
 * Description: Self-checking unit testbench for the four pipeline registers,
 *   named as in lecture 7: F/D (if_id_reg), D/X (id_ex_reg), X/M (ex_mem_reg)
 *   and M/W (mem_wb_reg). Each register has its own stall and flush inputs.
 *   After every clock edge, every output of every register is compared with a
 *   reference model kept in this testbench.
 *
 * Test cases, grouped by rubric category:
 *   Trivial
 *     T1  Each register loads its inputs on a clock edge.
 *   Corner
 *     C1  Stall holds F/D, D/X and X/M while their inputs change.
 *     C2  M/W has no stall input: it loads on every edge it is not flushed.
 *     C3  Flush loads a bubble: NOP in F/D, ALU_NOP in D/X, zeros in X/M and M/W.
 *     C4  Flush and stall in the same cycle: flush wins.
 *     C5  Releasing a stall: the next edge loads the new inputs.
 *     C6  All-ones and all-zeros values pass through unchanged.
 *   Invalid
 *     I1  Reset asserted between clock edges clears every register at once.
 *     I2  Stall and flush asserted during reset: reset wins, nothing is loaded.
 *     I3  Inputs change while reset is held: nothing is loaded.
 *   Non-trivial sequences
 *     S1  2,000 cycles of random data and random stall/flush per register,
 *         checked after every edge against the reference model.
 *
 * Prints PASS or FAIL per case, then "Test Passed" or "Test Failed".
 */

`timescale 1ns/1ps
`include "constants.svh"

module tb_pipeline_regs;

    localparam int AWIDTH     = 32;     // address width
    localparam int DWIDTH     = 32;     // data width
    localparam int HALF_CYCLE = 5;      // half the clock period, in ns
    localparam int RANDOM_CYCLES = 2000;  // length of the random sequence S1

    //---------- Register contents, in the same layout as the RTL ----------//
    typedef struct packed {
        logic [AWIDTH-1:0] pc;
        logic [DWIDTH-1:0] insn;
    } f_d_t;

    typedef struct packed {
        logic [AWIDTH-1:0]    pc;
        logic [DWIDTH-1:0]    rs1_data;
        logic [DWIDTH-1:0]    rs2_data;
        logic [DWIDTH-1:0]    imm;
        logic [REG_IDX_W-1:0] rd;
        logic [REG_IDX_W-1:0] rs1;
        logic [REG_IDX_W-1:0] rs2;
        logic [FUNCT3_W-1:0]  funct3;
        logic [FUNCT7_W-1:0]  funct7;
        logic [OPCODE_W-1:0]  opcode;
        logic                 pcsel;
        logic                 regwren;
        logic                 memren;
        logic                 memwren;
        logic [WBSEL_W-1:0]   wbsel;
        logic [ALUSEL_W-1:0]  alusel;
    } d_x_t;

    typedef struct packed {
        logic [AWIDTH-1:0]    pc;
        logic [DWIDTH-1:0]    alu_res;
        logic [DWIDTH-1:0]    rs2_data;
        logic [DWIDTH-1:0]    imm;
        logic [REG_IDX_W-1:0] rd;
        logic [FUNCT3_W-1:0]  funct3;
        logic                 regwren;
        logic                 memren;
        logic                 memwren;
        logic [WBSEL_W-1:0]   wbsel;
    } x_m_t;

    typedef struct packed {
        logic [AWIDTH-1:0]    pc;
        logic [DWIDTH-1:0]    alu_res;
        logic [DWIDTH-1:0]    mem_data;
        logic [DWIDTH-1:0]    imm;
        logic [REG_IDX_W-1:0] rd;
        logic                 regwren;
        logic [WBSEL_W-1:0]   wbsel;
    } m_w_t;

    // Expected contents after reset or a flush.
    localparam f_d_t F_D_BUBBLE = '{pc: '0, insn: `NOP};
    localparam d_x_t D_X_BUBBLE = '{alusel: `ALU_NOP, default: '0};
    localparam x_m_t X_M_BUBBLE = '0;
    localparam m_w_t M_W_BUBBLE = '0;

    //---------- Signals ----------//
    logic clk;                    // clock
    logic rst;                    // asynchronous active-high reset
    logic f_d_stall, f_d_flush;   // F/D controls
    logic d_x_stall, d_x_flush;   // D/X controls
    logic x_m_stall, x_m_flush;   // X/M controls
    logic m_w_flush;              // M/W control (M/W has no stall)

    f_d_t f_d_in, f_d_out, f_d_exp;   // F/D inputs, outputs and expected outputs
    d_x_t d_x_in, d_x_out, d_x_exp;   // D/X inputs, outputs and expected outputs
    x_m_t x_m_in, x_m_out, x_m_exp;   // X/M inputs, outputs and expected outputs
    m_w_t m_w_in, m_w_out, m_w_exp;   // M/W inputs, outputs and expected outputs

    int    errors;        // failed checks so far
    int    checks;        // checks done so far
    int    case_errors;   // value of errors when the current case started
    string case_name;     // name of the current case

    //---------- Devices under test ----------//
    if_id_reg #(.AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) dut_f_d (
        .clk(clk), .rst(rst), .stall_i(f_d_stall), .flush_i(f_d_flush),
        .pc_i(f_d_in.pc), .insn_i(f_d_in.insn),
        .pc_o(f_d_out.pc), .insn_o(f_d_out.insn)
    );

    id_ex_reg #(.AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) dut_d_x (
        .clk(clk), .rst(rst), .flush_i(d_x_flush), .stall_i(d_x_stall),
        .pc_i(d_x_in.pc), .rs1_data_i(d_x_in.rs1_data), .rs2_data_i(d_x_in.rs2_data),
        .imm_i(d_x_in.imm), .rd_i(d_x_in.rd), .rs1_i(d_x_in.rs1), .rs2_i(d_x_in.rs2),
        .funct3_i(d_x_in.funct3), .funct7_i(d_x_in.funct7), .opcode_i(d_x_in.opcode),
        .pcsel_i(d_x_in.pcsel), .regwren_i(d_x_in.regwren), .memren_i(d_x_in.memren),
        .memwren_i(d_x_in.memwren), .wbsel_i(d_x_in.wbsel), .alusel_i(d_x_in.alusel),
        .pc_o(d_x_out.pc), .rs1_data_o(d_x_out.rs1_data), .rs2_data_o(d_x_out.rs2_data),
        .imm_o(d_x_out.imm), .rd_o(d_x_out.rd), .rs1_o(d_x_out.rs1), .rs2_o(d_x_out.rs2),
        .funct3_o(d_x_out.funct3), .funct7_o(d_x_out.funct7), .opcode_o(d_x_out.opcode),
        .pcsel_o(d_x_out.pcsel), .regwren_o(d_x_out.regwren), .memren_o(d_x_out.memren),
        .memwren_o(d_x_out.memwren), .wbsel_o(d_x_out.wbsel), .alusel_o(d_x_out.alusel)
    );

    ex_mem_reg #(.AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) dut_x_m (
        .clk(clk), .rst(rst), .flush_i(x_m_flush), .stall_i(x_m_stall),
        .pc_i(x_m_in.pc), .alu_res_i(x_m_in.alu_res), .rs2_data_i(x_m_in.rs2_data),
        .imm_i(x_m_in.imm), .rd_i(x_m_in.rd), .funct3_i(x_m_in.funct3),
        .regwren_i(x_m_in.regwren), .memren_i(x_m_in.memren),
        .memwren_i(x_m_in.memwren), .wbsel_i(x_m_in.wbsel),
        .pc_o(x_m_out.pc), .alu_res_o(x_m_out.alu_res), .rs2_data_o(x_m_out.rs2_data),
        .imm_o(x_m_out.imm), .rd_o(x_m_out.rd), .funct3_o(x_m_out.funct3),
        .regwren_o(x_m_out.regwren), .memren_o(x_m_out.memren),
        .memwren_o(x_m_out.memwren), .wbsel_o(x_m_out.wbsel)
    );

    mem_wb_reg #(.AWIDTH(AWIDTH), .DWIDTH(DWIDTH)) dut_m_w (
        .clk(clk), .rst(rst), .flush_i(m_w_flush),
        .pc_i(m_w_in.pc), .alu_res_i(m_w_in.alu_res), .mem_data_i(m_w_in.mem_data),
        .imm_i(m_w_in.imm), .rd_i(m_w_in.rd), .regwren_i(m_w_in.regwren),
        .wbsel_i(m_w_in.wbsel),
        .pc_o(m_w_out.pc), .alu_res_o(m_w_out.alu_res), .mem_data_o(m_w_out.mem_data),
        .imm_o(m_w_out.imm), .rd_o(m_w_out.rd), .regwren_o(m_w_out.regwren),
        .wbsel_o(m_w_out.wbsel)
    );

    // Free-running clock.
    always #HALF_CYCLE clk = ~clk;

    //---------- Helper tasks ----------//

    // Records one check and reports a failure.
    task automatic check(input string what, input logic ok);
        checks++;
        if (!ok) begin
            errors++;
            $display("  mismatch: %s (case %s, time %0t)", what, case_name, $time);
        end
    endtask

    // Compares every register's outputs with the reference model.
    task automatic check_all();
        check("F/D", f_d_out == f_d_exp);
        check("D/X", d_x_out == d_x_exp);
        check("X/M", x_m_out == x_m_exp);
        check("M/W", m_w_out == m_w_exp);
    endtask

    // Starts and ends a named case, and prints its result.
    task automatic begin_case(input string name);
        case_name   = name;
        case_errors = errors;
    endtask

    task automatic end_case();
        if (errors == case_errors) $display("PASS: %s", case_name);
        else                       $display("FAIL: %s", case_name);
    endtask

    // Sets every stall and flush input.
    task automatic set_controls(input logic fd_s, input logic fd_f, input logic dx_s,
                                input logic dx_f, input logic xm_s, input logic xm_f,
                                input logic mw_f);
        {f_d_stall, f_d_flush, d_x_stall, d_x_flush} = {fd_s, fd_f, dx_s, dx_f};
        {x_m_stall, x_m_flush, m_w_flush}            = {xm_s, xm_f, mw_f};
    endtask

    // Gives every input field a new random value.
    task automatic randomize_inputs();
        f_d_in = '{pc: $urandom(), insn: $urandom()};
        d_x_in = '{pc: $urandom(), rs1_data: $urandom(), rs2_data: $urandom(), imm: $urandom(),
                   rd: REG_IDX_W'($urandom()), rs1: REG_IDX_W'($urandom()),
                   rs2: REG_IDX_W'($urandom()), funct3: FUNCT3_W'($urandom()),
                   funct7: FUNCT7_W'($urandom()), opcode: OPCODE_W'($urandom()),
                   pcsel: 1'($urandom()), regwren: 1'($urandom()), memren: 1'($urandom()),
                   memwren: 1'($urandom()), wbsel: WBSEL_W'($urandom()),
                   alusel: ALUSEL_W'($urandom())};
        x_m_in = '{pc: $urandom(), alu_res: $urandom(), rs2_data: $urandom(), imm: $urandom(),
                   rd: REG_IDX_W'($urandom()), funct3: FUNCT3_W'($urandom()),
                   regwren: 1'($urandom()), memren: 1'($urandom()), memwren: 1'($urandom()),
                   wbsel: WBSEL_W'($urandom())};
        m_w_in = '{pc: $urandom(), alu_res: $urandom(), mem_data: $urandom(), imm: $urandom(),
                   rd: REG_IDX_W'($urandom()), regwren: 1'($urandom()),
                   wbsel: WBSEL_W'($urandom())};
    endtask

    // Sets every input field to the same fill value (all zeros or all ones).
    task automatic fill_inputs(input logic bit_value);
        f_d_in = {$bits(f_d_t){bit_value}};
        d_x_in = {$bits(d_x_t){bit_value}};
        x_m_in = {$bits(x_m_t){bit_value}};
        m_w_in = {$bits(m_w_t){bit_value}};
    endtask

    // Reference model: what each register holds after the next clock edge.
    // Flush wins over stall. M/W has no stall.
    task automatic model_edge();
        if (f_d_flush)       f_d_exp = F_D_BUBBLE;
        else if (!f_d_stall) f_d_exp = f_d_in;
        if (d_x_flush)       d_x_exp = D_X_BUBBLE;
        else if (!d_x_stall) d_x_exp = d_x_in;
        if (x_m_flush)       x_m_exp = X_M_BUBBLE;
        else if (!x_m_stall) x_m_exp = x_m_in;
        m_w_exp = m_w_flush ? M_W_BUBBLE : m_w_in;
    endtask

    // Expected contents while reset is held.
    task automatic model_reset();
        f_d_exp = F_D_BUBBLE;
        d_x_exp = D_X_BUBBLE;
        x_m_exp = X_M_BUBBLE;
        m_w_exp = M_W_BUBBLE;
    endtask

    // One clock edge: inputs and controls are already set. Updates the model
    // from the values present before the edge, then checks just after it.
    task automatic step();
        @(posedge clk);
        model_edge();
        #1 check_all();
    endtask

    //---------- Test sequence ----------//
    initial begin
        clk    = 1'b0;
        errors = 0;
        checks = 0;
        rst    = 1'b1;
        set_controls(0, 0, 0, 0, 0, 0, 0);
        fill_inputs(1'b0);
        model_reset();
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        begin_case("T1  each register loads its inputs");
        randomize_inputs();
        step();
        end_case();

        begin_case("C1  stall holds F/D, D/X and X/M");
        @(negedge clk) set_controls(1, 0, 1, 0, 1, 0, 0);
        repeat (3) begin
            @(negedge clk) randomize_inputs();
            step();
        end
        end_case();

        begin_case("C2  M/W loads on every edge (no stall input)");
        @(negedge clk) randomize_inputs();
        step();
        end_case();

        begin_case("C3  flush loads a bubble");
        @(negedge clk) begin
            set_controls(0, 1, 0, 1, 0, 1, 1);
            randomize_inputs();
        end
        step();
        end_case();

        begin_case("C4  flush and stall together: flush wins");
        @(negedge clk) begin set_controls(0, 0, 0, 0, 0, 0, 0); randomize_inputs(); end
        step();
        @(negedge clk) begin set_controls(1, 1, 1, 1, 1, 1, 1); randomize_inputs(); end
        step();
        end_case();

        begin_case("C5  releasing a stall loads the new inputs");
        @(negedge clk) begin set_controls(1, 0, 1, 0, 1, 0, 0); randomize_inputs(); end
        step();
        @(negedge clk) begin set_controls(0, 0, 0, 0, 0, 0, 0); randomize_inputs(); end
        step();
        end_case();

        begin_case("C6  all-ones and all-zeros pass through");
        @(negedge clk) fill_inputs(1'b1);
        step();
        @(negedge clk) fill_inputs(1'b0);
        step();
        end_case();

        begin_case("I1  reset between edges clears at once");
        @(negedge clk) randomize_inputs();
        step();
        #2 rst = 1'b1;
        model_reset();
        #1 check_all();
        end_case();

        begin_case("I2  stall and flush during reset: reset wins");
        @(negedge clk) set_controls(1, 1, 1, 1, 1, 1, 1);
        @(posedge clk);
        #1 check_all();
        end_case();

        begin_case("I3  inputs change while reset is held");
        @(negedge clk) begin set_controls(0, 0, 0, 0, 0, 0, 0); randomize_inputs(); end
        @(posedge clk);
        #1 check_all();
        @(negedge clk) rst = 1'b0;
        end_case();

        begin_case("S1  random data, stall and flush for 2,000 cycles");
        repeat (RANDOM_CYCLES) begin
            @(negedge clk) begin
                randomize_inputs();
                set_controls(1'($urandom()), 1'($urandom()), 1'($urandom()),
                             1'($urandom()), 1'($urandom()), 1'($urandom()),
                             1'($urandom()));
            end
            step();
        end
        end_case();

        $display("Checks: %0d, errors: %0d", checks, errors);
        if (errors == 0) begin
            $display("Test Passed");
            $finish;
        end else begin
            $display("Test Failed");
            $fatal(1, "tb_pipeline_regs: %0d check(s) failed", errors);
        end
    end

endmodule : tb_pipeline_regs
