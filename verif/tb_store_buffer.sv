/*
 * Testbench: tb_store_buffer
 *
 * Description: Self-checking unit testbench for store_buffer (SB), run at depths 2, 4, 8 and 16.
 *   A reference model of the SB (a queue of stores, oldest first) is updated on every clock edge
 *   and compared with the RTL after every edge: count, full and empty flags and the head store.
 *   Every load search is compared with the model: forward, partial match or no match, and the
 *   forwarded value on the bytes the load reads. The directed cases also state the expected
 *   result by hand, so a wrong model cannot hide a wrong SB.
 *
 * Test cases, grouped by rubric category:
 *   Trivial
 *     T1  One store is allocated and then written to memory.
 *     T2  A load with no matching store.
 *     T3  sw then lw to the same word: a forward, while the store is still queued.
 *   Corner
 *     C1  Fill to the depth. A store held while full changes nothing. A store arriving with a
 *         head write is still held (the fill-and-free rule), then it is accepted once.
 *     C2  The SB is empty after the last head write.
 *     C3  Store allocate and head free in the same cycle.
 *     C4  Pointer wrap: head-write order and the youngest match across the wrap.
 *     C5  Two stores to one word: the youngest wins.
 *     C6  Each legal store size and lane against each legal load size and lane (7 x 7), plus
 *         hand-written subword cases with sign and zero extension bytes.
 *     C7  A younger disjoint store leaves an older forward alone. A younger partial store
 *         over an older store gives a partial match.
 *     C8  Different words with the same low address bits do not match.
 *     C9  A search on the same edge as the head write that frees the store.
 *   Invalid (I1, I2 and I4 are left out when built with -DSB_SKIP_ILLEGAL, see below)
 *     I1  head_written_i while empty is ignored.
 *     I2  A store with no byte enable never matches a load.
 *     I3  Reset in the middle of a burst empties the SB at once and leaves no stale entry.
 *     I4  Reset on the edge of the would-be final head write: reset wins.
 *   Non-trivial sequences
 *     S1  Seeded random run against the model (coverage of every outcome is checked).
 *     S2  A burst longer than the depth, back to back, with head writes freeing entries.
 *     S3  Repeated fill and drain.
 *
 * Prints PASS or FAIL per case, then "Test Passed" or "Test Failed".
 * TODO: bind the same checks to memory.sv to test the port sharing and data_ready_o.
 * TODO: add a second model that checks the bytes in main memory after every head write.
 */

`timescale 1ns/1ps
`include "constants.svh"

