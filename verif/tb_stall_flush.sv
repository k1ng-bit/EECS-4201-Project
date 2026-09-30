/*
 * Testbench: tb_stall_flush
 *
 * Description:
 * Standalone unit testbench for stall_flush_logic.
 *
 * Tests:
 * 1. Normal instruction flow
 * 2. Load-use hazard
 * 3. RAW hazard from EX
 * 4. RAW hazard from MEM
 * 5. Taken branch
 * 6. Branch not taken
 * 7. x0 false hazard
 * 8. Simultaneous load hazard and taken branch
 */

module tb_stall_flush;

    // ID stage inputs
    logic [4:0] id_rs1_i;
    logic [4:0] id_rs2_i;
    logic       id_rs1_valid_i;
    logic       id_rs2_valid_i;

    // EX stage inputs
    logic [4:0] ex_rd_i;
    logic       ex_regwren_i;
    logic       ex_memren_i;
    logic       ex_brtaken_i;
    logic       ex_is_jump_i;

    // MEM stage inputs
    logic [4:0] mem_rd_i;
    logic       mem_regwren_i;
    logic       mem_memren_i;

    // Outputs from stall/flush logic
    logic       pc_en_o;
    logic       if_id_stall_o;
    logic       if_id_flush_o;
    logic       id_ex_flush_o;
    logic       ex_mem_flush_o;

    // Device Under Test
    stall_flush_logic dut (
        .id_rs1_i(id_rs1_i),
        .id_rs2_i(id_rs2_i),
        .id_rs1_valid_i(id_rs1_valid_i),
        .id_rs2_valid_i(id_rs2_valid_i),

        .ex_rd_i(ex_rd_i),
        .ex_regwren_i(ex_regwren_i),
        .ex_memren_i(ex_memren_i),
        .ex_brtaken_i(ex_brtaken_i),
        .ex_is_jump_i(ex_is_jump_i),

        .mem_rd_i(mem_rd_i),
        .mem_regwren_i(mem_regwren_i),
        .mem_memren_i(mem_memren_i),

        .pc_en_o(pc_en_o),
        .if_id_stall_o(if_id_stall_o),
        .if_id_flush_o(if_id_flush_o),
        .id_ex_flush_o(id_ex_flush_o),
        .ex_mem_flush_o(ex_mem_flush_o)
    );

    // Check all output signals against expected values
    task automatic check_outputs(
        input logic expected_pc_en,
        input logic expected_if_id_stall,
        input logic expected_if_id_flush,
        input logic expected_id_ex_flush,
        input logic expected_ex_mem_flush
    );
        begin
            #1;

            if ((pc_en_o !== expected_pc_en) ||
                (if_id_stall_o !== expected_if_id_stall) ||
                (if_id_flush_o !== expected_if_id_flush) ||
                (id_ex_flush_o !== expected_id_ex_flush) ||
                (ex_mem_flush_o !== expected_ex_mem_flush)) begin

                $display("FAIL");

                $display(
                    "Expected: PC=%0b IFID_STALL=%0b IFID_FLUSH=%0b ID_EX_FLUSH=%0b EX_MEM_FLUSH=%0b",
                    expected_pc_en,
                    expected_if_id_stall,
                    expected_if_id_flush,
                    expected_id_ex_flush,
                    expected_ex_mem_flush
                );

                $display(
                    "Actual:   PC=%0b IFID_STALL=%0b IFID_FLUSH=%0b ID_EX_FLUSH=%0b EX_MEM_FLUSH=%0b",
                    pc_en_o,
                    if_id_stall_o,
                    if_id_flush_o,
                    id_ex_flush_o,
                    ex_mem_flush_o
                );

                $fatal(1);
            end
        end
    endtask

    initial begin

        // ---------------------------------------------------------
        // Initialize all inputs
        // ---------------------------------------------------------

        id_rs1_i = 5'd0;
        id_rs2_i = 5'd0;
        id_rs1_valid_i = 1'b0;
        id_rs2_valid_i = 1'b0;

        ex_rd_i = 5'd0;
        ex_regwren_i = 1'b0;
        ex_memren_i = 1'b0;
        ex_brtaken_i = 1'b0;
        ex_is_jump_i = 1'b0;

        mem_rd_i = 5'd0;
        mem_regwren_i = 1'b0;
        mem_memren_i = 1'b0;

        #1;

        // ---------------------------------------------------------
        // TEST 1: Normal instruction flow
        // ---------------------------------------------------------

        $display("TEST 1: Normal instruction flow");

        check_outputs(
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );

        $display("TEST 1 PASS");


        // ---------------------------------------------------------
        // TEST 2: Load-use hazard
        // ---------------------------------------------------------

        $display("TEST 2: Load-use hazard");

        id_rs1_i = 5'd5;
        id_rs1_valid_i = 1'b1;

        ex_rd_i = 5'd5;
        ex_regwren_i = 1'b1;
        ex_memren_i = 1'b1;

        check_outputs(
            1'b0,
            1'b1,
            1'b0,
            1'b1,
            1'b0
        );

        $display("TEST 2 PASS");


        // ---------------------------------------------------------
        // TEST 3: RAW hazard from EX
        // ---------------------------------------------------------

        $display("TEST 3: RAW hazard from EX");

        ex_memren_i = 1'b0;
        ex_regwren_i = 1'b1;
        ex_rd_i = 5'd10;

        id_rs1_i = 5'd10;
        id_rs1_valid_i = 1'b1;

        check_outputs(
            1'b0,
            1'b1,
            1'b0,
            1'b1,
            1'b0
        );

        $display("TEST 3 PASS");


        // ---------------------------------------------------------
        // TEST 4: RAW hazard from MEM
        // ---------------------------------------------------------

        $display("TEST 4: RAW hazard from MEM");

        ex_regwren_i = 1'b0;
        ex_rd_i = 5'd0;

        mem_rd_i = 5'd11;
        mem_regwren_i = 1'b1;

        id_rs1_i = 5'd11;
        id_rs1_valid_i = 1'b1;

        check_outputs(
            1'b0,
            1'b1,
            1'b0,
            1'b1,
            1'b0
        );

        $display("TEST 4 PASS");


        // ---------------------------------------------------------
        // TEST 5: Taken branch
        // ---------------------------------------------------------

        $display("TEST 5: Taken branch");

        id_rs1_i = 5'd0;
        id_rs1_valid_i = 1'b0;

        mem_rd_i = 5'd0;
        mem_regwren_i = 1'b0;

        ex_brtaken_i = 1'b1;

        check_outputs(
            1'b1,
            1'b0,
            1'b1,
            1'b1,
            1'b0
        );

        $display("TEST 5 PASS");


        // ---------------------------------------------------------
        // TEST 6: Branch not taken
        // ---------------------------------------------------------

        $display("TEST 6: Branch not taken");

        ex_brtaken_i = 1'b0;
        ex_is_jump_i = 1'b0;

        check_outputs(
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );

        $display("TEST 6 PASS");


        // ---------------------------------------------------------
        // TEST 7: x0 false hazard
        // ---------------------------------------------------------

        $display("TEST 7: x0 false hazard");

        id_rs1_i = 5'd0;
        id_rs1_valid_i = 1'b1;

        ex_rd_i = 5'd0;
        ex_regwren_i = 1'b1;
        ex_memren_i = 1'b1;

        check_outputs(
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );

        $display("TEST 7 PASS");


        // ---------------------------------------------------------
        // TEST 8: Load hazard + taken branch
        // ---------------------------------------------------------

        $display("TEST 8: Load hazard + taken branch");

        id_rs1_i = 5'd7;
        id_rs1_valid_i = 1'b1;

        ex_rd_i = 5'd7;
        ex_regwren_i = 1'b1;
        ex_memren_i = 1'b1;
        ex_brtaken_i = 1'b1;

        check_outputs(
            1'b1,
            1'b0,
            1'b1,
            1'b1,
            1'b0
        );

        $display("TEST 8 PASS");


        // ---------------------------------------------------------
        // All tests passed
        // ---------------------------------------------------------

        $display("");
        $display("======================================");
        $display("ALL STALL/FLUSH TESTS PASSED");
        $display("======================================");

        $finish;

    end

endmodule
