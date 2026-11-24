/*
 * Testbench: tb_control
 *
 * Description: Self-checking unit testbench for the control module (lecture 6 control
 *   signals). This first version covers the FENCE decode added for the store buffer
 *   and the signals that must stay quiet for it. The control module is combinational,
 *   so each case drives an opcode and funct3 and checks the outputs after a short delay.
 *
 * Test cases, grouped by rubric category:
 *   Trivial
 *     T1  FENCE (MISC_MEM, funct3 = 0) raises is_fence_o and does nothing else:
 *         no register write, no memory access, no jump, ALU_NOP.
 *   Corner
 *     C1  Every other legal opcode leaves is_fence_o low.
 *     C2  FENCE.I (MISC_MEM, funct3 = 1) does not raise is_fence_o and has no side effect.
 *   Invalid
 *     I1  An unknown opcode writes no register, writes no memory and raises no flag.
 *   Non-trivial sequences
 *     S1  Every opcode with every funct3: is_fence_o is high only for FENCE, a memory
 *         write only for stores, a memory read only for loads.
 *
 * Prints PASS or FAIL per case, then "Test Passed" or "Test Failed".
 * TODO: check every lecture-6 control signal (PCSel, ImmSel, RegWEn, ASel/BSel, ALUSel,
 *       MemRW, WBSel) for every opcode, together with decode and igen.
 */

`timescale 1ns/1ps
`include "constants.svh"

module tb_control;

    localparam int DWIDTH = 32;   // data width

    logic [DWIDTH-1:0] insn;      // instruction (not used by control, kept at zero)
    logic [6:0]        opcode;    // opcode field
    logic [6:0]        funct7;    // funct7 field
    logic [2:0]        funct3;    // funct3 field
    logic              pcsel, immsel, regwren, rs1sel, rs2sel, memren, memwren, is_fence;
    logic [1:0]        wbsel;
    logic [3:0]        alusel;

    int    errors;        // failed checks so far
    int    checks;        // checks done so far
    int    case_errors;   // value of errors when the current case started
    string case_name;     // name of the current case

    // Opcodes of the legal instructions in this core.
    localparam logic [6:0] LEGAL_OPCODES [9] = '{`R_TYPE, `I_TYPE, `I_TYPE_L, `I_TYPE_JALR, `S_TYPE,
                                                 `B_TYPE, `J_TYPE, `U_TYPE_LUI, `U_TYPE_AUIPC};

    control #(.DWIDTH(DWIDTH)) dut (
        .insn_i(insn), .opcode_i(opcode), .funct7_i(funct7), .funct3_i(funct3),
        .pcsel_o(pcsel), .immsel_o(immsel), .regwren_o(regwren), .rs1sel_o(rs1sel),
        .rs2sel_o(rs2sel), .memren_o(memren), .memwren_o(memwren), .wbsel_o(wbsel),
        .alusel_o(alusel), .is_fence_o(is_fence)
    );

    task automatic check(input string what, input logic ok);
        checks++;
        if (!ok) begin
            errors++;
            $display("  mismatch: %s (case %s, opcode %b, funct3 %b)", what, case_name, opcode, funct3);
        end
    endtask

    task automatic begin_case(input string name);
        case_name   = name;
        case_errors = errors;
    endtask

    task automatic end_case();
        if (errors == case_errors) $display("PASS: %s", case_name);
        else                       $display("FAIL: %s", case_name);
    endtask

    // Drives one instruction and waits for the combinational outputs to settle.
    task automatic drive(input logic [6:0] op, input logic [2:0] f3);
        opcode = op;  funct3 = f3;
        #1;
    endtask

    // Checks that the instruction has no side effect: no register write, memory access or jump.
    task automatic check_no_side_effect();
        check("no register write", regwren === 1'b0);
        check("no memory read",    memren  === 1'b0);
        check("no memory write",   memwren === 1'b0);
        check("no jump",           pcsel   === 1'b0);
        check("ALU_NOP",           alusel  === `ALU_NOP);
    endtask

    initial begin
        errors = 0;  checks = 0;  insn = '0;  funct7 = '0;

        begin_case("T1  FENCE raises is_fence_o and has no side effect");
        drive(`MISC_MEM, `F3_FENCE);
        check("is_fence_o is high", is_fence === 1'b1);
        check_no_side_effect();
        end_case();

        begin_case("C1  every other legal opcode leaves is_fence_o low");
        for (int i = 0; i < 9; i++) begin
            drive(LEGAL_OPCODES[i], 3'b000);
            check("is_fence_o is low", is_fence === 1'b0);
        end
        end_case();

        begin_case("C2  FENCE.I does not raise is_fence_o and has no side effect");
        drive(`MISC_MEM, 3'b001);
        check("is_fence_o is low", is_fence === 1'b0);
        check_no_side_effect();
        end_case();

        begin_case("I1  an unknown opcode has no effect");
        drive(7'b1111111, 3'b000);
        check("is_fence_o is low", is_fence === 1'b0);
        check_no_side_effect();
        end_case();

        begin_case("S1  every opcode with every funct3");
        for (int op = 0; op < 128; op++) begin
            for (int f3 = 0; f3 < 8; f3++) begin
                drive(7'(op), 3'(f3));
                check("is_fence_o only for FENCE",  is_fence === (7'(op) == `MISC_MEM && 3'(f3) == `F3_FENCE));
                check("memory write only for a store", memwren === (7'(op) == `S_TYPE));
                check("memory read only for a load",   memren  === (7'(op) == `I_TYPE_L));
            end
        end
        end_case();

        $display("Checks: %0d, errors: %0d", checks, errors);
        if (errors == 0) begin
            $display("Test Passed");
            $finish;
        end else begin
            $display("Test Failed");
            $fatal(1, "tb_control: %0d check(s) failed", errors);
        end
    end

endmodule : tb_control
