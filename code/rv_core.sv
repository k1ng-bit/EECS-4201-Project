/*
 * Module: rv_core
 *
 * Description: Top-level 5-stage in-order pipelined RISC-V core (RV32I).
 *              Instantiates all pipeline stages, pipeline registers,
 *              and the stall/flush hazard control unit.
 *
 * Pipeline stages:
 *   IF  → IF/ID reg → ID  → ID/EX reg → EX  → EX/MEM reg → MEM → MEM/WB reg → WB
 *
 * Inputs:
 *   1) clk   - Clock signal
 *   2) reset - Asynchronous active-high reset
 */

`include "constants.svh"

module rv_core #(
    parameter int AWIDTH = 32,
    parameter int DWIDTH = 32
)(
    input logic clk,
    input logic reset
);

    // ================================================================
    //  PIPELINE CONTROL SIGNALS (from stall_flush_logic)
    // ================================================================
    logic if_pc_en;         // PC advance enable (0 = stall)
    logic stall_if_id;      // Hold IF/ID register contents
    logic flush_if_id;      // Flush IF/ID to NOP bubble
    logic flush_id_ex;      // Flush ID/EX to bubble
    logic flush_ex_mem;     // Flush EX/MEM to bubble

    // Testbench backward-compatibility probes for top_tb / rv_official_tb
    logic              stall;
    logic              flush;
    assign stall = stall_if_id;
    assign flush = flush_if_id || flush_id_ex;

    // ================================================================
    //  IF STAGE — Instruction Fetch
    // ================================================================
    // IF stage signals
    logic [AWIDTH-1:0] if_pc;       // Current program counter
    logic [DWIDTH-1:0] if_insn;     // Fetched instruction from memory
    logic [DWIDTH-1:0] f_insn;      // Instruction alias for testbench probe
    assign f_insn = if_insn;

    // Branch/jump resolution feedback from EX stage
    logic              ex_jump_branch;  // Branch taken or jump in EX
    logic [DWIDTH-1:0] ex_alu_res;      // Branch/jump target from ALU

    // Fetch module: manages the PC register
    fetch #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .BASEADDR(32'h01000000)
    ) fetch1 (
        .clk(clk),
        .rst(reset),
        .next_pc_i(ex_alu_res),
        .pc_en_i(if_pc_en),
        .jump_branch_i(ex_jump_branch),
        .pc_o(if_pc)
    );

    // ================================================================
    //  IF/ID PIPELINE REGISTER
    // ================================================================
    logic [AWIDTH-1:0] id_pc;       // PC in decode stage
    logic [DWIDTH-1:0] id_insn;     // Instruction in decode stage

    if_id_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) if_id (
        .clk(clk),
        .rst(reset),
        .stall_i(stall_if_id),
        .flush_i(flush_if_id),
        .pc_i(if_pc),
        .insn_i(if_insn),
        .pc_o(id_pc),
        .insn_o(id_insn)
    );

    // ================================================================
    //  ID STAGE — Instruction Decode, Immediate Gen, Control, Reg Read
    // ================================================================
    // Decoded instruction fields
    logic [6:0] id_opcode;
    logic [4:0] id_rd, id_rs1, id_rs2;
    logic [6:0] id_funct7;
    logic [2:0] id_funct3;

    // Decode module: extract instruction fields
    decode #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) decode1 (
        .clk(clk),
        .rst(reset),
        .insn_i(id_insn),
        .pc_i(id_pc),
        .pc_o(),             // Unused: pipeline registers handle propagation
        .insn_o(),           // Unused: pipeline registers handle propagation
        .opcode_o(id_opcode),
        .rd_o(id_rd),
        .rs1_o(id_rs1),
        .rs2_o(id_rs2),
        .funct7_o(id_funct7),
        .funct3_o(id_funct3),
        .shamt_o(),          // Unused: shamt derived from immediate
        .imm_o()             // Unused: immediate comes from igen
    );

    // Immediate generator
    logic [DWIDTH-1:0] id_imm;

    igen #(
        .DWIDTH(DWIDTH)
    ) igen1 (
        .opcode_i(id_opcode),
        .insn_i(id_insn),
        .imm_o(id_imm)
    );

    // Control path: generate control signals from decoded instruction
    logic       id_pcsel, id_immsel, id_regwren;
    logic       id_rs1sel, id_rs2sel;
    logic       id_memren, id_memwren;
    logic [1:0] id_wbsel;
    logic [3:0] id_alusel;

    control #(
        .DWIDTH(DWIDTH)
    ) control1 (
        .insn_i(id_insn),
        .opcode_i(id_opcode),
        .funct7_i(id_funct7),
        .funct3_i(id_funct3),
        .pcsel_o(id_pcsel),
        .immsel_o(id_immsel),
        .regwren_o(id_regwren),
        .rs1sel_o(id_rs1sel),
        .rs2sel_o(id_rs2sel),
        .memren_o(id_memren),
        .memwren_o(id_memwren),
        .wbsel_o(id_wbsel),
        .alusel_o(id_alusel)
    );

    // Register file: read in ID, write in WB
    logic [DWIDTH-1:0] id_rs1_data, id_rs2_data;
    // WB stage write signals (declared here, driven in WB section below)
    logic [4:0]        wb_rd;
    logic [DWIDTH-1:0] wb_data;
    logic              wb_regwren;

    register_file #(
        .DWIDTH(DWIDTH)
    ) register_file1 (
        .clk(clk),
        .rst(reset),
        .rs1_i(id_rs1),
        .rs2_i(id_rs2),
        .rd_i(wb_rd),
        .datawb_i(wb_data),
        .regwren_i(wb_regwren),
        .rs1data_o(id_rs1_data),
        .rs2data_o(id_rs2_data)
    );

    // ================================================================
    //  ID/EX PIPELINE REGISTER
    // ================================================================
    logic [AWIDTH-1:0] ex_pc;
    logic [DWIDTH-1:0] ex_rs1_data, ex_rs2_data, ex_imm;
    logic [4:0]        ex_rd, ex_rs1, ex_rs2;
    logic [2:0]        ex_funct3;
    logic [6:0]        ex_funct7, ex_opcode;
    logic              ex_pcsel, ex_regwren, ex_memren, ex_memwren;
    logic [1:0]        ex_wbsel;
    logic [3:0]        ex_alusel;

    id_ex_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) id_ex (
        .clk(clk),
        .rst(reset),
        .flush_i(flush_id_ex),
        // Data from ID
        .pc_i(id_pc),
        .rs1_data_i(id_rs1_data),
        .rs2_data_i(id_rs2_data),
        .imm_i(id_imm),
        // Metadata from ID
        .rd_i(id_rd),
        .rs1_i(id_rs1),
        .rs2_i(id_rs2),
        .funct3_i(id_funct3),
        .funct7_i(id_funct7),
        .opcode_i(id_opcode),
        // Control from ID
        .pcsel_i(id_pcsel),
        .regwren_i(id_regwren),
        .memren_i(id_memren),
        .memwren_i(id_memwren),
        .wbsel_i(id_wbsel),
        .alusel_i(id_alusel),
        // Outputs to EX
        .pc_o(ex_pc),
        .rs1_data_o(ex_rs1_data),
        .rs2_data_o(ex_rs2_data),
        .imm_o(ex_imm),
        .rd_o(ex_rd),
        .rs1_o(ex_rs1),
        .rs2_o(ex_rs2),
        .funct3_o(ex_funct3),
        .funct7_o(ex_funct7),
        .opcode_o(ex_opcode),
        .pcsel_o(ex_pcsel),
        .regwren_o(ex_regwren),
        .memren_o(ex_memren),
        .memwren_o(ex_memwren),
        .wbsel_o(ex_wbsel),
        .alusel_o(ex_alusel)
    );

    // ================================================================
    //  EX STAGE — ALU Execution and Branch Resolution
    // ================================================================
    // ALU input muxing
    logic [DWIDTH-1:0] ex_alu_a, ex_alu_b;
    logic              ex_brtaken;

    // ALU operand A: always rs1 data
    assign ex_alu_a = ex_rs1_data;

    // ALU operand B: immediate for I/L/JALR/S types, otherwise rs2 data
    assign ex_alu_b = ((ex_opcode == `I_TYPE)      ||
                       (ex_opcode == `I_TYPE_L)    ||
                       (ex_opcode == `I_TYPE_JALR) ||
                       (ex_opcode == `S_TYPE)) ? ex_imm : ex_rs2_data;

    // ALU instance
    alu #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) alu1 (
        .pc_i(ex_pc),
        .rs1_i(ex_alu_a),
        .rs2_i(ex_alu_b),
        .funct3_i(ex_funct3),
        .funct7_i(ex_funct7),
        .opcode_i(ex_opcode),
        .imm_i(ex_imm),
        .alusel_i(ex_alusel),
        .res_o(ex_alu_res),
        .brtaken_o(ex_brtaken)
    );

    // Branch/jump resolution: redirect PC on taken branch or jump
    assign ex_jump_branch = ex_pcsel || ex_brtaken;

    // ================================================================
    //  EX/MEM PIPELINE REGISTER
    // ================================================================
    logic [AWIDTH-1:0] mem_pc;
    logic [DWIDTH-1:0] mem_alu_res, mem_rs2_data, mem_imm;
    logic [4:0]        mem_rd;
    logic [2:0]        mem_funct3;
    logic              mem_regwren, mem_memren, mem_memwren;
    logic [1:0]        mem_wbsel;

    ex_mem_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) ex_mem (
        .clk(clk),
        .rst(reset),
        .flush_i(flush_ex_mem),
        // Data from EX
        .pc_i(ex_pc),
        .alu_res_i(ex_alu_res),
        .rs2_data_i(ex_rs2_data),
        .imm_i(ex_imm),
        // Metadata from EX
        .rd_i(ex_rd),
        .funct3_i(ex_funct3),
        // Control from EX
        .regwren_i(ex_regwren),
        .memren_i(ex_memren),
        .memwren_i(ex_memwren),
        .wbsel_i(ex_wbsel),
        // Outputs to MEM
        .pc_o(mem_pc),
        .alu_res_o(mem_alu_res),
        .rs2_data_o(mem_rs2_data),
        .imm_o(mem_imm),
        .rd_o(mem_rd),
        .funct3_o(mem_funct3),
        .regwren_o(mem_regwren),
        .memren_o(mem_memren),
        .memwren_o(mem_memwren),
        .wbsel_o(mem_wbsel)
    );

    // ================================================================
    //  MEM STAGE — Data Memory Access
    // ================================================================
    logic [DWIDTH-1:0] mem_rdata;   // Data loaded from memory

    memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .OWIDTH(2),
        .BASE_ADDR(32'h01000000)
    ) memory1 (
        .clk(clk),
        .rst(reset),
        .pc_i(if_pc),              // IF stage: instruction address
        .addr_i(mem_alu_res),      // MEM stage: data address
        .data_i(mem_rs2_data),     // MEM stage: store data
        .funct3_i(mem_funct3),     // MEM stage: byte/half/word select
        .memren_i(mem_memren),     // MEM stage: read enable
        .memwren_i(mem_memwren),   // MEM stage: write enable
        .insnen_i(1'b1),           // IF stage: always fetch instructions
        .insn_o(if_insn),          // IF stage: fetched instruction
        .data_o(mem_rdata)         // MEM stage: loaded data
    );

    // ================================================================
    //  MEM/WB PIPELINE REGISTER
    // ================================================================
    logic [AWIDTH-1:0] wb_pc;
    logic [DWIDTH-1:0] wb_alu_res, wb_mem_data, wb_imm;
    logic [1:0]        wb_wbsel;

    mem_wb_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) mem_wb (
        .clk(clk),
        .rst(reset),
        // Data from MEM
        .pc_i(mem_pc),
        .alu_res_i(mem_alu_res),
        .mem_data_i(mem_rdata),
        .imm_i(mem_imm),
        // Metadata from MEM
        .rd_i(mem_rd),
        // Control from MEM
        .regwren_i(mem_regwren),
        .wbsel_i(mem_wbsel),
        // Outputs to WB
        .pc_o(wb_pc),
        .alu_res_o(wb_alu_res),
        .mem_data_o(wb_mem_data),
        .imm_o(wb_imm),
        .rd_o(wb_rd),
        .regwren_o(wb_regwren),
        .wbsel_o(wb_wbsel)
    );

    // ================================================================
    //  WB STAGE — Writeback to Register File
    // ================================================================
    writeback #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) wb_wb1 (
        .pc_i(wb_pc),
        .alu_res_i(wb_alu_res),
        .memory_data_i(wb_mem_data),
        .wbsel_i(wb_wbsel),
        .imm_i(wb_imm),
        .writeback_data_o(wb_data)
    );

    // ================================================================
    //  HAZARD CONTROL — Stall & Flush Logic
    // ================================================================
    stall_flush_logic stall_flush (
        // ID stage source registers
        .id_rs1_i(id_rs1),
        .id_rs2_i(id_rs2),
        .id_rs1_valid_i(id_rs1sel),
        .id_rs2_valid_i(id_rs2sel),
        // EX stage destination and control
        .ex_rd_i(ex_rd),
        .ex_regwren_i(ex_regwren),
        .ex_memren_i(ex_memren),
        .ex_brtaken_i(ex_brtaken),
        .ex_is_jump_i(ex_pcsel),
        // MEM stage destination and control
        .mem_rd_i(mem_rd),
        .mem_regwren_i(mem_regwren),
        .mem_memren_i(mem_memren),
        // Pipeline control outputs
        .pc_en_o(if_pc_en),
        .if_id_stall_o(stall_if_id),
        .if_id_flush_o(flush_if_id),
        .id_ex_flush_o(flush_id_ex),
        .ex_mem_flush_o(flush_ex_mem)
    );

    // Synthesis keep signal so yosys does not optimize away the design
    (* keep *) logic busy;
    assign busy = (wb_regwren || mem_memren || mem_memwren);

endmodule : rv_core
