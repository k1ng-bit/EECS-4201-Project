/*
 * Module: mem_wb_reg
 *
 * Description: Pipeline register between the Memory Access (MEM) and
 *              Writeback (WB) stages. Latches ALU result, memory read
 *              data, and writeback control signals.
 *
 * Features:
 *   - Asynchronous reset: clears all fields to zero / safe defaults
 *
 * Inputs:
 *   1) clk, rst                      - Clock and asynchronous reset
 *   2) pc_i                          - Program counter (for WB_PC4)
 *   3) alu_res_i                     - ALU result from EX stage
 *   4) mem_data_i                    - Data loaded from memory
 *   5) rd_i                          - Destination register address
 *   6) imm_i                         - Immediate value (for WB_IMM / LUI)
 *   7) regwren_i, wbsel_i            - Writeback control signals
 *
 * Outputs:
 *   Corresponding latched values with _o suffix for the WB stage.
 */

`include "constants.svh"

module mem_wb_reg #(
    parameter int AWIDTH = 32,
    parameter int DWIDTH = 32
)(
    input  logic              clk,
    input  logic              rst,
    // Data inputs from MEM stage
    input  logic [AWIDTH-1:0] pc_i,
    input  logic [DWIDTH-1:0] alu_res_i,
    input  logic [DWIDTH-1:0] mem_data_i,
    input  logic [DWIDTH-1:0] imm_i,
    // Instruction metadata input from MEM stage
    input  logic [4:0]        rd_i,
    // Control signal inputs from MEM stage
    input  logic              regwren_i,
    input  logic [1:0]        wbsel_i,
    // Data outputs to WB stage
    output logic [AWIDTH-1:0] pc_o,
    output logic [DWIDTH-1:0] alu_res_o,
    output logic [DWIDTH-1:0] mem_data_o,
    output logic [DWIDTH-1:0] imm_o,
    // Instruction metadata output to WB stage
    output logic [4:0]        rd_o,
    // Control signal outputs to WB stage
    output logic              regwren_o,
    output logic [1:0]        wbsel_o
);

    // Latch program counter and ALU result
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_o      <= '0;
            alu_res_o <= '0;
        end else begin
            pc_o      <= pc_i;
            alu_res_o <= alu_res_i;
        end
    end

    // Latch memory data and immediate value
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_data_o <= '0;
            imm_o      <= '0;
        end else begin
            mem_data_o <= mem_data_i;
            imm_o      <= imm_i;
        end
    end

    // Latch destination register and writeback control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_o      <= '0;
            regwren_o <= '0;
            wbsel_o   <= '0;
        end else begin
            rd_o      <= rd_i;
            regwren_o <= regwren_i;
            wbsel_o   <= wbsel_i;
        end
    end

endmodule : mem_wb_reg
