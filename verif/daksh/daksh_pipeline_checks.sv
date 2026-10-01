// Verification-only checker. Connect to actual pipeline state at integration.
module daksh_pipeline_checks (
    input logic clk,
    input logic reset,
    input logic pc_stall,       // Effective PC hold, after redirect priority.
    input logic if_id_flush,    // Effective flush applied at this edge.
    input logic [31:0] pc,      // Actual PC register.
    input logic [31:0] id_insn, // Instruction stored in IF/ID.
    input logic [31:0] x0       // Actual architectural register x0.
);
    // Check the result of the preceding edge's hold decision.
    a_pc_hold: assert property (@(posedge clk) disable iff (reset)
        pc_stall |=> $stable(pc))
        else $fatal(1, "PC changed while stalled");

    // The plan specifies flushing IF/ID to the canonical RISC-V NOP.
    a_flush_nop: assert property (@(posedge clk) disable iff (reset)
        if_id_flush |=> (id_insn == 32'h00000013))
        else $fatal(1, "IF/ID flush did not produce NOP");

    a_x0: assert property (@(posedge clk) disable iff (reset)
        x0 == 32'b0)
        else $fatal(1, "x0 changed");
endmodule
