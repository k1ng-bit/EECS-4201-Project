/*
 * Module: stall_flush_logic
 *
 * Description:
 * Hazard unit of the 5-stage in-order RV32I pipeline, in the words of lecture 7.
 * A data hazard is solved by an interlock (stall), a control hazard by a flush,
 * and a slow memory by holding the pipeline. The pipeline registers are
 * F/D (if_id), D/X (id_ex), X/M (ex_mem) and M/W (mem_wb).
 *
 * What each case does (rows are in priority order, the first one that applies wins):
 *
 *   Case                              PC write enable  F/D       D/X            X/M     M/W
 *   mem_wait: a load or store in MEM  off (frozen)     hold      hold           hold    bubble (flush)
 *     waits for memory
 *   control_hazard: taken branch      on (new PC)      flush     flush          -       -
 *     or jump resolved in EX
 *   data_hazard: RAW on a register    off (frozen)     hold      insert a NOP   -       -
 *     written by EX or MEM
 *   fetch_wait: the instruction       off (frozen)     bubble    -              -       -
 *     for the PC has not arrived
 *
 * "hold" = disable the pipeline register (lecture: "disable F/D pipeline reg"),
 * "flush" and "bubble" = load a NOP into it, "-" = unchanged.
 * Every load sets regwren, so ex_hazard also covers the load-use case.
 *
 * Inputs:
 *   insn_ready_i                       - IF: the fetched instruction has arrived
 *   id_rs1_i, id_rs2_i, *_valid_i      - ID: source registers of the instruction in D
 *   ex_*_i                             - EX: the instruction one stage ahead
 *   mem_*_i                            - MEM: the instruction two stages ahead,
 *                                        mem_ready_i = its load or store has finished
 *
 * Outputs:
 *   pc_en_o                            - PC write enable (0 = PC frozen)
 *   if_id_stall_o, if_id_flush_o,
 *   if_id_bubble_o                     - hold, flush or bubble F/D
 *   id_ex_stall_o, id_ex_flush_o       - hold D/X, or insert a NOP into it
 *   ex_mem_stall_o, ex_mem_flush_o     - hold X/M, or flush it (never: always 0)
 *   mem_wb_flush_o                     - put a bubble into M/W
 *
 * TODO: add the EX-store and decode-FENCE inputs, so a FENCE waits in D until every
 *       older store has been written (the store buffer is empty).
 * TODO: rename the ports to the F/D, D/X, X/M, M/W style (f_d_stall_o, d_x_flush_o, ...)
 *       together with the wiring in rv_core.sv.
 */

module stall_flush_logic (
    
    // IF stage: fetch waiter
    input  logic       insn_ready_i,     // 1 = the instruction for the PC has arrived

    // ID stage: current instruction source registers
    input  logic [4:0] id_rs1_i,         // source register 1 of the instruction in D
    input  logic [4:0] id_rs2_i,         // source register 2 of the instruction in D
    input  logic       id_rs1_valid_i,   // 1 = the instruction in D reads rs1
    input  logic       id_rs2_valid_i,   // 1 = the instruction in D reads rs2

    // EX stage: instruction one stage ahead
    input  logic [4:0] ex_rd_i,          // destination register of the instruction in EX
    input  logic       ex_regwren_i,     // 1 = the instruction in EX writes a register
    input  logic       ex_memren_i,      // 1 = the instruction in EX is a load
    input  logic       ex_brtaken_i,     // 1 = the branch in EX is taken
    input  logic       ex_is_jump_i,     // 1 = the instruction in EX is a jump

    // MEM stage: instruction two stages ahead
    input  logic [4:0] mem_rd_i,         // destination register of the instruction in MEM
    input  logic       mem_regwren_i,    // 1 = the instruction in MEM writes a register
    input  logic       mem_memren_i,     // 1 = the instruction in MEM is a load
    input  logic       mem_memwren_i,    // 1 = the instruction in MEM is a store
    input  logic       mem_ready_i,      // 1 = the load or store in MEM has finished

    // Pipeline control outputs
    output logic       pc_en_o,          // PC write enable: 0 = PC frozen
    output logic       if_id_stall_o,    // disable F/D: hold its contents
    output logic       if_id_flush_o,    // F/D gets a NOP after a taken branch or jump
    output logic       id_ex_flush_o,    // insert a NOP (bubble) into D/X
    output logic       id_ex_stall_o,    // hold D/X while MEM waits
    output logic       if_id_bubble_o,   // F/D gets a NOP while the fetch is not ready
    output logic       ex_mem_flush_o,   // flush X/M: always 0, branches resolve in EX
    output logic       ex_mem_stall_o,   // hold X/M while MEM waits
    output logic       mem_wb_flush_o    // put a bubble into M/W while MEM waits
);

    // Internal hazard signals
    logic ex_hazard;        // a source register of D is written by the instruction in EX
    logic mem_hazard;       // a source register of D is written by the instruction in MEM
    logic data_hazard;      // RAW hazard: stall (interlock) until the value is in the register file
    logic control_hazard;   // a taken branch or jump: the fetched instructions are wrong
    logic fetch_wait;       // the instruction for the PC has not arrived
    logic mem_wait;         // a load or store in MEM is not finished

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

    // Any data hazard requires a stall
    // load_use is covered by ex_hazard where every load sets regwren
    assign data_hazard =
        ex_hazard ||
        mem_hazard;

    // Taken branch or jump creates a control hazard
    assign control_hazard =
        ex_brtaken_i ||
        ex_is_jump_i;

    // Stall PC and IF/ID gets a bubble as instruction is not ready and there is no control hazard
    assign fetch_wait = !insn_ready_i && !control_hazard; 

    assign mem_wait = (mem_memren_i || mem_memwren_i) && !mem_ready_i;

    // Stall PC when a data hazard is present
    assign pc_en_o =
        !mem_wait && !(data_hazard && !control_hazard) && !fetch_wait;

    // Hold IF/ID during a data hazard or memory wait.
    assign if_id_stall_o =
        mem_wait || (data_hazard && !control_hazard);

    // Flush IF/ID after a taken branch or jump as long as memory is not waiting
    assign if_id_flush_o =
        !mem_wait && control_hazard;

    // Bubble at IF/ID when waiting for fetch and no data hazard and no memory wait
    assign if_id_bubble_o = !mem_wait && fetch_wait && !data_hazard;

    // Insert a bubble into ID/EX for a data hazard
    // or flush it for a taken branch/jump
    assign id_ex_flush_o =
        !mem_wait   &&
        (data_hazard ||
        control_hazard);

    // EX/MEM is not flushed by Stage 2 hazard logic
    assign ex_mem_flush_o =
        1'b0;
    
    assign id_ex_stall_o = mem_wait;    // while the memory is waiting, hold ID/EX
    assign ex_mem_stall_o = mem_wait;   // while memory waits, hold EX/MEM
    assign mem_wb_flush_o = mem_wait;   // while memory waits, flush MEM/WB

endmodule
