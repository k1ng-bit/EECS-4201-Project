/*
 * Module: register_file
 *
 * Description: NUM_REGS x DWIDTH register file with two combinational read
 *              ports (rs1, rs2) and one write port (rd), as in lecture 7
 *              ("two independent read ports and one independent write port").
 *              x0 reads as zero and is never written. The stack pointer
 *              (x2) resets to the top of memory.
 *              A write in WB is seen by a read in ID in the same cycle
 *              (write-then-read bypass), so ID never reads a stale value.
 *
 * Inputs:
 *   1) clk       - Clock signal
 *   2) rst       - Asynchronous active-high reset
 *   3) rs1_i     - Read port A: source register 1
 *   4) rs2_i     - Read port B: source register 2
 *   5) rd_i      - Write port: destination register
 *   6) datawb_i  - Value written to rd (from WB)
 *   7) regwren_i - RegWEn (lecture 6): write rd this cycle
 *
 * Outputs:
 *   1) rs1data_o - Value of rs1
 *   2) rs2data_o - Value of rs2
 */

`include "constants.svh"

module register_file #(
    parameter int DWIDTH = 32   // data width
)(
    input  logic                 clk,         // clock
    input  logic                 rst,         // asynchronous active-high reset
    input  logic [REG_IDX_W-1:0] rs1_i,       // read port A: source register 1
    input  logic [REG_IDX_W-1:0] rs2_i,       // read port B: source register 2
    input  logic [REG_IDX_W-1:0] rd_i,        // write port: destination register
    input  logic [DWIDTH-1:0]    datawb_i,    // value written to rd
    input  logic                 regwren_i,   // RegWEn: write rd this cycle
    output logic [DWIDTH-1:0]    rs1data_o,   // value of rs1
    output logic [DWIDTH-1:0]    rs2data_o    // value of rs2
);

    logic [DWIDTH-1:0] x [NUM_REGS-1:0];   // the registers x0-x31
    logic              wb_write_valid;     // WB writes a real register (not x0) this cycle

    // Write port. Reset clears every register and points sp at the top of memory.
    always_ff @(posedge clk or posedge rst) begin : register_write
        if (rst) begin
            for (int i = 0; i < NUM_REGS; i++) x[i] <= '0;
            x[REG_SP] <= STACK_TOP_ADDR;
        end else if (regwren_i && (rd_i != REG_X0)) begin
            x[rd_i] <= datawb_i;
        end
    end

    assign wb_write_valid = !rst && regwren_i && (rd_i != REG_X0);

    // Read ports with write-then-read bypass: if WB writes the register ID reads
    // this cycle, ID gets the new value. x0 always reads zero.
    assign rs1data_o = (rs1_i == REG_X0) ? '0
                     : ((wb_write_valid && (rd_i == rs1_i)) ? datawb_i : x[rs1_i]);
    assign rs2data_o = (rs2_i == REG_X0) ? '0
                     : ((wb_write_valid && (rd_i == rs2_i)) ? datawb_i : x[rs2_i]);

endmodule : register_file
