/*
 * Module: id_ex_reg
 *
 * Description: D/X pipeline register (lecture 7), between ID and EX. Holds
 *              the decoded operands, immediate, instruction fields and the
 *              control signals EX, MEM and WB will need.
 *   - Asynchronous reset: loads a bubble.
 *   - Flush: loads a bubble (lecture 7, "insert NOPs into pipeline and clear
 *     datapath control signals"): every control signal off, ALU idle.
 *   - Stall: keeps its value while MEM waits for memory.
 *   Flush wins over stall.
 *
 * Inputs:
 *   1) clk, rst, flush_i, stall_i      - Clock, reset and pipeline controls
 *   2) pc_i                            - PC from ID
 *   3) rs1_data_i, rs2_data_i          - Register file read data
 *   4) imm_i                           - Immediate from igen
 *   5) rd_i, rs1_i, rs2_i              - Register indices
 *   6) funct3_i, funct7_i, opcode_i    - Instruction fields
 *   7) pcsel_i .. alusel_i             - Control signals from control.sv
 *
 * Outputs:
 *   The same values with an _o suffix, to EX.
 */

`include "constants.svh"

module id_ex_reg #(
    parameter int AWIDTH = 32,   // address width
    parameter int DWIDTH = 32    // data width
)(
    input  logic                 clk,          // clock
    input  logic                 rst,          // asynchronous active-high reset
    input  logic                 flush_i,      // 1 = load a bubble
    input  logic                 stall_i,      // 1 = keep the current values
    // Data from ID
    input  logic [AWIDTH-1:0]    pc_i,         // PC of the instruction
    input  logic [DWIDTH-1:0]    rs1_data_i,   // value of rs1
    input  logic [DWIDTH-1:0]    rs2_data_i,   // value of rs2
    input  logic [DWIDTH-1:0]    imm_i,        // immediate
    // Instruction fields from ID
    input  logic [REG_IDX_W-1:0] rd_i,         // destination register
    input  logic [REG_IDX_W-1:0] rs1_i,        // source register 1
    input  logic [REG_IDX_W-1:0] rs2_i,        // source register 2
    input  logic [FUNCT3_W-1:0]  funct3_i,     // funct3 field
    input  logic [FUNCT7_W-1:0]  funct7_i,     // funct7 field
    input  logic [OPCODE_W-1:0]  opcode_i,     // opcode field
    // Control signals from ID
    input  logic                 pcsel_i,      // PCSel: the instruction is a jump
    input  logic                 regwren_i,    // RegWEn: write rd in WB
    input  logic                 memren_i,     // the instruction is a load
    input  logic                 memwren_i,    // the instruction is a store
    input  logic [WBSEL_W-1:0]   wbsel_i,      // WBSel: write-back source
    input  logic [ALUSEL_W-1:0]  alusel_i,     // ALUSel: ALU operation
    // To EX
    output logic [AWIDTH-1:0]    pc_o,         // PC of the instruction
    output logic [DWIDTH-1:0]    rs1_data_o,   // value of rs1
    output logic [DWIDTH-1:0]    rs2_data_o,   // value of rs2
    output logic [DWIDTH-1:0]    imm_o,        // immediate
    output logic [REG_IDX_W-1:0] rd_o,         // destination register
    output logic [REG_IDX_W-1:0] rs1_o,        // source register 1
    output logic [REG_IDX_W-1:0] rs2_o,        // source register 2
    output logic [FUNCT3_W-1:0]  funct3_o,     // funct3 field
    output logic [FUNCT7_W-1:0]  funct7_o,     // funct7 field
    output logic [OPCODE_W-1:0]  opcode_o,     // opcode field
    output logic                 pcsel_o,      // PCSel
    output logic                 regwren_o,    // RegWEn
    output logic                 memren_o,     // load
    output logic                 memwren_o,    // store
    output logic [WBSEL_W-1:0]   wbsel_o,      // WBSel
    output logic [ALUSEL_W-1:0]  alusel_o      // ALUSel
);

    // Contents of the D/X register.
    typedef struct packed {
        logic [AWIDTH-1:0]    pc;         // PC of the instruction
        logic [DWIDTH-1:0]    rs1_data;   // value of rs1
        logic [DWIDTH-1:0]    rs2_data;   // value of rs2
        logic [DWIDTH-1:0]    imm;        // immediate
        logic [REG_IDX_W-1:0] rd;         // destination register
        logic [REG_IDX_W-1:0] rs1;        // source register 1
        logic [REG_IDX_W-1:0] rs2;        // source register 2
        logic [FUNCT3_W-1:0]  funct3;     // funct3 field
        logic [FUNCT7_W-1:0]  funct7;     // funct7 field
        logic [OPCODE_W-1:0]  opcode;     // opcode field
        logic                 pcsel;      // PCSel
        logic                 regwren;    // RegWEn
        logic                 memren;     // load
        logic                 memwren;    // store
        logic [WBSEL_W-1:0]   wbsel;      // WBSel
        logic [ALUSEL_W-1:0]  alusel;     // ALUSel
    } d_x_t;

    // Bubble: every field zero, so nothing is written, and the ALU idle.
    localparam d_x_t D_X_BUBBLE = '{alusel: `ALU_NOP, default: '0};

    d_x_t d_x_q;   // register contents
    d_x_t d_x_d;   // values arriving from ID

    assign d_x_d = '{pc: pc_i, rs1_data: rs1_data_i, rs2_data: rs2_data_i, imm: imm_i,
                     rd: rd_i, rs1: rs1_i, rs2: rs2_i,
                     funct3: funct3_i, funct7: funct7_i, opcode: opcode_i,
                     pcsel: pcsel_i, regwren: regwren_i, memren: memren_i,
                     memwren: memwren_i, wbsel: wbsel_i, alusel: alusel_i};

    // D/X register: reset or flush load a bubble, stall holds, otherwise load ID.
    always_ff @(posedge clk or posedge rst) begin : d_x_register
        if (rst)           d_x_q <= D_X_BUBBLE;
        else if (flush_i)  d_x_q <= D_X_BUBBLE;
        else if (!stall_i) d_x_q <= d_x_d;
    end

    assign pc_o       = d_x_q.pc;
    assign rs1_data_o = d_x_q.rs1_data;
    assign rs2_data_o = d_x_q.rs2_data;
    assign imm_o      = d_x_q.imm;
    assign rd_o       = d_x_q.rd;
    assign rs1_o      = d_x_q.rs1;
    assign rs2_o      = d_x_q.rs2;
    assign funct3_o   = d_x_q.funct3;
    assign funct7_o   = d_x_q.funct7;
    assign opcode_o   = d_x_q.opcode;
    assign pcsel_o    = d_x_q.pcsel;
    assign regwren_o  = d_x_q.regwren;
    assign memren_o   = d_x_q.memren;
    assign memwren_o  = d_x_q.memwren;
    assign wbsel_o    = d_x_q.wbsel;
    assign alusel_o   = d_x_q.alusel;

endmodule : id_ex_reg