// One run of the whole suite against a store_buffer of one depth.
module sb_test #(
    parameter int DEPTH         = 4,      // entries in the SB under test
    parameter int SEED          = 1,      // seed of the random sequence
    parameter int RANDOM_CYCLES = 4000    // length of the random sequence S1
)(
    input  logic clk,      // clock, from the top
    input  logic start,    // 1 = begin this run
    output logic done,     // 1 = this run finished
    output int   errors    // failed checks in this run
);

    localparam int AWIDTH = 32;           // address width
    localparam int DWIDTH = 32;           // data width
    localparam int BYTES  = DWIDTH / 8;   // bytes per word

    // The sizes and lanes a store or load can have: sb/lb at four lanes, sh/lh at two, sw/lw.
    localparam logic [BYTES-1:0] LEGAL_BE [7] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000,
                                                  4'b0011, 4'b1100, 4'b1111};
    localparam logic [BYTES-1:0] WORD_BE = 4'b1111;           // a whole word
    localparam logic [DWIDTH-1:0] VALUE_A = 32'h80ff_7f01;    // bytes 01, 7f, ff, 80 (signs differ)
    localparam logic [DWIDTH-1:0] VALUE_B = 32'h1234_abcd;    // a second value

    typedef enum logic [1:0] {NONE, FORWARD, PARTIAL} result_t;   // outcome of a load search

    // One store in the reference model.
    typedef struct packed {
        logic [AWIDTH-1:0] address;   // word-aligned byte address
        logic [BYTES-1:0]  be;        // byte enables
        logic [DWIDTH-1:0] value;     // value on its byte lanes
    } entry_t;

    //---------- Signals of the device under test ----------//
    logic              rst;            // asynchronous active-high reset
    logic              st_valid;       // a store asks for an entry
    logic [AWIDTH-1:0] st_address;     // store address
    logic [DWIDTH-1:0] st_value;       // store value
    logic [BYTES-1:0]  st_be;          // store byte enables
    logic              ld_valid;       // a load searches the SB
    logic [AWIDTH-1:0] ld_address;     // load address
    logic [BYTES-1:0]  ld_be;          // load byte enables
    logic              head_written;   // memory wrote the head store
    logic              ld_forward;     // search result: forward
    logic [DWIDTH-1:0] ld_value;       // search result: forwarded value
    logic              ld_partial;     // search result: partial match
    logic              head_valid;     // a store waits to be written
    logic [AWIDTH-1:0] head_address;   // head store address
    logic [DWIDTH-1:0] head_value;     // head store value
    logic [BYTES-1:0]  head_be;        // head store byte enables
    logic              full;           // no free entry
    logic              empty;          // no store waiting

    //---------- Testbench state ----------//
    entry_t model [$];         // reference model: stores waiting, oldest first
    logic [31:0] rng;          // state of the random number generator (never 0)
    int     checks;            // checks done in this run
    int     case_errors;       // value of errors when the current case started
    string  case_name;         // name of the current case
    int     forwards;          // loads forwarded since the counters were cleared
    int     partials;          // loads that found a partial match
    int     no_matches;        // loads that found no match
    int     held_stores;       // store requests refused because the SB was full
    int     head_writes;       // head stores written
    int     peak;              // most stores waiting at once

    store_buffer #(.AWIDTH(AWIDTH), .DWIDTH(DWIDTH), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst),
        .st_valid_i(st_valid), .st_address_i(st_address), .st_value_i(st_value), .st_be_i(st_be),
        .ld_valid_i(ld_valid), .ld_address_i(ld_address), .ld_be_i(ld_be),
        .ld_forward_o(ld_forward), .ld_value_o(ld_value), .ld_partial_o(ld_partial),
        .head_valid_o(head_valid), .head_address_o(head_address),
        .head_value_o(head_value), .head_be_o(head_be), .head_written_i(head_written),
        .full_o(full), .empty_o(empty)
    );

    //---------- Functions ----------//
    // Mask of the bits that belong to the enabled byte lanes.
    function automatic logic [DWIDTH-1:0] lane_mask(input logic [BYTES-1:0] be);
        lane_mask = '0;
        for (int b = 0; b < BYTES; b++) lane_mask[b*8 +: 8] = {8{be[b]}};
    endfunction

    // Address of word number n.
    function automatic logic [AWIDTH-1:0] word_addr(input int n);
        return AWIDTH'(n) << 2;
    endfunction

    // Next number of a xorshift32 generator. Fixed seeds make every run repeat exactly.
    function automatic logic [31:0] next_random();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    // Random number in 0 .. n-1.
    function automatic int rand_below(input int n);
        return int'(next_random() % 32'(n));
    endfunction

    // A random legal byte-enable pattern.
    function automatic logic [BYTES-1:0] random_be();
        int idx;
        idx = rand_below(7);
        return LEGAL_BE[idx];
    endfunction

    // A random data word.
    function automatic logic [DWIDTH-1:0] random_value();
        return DWIDTH'(next_random());
    endfunction

    // Expected result of a load search, written without the RTL's age arithmetic:
    // walk the model from the youngest store to the oldest and stop at the first overlap.
    function automatic result_t search(input logic [AWIDTH-1:0] addr, input logic [BYTES-1:0] be,
                                       output logic [DWIDTH-1:0] value);
        value  = '0;
        search = NONE;
        for (int i = int'(model.size()) - 1; i >= 0; i--) begin
            if (model[i].address == addr && (model[i].be & be) != '0) begin
                if ((model[i].be & be) == be) begin
                    value  = model[i].value;
                    return FORWARD;
                end
                return PARTIAL;
            end
        end
    endfunction

    //---------- Check and case tasks ----------//
    task automatic check(input string what, input logic ok);
        checks++;
        if (!ok) begin
            errors++;
            $display("  mismatch: %s (case %s, time %0t)", what, case_name, $time);
        end
    endtask

    task automatic begin_case(input string name);
        case_name   = name;
        case_errors = errors;
    endtask

    task automatic end_case();
        if (errors == case_errors) $display("PASS: %s", case_name);
        else                       $display("FAIL: %s", case_name);
    endtask

    // Compares the RTL's state with the model.
    task automatic check_state();
        check("count matches the model", int'(dut.sb_count) == int'(model.size()));
        check("full flag",       full       === (int'(model.size()) == DEPTH));
        check("empty flag",      empty      === (model.size() == 0));
        check("head_valid flag", head_valid === (model.size() != 0));
        if (model.size() > 0) begin
            check("head address",      head_address === model[0].address);
            check("head value",        head_value   === model[0].value);
            check("head byte enables", head_be      === model[0].be);
        end
    endtask

    // Applies one clock edge to the model, with the SB's own rules: a store is accepted
    // only if the SB is not full before the edge, and only a real head entry is freed.
    task automatic update_model(input logic st, input logic [AWIDTH-1:0] a,
                                input logic [BYTES-1:0] b, input logic [DWIDTH-1:0] v,
                                input logic hw);
        entry_t new_entry;
        logic   allocate;
        logic   free_head;
        allocate  = st && (int'(model.size()) < DEPTH);
        free_head = hw && (model.size() > 0);
        if (st && !allocate) held_stores++;
        if (free_head) begin
            void'(model.pop_front());
            head_writes++;
        end
        if (allocate) begin
            new_entry = '{address: a, be: b, value: v};
            model.push_back(new_entry);
        end
        if (int'(model.size()) > peak) peak = int'(model.size());
    endtask

    // One clock cycle. Inputs are driven just after an edge, the load search is checked
    // before the next edge, and the state is checked just after it.
    task automatic cycle(input logic st, input logic [AWIDTH-1:0] st_a, input logic [BYTES-1:0] st_b,
                         input logic [DWIDTH-1:0] st_v, input logic ld, input logic [AWIDTH-1:0] ld_a,
                         input logic [BYTES-1:0] ld_b, input logic hw);
        result_t           expected;
        logic [DWIDTH-1:0] expected_value;
        st_valid = st;  st_address = st_a;  st_be = st_b;  st_value = st_v;
        ld_valid = ld;  ld_address = ld_a;  ld_be = ld_b;  head_written = hw;
        #1;
        expected = search(ld_a, ld_b, expected_value);
        check("load forward flag", ld_forward === (ld && expected == FORWARD));
        check("load partial flag", ld_partial === (ld && expected == PARTIAL));
        if (ld && expected == FORWARD)
            check("forwarded value", (ld_value & lane_mask(ld_b)) === (expected_value & lane_mask(ld_b)));
        if (ld) begin
            if (expected == FORWARD)      forwards++;
            else if (expected == PARTIAL) partials++;
            else                          no_matches++;
        end
        @(posedge clk);
        update_model(st, st_a, st_b, st_v, hw);
        #1;
        check_state();
    endtask

    task automatic do_idle();
        cycle(1'b0, '0, '0, '0, 1'b0, '0, '0, 1'b0);
    endtask

    task automatic do_store(input logic [AWIDTH-1:0] a, input logic [BYTES-1:0] b, input logic [DWIDTH-1:0] v);
        cycle(1'b1, a, b, v, 1'b0, '0, '0, 1'b0);
    endtask

    task automatic do_load(input logic [AWIDTH-1:0] a, input logic [BYTES-1:0] b);
        cycle(1'b0, '0, '0, '0, 1'b1, a, b, 1'b0);
    endtask

    task automatic do_head();
        cycle(1'b0, '0, '0, '0, 1'b0, '0, '0, 1'b1);
    endtask

    task automatic do_store_and_head(input logic [AWIDTH-1:0] a, input logic [BYTES-1:0] b, input logic [DWIDTH-1:0] v);
        cycle(1'b1, a, b, v, 1'b0, '0, '0, 1'b1);
    endtask

    // A load whose result is also stated by hand: want, and the value on its byte lanes.
    // hw = 1 puts the search on the same edge as a head write.
    task automatic load_expect(input logic [AWIDTH-1:0] a, input logic [BYTES-1:0] b, input result_t want,
                               input logic [DWIDTH-1:0] v, input logic hw);
        st_valid = 1'b0;  ld_valid = 1'b1;  ld_address = a;  ld_be = b;  head_written = hw;
        #1;
        check("expected forward flag", ld_forward === (want == FORWARD));
        check("expected partial flag", ld_partial === (want == PARTIAL));
        if (want == FORWARD) check("expected forwarded value", (ld_value & lane_mask(b)) === (v & lane_mask(b)));
        cycle(1'b0, '0, '0, '0, 1'b1, a, b, hw);
    endtask

    task automatic do_load_expect(input logic [AWIDTH-1:0] a, input logic [BYTES-1:0] b,
                                  input result_t want, input logic [DWIDTH-1:0] v);
        load_expect(a, b, want, v, 1'b0);
    endtask

    // Writes every waiting store to memory, oldest first.
    task automatic drain();
        while (model.size() > 0) do_head();
    endtask

    // Asserts reset between two clock edges, as an asynchronous reset can arrive.
    // hw_on_edge = 1 also raises head_written_i, so reset meets the would-be last head write.
    task automatic reset_between_edges(input logic hw_on_edge);
        st_valid = 1'b0;  ld_valid = 1'b0;  head_written = hw_on_edge;
        #2;
        rst = 1'b1;
        #1;
        check("reset empties the SB at once", empty === 1'b1 && int'(dut.sb_count) == 0);
        check("reset clears the head flag",   head_valid === 1'b0);
        model.delete();
        @(posedge clk);
        #1;
        rst = 1'b0;
        head_written = 1'b0;
        check_state();
    endtask

    // Clears the counters that the random sequence reports.
    task automatic clear_counters();
        forwards = 0;  partials = 0;  no_matches = 0;
        held_stores = 0;  head_writes = 0;  peak = 0;
    endtask

    //---------- The test sequence ----------//
    initial begin
        done = 1'b0;  errors = 0;  checks = 0;  rng = 32'(SEED);
        rst = 1'b1;
        st_valid = 1'b0;  ld_valid = 1'b0;  head_written = 1'b0;
        st_address = '0;  st_value = '0;  st_be = '0;  ld_address = '0;  ld_be = '0;
        clear_counters();
        wait (start);
        $display("---- store buffer, depth %0d ----", DEPTH);
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;
        check_state();

        //--- Trivial ---
        begin_case("T1  one store is allocated, then written to memory");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        check("one store waits", int'(dut.sb_count) == 1 && !empty);
        check("the head is that store", head_address === word_addr(1) && head_value === VALUE_A && head_be === WORD_BE);
        do_head();
        check("empty after the write", empty && int'(dut.sb_count) == 0);
        end_case();

        begin_case("T2  a load with no matching store");
        do_load_expect(word_addr(2), WORD_BE, NONE, '0);
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_load_expect(word_addr(2), WORD_BE, NONE, '0);
        drain();
        end_case();

        begin_case("T3  sw then lw to the same word forwards while the store is queued");
        do_store(word_addr(3), WORD_BE, VALUE_A);
        do_load_expect(word_addr(3), WORD_BE, FORWARD, VALUE_A);
        check("the store is still waiting for memory", !empty);
        drain();
        end_case();

        //--- Corner ---
        begin_case("C1  fill to the depth, hold a store while full, then accept it once");
        for (int i = 0; i < DEPTH; i++) do_store(word_addr(i), WORD_BE, 32'(1000 + i));
        check("the SB is full", full === 1'b1 && int'(dut.sb_count) == DEPTH);
        repeat (3) do_store(word_addr(20), WORD_BE, VALUE_B);
        check("a held store changes nothing", int'(dut.sb_count) == DEPTH && head_value === 32'(1000));
        do_load_expect(word_addr(20), WORD_BE, NONE, '0);
        do_store_and_head(word_addr(20), WORD_BE, VALUE_B);
        check("the store arriving with a head write is still held", int'(dut.sb_count) == DEPTH - 1);
        do_store(word_addr(20), WORD_BE, VALUE_B);
        check("the store is accepted once", int'(dut.sb_count) == DEPTH);
        do_load_expect(word_addr(20), WORD_BE, FORWARD, VALUE_B);
        drain();
        end_case();

        begin_case("C2  empty after the last head write");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_store(word_addr(2), WORD_BE, VALUE_B);
        do_head();
        check("one store still waits", !empty);
        do_head();
        check("empty after the last head write", empty === 1'b1 && head_valid === 1'b0 && int'(dut.sb_count) == 0);
        end_case();

        begin_case("C3  store allocate and head free in the same cycle");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_store_and_head(word_addr(2), WORD_BE, VALUE_B);
        check("the count is unchanged", int'(dut.sb_count) == 1);
        check("the new store is now the head", head_address === word_addr(2) && head_value === VALUE_B);
        drain();
        end_case();

        begin_case("C4  pointer wrap: head-write order and the youngest match across the wrap");
        begin
            int moved;   // stores that have gone through the SB, so the pointers sit at moved mod DEPTH
            moved = 0;
            for (int k = 0; k < 2 * DEPTH + 3; k++) begin
                do_store(word_addr(k % 3), WORD_BE, 32'(2000 + k));
                check("head is the store just written", head_value === 32'(2000 + k));
                do_head();
                moved++;
            end
            // Move both pointers to the last slot, then store the same word twice across the wrap.
            while (moved % DEPTH != DEPTH - 1) begin
                do_store(word_addr(5), WORD_BE, 32'(3000 + moved));
                do_head();
                moved++;
            end
        end
        do_store(word_addr(7), WORD_BE, 32'hAAAA_0001);
        do_store(word_addr(7), WORD_BE, 32'hBBBB_0002);
        do_load_expect(word_addr(7), WORD_BE, FORWARD, 32'hBBBB_0002);
        drain();
        end_case();

        begin_case("C5  two stores to one word: the youngest wins");
        do_store(word_addr(4), WORD_BE, 32'h0bad_f00d);
        do_store(word_addr(4), WORD_BE, 32'h600d_cafe);
        do_load_expect(word_addr(4), WORD_BE, FORWARD, 32'h600d_cafe);
        drain();
        end_case();

        begin_case("C6  every store size and lane against every load size and lane");
        // Hand-written cases first: sign and zero extension bytes are 0x80 and 0xff.
        do_store(word_addr(1), 4'b0001, 32'h0000_00aa);
        do_load_expect(word_addr(1), 4'b0001, FORWARD, 32'h0000_00aa);      // sb then lb, same lane
        drain();
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_load_expect(word_addr(1), 4'b0100, FORWARD, VALUE_A);            // sw then lb of lane 2 (0xff)
        do_load_expect(word_addr(1), 4'b1000, FORWARD, VALUE_A);            // sw then lb of lane 3 (0x80)
        do_load_expect(word_addr(1), 4'b1100, FORWARD, VALUE_A);            // sw then lh of the high half
        drain();
        do_store(word_addr(1), 4'b0010, 32'h0000_5500);
        do_load_expect(word_addr(1), WORD_BE, PARTIAL, '0);                 // sb inside the word, then lw
        do_load_expect(word_addr(1), 4'b0100, NONE, '0);                    // sb lane 1, then lb of lane 2
        drain();
        do_store(word_addr(1), 4'b1100, 32'h80ff_0000);
        do_load_expect(word_addr(1), 4'b0011, NONE, '0);                    // sh high half, then lh low half
        do_load_expect(word_addr(1), 4'b1100, FORWARD, 32'h80ff_0000);      // same half
        do_load_expect(word_addr(1), 4'b1000, FORWARD, 32'h80ff_0000);      // lb inside the half
        do_load_expect(word_addr(1), 4'b0110, PARTIAL, '0);                 // crosses the half boundary
        drain();
        // All 7 x 7 combinations. The expected result comes from the byte overlap alone.
        for (int s = 0; s < 7; s++) begin
            for (int l = 0; l < 7; l++) begin
                logic [DWIDTH-1:0] v;
                logic [BYTES-1:0]  overlap;
                v       = VALUE_A + 32'(s * 7 + l);
                overlap = LEGAL_BE[s] & LEGAL_BE[l];
                do_store(word_addr(1), LEGAL_BE[s], v);
                if (overlap == LEGAL_BE[l])    do_load_expect(word_addr(1), LEGAL_BE[l], FORWARD, v);
                else if (overlap == '0)        do_load_expect(word_addr(1), LEGAL_BE[l], NONE, '0);
                else                           do_load_expect(word_addr(1), LEGAL_BE[l], PARTIAL, '0);
                drain();
            end
        end
        end_case();

        begin_case("C7  a younger store over an older store");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_store(word_addr(1), 4'b0010, 32'h0000_9900);                     // disjoint from lane 2
        do_load_expect(word_addr(1), 4'b0100, FORWARD, VALUE_A);            // the older store still forwards
        do_load_expect(word_addr(1), WORD_BE, PARTIAL, '0);                 // the younger one covers only lane 1
        drain();
        end_case();

        begin_case("C8  different words with the same low address bits");
        do_store(32'h0001_0010, WORD_BE, VALUE_A);
        do_load_expect(32'h0002_0010, WORD_BE, NONE, '0);
        do_load_expect(32'h0001_0010, WORD_BE, FORWARD, VALUE_A);
        drain();
        end_case();

        begin_case("C9  a search on the edge of the head write that frees the store");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        load_expect(word_addr(1), WORD_BE, FORWARD, VALUE_A, 1'b1);         // still there before the edge
        do_load_expect(word_addr(1), WORD_BE, NONE, '0);                    // gone after it
        do_store(word_addr(2), 4'b0010, 32'h0000_5500);
        load_expect(word_addr(2), WORD_BE, PARTIAL, '0, 1'b1);              // partial before the edge
        do_load_expect(word_addr(2), WORD_BE, NONE, '0);
        end_case();

        //--- Invalid ---
`ifndef SB_SKIP_ILLEGAL
        // I1, I2 and I4 break the SB's protocol assertions on purpose. Build with --assert and
        // -DSB_SKIP_ILLEGAL to run everything else with the assertions armed.
        begin_case("I1  head_written_i while empty is ignored");
        do_head();
        check("still empty, the count did not underflow", empty === 1'b1 && int'(dut.sb_count) == 0);
        do_store(word_addr(1), WORD_BE, VALUE_A);
        do_load_expect(word_addr(1), WORD_BE, FORWARD, VALUE_A);
        drain();
        end_case();

        begin_case("I2  a store with no byte enable never matches a load");
        do_store(word_addr(1), '0, VALUE_A);
        do_load_expect(word_addr(1), WORD_BE, NONE, '0);
        do_load_expect(word_addr(1), 4'b0001, NONE, '0);
        drain();
        end_case();
        // Memory acknowledges a head write while reset is asserted: also against the protocol.
        begin_case("I4  reset on the edge of the would-be final head write");
        do_store(word_addr(1), WORD_BE, VALUE_A);
        reset_between_edges(1'b1);
        do_load_expect(word_addr(1), WORD_BE, NONE, '0);
        check("no stale entry after reset", empty === 1'b1 && int'(dut.sb_count) == 0);
        end_case();

`endif

        begin_case("I3  reset in the middle of a burst");
        for (int i = 0; i < DEPTH - 1; i++) do_store(word_addr(i), WORD_BE, 32'(4000 + i));
        reset_between_edges(1'b0);
        do_load_expect(word_addr(0), WORD_BE, NONE, '0);
        do_store(word_addr(0), WORD_BE, VALUE_B);
        do_load_expect(word_addr(0), WORD_BE, FORWARD, VALUE_B);
        drain();
        end_case();

        //--- Non-trivial sequences ---
        begin_case("S1  seeded random run against the model");
        clear_counters();
        repeat (RANDOM_CYCLES) begin
            int                kind;
            logic [AWIDTH-1:0] a;
            logic [BYTES-1:0]  b;
            logic [DWIDTH-1:0] v;
            logic              hw;
            kind = rand_below(100);
            a    = word_addr(rand_below(4));
            b    = random_be();
            v    = random_value();
            hw   = (model.size() > 0) && (rand_below(100) < 30);
            if (kind < 45)      cycle(1'b1, a, b, v, 1'b0, '0, '0, hw);
            else if (kind < 80) cycle(1'b0, '0, '0, '0, 1'b1, a, b, hw);
            else                cycle(1'b0, '0, '0, '0, 1'b0, '0, '0, hw);
        end
        check("the random run forwarded loads",         forwards > 0);
        check("the random run met partial matches",     partials > 0);
        check("the random run met loads with no match", no_matches > 0);
        check("the random run held stores while full",  held_stores > 0);
        check("the random run filled the SB",           peak == DEPTH);
        $display("  random run: seed %0d, %0d cycles, %0d forwards, %0d partial, %0d no match, %0d held stores, %0d head writes, peak %0d",
                 SEED, RANDOM_CYCLES, forwards, partials, no_matches, held_stores, head_writes, peak);
        drain();
        end_case();

        begin_case("S2  a burst longer than the depth, back to back");
        for (int k = 0; k < DEPTH + 5; k++) begin
            logic accepted;
            int   tries;
            accepted = 1'b0;
            tries    = 0;
            while (!accepted) begin
                accepted = (int'(model.size()) < DEPTH);
                cycle(1'b1, word_addr(k), WORD_BE, 32'(5000 + k), 1'b0, '0, '0, (tries % 3 == 2) && (model.size() > 0));
                tries++;
            end
        end
        // Loads of the burst's words: the model decides which are forwarded and which read memory.
        for (int k = 0; k < DEPTH + 5; k++) do_load(word_addr(k), WORD_BE);
        drain();
        end_case();

        begin_case("S3  repeated fill and drain");
        repeat (20) begin
            for (int i = 0; i < DEPTH; i++) do_store(word_addr(rand_below(6)), random_be(), random_value());
            check("full after DEPTH stores", full === 1'b1);
            while (model.size() > 0) begin
                cycle(1'b0, '0, '0, '0, 1'b1, word_addr(rand_below(6)), random_be(), 1'b1);
            end
            check("empty after the drain", empty === 1'b1);
        end
        end_case();

        do_idle();   // stop driving the last cycle's inputs while the other depths run
        $display("  depth %0d: %0d checks, %0d errors", DEPTH, checks, errors);
        done = 1'b1;
    end

endmodule : sb_test

// Runs the suite at four depths, one after the other, and prints the overall result.
module tb_store_buffer;

    localparam int HALF_CYCLE = 5;          // half the clock period, in ns
    localparam int WATCHDOG   = 50_000_000; // bounded run time, in ns

    logic       clk = 1'b0;                 // clock
    logic [3:0] start = '0;                 // start of the run for depth 2, 4, 8 and 16
    logic [3:0] done;                       // end of the run for depth 2, 4, 8 and 16
    int         errors_2, errors_4, errors_8, errors_16;   // failed checks at each depth

    always #HALF_CYCLE clk = ~clk;

    sb_test #(.DEPTH(2),  .SEED(11)) run_2  (.clk(clk), .start(start[0]), .done(done[0]), .errors(errors_2));
    sb_test #(.DEPTH(4),  .SEED(22)) run_4  (.clk(clk), .start(start[1]), .done(done[1]), .errors(errors_4));
    sb_test #(.DEPTH(8),  .SEED(33)) run_8  (.clk(clk), .start(start[2]), .done(done[2]), .errors(errors_8));
    sb_test #(.DEPTH(16), .SEED(44)) run_16 (.clk(clk), .start(start[3]), .done(done[3]), .errors(errors_16));

    initial begin
        start[0] = 1'b1;  wait (done[0]);
        start[1] = 1'b1;  wait (done[1]);
        start[2] = 1'b1;  wait (done[2]);
        start[3] = 1'b1;  wait (done[3]);
        $display("Errors at depth 2, 4, 8, 16: %0d, %0d, %0d, %0d", errors_2, errors_4, errors_8, errors_16);
        if (errors_2 + errors_4 + errors_8 + errors_16 == 0) begin
            $display("Test Passed");
            $finish;
        end else begin
            $display("Test Failed");
            $fatal(1, "tb_store_buffer: check(s) failed");
        end
    end

    // Stops a run that never finishes.
    initial begin
        #WATCHDOG;
        $display("Simulation TIMEOUT");
        $fatal(1, "tb_store_buffer: watchdog expired");
    end

endmodule : tb_store_buffer
