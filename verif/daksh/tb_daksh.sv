`timescale 1ns/1ps
module tb_daksh;
    logic clk = 0;
    logic reset = 1;
    int cycles = 0;
    string test_name;

    rv_core hut (.clk(clk), .reset(reset));

    // Simulation clock: ten time units per cycle.
    always #5 clk = ~clk;

    // Observe after rising-edge register updates have completed.
    task automatic step_cycle();
        @(negedge clk);
        cycles++;
    endtask

    // Stop simulation immediately when a register is incorrect.
    task automatic check_reg_val(input int reg_id, input logic [31:0] expected);
        if (hut.register_file1.x[reg_id] !== expected)
            $fatal(1, "x%0d: got %08x, expected %08x", reg_id,
                   hut.register_file1.x[reg_id], expected);
    endtask

    // Enabled by Verilator's --assert option.
    a_x0: assert property (@(posedge clk) disable iff (reset)
        hut.register_file1.x[0] == 32'b0)
        else $fatal(1, "x0 changed");

    initial begin
        if (!$value$plusargs("TEST=%s", test_name))
            $fatal(1, "Missing +TEST");

        repeat (3) step_cycle();
        reset = 0;
        cycles = 0;

        // x31 is written by the program only on completion.
        while (hut.register_file1.x[31] == 0 && cycles < 3000)
            step_cycle();

        if (cycles >= 3000) $fatal(1, "Test timed out");

        check_reg_val(31, 1);
        check_reg_val(0, 0);

        case (test_name)
            "load_use": begin
                check_reg_val(5, 41); check_reg_val(6, 48);
                check_reg_val(8, 32'hfffffffd); check_reg_val(9, 45);
            end
            "raw_distance": begin
                check_reg_val(6, 11); check_reg_val(8, 22);
                check_reg_val(10, 33); check_reg_val(12, 44);
                check_reg_val(14, 8);
            end
            "branch_delay": begin
                check_reg_val(8, 0); check_reg_val(20, 0);
                check_reg_val(21, 7); check_reg_val(22, 9);
                check_reg_val(23, 0);
            end
            "jalr_flush": begin
                check_reg_val(9, 0); check_reg_val(20, 0);
            end
            "x0_hazard": begin
                check_reg_val(5, 7); check_reg_val(6, 9);
                check_reg_val(7, 11); check_reg_val(8, 17);
                check_reg_val(9, 8);
            end
            default: $fatal(1, "Unknown test name");
        endcase

        $display("daksh_pass %s cycles=%0d", test_name, cycles);
        $finish;
    end
endmodule
