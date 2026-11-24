/*
 * Module: if_id_reg
 *
 * Description: F/D pipeline register (lecture 7), between IF and ID. Holds
 *              the PC and the fetched instruction.
 *   - Asynchronous reset: loads a NOP bubble.
 *   - Flush: loads a NOP bubble (wrong-path instruction after a taken branch,
 *     or no instruction yet because the fetch is still waiting).
 *   - Stall: keeps its value (lecture 7, "disable F/D pipeline reg").
 *   Flush wins over stall.
 *
 * Inputs:
 *   1) clk      - Clock signal
 *   2) rst      - Asynchronous active-high reset
 *   3) stall_i  - Keep the current values
 *   4) flush_i  - Load a NOP bubble
 *   5) pc_i     - PC from IF
 *   6) insn_i   - Instruction from IF
 *
 * Outputs:
 *   1) pc_o     - PC to ID
 *   2) insn_o   - Instruction to ID
 */

`include "constants.svh"

module if_id_reg #(
    parameter int AWIDTH = 32,   // address width
    parameter int DWIDTH = 32    // data width
)(
    input  logic              clk,       // clock
    input  logic              rst,       // asynchronous active-high reset
    input  logic              stall_i,   // 1 = keep the current values
    input  logic              flush_i,   // 1 = load a NOP bubble
    input  logic [AWIDTH-1:0] pc_i,      // PC from IF
    input  logic [DWIDTH-1:0] insn_i,    // instruction from IF
    output logic [AWIDTH-1:0] pc_o,      // PC to ID
    output logic [DWIDTH-1:0] insn_o     // instruction to ID
);

    // Contents of the F/D register.
    typedef struct packed {
        logic [AWIDTH-1:0] pc;     // PC of the instruction
        logic [DWIDTH-1:0] insn;   // the instruction
    } f_d_t;

    // Bubble: a NOP at PC 0.
    localparam f_d_t F_D_BUBBLE = '{pc: '0, insn: `NOP};

    f_d_t f_d_q;   // register contents
    f_d_t f_d_d;   // values arriving from IF

    assign f_d_d = '{pc: pc_i, insn: insn_i};

    // F/D register: reset or flush load a bubble, stall holds, otherwise load IF.
    always_ff @(posedge clk or posedge rst) begin : f_d_register
        if (rst)           f_d_q <= F_D_BUBBLE;
        else if (flush_i)  f_d_q <= F_D_BUBBLE;
        else if (!stall_i) f_d_q <= f_d_d;
    end

    assign pc_o   = f_d_q.pc;
    assign insn_o = f_d_q.insn;

endmodule : if_id_reg
