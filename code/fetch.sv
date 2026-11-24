/*
 * Module: fetch
 *
 * Description: IF stage program counter (PC). Each cycle the PC write enable
 *              (lecture 7, "PC write enable") either holds the PC or moves
 *              it: to the branch or jump target when EX redirects, otherwise
 *              to the next instruction, PC + 4.
 *
 * Inputs:
 *   1) clk            - Clock signal
 *   2) rst            - Asynchronous active-high reset (PC = BASE_ADDR)
 *   3) next_pc_i      - Branch or jump target computed in EX
 *   4) pc_en_i        - PC write enable: 0 holds the PC (stall)
 *   5) jump_branch_i  - EX took a branch or jump: go to next_pc_i
 *
 * Outputs:
 *   1) pc_o           - Current program counter
 */

`include "constants.svh"

module fetch #(
    parameter int DWIDTH = 32,                               // data width
    parameter int AWIDTH = 32,                               // address width
    parameter logic [AWIDTH-1:0] BASE_ADDR = MEM_BASE_ADDR   // reset PC: the first instruction
)(
    input  logic              clk,            // clock
    input  logic              rst,            // asynchronous active-high reset
    input  logic [AWIDTH-1:0] next_pc_i,      // branch or jump target from EX
    input  logic              pc_en_i,        // PC write enable (0 = stall)
    input  logic              jump_branch_i,  // 1 = redirect to next_pc_i
    output logic [AWIDTH-1:0] pc_o            // current program counter
);

    logic [AWIDTH-1:0] pc;   // program counter register

    assign pc_o = pc;

    // PC register: holds while the PC write enable is low; otherwise it
    // redirects on a taken branch or jump, or steps to the next instruction.
    // TODO: take a predicted target here once a branch predictor exists.
    always_ff @(posedge clk or posedge rst) begin : pc_register
        if (rst)          pc <= BASE_ADDR;
        else if (pc_en_i) pc <= jump_branch_i ? next_pc_i : pc + INSN_BYTES;
    end

endmodule : fetch
