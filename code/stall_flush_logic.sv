/*
 * Module: stall_flush_logic
 *
 * Description: Generates pipeline control signals to handle data hazards
 *              (stall) and control hazards (flush). This stub implements
 *              only branch/jump flush logic. Data hazard detection is
 *              left for Member 2 to complete.
 *
 * Inputs:
 *   1)  id_rs1_i, id_rs2_i           - Source register addresses in ID
 *   2)  id_rs1_valid_i, id_rs2_valid_i - Whether ID instruction reads rs1/rs2
 *   3)  ex_rd_i, ex_regwren_i        - Destination reg and write-en in EX
 *   4)  ex_memren_i                  - Load instruction in EX
 *   5)  ex_brtaken_i                 - Branch taken in EX
 *   6)  ex_is_jump_i                 - JAL/JALR in EX
 *   7)  mem_rd_i, mem_regwren_i      - Destination reg and write-en in MEM
 *   8)  mem_memren_i                 - Load instruction in MEM
 *
 * Outputs:
 *   1) pc_en_o        - 0 = freeze PC (stall), 1 = advance normally
 *   2) if_id_stall_o  - 1 = hold IF/ID register contents
 *   3) if_id_flush_o  - 1 = flush IF/ID to NOP bubble
 *   4) id_ex_flush_o  - 1 = flush ID/EX to bubble
 *   5) ex_mem_flush_o - 1 = flush EX/MEM to bubble
 */

`include "constants.svh"

module stall_flush_logic (
    // Source register info from ID stage
    input  logic [4:0] id_rs1_i,
    input  logic [4:0] id_rs2_i,
    input  logic       id_rs1_valid_i,
    input  logic       id_rs2_valid_i,
    // Destination and control from EX stage
    input  logic [4:0] ex_rd_i,
    input  logic       ex_regwren_i,
    input  logic       ex_memren_i,
    input  logic       ex_brtaken_i,
    input  logic       ex_is_jump_i,
    // Destination and control from MEM stage
    input  logic [4:0] mem_rd_i,
    input  logic       mem_regwren_i,
    input  logic       mem_memren_i,
    // Pipeline control outputs
    output logic       pc_en_o,
    output logic       if_id_stall_o,
    output logic       if_id_flush_o,
    output logic       id_ex_flush_o,
    output logic       ex_mem_flush_o
);

    // ------------------------------------------------------------------
    // Control hazard detection: flush pipeline on taken branch or jump
    // ------------------------------------------------------------------
    logic control_hazard;
    assign control_hazard = ex_brtaken_i || ex_is_jump_i;

    // ------------------------------------------------------------------
    // Data hazard detection (STUB — to be completed by Member 2)
    // TODO: Detect RAW hazards between ID and EX/MEM stages
    // TODO: Detect load-use hazards requiring pipeline stall
    // ------------------------------------------------------------------
    logic data_hazard;
    assign data_hazard = 1'b0;  // Stub: no data hazard detection

    // ------------------------------------------------------------------
    // Output generation
    // ------------------------------------------------------------------
    // PC stalls only on data hazards (not on control hazards)
    assign pc_en_o       = !data_hazard;

    // Stall IF/ID only on data hazards
    assign if_id_stall_o = data_hazard;

    // Flush IF/ID on control hazard (wrong instruction was fetched)
    assign if_id_flush_o = control_hazard;

    // Flush ID/EX on control hazard OR data hazard (insert bubble)
    assign id_ex_flush_o = control_hazard || data_hazard;

    // Flush EX/MEM only if needed (reserved for future use)
    assign ex_mem_flush_o = 1'b0;

endmodule : stall_flush_logic
