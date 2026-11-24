/*
 * Module: store_buffer
 *
 * Description: Store buffer (SB) between the MEM stage and data memory, built
 *              like the store buffer of lec13 (slide 65) and the memory
 *              ordering buffer (MOB) of lec10 (slides 47-52).
 *
 *   Store allocate (lecture "Store Execute: address+value to MOB"):
 *     a store in MEM writes its address, value and byte enables into the
 *     entry at the tail and the pipeline keeps going.
 *   Head write (lecture "Store Retire: write head of MOB to D$"):
 *     the entry at the head is offered to memory. When memory has written
 *     it, the head entry is freed. Stores reach memory in program order.
 *   Load search (lecture "Load Execute: compare to older store addresses"):
 *     a load in MEM compares its word address with every store in the SB.
 *     The youngest store whose bytes overlap the load decides the result:
 *       - it writes every byte the load reads -> forward its value;
 *       - it writes only some of them         -> partial match, the load
 *         must interlock until that store has been written to memory;
 *       - no store overlaps                   -> the load reads memory.
 *
 *   The SB holds stores only, so the lecture MOB's L/S column is not needed.
 *   The pipeline is in order, so every entry is older than the load in MEM
 *   and every older store address is known: no memory disambiguation.
 *   Stores enter in MEM after their branch resolved in EX, so an entry is
 *   never on a wrong path and the SB needs no flush input.
 *
 * Inputs:
 *   1) clk, rst          - Clock and asynchronous active-high reset
 *   2) st_valid_i        - A store in MEM asks for an entry
 *   3) st_address_i      - Word-aligned, base-relative byte address of the store
 *   4) st_value_i        - Store value, already placed on its byte lanes
 *   5) st_be_i           - Byte enables of the store
 *   6) ld_valid_i        - A load in MEM searches the SB
 *   7) ld_address_i      - Word-aligned, base-relative byte address of the load
 *   8) ld_be_i           - Byte enables of the bytes the load reads
 *   9) head_written_i    - Memory wrote the head entry this cycle (frees it)
 *
 * Outputs:
 *   1) ld_forward_o      - The youngest overlapping store covers the load
 *   2) ld_value_o        - That store's value, on its byte lanes
 *   3) ld_partial_o      - The youngest overlapping store covers only part
 *   4) head_valid_o      - The SB holds a store that must be written
 *   5) head_address_o    - Address of the head store
 *   6) head_value_o      - Value of the head store, on its byte lanes
 *   7) head_be_o         - Byte enables of the head store
 *   8) full_o, empty_o   - Occupancy flags (full stalls a store, empty releases FENCE)
 *
 * TODO: merge a new store into an entry for the same word (store coalescing)
 *       to save entries and memory writes.
 * TODO: forward by merging bytes from several entries instead of
 *       interlocking on a partial match.
 * TODO: start the memory read in parallel with the search, as the lecture
 *       MOB does, once memory can cancel a read that turns out to be forwarded.
 */

