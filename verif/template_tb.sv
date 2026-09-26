`include "constants.svh"
`include "execute.sv" // required for this testbench example

`timescale 1ns/1ps

`ifndef TIMEOUT
  `define TIMEOUT 32'd50
`endif

`ifndef RESET_CYCLES
  `define RESET_CYCLES 2
`endif

module template_tb;

   logic clk = 0;
   logic rst = 1;
   always #1 clk = ~clk;

   localparam int DWIDTH = 32;
   localparam int AWIDTH = 32;

   /* 
    * Instantiate your DUT/HUT (device/hardware under test)
    * This could be the whole design (top module), or a stage/module/sub-module of your design.
    * To help isolate functionality issues, instantiate and test each module separately.
    */

    /*
     * In the following sequential block include logic to test parts of or the whole device.
     * Some ideas:
     *  * Test for program completion and that a specific value has been written to a specific register.
        * Test on each cycle that certain signals match expected values (C1: f_pc == BASE_ADDR, C2: f_pc == BASE_ADDR + 32'd4...etc)
        * Test functionality: i.e., are you jumping/branching when you are expecting to, are you writing to the correct address (or byte of that address) in memory.
        * Test edge cases for branching, jumping, arithmetic, etc.
     * Below is ONE EXAMPLE of a test bench that is testing an arithmetic edge case.
     * This is just a skeleton to get you started and to give you some ideas, it is by no means exhaustive.
     */
    
    // Some signals for this testbench.
    logic [DWIDTH-1:0] rs1, rs2, result;
    logic [6:0]        opcode;
    logic [3:0]        alusel;

    // Only testing R-Type Arithmetic
    assign opcode = `R_TYPE;

    alu #(
        .DWIDTH(DWIDTH),
        .AWIDTH(AWIDTH)
    ) hut (
        .pc_i(),
        .rs1_i(rs1),
        .rs2_i(rs2),
        .funct3_i(),
        .funct7_i(),
        .opcode_i(opcode),
        .imm_i(),
        .alusel_i(alusel),
        .res_o(result),
        .brtaken_o()
    );

    // int number_of_tests = 10;
    // int test_counter = 0; 
    
    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         alusel <= '0;
    //         rs1 <= '0;
    //         rs2 <= '0;
    //         test_counter <= 0;
    //     end
    //     else if (test_counter < number_of_tests) begin
    //         alusel <= 4'($urandom_range(9, 0));
    //         rs1 <= $urandom();
    //         rs2 <= $urandom();
    //         test_counter <= test_counter + 1;
    //     end
    //     else begin
    //         $display("=========================================");
    //         $display("Completed %0d Tests. Simulation Complete!", number_of_tests);
    //         $display("=========================================");
    //         $finish;
    //     end
    // end

    initial begin
    // Start with known input values.
    rs1 = 32'd0;
    rs2 = 32'd0;
    alusel = `ALU_ADD;

    // Wait for the template's reset period to finish.
    wait (rst == 1'b0);

    // --- ADDITION & SUBTRACTION ---
    // TEST 1: Addition: 5 + 7 = 12
    @(negedge clk); rs1 = 32'd5; rs2 = 32'd7; alusel = `ALU_ADD;
    @(posedge clk); if (result !== 32'd12) $fatal(1, "ADD failed: expected 12, got %h", result); else $display("PASS: ADD 5 + 7 = 12");

    // TEST 2: Subtraction: 9 - 4 = 5
    @(negedge clk); rs1 = 32'd9; rs2 = 32'd4; alusel = `ALU_SUB;
    @(posedge clk); if (result !== 32'd5) $fatal(1, "SUB failed: expected 5, got %h", result); else $display("PASS: SUB 9 - 4 = 5");

    // TEST 3: ADD wraparound (FFFFFFFF + 1 = 0)
    @(negedge clk); rs1 = 32'hFFFFFFFF; rs2 = 32'd1; alusel = `ALU_ADD;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "ADD wraparound failed: expected 0, got %h", result); else $display("PASS: ADD wraparound");

    // TEST 4: SUB underflow (0 - 1 = FFFFFFFF)
    @(negedge clk); rs1 = 32'd0; rs2 = 32'd1; alusel = `ALU_SUB;
    @(posedge clk); if (result !== 32'hFFFFFFFF) $fatal(1, "SUB underflow failed: expected FFFFFFFF, got %h", result); else $display("PASS: SUB underflow");

    // --- BITWISE OPERATIONS ---
    // TEST 5: AND (AAAAAAAA & 55555555 = 0)
    @(negedge clk); rs1 = 32'hAAAAAAAA; rs2 = 32'h55555555; alusel = `ALU_AND;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "AND failed: expected 0, got %h", result); else $display("PASS: AND checkerboard");

    // TEST 6: OR (AAAAAAAA | 55555555 = FFFFFFFF)
    @(negedge clk); rs1 = 32'hAAAAAAAA; rs2 = 32'h55555555; alusel = `ALU_OR;
    @(posedge clk); if (result !== 32'hFFFFFFFF) $fatal(1, "OR failed: expected FFFFFFFF, got %h", result); else $display("PASS: OR checkerboard");

    // TEST 7: XOR (FFFFFFFF ^ FFFFFFFF = 0)
    @(negedge clk); rs1 = 32'hFFFFFFFF; rs2 = 32'hFFFFFFFF; alusel = `ALU_XOR;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "XOR failed: expected 0, got %h", result); else $display("PASS: XOR same value");

    // --- LOGICAL SHIFTS ---
    // TEST 8: SLL (1 << 31 = 80000000)
    @(negedge clk); rs1 = 32'd1; rs2 = 32'd31; alusel = `ALU_SLL;
    @(posedge clk); if (result !== 32'h80000000) $fatal(1, "SLL failed: expected 80000000, got %h", result); else $display("PASS: SLL by 31");

    // TEST 9: SRL (80000000 >> 31 = 1)
    @(negedge clk); rs1 = 32'h80000000; rs2 = 32'd31; alusel = `ALU_SRL;
    @(posedge clk); if (result !== 32'd1) $fatal(1, "SRL failed: expected 1, got %h", result); else $display("PASS: SRL by 31");

    // TEST 10: SRL over shift amount (shift by 32+n only takes lower 5 bits of rs2)
    // 0xFFFFFFFF >> 4 (represented as 36 in rs2) = 0x0FFFFFFF
    @(negedge clk); rs1 = 32'hFFFFFFFF; rs2 = 32'd36; alusel = `ALU_SRL;
    @(posedge clk); if (result !== 32'h0FFFFFFF) $fatal(1, "SRL over-shift failed: expected 0FFFFFFF, got %h", result); else $display("PASS: SRL ignores upper bits of rs2");

    // --- ARITHMETIC SHIFTS ---
    // TEST 11: SRA (80000000 >>> 31 = FFFFFFFF)
    @(negedge clk); rs1 = 32'h80000000; rs2 = 32'd31; alusel = `ALU_SRA;
    @(posedge clk); if (result !== 32'hFFFFFFFF) $fatal(1, "SRA negative failed: expected FFFFFFFF, got %h", result); else $display("PASS: SRA negative sign extension");

    // TEST 12: SRA (7FFFFFFF >>> 4 = 07FFFFFF)
    @(negedge clk); rs1 = 32'h7FFFFFFF; rs2 = 32'd4; alusel = `ALU_SRA;
    @(posedge clk); if (result !== 32'h07FFFFFF) $fatal(1, "SRA positive failed: expected 07FFFFFF, got %h", result); else $display("PASS: SRA positive sign extension");

    // --- SET LESS THAN (SIGNED) ---
    // TEST 13: SLT ( -1 < 0 -> FFFFFFFF < 0 -> 1 )
    @(negedge clk); rs1 = 32'hFFFFFFFF; rs2 = 32'd0; alusel = `ALU_SLT;
    @(posedge clk); if (result !== 32'd1) $fatal(1, "SLT (-1 < 0) failed: expected 1, got %h", result); else $display("PASS: SLT (-1 < 0)");

    // TEST 14: SLT ( 0 < -1 -> 0 < FFFFFFFF -> 0 )
    @(negedge clk); rs1 = 32'd0; rs2 = 32'hFFFFFFFF; alusel = `ALU_SLT;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "SLT (0 < -1) failed: expected 0, got %h", result); else $display("PASS: SLT (0 < -1)");

    // TEST 15: SLT ( 7FFFFFFF < 80000000 -> positive < negative -> 0 )
    @(negedge clk); rs1 = 32'h7FFFFFFF; rs2 = 32'h80000000; alusel = `ALU_SLT;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "SLT (pos < neg) failed: expected 0, got %h", result); else $display("PASS: SLT (pos < neg)");

    // TEST 16: SLT ( 80000000 < 7FFFFFFF -> negative < positive -> 1 )
    @(negedge clk); rs1 = 32'h80000000; rs2 = 32'h7FFFFFFF; alusel = `ALU_SLT;
    @(posedge clk); if (result !== 32'd1) $fatal(1, "SLT (neg < pos) failed: expected 1, got %h", result); else $display("PASS: SLT (neg < pos)");

    // --- SET LESS THAN (UNSIGNED) ---
    // TEST 17: SLTU ( FFFFFFFF < 0 -> 0 )
    @(negedge clk); rs1 = 32'hFFFFFFFF; rs2 = 32'd0; alusel = `ALU_SLTU;
    @(posedge clk); if (result !== 32'd0) $fatal(1, "SLTU (FFFFFFFF < 0) failed: expected 0, got %h", result); else $display("PASS: SLTU (FFFFFFFF < 0)");

    // TEST 18: SLTU ( 0 < FFFFFFFF -> 1 )
    @(negedge clk); rs1 = 32'd0; rs2 = 32'hFFFFFFFF; alusel = `ALU_SLTU;
    @(posedge clk); if (result !== 32'd1) $fatal(1, "SLTU (0 < FFFFFFFF) failed: expected 1, got %h", result); else $display("PASS: SLTU (0 < FFFFFFFF)");

    // TEST 19: SLTU ( 7FFFFFFF < 80000000 -> 1 )
    @(negedge clk); rs1 = 32'h7FFFFFFF; rs2 = 32'h80000000; alusel = `ALU_SLTU;
    @(posedge clk); if (result !== 32'd1) $fatal(1, "SLTU (7FFFFFFF < 80000000) failed: expected 1, got %h", result); else $display("PASS: SLTU (7FFFFFFF < 80000000)");

    $display("All 19 ALU checks passed.");
    $finish;
end

    /* 
     * This block is to stop infinite loops, if you you see "SIMULATION TIMEOUT" it means either:
     *      1) The number of cycles before timeout is too few to capture the full length of your program.
     *      2) There is a flaw in your logic or execution causing an infinite loop. [THIS IS MOST LIKELY]
     */
    integer counter = 0;
    always_ff @(posedge clk) begin
        counter <= counter + 1;
        if (counter < `RESET_CYCLES) begin
            rst <= 1;
        end else begin
            rst <= 0;
        end
        if (counter >= `TIMEOUT) begin
            $display("========== Simulation TIMEOUT!!! ==========");
            $finish;
        end
    end

    // Dump commands to produce waveform files.
    initial begin
      $dumpfile("template_tb.vcd");
      $dumpvars(0, template_tb);
      $system("date");
   end

    /*
     * Failing your own tests is a normal part of design and verification.
     * Learn to read waveforms, it helps, not only in determining functional correctness but also TIMING!!!
     * Provided for you in wf_signals are a few template files of preloaded signals to help get you started.
     * Sometimes you will need to compare an execution diagram to your waveforms, you might have the correct values but at the wrong time.
     * Plan and think about what should happen with your design, write pseudo code for your test bench, and learn to translate it to HDL.
     * Learning to do this is a skill that requires practice that will go a long way to help you with this project (especially as your design becomes more complex).
     */

endmodule : template_tb