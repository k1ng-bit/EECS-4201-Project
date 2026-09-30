/*
 * Module: id_ex_reg
 *
 * Description: Pipeline register between the Instruction Decode (ID) and
 *              Execute (EX) stages. Latches decoded operands, immediate
 *              value, instruction metadata, and control signals.
 *
 * Features:
 *   - Asynchronous reset: clears all fields to zero / safe defaults
 *   - Synchronous flush:  inserts bubble (zeroes control signals)
 *
 * Inputs:
 *   1)  clk, rst, flush_i                - Clock, reset, flush control
 *   2)  pc_i                             - Program counter from ID stage
 *   3)  rs1_data_i, rs2_data_i           - Register file read data
 *   4)  imm_i                            - Immediate from igen
 *   5)  rd_i, rs1_i, rs2_i              - Register addresses
 *   6)  funct3_i, funct7_i, opcode_i    - Instruction decode fields
 *   7)  pcsel_i .. alusel_i             - Control signals from control.sv
 *
 * Outputs:
 *   Corresponding latched values with _o suffix for the EX stage.
 */

`include "constants.svh"

module id_ex_reg #(
    parameter int AWIDTH = 32,
    parameter int DWIDTH = 32
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush_i,
    // Data inputs from ID stage
    input  logic [AWIDTH-1:0] pc_i,
    input  logic [DWIDTH-1:0] rs1_data_i,
    input  logic [DWIDTH-1:0] rs2_data_i,
    input  logic [DWIDTH-1:0] imm_i,
    // Instruction metadata inputs from ID stage
    input  logic [4:0]        rd_i,
    input  logic [4:0]        rs1_i,
    input  logic [4:0]        rs2_i,
    input  logic [2:0]        funct3_i,
    input  logic [6:0]        funct7_i,
    input  logic [6:0]        opcode_i,
    // Control signal inputs from control module
    input  logic              pcsel_i,
    input  logic              regwren_i,
    input  logic              memren_i,
    input  logic              memwren_i,
    input  logic [1:0]        wbsel_i,
    input  logic [3:0]        alusel_i,
    // Data outputs to EX stage
    output logic [AWIDTH-1:0] pc_o,
    output logic [DWIDTH-1:0] rs1_data_o,
    output logic [DWIDTH-1:0] rs2_data_o,
    output logic [DWIDTH-1:0] imm_o,
    // Instruction metadata outputs to EX stage
    output logic [4:0]        rd_o,
    output logic [4:0]        rs1_o,
    output logic [4:0]        rs2_o,
    output logic [2:0]        funct3_o,
    output logic [6:0]        funct7_o,
    output logic [6:0]        opcode_o,
    // Control signal outputs to EX stage
    output logic              pcsel_o,
    output logic              regwren_o,
    output logic              memren_o,
    output logic              memwren_o,
    output logic [1:0]        wbsel_o,
    output logic [3:0]        alusel_o
);

    // Latch program counter and immediate value
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_o  <= '0;
            imm_o <= '0;
        end else if (flush_i) begin
            pc_o  <= '0;
            imm_o <= '0;
        end else begin
            pc_o  <= pc_i;
            imm_o <= imm_i;
        end
    end

    // Latch register file read data
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rs1_data_o <= '0;
            rs2_data_o <= '0;
        end else if (flush_i) begin
            rs1_data_o <= '0;
            rs2_data_o <= '0;
        end else begin
            rs1_data_o <= rs1_data_i;
            rs2_data_o <= rs2_data_i;
        end
    end

    // Latch register addresses for hazard detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_o  <= '0;
            rs1_o <= '0;
            rs2_o <= '0;
        end else if (flush_i) begin
            rd_o  <= '0;
            rs1_o <= '0;
            rs2_o <= '0;
        end else begin
            rd_o  <= rd_i;
            rs1_o <= rs1_i;
            rs2_o <= rs2_i;
        end
    end

    // Latch instruction decode fields
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            funct3_o <= '0;
            funct7_o <= '0;
            opcode_o <= '0;
        end else if (flush_i) begin
            funct3_o <= '0;
            funct7_o <= '0;
            opcode_o <= '0;
        end else begin
            funct3_o <= funct3_i;
            funct7_o <= funct7_i;
            opcode_o <= opcode_i;
        end
    end

    // Latch control signals: PC select and register/memory enables
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pcsel_o   <= '0;
            regwren_o <= '0;
            memren_o  <= '0;
        end else if (flush_i) begin
            pcsel_o   <= '0;
            regwren_o <= '0;
            memren_o  <= '0;
        end else begin
            pcsel_o   <= pcsel_i;
            regwren_o <= regwren_i;
            memren_o  <= memren_i;
        end
    end

    // Latch control signals: memory write, writeback select, ALU select
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            memwren_o <= '0;
            wbsel_o   <= '0;
            alusel_o  <= `ALU_NOP;
        end else if (flush_i) begin
            memwren_o <= '0;
            wbsel_o   <= '0;
            alusel_o  <= `ALU_NOP;
        end else begin
            memwren_o <= memwren_i;
            wbsel_o   <= wbsel_i;
            alusel_o  <= alusel_i;
        end
    end

endmodule : id_ex_reg
