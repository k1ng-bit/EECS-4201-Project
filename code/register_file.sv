/*
 * Module: register_file
 *
 * Description: 32-entry x DWIDTH-bit register file with two combinational
 *              read ports (rs1, rs2) and one sequential write port (rd).
 *              Register x0 is hardwired to zero and cannot be written.
 *              Stack pointer (x2) is initialized to the top of memory.
 *
 * Inputs:
 *   1) clk       - Clock signal
 *   2) rst       - Asynchronous active-high reset
 *   3) rs1_i     - 5-bit source register 1 address (read port A)
 *   4) rs2_i     - 5-bit source register 2 address (read port B)
 *   5) rd_i      - 5-bit destination register address (write port)
 *   6) datawb_i  - DWIDTH-wide writeback data
 *   7) regwren_i - Write enable (from WB stage)
 *
 * Outputs:
 *   1) rs1data_o - DWIDTH-wide read data for rs1
 *   2) rs2data_o - DWIDTH-wide read data for rs2
 */

`include "constants.svh"

module register_file #(
    parameter int DWIDTH = 32
)(
    input  logic              clk,
    input  logic              rst,
    input  logic [4:0]        rs1_i,
    input  logic [4:0]        rs2_i,
    input  logic [4:0]        rd_i,
    input  logic [DWIDTH-1:0] datawb_i,
    input  logic              regwren_i,
    output logic [DWIDTH-1:0] rs1data_o,
    output logic [DWIDTH-1:0] rs2data_o
);

    // 32-entry register array, each DWIDTH bits wide
    logic [DWIDTH-1:0] x [31:0];

    // Sequential write with asynchronous reset
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) x[i] <= '0;
            x[2] <= 32'h01100000;  // Initialize stack pointer (sp)
        end else if (regwren_i && rd_i != 5'd0) begin
            x[rd_i] <= datawb_i;   // Write to rd, guard x0
        end
    end

    // Write first reads, ID sees a matching WB value before ID/EX captures it.
    // Writes to x0 never bypass, reads of x0 always return zero.
    logic wb_write_valid;
    assign wb_write_valid = !rst && regwren_i && (rd_i != 5'd0);

    assign rs1data_o = (rs1_i == 5'd0) ? '0 : ((wb_write_valid && (rd_i == rs1_i)) ? datawb_i : x[rs1_i]);
    assign rs2data_o = (rs2_i == 5'd0) ? '0 : ((wb_write_valid && (rd_i == rs2_i)) ? datawb_i : x[rs2_i]);

endmodule : register_file
