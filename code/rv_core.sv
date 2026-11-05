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

    
    //  PIPELINE CONTROL SIGNALS (from stall_flush_logic)
    
    logic pc_en;            // 1 = PC moves foward, 0 = PC frozen
    logic f_d_stall;        // hold the F/D register contents 
    logic f_d_flush;        // flush F/D register with NOP bubble
    logic d_x_flush;      // flush D/X to bubble
    logic flush_ex_mem;     // flush X/MEM to bubble

    // Testbench probes for top_tb / rv_official_tb
    logic              stall;
    logic              flush;
    assign stall = f_d_stall;
    assign flush = f_d_flush;

    
    // Fetch STAGE — Instruction Fetch 
    // Fetch stage signals
    logic [AWIDTH-1:0] f_pc;       // Current program counter
    logic [DWIDTH-1:0] f_insn;     // Fetched instruction from memory

    // Branch/jump resolution feedback from EX stage
    logic              jump_branch;         // Branch taken or jump in EX
    logic [DWIDTH-1:0] e_res;               // alu result or branch/jump target from ALU

    // Fetch module: manages the PC register
    fetch #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .BASEADDR(32'h01000000)
    ) fetch1 (
        .clk(clk),
        .rst(reset),
        .next_pc_i(e_res),
        .pc_en_i(pc_en),
        .jump_branch_i(jump_branch),
        .pc_o(f_pc)
    );

    
    //  F/D PIPELINE REGISTER
     
    logic [AWIDTH-1:0] f_d_pc;       // PC in decode stage
    logic [DWIDTH-1:0] f_d_insn;     // Instruction in decode stage

    if_id_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) if_id (
        .clk(clk),
        .rst(reset),
        .stall_i(f_d_stall),
        .flush_i(f_d_flush),
        .pc_i(f_pc),
        .insn_i(f_insn),
        .pc_o(f_d_pc),
        .insn_o(f_d_insn)
    );

    
    //  ID STAGE — Instruction Decode, Immediate Gen, Control, Reg Read
    // Decoded instruction fields
    logic [6:0] d_opcode;
    logic [4:0] d_rd, d_rs1, d_rs2;
    logic [6:0] d_funct7;
    logic [2:0] d_funct3;

    // Decode module: extract instruction fields
    decode #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) decode1 (
        .clk(clk),
        .rst(reset),
        .insn_i(f_d_insn),
        .pc_i(f_d_pc),
        .pc_o(),             // Unused: pipeline registers handle propagation
        .insn_o(),           // Unused: pipeline registers handle propagation
        .opcode_o(d_opcode),
        .rd_o(d_rd),
        .rs1_o(d_rs1),
        .rs2_o(d_rs2),
        .funct7_o(d_funct7),
        .funct3_o(d_funct3),
        .shamt_o(),          // Unused: shamt derived from immediate
        .imm_o()             // Unused: immediate comes from igen
    );

    // Immediate generator
    logic [DWIDTH-1:0] d_imm;

    igen #(
        .DWIDTH(DWIDTH)
    ) igen1 (
        .opcode_i(d_opcode),
        .insn_i(f_d_insn),
        .imm_o(d_imm)
    );

    // Control path: generate control signals from decoded instruction
    logic       c_pcsel, c_immsel, c_regwren;
    logic       c_rs1sel, c_rs2sel;
    logic       c_memren, c_memwren;
    logic [1:0] c_wbsel;
    logic [3:0] c_alusel;

    control #(
        .DWIDTH(DWIDTH)
    ) control1 (
        .insn_i(f_d_insn),
        .opcode_i(d_opcode),
        .funct7_i(d_funct7),
        .funct3_i(d_funct3),
        .pcsel_o(c_pcsel),
        .immsel_o(c_immsel),
        .regwren_o(c_regwren),
        .rs1sel_o(c_rs1sel),
        .rs2sel_o(c_rs2sel),
        .memren_o(c_memren),
        .memwren_o(c_memwren),
        .wbsel_o(c_wbsel),
        .alusel_o(c_alusel)
    );

    // Register file: read in ID, write in WB
    logic [DWIDTH-1:0] r_rs1data, r_rs2data;
    // WB stage write signals (declared here, driven in WB section below)
    logic [4:0]        wb_rd;
    logic [DWIDTH-1:0] wb_data;
    logic              wb_regwren;

    register_file #(
        .DWIDTH(DWIDTH)
    ) register_file1 (
        .clk(clk),
        .rst(reset),
        .rs1_i(d_rs1),
        .rs2_i(d_rs2),
        .rd_i(wb_rd),
        .datawb_i(wb_data),
        .regwren_i(wb_regwren),
        .rs1data_o(r_rs1data),
        .rs2data_o(r_rs2data)
    );

    
    //  D/X PIPELINE REGISTER
    
    logic [AWIDTH-1:0] d_x_pc;                                  // pc in the pipeline register
    logic [DWIDTH-1:0] d_x_rs1data, d_x_rs2data, d_x_imm;       // register values rs1 and rs2 and imm 
    logic [4:0]        d_x_rd, d_x_rs1, d_x_rs2;                // register numbers
    logic [2:0]        d_x_funct3;                              
    logic [6:0]        d_x_funct7, d_x_opcode;
    logic              d_x_pcsel, d_x_regwren, d_x_memren, d_x_memwren;     // controls for the pipeline register
    logic [1:0]        d_x_wbsel;
    logic [3:0]        d_x_alusel;

    id_ex_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) id_ex (
        .clk(clk),
        .rst(reset),
        .flush_i(d_x_flush),
        // Data from ID
        .pc_i(f_d_pc),
        .rs1_data_i(r_rs1data),
        .rs2_data_i(r_rs2data),
        .imm_i(d_imm),
        // Metadata from ID
        .rd_i(d_rd),
        .rs1_i(d_rs1),
        .rs2_i(d_rs2),
        .funct3_i(d_funct3),
        .funct7_i(d_funct7),
        .opcode_i(d_opcode),
        // Control from ID
        .pcsel_i(c_pcsel),
        .regwren_i(c_regwren),
        .memren_i(c_memren),
        .memwren_i(c_memwren),
        .wbsel_i(c_wbsel),
        .alusel_i(c_alusel),
        // Outputs to EX
        .pc_o(d_x_pc),
        .rs1_data_o(d_x_rs1data),
        .rs2_data_o(d_x_rs2data),
        .imm_o(d_x_imm),
        .rd_o(d_x_rd),
        .rs1_o(d_x_rs1),
        .rs2_o(d_x_rs2),
        .funct3_o(d_x_funct3),
        .funct7_o(d_x_funct7),
        .opcode_o(d_x_opcode),
        .pcsel_o(d_x_pcsel),
        .regwren_o(d_x_regwren),
        .memren_o(d_x_memren),
        .memwren_o(d_x_memwren),
        .wbsel_o(d_x_wbsel),
        .alusel_o(d_x_alusel)
    );

    
    //  EX STAGE — ALU Execution and Branch Resolution
    // ALU input muxing
    logic [DWIDTH-1:0] alu_A, alu_b;        // alu input A and B
    logic              e_brtaken;           // 1 if branch condition is true, else 0

    // ALU operand A: always rs1 data
    assign alu_A = d_x_rs1data;

    // ALU operand B: immediate for I/L/JALR/S types, otherwise rs2 data
    assign alu_b = ((d_x_opcode == `I_TYPE)      ||
                       (d_x_opcode == `I_TYPE_L)    ||
                       (d_x_opcode == `I_TYPE_JALR) ||
                       (d_x_opcode == `S_TYPE)) ? d_x_imm : d_x_rs2data;

    // ALU instance
    alu #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) e_alu1 (
        .pc_i(d_x_pc),
        .rs1_i(alu_A),
        .rs2_i(alu_b),
        .funct3_i(d_x_funct3),
        .funct7_i(d_x_funct7),
        .opcode_i(d_x_opcode),
        .imm_i(d_x_imm),
        .alusel_i(d_x_alusel),
        .res_o(e_res),
        .brtaken_o(e_brtaken)
    );

    // Branch/jump resolution: redirect PC on taken branch or jump
    assign jump_branch = d_x_pcsel || e_brtaken;

    
    //  EX/MEM PIPELINE REGISTER
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
        .pc_i(d_x_pc),
        .alu_res_i(e_res),
        .rs2_data_i(d_x_rs2data),
        .imm_i(d_x_imm),
        // Metadata from EX
        .rd_i(d_x_rd),
        .funct3_i(d_x_funct3),
        // Control from EX
        .regwren_i(d_x_regwren),
        .memren_i(d_x_memren),
        .memwren_i(d_x_memwren),
        .wbsel_i(d_x_wbsel),
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


    //  MEM STAGE — Data Memory Access
    
    logic [DWIDTH-1:0] mem_rdata;   // Data loaded from memory

    memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .OWIDTH(2),
        .BASE_ADDR(32'h01000000)
    ) memory1 (
        .clk(clk),
        .rst(reset),
        .pc_i(f_pc),              // IF stage: instruction address
        .addr_i(mem_alu_res),      // MEM stage: data address
        .data_i(mem_rs2_data),     // MEM stage: store data
        .funct3_i(mem_funct3),     // MEM stage: byte/half/word select
        .memren_i(mem_memren),     // MEM stage: read enable
        .memwren_i(mem_memwren),   // MEM stage: write enable
        .insnen_i(1'b1),           // IF stage: always fetch instructions
        .insn_o(f_insn),          // IF stage: fetched instruction
        .data_o(mem_rdata)         // MEM stage: loaded data
    );

    
    //  MEM/WB PIPELINE REGISTER
    
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

    
    //  WB STAGE — Writeback to Register File
    
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

    
    //  HAZARD CONTROL — Stall & Flush Logic
    
    stall_flush_logic stall_flush (
        // ID stage source registers
        .id_rs1_i(d_rs1),
        .id_rs2_i(d_rs2),
        .id_rs1_valid_i(c_rs1sel),
        .id_rs2_valid_i(c_rs2sel),
        // EX stage destination and control
        .ex_rd_i(d_x_rd),
        .ex_regwren_i(d_x_regwren),
        .ex_memren_i(d_x_memren),
        .ex_brtaken_i(e_brtaken),
        .ex_is_jump_i(d_x_pcsel),
        // MEM stage destination and control
        .mem_rd_i(mem_rd),
        .mem_regwren_i(mem_regwren),
        .mem_memren_i(mem_memren),
        // Pipeline control outputs
        .pc_en_o(pc_en),
        .if_id_stall_o(f_d_stall),
        .if_id_flush_o(f_d_flush),
        .id_ex_flush_o(d_x_flush),
        .ex_mem_flush_o(flush_ex_mem)
    );

    // Synthesis keep signal so yosys does not optimize away the design
    (* keep *) logic busy;
    assign busy = (wb_regwren || mem_memren || mem_memwren);

endmodule : rv_core
