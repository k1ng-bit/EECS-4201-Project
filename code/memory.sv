/*
 * Module: memory
 *
 * Description: MEM-stage memory unit: the lecture's "memory FU" (lec10 slide 47),
 *              built from three parts.
 *   1) memory_controller - word-aligns the address, places store data on its
 *                          byte lanes, and formats (shifts and extends) load data.
 *   2) store_buffer (SB) - holds stores so the pipeline keeps going while they are
 *                          written to memory in the background (lec13 slide 65).
 *                          Loads search it first and get forwarded data on a match.
 *   3) main_memory       - instruction port (fetch) and one data port.
 *
 *   The data port is shared by load reads and SB head writes: a structural hazard
 *   (lecture 7, "resource needed twice in one cycle"), solved by stalling.
 *     - A load that found no SB match gets the port first.
 *     - A head write that has started keeps the port until it finishes.
 *     - Otherwise the SB writes its head store whenever the port is free.
 *   MEM holds one instruction, so while a store waits for a free entry no load
 *   competes for the port and the SB keeps draining: no fairness logic is needed.
 *
 *   data_ready_o tells the hazard unit when the access in MEM is finished:
 *     - a store is finished once the SB accepts it (the SB is not full);
 *     - a load is finished when the SB forwards it or its memory read is done.
 *   A partial SB match or a busy data port keeps data_ready_o low, which stalls
 *   the pipeline through the existing memory-wait logic.
 *
 * Inputs:
 *   1) clk, rst         - Clock and asynchronous active-high reset
 *   2) pc_i             - Instruction address (IF stage)
 *   3) addr_i           - Data address (MEM stage)
 *   4) data_i           - Store data (MEM stage)
 *   5) funct3_i         - Access size and sign: byte, halfword or word
 *   6) memren_i         - The instruction in MEM is a load
 *   7) memwren_i        - The instruction in MEM is a store
 *   8) insnen_i         - Instruction read enable
 *   9) insn_taken_i     - The core took the fetched instruction (starts a new fetch)
 *
 * Outputs:
 *   1) insn_ready_o     - The instruction for pc_i is ready
 *   2) insn_o           - Fetched instruction
 *   3) data_ready_o     - The load or store in MEM is finished
 *   4) data_o           - Loaded data, shifted and sign- or zero-extended
 *   5) sb_empty_o       - No store is waiting in the SB (a FENCE may proceed)
 */