`include "constants.svh"

module store_buffer #(
    parameter int AWIDTH = 32,        // address width
    parameter int DWIDTH = 32,        // data width
    parameter int DEPTH  = SB_DEPTH   // number of entries, a power of two >= 2
)(
    input  logic                    clk,             // clock
    input  logic                    rst,             // asynchronous active-high reset
    // Store allocate
    input  logic                    st_valid_i,      // a store in MEM asks for an entry
    input  logic [AWIDTH-1:0]       st_address_i,    // word-aligned, base-relative byte address
    input  logic [DWIDTH-1:0]       st_value_i,      // store value on its byte lanes
    input  logic [(DWIDTH/8)-1:0]   st_be_i,         // byte enables of the store
    // Load search
    input  logic                    ld_valid_i,      // a load in MEM searches the SB
    input  logic [AWIDTH-1:0]       ld_address_i,    // word-aligned, base-relative byte address
    input  logic [(DWIDTH/8)-1:0]   ld_be_i,         // bytes of the word the load reads
    output logic                    ld_forward_o,    // forward: the youngest overlapping store covers the load
    output logic [DWIDTH-1:0]       ld_value_o,      // value to forward, on its byte lanes
    output logic                    ld_partial_o,    // partial match: the load must interlock
    // Head write
    output logic                    head_valid_o,    // a store is waiting to be written to memory
    output logic [AWIDTH-1:0]       head_address_o,  // address of the head store
    output logic [DWIDTH-1:0]       head_value_o,    // value of the head store
    output logic [(DWIDTH/8)-1:0]   head_be_o,       // byte enables of the head store
    input  logic                    head_written_i,  // memory wrote the head entry this cycle
    // Occupancy
    output logic                    full_o,          // every entry holds a store
    output logic                    empty_o          // no store is waiting
);

    localparam int BYTES = DWIDTH / 8;        // bytes per word
    localparam int PTR_W = $clog2(DEPTH);     // width of the head and tail pointers
    localparam int CNT_W = PTR_W + 1;         // width of the count, which reaches DEPTH

    // One SB entry: the lecture MOB's address and value columns, plus byte enables.
    typedef struct packed {
        logic [AWIDTH-1:0] address;   // word-aligned, base-relative byte address
        logic [BYTES-1:0]  be;        // which bytes of the word the store writes
        logic [DWIDTH-1:0] value;     // store value on its byte lanes
    } sb_entry_t;

    sb_entry_t        sb_entries [DEPTH];   // entry storage
    logic [PTR_W-1:0] sb_head;              // oldest store: the next one written to memory
    logic [PTR_W-1:0] sb_tail;              // next free entry: where the next store goes
    logic [CNT_W-1:0] sb_count;             // number of stores waiting
    logic             sb_allocate;          // a store takes the tail entry this cycle
    logic             sb_free;              // the head entry is freed this cycle

    logic [PTR_W-1:0] sb_age [DEPTH];       // age of each entry: 0 = head (oldest)
    logic [DEPTH-1:0] sb_valid;             // entry holds a store
    logic [DEPTH-1:0] sb_match;             // entry overlaps the load (lecture "==" column)
    logic [DEPTH-1:0] sb_match_by_age;      // sb_match reordered so bit k is the entry of age k
    logic [PTR_W-1:0] sb_youngest;          // index of the youngest overlapping entry
    logic             sb_any_match;         // at least one entry overlaps the load
    logic             sb_covered;           // the youngest overlapping entry covers the load

    // Returns the highest set bit: the age of the youngest overlapping store.
    function automatic logic [PTR_W-1:0] youngest_age(input logic [DEPTH-1:0] match_by_age);
        youngest_age = '0;
        for (int k = 0; k < DEPTH; k++)
            if (match_by_age[k]) youngest_age = PTR_W'(k);
    endfunction

    // A store covers a load when it writes every byte the load reads.
    function automatic logic covers(input logic [BYTES-1:0] store_be, input logic [BYTES-1:0] load_be);
        return (store_be & load_be) == load_be;
    endfunction

    //---------- Occupancy ----------//
    assign full_o      = (sb_count == CNT_W'(DEPTH));
    assign empty_o     = (sb_count == '0);
    assign sb_allocate = st_valid_i && !full_o;       // a full SB makes the store wait
    assign sb_free     = head_written_i && !empty_o;  // only a real head entry can be freed

    //---------- Store allocate (lecture "Store Execute") ----------//
    // Writes the store into the tail entry. Reset clears every entry.
    always_ff @(posedge clk or posedge rst) begin : sb_entry_write
        if (rst) begin
            for (int i = 0; i < DEPTH; i++) sb_entries[i] <= '0;
        end else if (sb_allocate) begin
            sb_entries[sb_tail] <= '{address: st_address_i, be: st_be_i, value: st_value_i};
        end
    end

    // Tail pointer: moves to the next entry after each store allocate.
    always_ff @(posedge clk or posedge rst) begin : sb_tail_update
        if (rst)              sb_tail <= '0;
        else if (sb_allocate) sb_tail <= sb_tail + PTR_W'(1);
    end

    // Head pointer: moves to the next entry after each head write.
    always_ff @(posedge clk or posedge rst) begin : sb_head_update
        if (rst)          sb_head <= '0;
        else if (sb_free) sb_head <= sb_head + PTR_W'(1);
    end

    // Count: one more per store allocate, one fewer per head write.
    always_ff @(posedge clk or posedge rst) begin : sb_count_update
        if (rst) sb_count <= '0;
        else     sb_count <= sb_count + CNT_W'(sb_allocate) - CNT_W'(sb_free);
    end

    //---------- Head write (lecture "Store Retire") ----------//
    assign head_valid_o   = !empty_o;
    assign head_address_o = sb_entries[sb_head].address;
    assign head_value_o   = sb_entries[sb_head].value;
    assign head_be_o      = sb_entries[sb_head].be;

    //---------- Load search (lecture "Load Execute") ----------//
    // Per entry: its age, whether it holds a store, and whether it overlaps the load.
    for (genvar i = 0; i < DEPTH; i++) begin : g_search
        assign sb_age[i]   = PTR_W'(i) - sb_head;
        assign sb_valid[i] = (CNT_W'(sb_age[i]) < sb_count);
        assign sb_match[i] = sb_valid[i] && (sb_entries[i].address == ld_address_i)
                             && ((sb_entries[i].be & ld_be_i) != '0);
    end

    // Rotate so that bit k is the entry of age k, then pick the youngest match
    // (lecture: "multiple matches? youngest matching store older than load").
    assign sb_match_by_age = DEPTH'({sb_match, sb_match} >> sb_head);
    assign sb_youngest     = sb_head + youngest_age(sb_match_by_age);
    assign sb_any_match    = |sb_match;
    assign sb_covered      = covers(sb_entries[sb_youngest].be, ld_be_i);

    assign ld_forward_o = ld_valid_i && sb_any_match && sb_covered;
    assign ld_partial_o = ld_valid_i && sb_any_match && !sb_covered;
    assign ld_value_o   = sb_entries[sb_youngest].value;

`ifndef SYNTHESIS
    // The pointers wrap on their own only for a power-of-two depth.
    initial assert ((DEPTH >= 2) && ((DEPTH & (DEPTH - 1)) == 0))
        else $fatal(1, "store_buffer: DEPTH must be a power of two of at least 2");

    // Each property also holds during reset, so no "disable iff" is needed.
    // The SB never holds more stores than it has entries.
    a_count_in_range: assert property (@(posedge clk) sb_count <= CNT_W'(DEPTH));
    // Memory may report a head write only while the SB holds a head entry.
    a_written_needs_head: assert property (@(posedge clk) head_written_i |-> !empty_o);
    // MEM holds one instruction, so a load search and a store allocate never happen together.
    a_one_access: assert property (@(posedge clk) !(ld_valid_i && st_valid_i));
    // A store or load always touches at least one byte.
    a_store_be: assert property (@(posedge clk) st_valid_i |-> (st_be_i != '0));
    a_load_be:  assert property (@(posedge clk) ld_valid_i |-> (ld_be_i != '0));
    // A search ends in a forward or a partial match, never both.
    a_one_result: assert property (@(posedge clk) !(ld_forward_o && ld_partial_o));
`endif

endmodule : store_buffer
