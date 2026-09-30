/*
 * Module: ex_mem_reg
 *
 * Description: Pipeline register between the Execute (EX) and
 *              Memory Access (MEM) stages. Latches ALU result,
 *              store data, instruction metadata, and control signals.
 *
 * Features:
 *   - Asynchronous reset: clears all fields to zero / safe defaults
 *   - Synchronous flush:  inserts bubble (zeroes control signals)
 *
 * Inputs:
 *   1) clk, rst, flush_i             - Clock, reset, flush control
 *   2) pc_i                          - Program counter (for WB_PC4)
 *   3) alu_res_i                     - ALU result (data addr or computation)
 *   4) rs2_data_i                    - Store data from rs2
 *   5) rd_i, funct3_i               - Destination register and funct3
 *   6) imm_i                         - Immediate value (for WB_IMM / LUI)
 *   7) regwren_i .. wbsel_i          - Control signals
 *
 * Outputs:
 *   Corresponding latched values with _o suffix for the MEM stage.
 */

`include "constants.svh"

module ex_mem_reg #(
    parameter int AWIDTH = 32,
    parameter int DWIDTH = 32
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush_i,
    // Data inputs from EX stage
    input  logic [AWIDTH-1:0] pc_i,
    input  logic [DWIDTH-1:0] alu_res_i,
    input  logic [DWIDTH-1:0] rs2_data_i,
    input  logic [DWIDTH-1:0] imm_i,
    // Instruction metadata inputs from EX stage
    input  logic [4:0]        rd_i,
    input  logic [2:0]        funct3_i,
    // Control signal inputs from EX stage
    input  logic              regwren_i,
    input  logic              memren_i,
    input  logic              memwren_i,
    input  logic [1:0]        wbsel_i,
    // Data outputs to MEM stage
    output logic [AWIDTH-1:0] pc_o,
    output logic [DWIDTH-1:0] alu_res_o,
    output logic [DWIDTH-1:0] rs2_data_o,
    output logic [DWIDTH-1:0] imm_o,
    // Instruction metadata outputs to MEM stage
    output logic [4:0]        rd_o,
    output logic [2:0]        funct3_o,
    // Control signal outputs to MEM stage
    output logic              regwren_o,
    output logic              memren_o,
    output logic              memwren_o,
    output logic [1:0]        wbsel_o
);

    // Latch ALU result and store data
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush_i) begin
            alu_res_o  <= '0;
            rs2_data_o <= '0;
        end else begin
            alu_res_o  <= alu_res_i;
            rs2_data_o <= rs2_data_i;
        end
    end

    // Latch program counter and immediate value
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush_i) begin
            pc_o  <= '0;
            imm_o <= '0;
        end else begin
            pc_o  <= pc_i;
            imm_o <= imm_i;
        end
    end

    // Latch destination register and funct3
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush_i) begin
            rd_o     <= '0;
            funct3_o <= '0;
        end else begin
            rd_o     <= rd_i;
            funct3_o <= funct3_i;
        end
    end

    // Latch memory control signals
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush_i) begin
            regwren_o <= '0;
            memren_o  <= '0;
            memwren_o <= '0;
        end else begin
            regwren_o <= regwren_i;
            memren_o  <= memren_i;
            memwren_o <= memwren_i;
        end
    end

    // Latch writeback source select
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush_i) wbsel_o <= '0;
        else                wbsel_o <= wbsel_i;
    end

endmodule : ex_mem_reg
