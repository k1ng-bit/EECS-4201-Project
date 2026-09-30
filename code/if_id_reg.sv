/*
 * Module: if_id_reg
 *
 * Description: Pipeline register between the Instruction Fetch (IF)
 *              and Instruction Decode (ID) stages. Latches the program
 *              counter and fetched instruction each cycle.
 *
 * Features:
 *   - Asynchronous reset: clears to NOP bubble
 *   - Synchronous stall:  holds current values (data hazard)
 *   - Synchronous flush:  inserts NOP bubble (control hazard)
 *
 * Inputs:
 *   1) clk       - Clock signal
 *   2) rst       - Asynchronous active-high reset
 *   3) stall_i   - Hold current register values
 *   4) flush_i   - Clear register to NOP bubble
 *   5) pc_i      - Program counter from IF stage
 *   6) insn_i    - Instruction fetched from memory
 *
 * Outputs:
 *   1) pc_o      - Latched program counter to ID stage
 *   2) insn_o    - Latched instruction to ID stage
 */

`include "constants.svh"

module if_id_reg #(
    parameter int AWIDTH = 32,
    parameter int DWIDTH = 32
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              stall_i,
    input  logic              flush_i,
    // IF stage inputs
    input  logic [AWIDTH-1:0] pc_i,
    input  logic [DWIDTH-1:0] insn_i,
    // ID stage outputs
    output logic [AWIDTH-1:0] pc_o,
    output logic [DWIDTH-1:0] insn_o
);

    // Latch program counter and instruction with async reset
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_o   <= '0;
            insn_o <= `NOP;
        end else if (flush_i) begin
            pc_o   <= '0;
            insn_o <= `NOP;
        end else if (!stall_i) begin
            pc_o   <= pc_i;
            insn_o <= insn_i;
        end
        // Implicit: if stall_i is high, hold current values
    end

endmodule : if_id_reg
