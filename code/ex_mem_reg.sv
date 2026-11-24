/*
 * Module: ex_mem_reg
 *
 * Description: X/M pipeline register (lecture 7), between EX and MEM. Holds
 *              the ALU result (the data address for a load or store), the
 *              store data, and the fields and controls MEM and WB need.
 *   - Asynchronous reset: loads a bubble (every field zero).
 *   - Flush: loads a bubble. Branches resolve in EX, so nothing in X/M is
 *     ever on a wrong path and the core keeps this input low.
 *   - Stall: keeps its value while MEM waits for memory.
 *   Flush wins over stall.
 *
 * Inputs:
 *   1) clk, rst, flush_i, stall_i      - Clock, reset and pipeline controls
 *   2) pc_i                            - PC (for WB_PC4)
 *   3) alu_res_i                       - ALU result: data address or computed value
 *   4) rs2_data_i                      - Store data from rs2
 *   5) imm_i                           - Immediate (for WB_IMM, LUI)
 *   6) rd_i, funct3_i                  - Destination register and access size
 *   7) regwren_i .. wbsel_i            - Control signals
 *
 * Outputs:
 *   The same values with an _o suffix, to MEM.
 */

`include "constants.svh"

module ex_mem_reg #(
    parameter int AWIDTH = 32,   // address width
    parameter int DWIDTH = 32    // data width
)(
    input  logic                 clk,          // clock
    input  logic                 rst,          // asynchronous active-high reset
    input  logic                 flush_i,      // 1 = load a bubble
    input  logic                 stall_i,      // 1 = keep the current values
    // Data from EX
    input  logic [AWIDTH-1:0]    pc_i,         // PC of the instruction
    input  logic [DWIDTH-1:0]    alu_res_i,    // ALU result or data address
    input  logic [DWIDTH-1:0]    rs2_data_i,   // store data
    input  logic [DWIDTH-1:0]    imm_i,        // immediate
    // Instruction fields from EX
    input  logic [REG_IDX_W-1:0] rd_i,         // destination register
    input  logic [FUNCT3_W-1:0]  funct3_i,     // access size and sign
    // Control signals from EX
    input  logic                 regwren_i,    // RegWEn: write rd in WB
    input  logic                 memren_i,     // the instruction is a load
    input  logic                 memwren_i,    // the instruction is a store
    input  logic [WBSEL_W-1:0]   wbsel_i,      // WBSel: write-back source
    // To MEM
    output logic [AWIDTH-1:0]    pc_o,         // PC of the instruction
    output logic [DWIDTH-1:0]    alu_res_o,    // ALU result or data address
    output logic [DWIDTH-1:0]    rs2_data_o,   // store data
    output logic [DWIDTH-1:0]    imm_o,        // immediate
    output logic [REG_IDX_W-1:0] rd_o,         // destination register
    output logic [FUNCT3_W-1:0]  funct3_o,     // access size and sign
    output logic                 regwren_o,    // RegWEn
    output logic                 memren_o,     // load
    output logic                 memwren_o,    // store
    output logic [WBSEL_W-1:0]   wbsel_o       // WBSel
);

    // Contents of the X/M register.
    typedef struct packed {
        logic [AWIDTH-1:0]    pc;         // PC of the instruction
        logic [DWIDTH-1:0]    alu_res;    // ALU result or data address
        logic [DWIDTH-1:0]    rs2_data;   // store data
        logic [DWIDTH-1:0]    imm;        // immediate
        logic [REG_IDX_W-1:0] rd;         // destination register
        logic [FUNCT3_W-1:0]  funct3;     // access size and sign
        logic                 regwren;    // RegWEn
        logic                 memren;     // load
        logic                 memwren;    // store
        logic [WBSEL_W-1:0]   wbsel;      // WBSel
    } x_m_t;

    // Bubble: every field zero, so nothing is loaded, stored or written.
    localparam x_m_t X_M_BUBBLE = '0;

    x_m_t x_m_q;   // register contents
    x_m_t x_m_d;   // values arriving from EX

    assign x_m_d = '{pc: pc_i, alu_res: alu_res_i, rs2_data: rs2_data_i, imm: imm_i,
                     rd: rd_i, funct3: funct3_i, regwren: regwren_i,
                     memren: memren_i, memwren: memwren_i, wbsel: wbsel_i};

    // X/M register: reset or flush load a bubble, stall holds, otherwise load EX.
    always_ff @(posedge clk or posedge rst) begin : x_m_register
        if (rst)           x_m_q <= X_M_BUBBLE;
        else if (flush_i)  x_m_q <= X_M_BUBBLE;
        else if (!stall_i) x_m_q <= x_m_d;
    end

    assign pc_o       = x_m_q.pc;
    assign alu_res_o  = x_m_q.alu_res;
    assign rs2_data_o = x_m_q.rs2_data;
    assign imm_o      = x_m_q.imm;
    assign rd_o       = x_m_q.rd;
    assign funct3_o   = x_m_q.funct3;
    assign regwren_o  = x_m_q.regwren;
    assign memren_o   = x_m_q.memren;
    assign memwren_o  = x_m_q.memwren;
    assign wbsel_o    = x_m_q.wbsel;

endmodule : ex_mem_reg
