`include "constants.svh"

`timescale 1ns/1ps

`ifndef TIMEOUT
  `define TIMEOUT 32'd10000
`endif

`ifndef RESET_CYCLES
  `define RESET_CYCLES 2
`endif


module top_tb;

   logic clk = 0;
   logic rst = 1;
   always #1 clk = ~clk;

   localparam int DWIDTH = 32;
   localparam int AWIDTH = 32;

   rv_core #(
      .AWIDTH(AWIDTH),
      .DWIDTH(DWIDTH)
   ) hut (
      .clk(clk),
      .reset(rst)
   );

   
   reg is_program = 0;
      
   logic [DWIDTH-1:0] first_test_register, second_test_register;

   assign first_test_register  = hut.register_file1.x[1];
   assign second_test_register = hut.register_file1.x[15];

   // Latency counters to delay checks until instructions reach Writeback
   int ecall_delay_cnt    = 0;
   int program_delay_cnt  = 0;
   localparam int PIPELINE_CYCLES = 5; // Adjust based on your pipeline depth

   always_ff @(negedge clk) begin
      // --- ECALL TRIGGER & DELAY ---
      if (hut.f_insn == 32'h00000073) begin
         ecall_delay_cnt <= PIPELINE_CYCLES;
      end 
      else if (ecall_delay_cnt > 1) begin
         ecall_delay_cnt <= ecall_delay_cnt - 1;
      end 
      else if (ecall_delay_cnt == 1) begin
         ecall_delay_cnt <= 0;
         $display("========== Simulation Completed! ==========");
         if (first_test_register == 1) begin
            $display("Test Passed");
            print_metrics(); // Call the function to print metrics
         end else begin
            $display("Test Failed");
         end
         $display("========== Terminating Simulation due to ecall ==========");
         $finish;
      end

      // --- RET PROGRAM TRIGGER & DELAY ---
      if (hut.f_insn == 32'h00008067) is_program <= 1;

      if (is_program && (hut.register_file1.x[2] == 32'h01000000 + `MEM_DEPTH) && program_delay_cnt == 0) begin
         program_delay_cnt <= PIPELINE_CYCLES;
      end else if (program_delay_cnt > 1) begin
         program_delay_cnt <= program_delay_cnt - 1;
      end else if (program_delay_cnt == 1) begin
         program_delay_cnt <= 0;
         $display("========== Simulation Completed! ==========");
         if (second_test_register == 1) begin
            $display("Test Passed");
            print_metrics(); // Call the function to print metrics
         end else begin
            $display("Test Failed");
         end
         $display("========== Terminating Simulation due to program completion ==========");
         $finish;
      end
   end

   // Borrowed from clockgen.sv
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

   int total_cycles = 0;
   int insn_exe = 0;
   int stalls = 0;
   int squashes = 0;
   real cpi = 0.0;

   `ifdef HAS_STALL_SIGNAL
      `define GET_STALL (hut.stall)
   `else
      `define GET_STALL (0)
   `endif  
   `ifdef HAS_FLUSH_SIGNAL
      `define GET_FLUSH (hut.flush)
   `else
      `define GET_FLUSH (0)
   `endif

   //---------- Stall-cause counters for the store buffer (SB) measurements ----------//
   // Each counts cycles after reset, except the two marked "events".
   // Probes use the hazard unit's ports, so they also work on a core without the SB.
   int store_stalls      = 0; // a store in MEM waits: for memory without the SB, for a free entry with it
   int store_only_stalls = 0; // a store waits while the next instruction is already fetched
                              // (the time an SB can save: Amdahl's f)
   int load_stalls       = 0; // a load in MEM waits for its data
`ifndef NO_STORE_BUFFER
   int sb_full_stalls    = 0; // a store waits because every SB entry is in use
   int sb_partial_stalls = 0; // a load waits on a partial match until the older store is written
   int sb_port_stalls    = 0; // a load waits because a head write owns the data port
   int sb_forwards       = 0; // events: a load took its value from the SB
   int sb_head_writes    = 0; // events: the SB wrote its head store to memory
   int sb_peak_count     = 0; // most stores held in the SB at once
`endif

   // Adds this cycle's stall causes to the counters.
   task automatic count_stall_causes();
      if (hut.stall_flush.mem_memwren_i && !hut.stall_flush.mem_ready_i) begin
         store_stalls++;
         if (hut.stall_flush.insn_ready_i) store_only_stalls++;
      end
      if (hut.stall_flush.mem_memren_i && !hut.stall_flush.mem_ready_i) load_stalls++;
`ifndef NO_STORE_BUFFER
      if (hut.stall_flush.mem_memwren_i && hut.memory1.sb_full) sb_full_stalls++;
      if (hut.memory1.sb_partial) sb_partial_stalls++;
      if (hut.memory1.load_needs_port && !hut.memory1.port_load) sb_port_stalls++;
      if (hut.memory1.sb_forward) sb_forwards++;
      if (hut.memory1.head_written) sb_head_writes++;
      if (int'(hut.memory1.sb.sb_count) > sb_peak_count) sb_peak_count = int'(hut.memory1.sb.sb_count);
`endif
   endtask

   // Prints the stall-cause counters (called by print_metrics).
   task automatic print_stall_causes();
      $display("Instructions        : %0d", insn_exe);
      $display("Store stalls        : %0d", store_stalls);
      $display("Store-only stalls   : %0d", store_only_stalls);
      $display("Load stalls         : %0d", load_stalls);
`ifndef NO_STORE_BUFFER
      $display("SB full stalls      : %0d", sb_full_stalls);
      $display("SB partial stalls   : %0d", sb_partial_stalls);
      $display("SB port-busy stalls : %0d", sb_port_stalls);
      $display("SB forwards         : %0d", sb_forwards);
      $display("SB head writes      : %0d", sb_head_writes);
      $display("SB peak count       : %0d", sb_peak_count);
`endif
   endtask

initial begin
`ifndef NO_WAVES  // -DNO_WAVES skips the waveform, for long slow-memory runs
      $dumpfile("top_tb.vcd");
      $dumpvars(0, top_tb);
`endif
      $system("date");
      wait (!rst);
      forever begin
         @(posedge clk);

         total_cycles++;
         if (hut.flush) begin
            squashes++;
         end
         else if (hut.stall) begin
            stalls++;
         end
         if (hut.wb_wb1.pc_i != '0) begin
            insn_exe++;
         end
         count_stall_causes();
      end
   end

   function automatic void print_metrics();

      // Calculate CPI after cycle sync
      if ((total_cycles - stalls - squashes) > 0) begin
         cpi = real'(total_cycles) / real'(insn_exe);
      end else begin
         cpi = 0.0;
      end

      $display("\n===========================================");
      $display("       PIPELINE PERFORMANCE METRICS       ");
      $display("===========================================");
      $display("Total Cycles : %0d", total_cycles);
      $display("Stalls       : %0d", stalls);
      $display("Squashes     : %0d", squashes);
      $display("Final CPI    : %0.2f", cpi);
      print_stall_causes();
      $display("===========================================\n");
   endfunction

endmodule: top_tb

