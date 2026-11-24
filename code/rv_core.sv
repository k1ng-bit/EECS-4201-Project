/*
 * Module: rv_core
 *
 * Description: Top level of the 5-stage in-order pipelined RISC-V core (RV32I).
 *              Instantiates the stages, the four pipeline registers (lecture 7
 *              names: F/D, D/X, X/M, M/W), the MEM-stage memory unit with its
 *              store buffer, and the stall/flush hazard unit.
 *
 * Pipeline:
 *   IF -> F/D -> ID -> D/X -> EX -> X/M -> MEM -> M/W -> WB
 *
 * Signal names start with the pipeline register or stage they belong to:
 *   f_  IF stage      f_d_  F/D register    d_  ID stage    c_  control
 *   r_  register file d_x_  D/X register    e_  EX stage    x_m_  X/M register
 *   m_  MEM stage     m_w_  M/W register    wb_ WB stage
 *
 * Inputs:
 *   1) clk   - Clock signal
 *   2) reset - Asynchronous active-high reset
 */

`include "constants.svh"

module rv_core #(
    parameter int AWIDTH = 32,   // address width
    parameter int DWIDTH = 32    // data width
)(
    input logic clk,     // clock
    input logic reset    // asynchronous active-high reset
);

    //---------- Pipeline control (from stall_flush_logic) ----------//
    logic pc_en;         // PC write enable: 1 = PC moves forward, 0 = PC frozen
    logic f_d_stall;     // hold the F/D register (lecture 7, "disable F/D pipeline reg")
    logic f_d_flush;     // flush F/D after a taken branch or jump
    logic f_d_bubble;    // put a bubble in F/D while the fetch is still waiting
    logic d_x_flush;     // put a bubble in D/X (lecture 7, "insert NOPs")
    logic d_x_stall;     // hold D/X while MEM waits for memory
    logic x_m_stall;     // hold X/M while MEM waits for memory
    logic x_m_flush;     // flush X/M: always 0, branches resolve in EX
    logic m_w_flush;     // bubble into M/W while MEM waits for memory

    // Probes read by top_tb and rv_official_tb through hierarchical references.
    logic stall;         // decode is held by a hazard or gets a bubble from a waiting fetch
    logic flush;         // F/D is flushed after a taken branch or jump

    assign stall = f_d_stall || f_d_bubble;
    assign flush = f_d_flush;

    //---------- IF stage: instruction fetch ----------//
    logic [AWIDTH-1:0] f_pc;          // current program counter
    logic [DWIDTH-1:0] f_insn;        // fetched instruction
    logic              f_insn_ready;  // 1 = the instruction at f_pc has arrived from memory

    // Branch and jump resolution, fed back from EX
    logic              jump_branch;   // taken branch or jump in EX
    logic [DWIDTH-1:0] e_res;         // ALU result, or the branch or jump target

    fetch #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .BASE_ADDR(MEM_BASE_ADDR)
    ) fetch1 (
        .clk(clk),
        .rst(reset),
        .next_pc_i(e_res),
        .pc_en_i(pc_en),
        .jump_branch_i(jump_branch),
        .pc_o(f_pc)
    );

    //---------- F/D pipeline register ----------//
    logic [AWIDTH-1:0] f_d_pc;        // PC of the instruction in ID
    logic [DWIDTH-1:0] f_d_insn;      // instruction in ID

    if_id_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) f_d_reg (
        .clk(clk),
        .rst(reset),
        .stall_i(f_d_stall),
        .flush_i(f_d_flush || f_d_bubble),
        .pc_i(f_pc),
        .insn_i(f_insn),
        .pc_o(f_d_pc),
        .insn_o(f_d_insn)
    );

    //---------- ID stage: decode, immediate, control, register read ----------//
    logic [OPCODE_W-1:0]  d_opcode;   // opcode field
    logic [REG_IDX_W-1:0] d_rd;       // destination register
    logic [REG_IDX_W-1:0] d_rs1;      // source register 1
    logic [REG_IDX_W-1:0] d_rs2;      // source register 2
    logic [FUNCT7_W-1:0]  d_funct7;   // funct7 field
    logic [FUNCT3_W-1:0]  d_funct3;   // funct3 field

    decode #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) decode1 (
        .clk(clk),
        .rst(reset),
        .insn_i(f_d_insn),
        .pc_i(f_d_pc),
        .pc_o(),             // unused: the pipeline registers carry the PC
        .insn_o(),           // unused: the pipeline registers carry the instruction
        .opcode_o(d_opcode),
        .rd_o(d_rd),
        .rs1_o(d_rs1),
        .rs2_o(d_rs2),
        .funct7_o(d_funct7),
        .funct3_o(d_funct3),
        .shamt_o(),          // unused: the shift amount comes from the immediate
        .imm_o()             // unused: the immediate comes from igen
    );

    logic [DWIDTH-1:0] d_imm;         // immediate from igen

    igen #(
        .DWIDTH(DWIDTH)
    ) igen1 (
        .opcode_i(d_opcode),
        .insn_i(f_d_insn),
        .imm_o(d_imm)
    );

    // Control signals (lecture 6 names in brackets)
    logic                c_pcsel;     // [PCSel] the instruction is a jump
    logic                c_immsel;    // [ImmSel] the instruction has an immediate
    logic                c_regwren;   // [RegWEn] write rd in WB
    logic                c_rs1sel;    // the instruction reads rs1 (used by the hazard unit)
    logic                c_rs2sel;    // the instruction reads rs2 (used by the hazard unit)
    logic                c_memren;    // the instruction is a load
    logic                c_memwren;   // the instruction is a store ([MemRW] for stores)
    logic [WBSEL_W-1:0]  c_wbsel;     // [WBSel] write-back source
    logic [ALUSEL_W-1:0] c_alusel;    // [ALUSel] ALU operation

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

    // Register file: read in ID, written in WB
    logic [DWIDTH-1:0]    r_rs1data;    // value of rs1
    logic [DWIDTH-1:0]    r_rs2data;    // value of rs2
    logic [REG_IDX_W-1:0] m_w_rd;       // destination register of the instruction in WB
    logic [DWIDTH-1:0]    wb_data;      // value written to rd, chosen by the WBSel mux
    logic                 m_w_regwren;  // [RegWEn] of the instruction in WB

    register_file #(
        .DWIDTH(DWIDTH)
    ) register_file1 (
        .clk(clk),
        .rst(reset),
        .rs1_i(d_rs1),
        .rs2_i(d_rs2),
        .rd_i(m_w_rd),
        .datawb_i(wb_data),
        .regwren_i(m_w_regwren),
        .rs1data_o(r_rs1data),
        .rs2data_o(r_rs2data)
    );

    //---------- D/X pipeline register ----------//
    logic [AWIDTH-1:0]    d_x_pc;         // PC of the instruction in EX
    logic [DWIDTH-1:0]    d_x_rs1data;    // value of rs1
    logic [DWIDTH-1:0]    d_x_rs2data;    // value of rs2
    logic [DWIDTH-1:0]    d_x_imm;        // immediate
    logic [REG_IDX_W-1:0] d_x_rd;         // destination register
    logic [REG_IDX_W-1:0] d_x_rs1;        // source register 1 (kept for a future bypass unit)
    logic [REG_IDX_W-1:0] d_x_rs2;        // source register 2 (kept for a future bypass unit)
    logic [FUNCT3_W-1:0]  d_x_funct3;     // funct3 field
    logic [FUNCT7_W-1:0]  d_x_funct7;     // funct7 field
    logic [OPCODE_W-1:0]  d_x_opcode;     // opcode field
    logic                 d_x_pcsel;      // [PCSel] the instruction is a jump
    logic                 d_x_regwren;    // [RegWEn]
    logic                 d_x_memren;     // load
    logic                 d_x_memwren;    // store
    logic [WBSEL_W-1:0]   d_x_wbsel;      // [WBSel]
    logic [ALUSEL_W-1:0]  d_x_alusel;     // [ALUSel]

    id_ex_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) d_x_reg (
        .clk(clk),
        .rst(reset),
        .flush_i(d_x_flush),
        .stall_i(d_x_stall),
        // Data from ID
        .pc_i(f_d_pc),
        .rs1_data_i(r_rs1data),
        .rs2_data_i(r_rs2data),
        .imm_i(d_imm),
        // Instruction fields from ID
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
        // To EX
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

    //---------- EX stage: ALU and branch resolution ----------//
    logic [DWIDTH-1:0] alu_a;         // ALU operand A
    logic [DWIDTH-1:0] alu_b;         // ALU operand B
    logic              e_brtaken;     // 1 = the branch condition is true

    // [ASel] Operand A: always the value of rs1.
    assign alu_a = d_x_rs1data;

    // [BSel] Operand B: the immediate for I-type, load, JALR and store
    // instructions, otherwise the value of rs2.
    assign alu_b = ((d_x_opcode == `I_TYPE)      ||
                    (d_x_opcode == `I_TYPE_L)    ||
                    (d_x_opcode == `I_TYPE_JALR) ||
                    (d_x_opcode == `S_TYPE)) ? d_x_imm : d_x_rs2data;

    alu #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) e_alu1 (
        .pc_i(d_x_pc),
        .rs1_i(alu_a),
        .rs2_i(alu_b),
        .funct3_i(d_x_funct3),
        .funct7_i(d_x_funct7),
        .opcode_i(d_x_opcode),
        .imm_i(d_x_imm),
        .alusel_i(d_x_alusel),
        .res_o(e_res),
        .brtaken_o(e_brtaken)
    );

    // Redirect the PC on a jump or a taken branch.
    assign jump_branch = d_x_pcsel || e_brtaken;

    //---------- X/M pipeline register ----------//
    logic [AWIDTH-1:0]    x_m_pc;         // PC of the instruction in MEM
    logic [DWIDTH-1:0]    x_m_alu_res;    // ALU result: the data address of a load or store
    logic [DWIDTH-1:0]    x_m_rs2data;    // store data
    logic [DWIDTH-1:0]    x_m_imm;        // immediate
    logic [REG_IDX_W-1:0] x_m_rd;         // destination register
    logic [FUNCT3_W-1:0]  x_m_funct3;     // access size and sign
    logic                 x_m_regwren;    // [RegWEn]
    logic                 x_m_memren;     // load
    logic                 x_m_memwren;    // store
    logic [WBSEL_W-1:0]   x_m_wbsel;      // [WBSel]

    ex_mem_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) x_m_reg (
        .clk(clk),
        .rst(reset),
        .flush_i(x_m_flush),
        .stall_i(x_m_stall),
        // Data from EX
        .pc_i(d_x_pc),
        .alu_res_i(e_res),
        .rs2_data_i(d_x_rs2data),
        .imm_i(d_x_imm),
        // Instruction fields from EX
        .rd_i(d_x_rd),
        .funct3_i(d_x_funct3),
        // Control from EX
        .regwren_i(d_x_regwren),
        .memren_i(d_x_memren),
        .memwren_i(d_x_memwren),
        .wbsel_i(d_x_wbsel),
        // To MEM
        .pc_o(x_m_pc),
        .alu_res_o(x_m_alu_res),
        .rs2_data_o(x_m_rs2data),
        .imm_o(x_m_imm),
        .rd_o(x_m_rd),
        .funct3_o(x_m_funct3),
        .regwren_o(x_m_regwren),
        .memren_o(x_m_memren),
        .memwren_o(x_m_memwren),
        .wbsel_o(x_m_wbsel)
    );

    //---------- MEM stage: store buffer and data memory ----------//
    logic              m_data_ready;  // 1 = the load or store in MEM is finished
    logic [DWIDTH-1:0] m_data_o;      // loaded data
    logic              m_sb_empty;    // 1 = no store waiting in the store buffer

    memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .OWIDTH(2),
        .BASE_ADDR(MEM_BASE_ADDR)
    ) memory1 (
        .clk(clk),
        .rst(reset),
        .pc_i(f_pc),                  // IF: instruction address
        .addr_i(x_m_alu_res),         // MEM: data address
        .data_i(x_m_rs2data),         // MEM: store data
        .funct3_i(x_m_funct3),        // MEM: byte, halfword or word
        .memren_i(x_m_memren),        // MEM: load
        .memwren_i(x_m_memwren),      // MEM: store
        .insnen_i(1'b1),              // IF: always fetch instructions
        .insn_taken_i(pc_en),         // IF: the PC moved, start the next fetch
        .insn_ready_o(f_insn_ready),  // IF: fetched instruction ready
        .insn_o(f_insn),              // IF: fetched instruction
        .data_ready_o(m_data_ready),  // MEM: load or store finished
        .data_o(m_data_o),            // MEM: loaded data
        .sb_empty_o(m_sb_empty)       // MEM: store buffer empty (for FENCE)
    );

    //---------- M/W pipeline register ----------//
    logic [AWIDTH-1:0] m_w_pc;        // PC of the instruction in WB
    logic [DWIDTH-1:0] m_w_alu_res;   // ALU result
    logic [DWIDTH-1:0] m_w_mem_data;  // loaded data
    logic [DWIDTH-1:0] m_w_imm;       // immediate
    logic [WBSEL_W-1:0] m_w_wbsel;    // [WBSel]

    mem_wb_reg #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) m_w_reg (
        .clk(clk),
        .rst(reset),
        .flush_i(m_w_flush),
        // Data from MEM
        .pc_i(x_m_pc),
        .alu_res_i(x_m_alu_res),
        .mem_data_i(m_data_o),
        .imm_i(x_m_imm),
        // Instruction field from MEM
        .rd_i(x_m_rd),
        // Control from MEM
        .regwren_i(x_m_regwren),
        .wbsel_i(x_m_wbsel),
        // To WB
        .pc_o(m_w_pc),
        .alu_res_o(m_w_alu_res),
        .mem_data_o(m_w_mem_data),
        .imm_o(m_w_imm),
        .rd_o(m_w_rd),
        .regwren_o(m_w_regwren),
        .wbsel_o(m_w_wbsel)
    );

    //---------- WB stage: write back to the register file ----------//
    writeback #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) wb_wb1 (
        .pc_i(m_w_pc),
        .alu_res_i(m_w_alu_res),
        .memory_data_i(m_w_mem_data),
        .wbsel_i(m_w_wbsel),
        .imm_i(m_w_imm),
        .writeback_data_o(wb_data)
    );

    //---------- Hazard control: stall and flush logic ----------//
    stall_flush_logic stall_flush (
        // IF: instruction ready
        .insn_ready_i(f_insn_ready),
        // ID: source registers
        .id_rs1_i(d_rs1),
        .id_rs2_i(d_rs2),
        .id_rs1_valid_i(c_rs1sel),
        .id_rs2_valid_i(c_rs2sel),
        // EX: destination and control
        .ex_rd_i(d_x_rd),
        .ex_regwren_i(d_x_regwren),
        .ex_memren_i(d_x_memren),
        .ex_brtaken_i(e_brtaken),
        .ex_is_jump_i(d_x_pcsel),
        // MEM: destination, control and completion
        .mem_rd_i(x_m_rd),
        .mem_regwren_i(x_m_regwren),
        .mem_memren_i(x_m_memren),
        .mem_memwren_i(x_m_memwren),
        .mem_ready_i(m_data_ready),
        // Pipeline controls
        .pc_en_o(pc_en),
        .if_id_stall_o(f_d_stall),
        .if_id_flush_o(f_d_flush),
        .if_id_bubble_o(f_d_bubble),
        .id_ex_stall_o(d_x_stall),
        .id_ex_flush_o(d_x_flush),
        .ex_mem_stall_o(x_m_stall),
        .ex_mem_flush_o(x_m_flush),
        .mem_wb_flush_o(m_w_flush)
    );

    // Keeps the design from being optimized away in synthesis: the core is busy
    // while it writes a register, accesses memory, or still holds stores in the SB.
    (* keep *) logic busy;
    assign busy = (m_w_regwren || x_m_memren || x_m_memwren || !m_sb_empty);

endmodule : rv_core