`include "constants.svh"

module memory #(
    parameter int AWIDTH = 32,                          // address width
    parameter int DWIDTH = 32,                          // data width
    parameter int OWIDTH = 2,                           // width of the byte offset in a word
    parameter logic [AWIDTH-1:0] BASE_ADDR = MEM_BASE_ADDR,  // address of the first byte of memory
    parameter int SB_ENTRIES = SB_DEPTH                 // number of store buffer entries
) (
    input  logic              clk,            // clock
    input  logic              rst,            // asynchronous active-high reset
    input  logic [AWIDTH-1:0] pc_i,           // instruction address
    input  logic [AWIDTH-1:0] addr_i,         // data address
    input  logic [DWIDTH-1:0] data_i,         // data to write to memory
    input  logic [2:0]        funct3_i,       // access size and sign
    input  logic              memren_i,       // the instruction in MEM is a load
    input  logic              memwren_i,      // the instruction in MEM is a store
    input  logic              insnen_i,       // instruction read enable
    input  logic              insn_taken_i,   // 1 = start a new fetch
    output logic              insn_ready_o,   // 1 = the instruction for pc_i is ready
    output logic [DWIDTH-1:0] insn_o,         // fetched instruction
    output logic              data_ready_o,   // 1 = the load or store in MEM is finished
    output logic [DWIDTH-1:0] data_o,         // loaded data, formatted
    output logic              sb_empty_o      // 1 = no store waiting in the SB
);

    localparam int BYTES = DWIDTH / 8;        // bytes per word

    // memory_controller outputs
    logic [AWIDTH-1:0] mem_address;           // word-aligned, base-relative address of the MEM access
    logic [DWIDTH-1:0] store_value;           // store data placed on its byte lanes
    logic [BYTES-1:0]  store_be;              // byte enables of the store in MEM
    // Load path
    logic [OWIDTH-1:0] mem_offset;            // byte offset of the access within its word
    logic [BYTES-1:0]  load_be;               // bytes of the word the load in MEM reads
    logic [DWIDTH-1:0] load_word;             // word given to the load formatter
    // Store buffer
    logic              sb_forward;            // the SB forwards the load
    logic              sb_partial;            // the SB only partly covers the load: interlock
    logic [DWIDTH-1:0] sb_value;              // forwarded word, on its byte lanes
    logic              sb_full;               // the SB has no free entry
    logic              sb_head_valid;         // the SB holds a store to write
    logic [AWIDTH-1:0] sb_head_address;       // address of the head store
    logic [DWIDTH-1:0] sb_head_value;         // value of the head store
    logic [BYTES-1:0]  sb_head_be;            // byte enables of the head store
    logic              head_written;          // main memory wrote the head store this cycle
    // Data port
    logic              load_needs_port;       // the load in MEM found no SB match and must read memory
    logic              port_load;             // the data port serves the load this cycle
    logic              port_head;             // the data port serves the SB head write this cycle
    logic              head_write_active;     // a head write started and has not finished
    logic [AWIDTH-1:0] ram_address;           // address on the data port
    logic              ram_ready;             // main memory finished the data-port access
    logic [DWIDTH-1:0] ram_data;              // word read from main memory

    // Bytes a load reads: one, two or four, starting at the byte offset.
    function automatic logic [BYTES-1:0] load_byte_enables(input logic [2:0] funct3,
                                                           input logic [OWIDTH-1:0] offset);
        case (funct3)
            `F3_LB, `F3_LBU: return BYTES'({1{1'b1}}) << offset;   // one byte
            `F3_LH, `F3_LHU: return BYTES'({2{1'b1}}) << offset;   // two bytes
            default:         return {BYTES{1'b1}} << offset;       // whole word
        endcase
    endfunction

    memory_controller #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .OWIDTH(OWIDTH),
        .BASE_ADDR(BASE_ADDR)
    ) mem_con (
        .rst(rst),
        .addr_i(addr_i),
        .data_i(data_i),
        .mem_data_i(load_word),
        .funct3_i(funct3_i),
        .memren_i(memren_i),
        .memwren_i(memwren_i),
        .waddr_o(mem_address),
        .wdata_o(store_value),
        .rdata_o(data_o),
        .byteen_o(store_be)
    );

    //---------- Load path ----------//
    assign mem_offset      = OWIDTH'(addr_i - BASE_ADDR);
    assign load_be         = load_byte_enables(funct3_i, mem_offset);
    // A forwarded word goes through the same formatter as a word read from memory.
    assign load_word       = sb_forward ? sb_value : ram_data;

    store_buffer #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .DEPTH(SB_ENTRIES)
    ) sb (
        .clk(clk),
        .rst(rst),
        .st_valid_i(memwren_i),
        .st_address_i(mem_address),
        .st_value_i(store_value),
        .st_be_i(store_be),
        .ld_valid_i(memren_i),
        .ld_address_i(mem_address),
        .ld_be_i(load_be),
        .ld_forward_o(sb_forward),
        .ld_value_o(sb_value),
        .ld_partial_o(sb_partial),
        .head_valid_o(sb_head_valid),
        .head_address_o(sb_head_address),
        .head_value_o(sb_head_value),
        .head_be_o(sb_head_be),
        .head_written_i(head_written),
        .full_o(sb_full),
        .empty_o(sb_empty_o)
    );

    //---------- Data port: load reads and head writes ----------//
    assign load_needs_port = memren_i && !sb_forward && !sb_partial;
    assign port_load       = load_needs_port && !head_write_active;
    assign port_head       = sb_head_valid && !port_load;
    assign ram_address     = port_head ? sb_head_address : mem_address;
    assign head_written    = port_head && ram_ready;

    // A head write keeps the data port from the cycle it starts until main memory
    // reports it finished, so main memory's wait counter is never interrupted.
    always_ff @(posedge clk or posedge rst) begin : head_write_owner
        if (rst) head_write_active <= 1'b0;
        else     head_write_active <= port_head && !ram_ready;
    end

    //---------- MEM completion for the hazard unit ----------//
    assign data_ready_o = (memwren_i && !sb_full)
                       || (memren_i && (sb_forward || (port_load && ram_ready)));

    main_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .BASE_ADDR(BASE_ADDR)
    ) ram (
        .clk(clk),
        .rst(rst),
        .pc_i(pc_i),
        .addr_i(ram_address),
        .data_i(sb_head_value),
        .bytelane_i(sb_head_be),
        .memren_i(port_load),
        .memwren_i(port_head),
        .insnen_i(insnen_i),
        .insn_taken_i(insn_taken_i),
        .insn_ready_o(insn_ready_o),
        .insn_o(insn_o),
        .data_ready_o(ram_ready),
        .data_o(ram_data)
    );

endmodule : memory
