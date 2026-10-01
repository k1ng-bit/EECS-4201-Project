/*
 * Module: stall_flush_logic
 *
 * Description:
 * Detects data hazards and control hazards in the
 * 5-stage in-order RV32I pipeline.
 *
 * Data hazards are handled by stalling the PC and IF/ID
 * register while inserting a bubble into ID/EX.
 *
 * Taken branches and jumps are handled by flushing
 * IF/ID and ID/EX.
 */

module stall_flush_logic (
    // ID stage: current instruction source registers
    input  logic [4:0] id_rs1_i,
    input  logic [4:0] id_rs2_i,
    input  logic       id_rs1_valid_i,
    input  logic       id_rs2_valid_i,

    // EX stage: instruction one stage ahead
    input  logic [4:0] ex_rd_i,
    input  logic       ex_regwren_i,
    input  logic       ex_memren_i,
    input  logic       ex_brtaken_i,
    input  logic       ex_is_jump_i,

    // MEM stage: instruction two stages ahead
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

    // Internal hazard signals
    logic ex_hazard;
    logic mem_hazard;
    logic load_use_hazard;
    logic data_hazard;
    logic control_hazard;

    // EX-stage RAW hazard
    assign ex_hazard =
        ex_regwren_i &&
        (ex_rd_i != 5'd0) &&
        ((id_rs1_valid_i && (id_rs1_i == ex_rd_i)) ||
         (id_rs2_valid_i && (id_rs2_i == ex_rd_i)));

    // MEM-stage RAW hazard
    assign mem_hazard =
        mem_regwren_i &&
        (mem_rd_i != 5'd0) &&
        ((id_rs1_valid_i && (id_rs1_i == mem_rd_i)) ||
         (id_rs2_valid_i && (id_rs2_i == mem_rd_i)));

    // Load-use hazard
    assign load_use_hazard =
        ex_memren_i &&
        (ex_rd_i != 5'd0) &&
        ((id_rs1_valid_i && (id_rs1_i == ex_rd_i)) ||
         (id_rs2_valid_i && (id_rs2_i == ex_rd_i)));

    // Any data hazard requires a stall
    assign data_hazard =
        ex_hazard ||
        mem_hazard ||
        load_use_hazard;

    // Taken branch or jump creates a control hazard
    assign control_hazard =
        ex_brtaken_i ||
        ex_is_jump_i;

    // Stall PC when a data hazard is present
    assign pc_en_o =
        !(data_hazard && !control_hazard);

    // Hold IF/ID during a data hazard
    assign if_id_stall_o =
        data_hazard && !control_hazard;

    // Flush IF/ID after a taken branch or jump
    assign if_id_flush_o =
        control_hazard;

    // Insert a bubble into ID/EX for a data hazard
    // or flush it for a taken branch/jump
    assign id_ex_flush_o =
        data_hazard ||
        control_hazard;

    // EX/MEM is not flushed by Stage 2 hazard logic
    assign ex_mem_flush_o =
        1'b0;

endmodule
