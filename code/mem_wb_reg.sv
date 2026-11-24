/*
 * Module: mem_wb_reg
 *
 * Description: M/W pipeline register (lecture 7), between MEM and WB. Holds
 *              the ALU result, the loaded data and the write-back controls.
 *   - Asynchronous reset: loads a bubble (every field zero).
 *   - Flush: loads a bubble. The core flushes M/W while MEM waits for memory,
 *     so WB gets nothing new and nothing is written twice.
 *   - There is no stall: M/W loads on every cycle it is not flushed.
 *
 * Inputs:
 *   1) clk, rst, flush_i               - Clock, reset and flush control
 *   2) pc_i                            - PC (for WB_PC4)
 *   3) alu_res_i                       - ALU result
 *   4) mem_data_i                      - Data loaded from memory
 *   5) imm_i                           - Immediate (for WB_IMM, LUI)
 *   6) rd_i                            - Destination register
 *   7) regwren_i, wbsel_i              - Write-back controls
 *
 * Outputs:
 *   The same values with an _o suffix, to WB.
 */

`include "constants.svh"

module mem_wb_reg #(
    parameter int AWIDTH = 32,   // address width
    parameter int DWIDTH = 32    // data width
)(
    input  logic                 clk,          // clock
    input  logic                 rst,          // asynchronous active-high reset
    input  logic                 flush_i,      // 1 = load a bubble
    // Data from MEM
    input  logic [AWIDTH-1:0]    pc_i,         // PC of the instruction
    input  logic [DWIDTH-1:0]    alu_res_i,    // ALU result
    input  logic [DWIDTH-1:0]    mem_data_i,   // data loaded from memory
    input  logic [DWIDTH-1:0]    imm_i,        // immediate
    // Instruction field from MEM
    input  logic [REG_IDX_W-1:0] rd_i,         // destination register
    // Control signals from MEM
    input  logic                 regwren_i,    // RegWEn: write rd
    input  logic [WBSEL_W-1:0]   wbsel_i,      // WBSel: write-back source
    // To WB
    output logic [AWIDTH-1:0]    pc_o,         // PC of the instruction
    output logic [DWIDTH-1:0]    alu_res_o,    // ALU result
    output logic [DWIDTH-1:0]    mem_data_o,   // data loaded from memory
    output logic [DWIDTH-1:0]    imm_o,        // immediate
    output logic [REG_IDX_W-1:0] rd_o,         // destination register
    output logic                 regwren_o,    // RegWEn
    output logic [WBSEL_W-1:0]   wbsel_o       // WBSel
);

    // Contents of the M/W register.
    typedef struct packed {
        logic [AWIDTH-1:0]    pc;         // PC of the instruction
        logic [DWIDTH-1:0]    alu_res;    // ALU result
        logic [DWIDTH-1:0]    mem_data;   // data loaded from memory
        logic [DWIDTH-1:0]    imm;        // immediate
        logic [REG_IDX_W-1:0] rd;         // destination register
        logic                 regwren;    // RegWEn
        logic [WBSEL_W-1:0]   wbsel;      // WBSel
    } m_w_t;

    // Bubble: every field zero, so nothing is written.
    localparam m_w_t M_W_BUBBLE = '0;

    m_w_t m_w_q;   // register contents
    m_w_t m_w_d;   // values arriving from MEM

    assign m_w_d = '{pc: pc_i, alu_res: alu_res_i, mem_data: mem_data_i, imm: imm_i,
                     rd: rd_i, regwren: regwren_i, wbsel: wbsel_i};

    // M/W register: reset or flush load a bubble, otherwise load MEM.
    always_ff @(posedge clk or posedge rst) begin : m_w_register
        if (rst)          m_w_q <= M_W_BUBBLE;
        else if (flush_i) m_w_q <= M_W_BUBBLE;
        else              m_w_q <= m_w_d;
    end

    assign pc_o       = m_w_q.pc;
    assign alu_res_o  = m_w_q.alu_res;
    assign mem_data_o = m_w_q.mem_data;
    assign imm_o      = m_w_q.imm;
    assign rd_o       = m_w_q.rd;
    assign regwren_o  = m_w_q.regwren;
    assign wbsel_o    = m_w_q.wbsel;

endmodule : mem_wb_reg
