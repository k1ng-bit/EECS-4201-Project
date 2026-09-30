/*
 * Module: fetch
 *
 * Description: Fetch stage — manages the program counter (PC) register.
 *              Advances PC by 4 each cycle, redirects on branch/jump,
 *              and holds on stall.
 *
 * Inputs:
 *   1) clk            - Clock signal
 *   2) rst            - Asynchronous active-high reset
 *   3) next_pc_i      - Branch/jump target address from EX stage
 *   4) pc_en_i        - PC enable (0 = stall, 1 = advance)
 *   5) jump_branch_i  - Branch taken or jump detected in EX stage
 *
 * Outputs:
 *   1) pc_o           - Current program counter value
 */

`include "constants.svh"

module fetch #(
    parameter int DWIDTH = 32,
    parameter int AWIDTH = 32,
    parameter int BASEADDR = 32'h01000000
)(
    input  logic              clk,
    input  logic              rst,
    input  logic [AWIDTH-1:0] next_pc_i,
    input  logic              pc_en_i,
    input  logic              jump_branch_i,
    output logic [AWIDTH-1:0] pc_o
);

    // Program counter register
    logic [AWIDTH-1:0] pc;

    // Drive output directly from the register
    assign pc_o = pc;

    // PC update logic with asynchronous reset
    // TODO: Consider adding branch prediction target as an input
    always_ff @(posedge clk or posedge rst) begin
        if (rst)                pc <= BASEADDR;
        else if (!pc_en_i)      ;                  // Stall: hold PC
        else if (jump_branch_i) pc <= next_pc_i;   // Redirect to target
        else                    pc <= pc + 32'd4;   // Sequential fetch
    end

endmodule : fetch
