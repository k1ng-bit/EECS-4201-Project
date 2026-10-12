# EECS-4201-project

This repository contains the hardware design, verification environment, and synthesis flow for York University's EECS 4201 course project. It implements a fully pipelined 5-stage in-order RISC-V processor supporting the RV32I base integer instruction set in SystemVerilog.

## Project structure
There are three main directories:
- `code`: Hardware logic implementation including top-level core, datapath modules, control logic, pipeline registers, and hazard detection.
- `verif`: Verification testbenches, Makefiles, official benchmarks, pipeline assertion checkers, and the Paradox automated regression suite (`verif/paradoxtests/`).
- `synthesis`: SkyWater 130nm cell library (`sky130nm.lib`), Yosys synthesis script (`synthesis.ys`), OpenSTA timing analysis script (`timing.tcl`), and full execution logs (`full_run.log`).

## Code structure
The following files are present in the `code/` directory:
- `rv_core.sv`: Top-level design module that instantiates and connects all pipeline stages, pipeline registers, and the hazard detection unit.
- `constants.svh`: Shared header containing opcodes, ALU operation selectors, and pipeline control constants.
- `fetch.sv`: Instruction fetch stage logic, managing program counter updates and instruction memory interfacing.
- `if_id_reg.sv`: IF/ID pipeline register with stall hold and synchronous flush logic.
- `decode.sv`: Instruction decode stage logic extracting register addresses and control fields.
- `igen.sv`: Immediate value generator supporting I, S, B, U, and J formats.
- `control.sv`: Main control unit decoding instruction opcodes into pipeline control signals.
- `branch_control.sv`: Branch control unit resolving conditional branches and branch target selection.
- `id_ex_reg.sv`: ID/EX pipeline register propagating control signals, operands, and immediate values with synchronous flush.
- `execute.sv`: Execution stage incorporating ALU arithmetic and logic operations.
- `ex_mem_reg.sv`: EX/MEM pipeline register carrying execution results and memory control flags.
- `memory.sv`: Top-level memory stage module interfacing the memory controller with main memory.
- `memory_controller.sv`: Memory controller managing byte, halfword, and word alignment for loads and stores.
- `main_memory.sv`: Memory array implementation supporting simulation initialization and synthesis-compatible technology mapping.
- `mem_wb_reg.sv`: MEM/WB pipeline register buffering memory data and ALU results for writeback.
- `register_file.sv`: 32-entry integer register file with internal write-to-read forwarding bypass.
- `writeback.sv`: Writeback stage multiplexing memory data and ALU results to destination registers.
- `stall_flush_logic.sv`: Hazard detection unit managing RAW dependencies, load-use stalls, and branch/jump flushes.

## Synthesis and timing analysis
The core is synthesized against the SkyWater 130nm standard cell library (`sky130_fd_sc_hd`) using Yosys for logic synthesis and OpenSTA for static timing analysis.

To run the synthesis flow on an EECS EA remote machine or Nix/Librelane environment:
1. Invoke the Librelane EDA suite:
   ```bash
   librelane
   ```
2. Run logic synthesis with Yosys:
   ```bash
   yosys synthesis/synthesis.ys
   ```
   This runs logic optimization, tech mapping to standard cells, flip-flop mapping, and produces cell count/area summaries.

3. Run static timing analysis with OpenSTA:
   ```bash
   sta synthesis/timing.tcl
   ```
   This performs setup timing checks, calculates the worst negative slack (WNS), and determines maximum operating frequency ($f_{max}$).

Full synthesis and timing analysis logs are recorded in `synthesis/full_run.log`.

## Getting started
Note that the below steps assume a Linux environment with ModelSim or Verilator installed.

### Step 0: Setup your workstation
You will need a workstation to do the project. You may either use your personal computer or use one of the Linux remote machines [EA machines](https://remotelab.eecs.yorku.ca/#/) provided by the department. We use [Verilator](https://verilator.org/) to build and simulate the design and [gtkwave](https://gtkwave.sourceforge.net/) to view the VCD waveforms. Both of these are available on the EA machines.

### Step 1: Get the starter code
Clone the repository to your local workspace or EA machine account.

### Step 2: Check your environment
Open a terminal and verify tool versions:
- `verilator --version`: Returns the installed Verilator version
- `gtkwave --version`: Returns the installed GTKWave version

### Step 3: Compiling the code
- In the repository root, build the hardware model using Verilator:
  ```bash
  make compile-tb -C verif/
  ```
  To inspect all compilation warnings:
  ```bash
  make compile-tb WARN=1 -C verif/
  ```

- Run the standalone hazard unit testbench:
  ```bash
  make tb-tb_stall_flush -C verif/
  ```

- Run sample testbench:
  ```bash
  make tb-template_tb -C verif/
  ```

### Step 4: Testing the code
- Run official sample benchmarks:
  ```bash
  make run-all -C verif/ TEST_DIR=sample-bmarks
  ```
  To run a single benchmark test:
  ```bash
  make run -C verif/ TEST_DIR=sample-bmarks TEST=test1
  ```

- Run the Paradox automated regression test suite:
  ```bash
  python3 verif/paradoxtests/run_tests.py
  ```

- Validate SystemVerilog assertions (SVA):
  ```bash
  verilator --assert -Wall -Wno-fatal --cc code/rv_core.sv verif/paradoxtests/paradoxtests_pipeline_checks.sv
  ```

- Inspect waveforms:
  If a test produces a failure or timeout, open the generated waveform in GTKWave:
  ```bash
  gtkwave verif/Sim/<name of .vcd file>
  ```

### Step 5: Submitting code to eclass
After verifying your design and running the required checks, zip up the `code/` directory and submit on eClass.

### Acknowledgements
Many thanks to the Fall 2025 students of EECS 4201 who caught bugs and suggested improvements to this project (Hussein, Salwan, Abdulbasit, Minhyeok, Areeba, Nitant, Anthony, Vikram, Steven, Cheuk, Clarence, Patrick, Dylan, Aadi, Paavan, Harman, Arnav, Salim, Salman, Manya, Artin, Yousif, Anagha, Kiet, Colin, Kaibin, Jackie, Quardin, Mavra, Kosy, Kanwarpartap, Paramkumar, Mateo, Taha, Sara, Abdullah, Ariana, and Erwin).
