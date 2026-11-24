/*
 * Module: writeback
 *
 * Description: WB stage. Selects the value written to register rd with the
 *              WBSel control signal (lecture 6):
 *                WB_ALU - ALU result (arithmetic, logic, shifts, compares)
 *                WB_MEM - data loaded from memory (loads)
 *                WB_PC4 - return address PC + 4 (JAL, JALR)
 *                WB_IMM - the immediate (LUI)
 *
 * Inputs:
 *   1) pc_i             - PC of the instruction in WB
 *   2) alu_res_i        - ALU result
 *   3) memory_data_i    - Data loaded from memory
 *   4) wbsel_i          - WBSel: which value to write back
 *   5) imm_i            - Immediate value
 *
 * Outputs:
 *   1) writeback_data_o - Value written to register rd
 */

`include "constants.svh"

module writeback #(
    parameter int DWIDTH = 32,   // data width
    parameter int AWIDTH = 32    // address width
)(
    input  logic [AWIDTH-1:0]  pc_i,              // PC of the instruction in WB
    input  logic [DWIDTH-1:0]  alu_res_i,         // ALU result
    input  logic [DWIDTH-1:0]  memory_data_i,     // data loaded from memory
    input  logic [WBSEL_W-1:0] wbsel_i,           // WBSel control
    input  logic [DWIDTH-1:0]  imm_i,             // immediate value
    output logic [DWIDTH-1:0]  writeback_data_o   // value written to rd
);

    // WBSel mux (lecture 6). The remaining code, WB_IMM, selects the immediate.
    assign writeback_data_o = (wbsel_i == `WB_ALU) ? alu_res_i
                            : (wbsel_i == `WB_MEM) ? memory_data_i
                            : (wbsel_i == `WB_PC4) ? pc_i + INSN_BYTES
                            :                        imm_i;

endmodule : writeback
