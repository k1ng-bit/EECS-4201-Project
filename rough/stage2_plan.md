# Stage 2: 5-Stage In-Order Pipelined RV-Core Plan
## Decoupled Zero-Wait Architecture & 3-Member Work Breakdown

This document defines the architecture, frozen interface contracts, and fully decoupled work breakdown for Stage 2. It is engineered so that **all 3 team members can work simultaneously from Day 1 without blocking or waiting on each other**, targeting **100/100 (Sophisticated)** on the marking rubric.

---

## 1. Architectural Overview & Hazard Strategy

The goal is to convert the single-cycle core into a 5-stage in-order pipelined RV32I processor:
1. **IF (Instruction Fetch)**: Fetches instruction using `pc`, updates `pc <= pc + 4` (or branch target).
2. **ID (Instruction Decode)**: Decodes instruction fields, generates immediate, and reads register file (`rs1`, `rs2`).
3. **EX (Execute)**: Computes ALU operations, resolves branch conditions (`brtaken`), and calculates branch/jump target addresses.
4. **MEM (Memory Access)**: Accesses data memory for Load (`memren`) and Store (`memwren`) operations.
5. **WB (Writeback)**: Selects final result and commits write data to the register file (`rd`).

### Hazards Handled in Stage 2 (Stall & Flush Only)
* **Control Hazards (Branch/Jump Taken)**: Resolved in the EX stage. When a branch is taken or a jump occurs, instructions in the pipeline behind it (IF/ID and ID/EX) must be **flushed** (turned into bubbles/NOPs), and the PC redirected to the target.
* **Data Hazards (RAW & Load-Use)**: Without data forwarding in Stage 2, any instruction in ID that depends on a register written by an instruction in EX or MEM requires **stalling** the pipeline until the value reaches WB (or using NOP bubbles). Specifically, a **Load-Use hazard** (load in EX followed by consumer in ID) requires freezing IF and ID stages and inserting a bubble into EX.

---

## 2. Frozen Interface Contract (Day 1 Agreement)

To ensure zero dependencies between team members, the signal interfaces are locked as follows:

### A. `stall_flush_logic.sv` Port Contract
```systemverilog
module stall_flush_logic (
    // Inputs from Decode stage (current instruction requesting operands)
    input  logic [4:0]  id_rs1_i,
    input  logic [4:0]  id_rs2_i,
    input  logic        id_rs1_valid_i,     // 1 if instruction reads rs1
    input  logic        id_rs2_valid_i,     // 1 if instruction reads rs2

    // Inputs from Execute stage (previous instruction 1 ahead)
    input  logic [4:0]  ex_rd_i,
    input  logic        ex_regwren_i,
    input  logic        ex_memren_i,        // Load in EX
    input  logic        ex_brtaken_i,       // Taken branch in EX
    input  logic        ex_is_jump_i,       // JAL/JALR in EX

    // Inputs from Memory stage (instruction 2 ahead)
    input  logic [4:0]  mem_rd_i,
    input  logic        mem_regwren_i,
    input  logic        mem_memren_i,       // Load in MEM

    // Outputs to Pipeline Control
    output logic        pc_en_o,            // 0 = stall PC, 1 = normal advance
    output logic        if_id_stall_o,      // 1 = hold IF/ID register
    output logic        if_id_flush_o,      // 1 = flush IF/ID to NOP
    output logic        id_ex_flush_o,      // 1 = insert bubble into ID/EX
    output logic        ex_mem_flush_o      // 1 = flush EX/MEM (if needed)
);
```

### B. Pipeline Register Modules (Standardized Template)
All pipeline registers must adhere to:
* **Asynchronous reset** (`posedge clk or posedge rst`)
* **Synchronous stall enable** (`stall_i`: hold current values)
* **Synchronous flush** (`flush_i`: reset control signals to safe NOPs)
* Processes kept under 10 lines each (`always_ff` only).

---

## 3. Decoupled Work Breakdown (Zero-Wait)

```
                 Day 1: Interface Contract Frozen
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
  [ Member 1 ]            [ Member 2 ]            [ Member 3 ]
Branch: feat/pipeline-regs Branch: feat/hazard-logic Branch: feat/verification-ci
- Build 4 pipeline regs  - Implement pure         - Build GitHub Actions CI
- Connect rv_core.sv      stall_flush_logic.sv     Verilator workflow
- Stub hazard signals to - Build dedicated unit   - Write assembly hazard
  0 / pass-through        testbench               test programs (.s)
- Validate with NOP      - Verify 100% hazard     - Build SV assertion
  programs                scenarios in isolation   suite & monitor tasks
        └───────────────────────┬───────────────────────┘
                                ▼
                   Integration & Merge Day
        Plug Member 2 logic into Member 1 core;
        Validate against Member 3 test suite and CI.
```

---

### Member 1: Datapath Integration & Pipeline Registers
* **Git Branch**: `feat/pipeline-registers`
* **Independent Workflow (No Waiting)**:
  1. Create the 4 pipeline register modules:
     - `if_id_reg.sv` (holds `pc`, `insn`)
     - `id_ex_reg.sv` (holds `pc`, `rs1_data`, `rs2_data`, `imm`, `rd`, `rs1`, `rs2`, funct3, funct7, opcode, control signals)
     - `ex_mem_reg.sv` (holds `alu_res`, `rs2_data`, `rd`, funct3, memory control signals, `regwren`, `wbsel`)
     - `mem_wb_reg.sv` (holds `alu_res`, `mem_rdata`, `rd`, `imm`, `pc`, `wbsel`, `regwren`)
  2. Instantiate these registers in [rv_core.sv](file:///c:/Users/Zain/Documents/code/courses/4201/code/rv_core.sv).
  3. **Stub out hazard logic**: Wire `stall_flush_logic` inputs to dummy/ground and outputs to `stall = 0`, `flush = 0`, `pc_en = 1`.
  4. **Self-Verification**: Member 1 can immediately verify their core using benchmark assembly programs where independent instructions or explicit `nop`s prevent hazards. The datapath pipeline is validated before hazard logic is even merged!
* **Rubric Focus**:
  - **Datapath design (8%)**: Every pipeline register uses **asynchronous reset logic** (`if (rst) ...`).
  - **Process definitions (5%)**: Strictly `always_ff`, lines per process <= 10.

---

### Member 2: Hazard Detection & Stall/Flush Logic
* **Git Branch**: `feat/stall-flush-logic`
* **Independent Workflow (No Waiting)**:
  1. Implement [stall_flush_logic.sv](file:///c:/Users/Zain/Documents/code/courses/4201/code/stall_flush_logic.sv) based strictly on the port contract above.
  2. **Data Hazard Logic**:
     - Check RAW hazards: If `(id_rs1 == ex_rd && id_rs1_valid && ex_regwren && ex_rd != 0)`, stall required.
     - Check Load-Use hazards: If `ex_memren && ((id_rs1 == ex_rd && id_rs1_valid) || (id_rs2 == ex_rd && id_rs2_valid))`, stall IF/ID and PC, flush ID/EX.
     - Special case: Ensure register `x0` NEVER triggers a hazard!
  3. **Control Hazard Logic**:
     - If `ex_brtaken_i || ex_is_jump_i`, assert `if_id_flush_o = 1` and `id_ex_flush_o = 1`.
  4. **Dedicated Standalone Testbench (`verif/tb_stall_flush.sv`)**:
     - Member 2 creates a standalone unit testbench that does not need `rv_core.sv`.
     - Directly tests all combinations of inputs:
       - Case 1: Trivial instruction flow (no stalls, no flushes)
       - Case 2: Load-use hazard detection
       - Case 3: RAW hazard across EX and MEM stages
       - Case 4: Branch taken (flush verification)
       - Case 5: Branch not taken (no flush)
       - Case 6: False hazard on register `x0` (`x0` as destination)
       - Case 7: Simultaneous branch resolution and load hazard
  5. Member 2 achieves **100% verified, bug-free logic** in isolation.
* **Rubric Focus**:
  - **Latch inferences (8%)**: Ensure all `case` and `if-else` have default assignments; zero latch inferences.
  - **Programming constructs (4%)**: Single-line `assign` and concise `always_comb` behavioral blocks.

---

### Member 3: Verification Suite, CI/CD & SV Extensions
* **Git Branch**: `feat/verification-ci`
* **Independent Workflow (No Waiting)**:
  1. **Continuous Integration (CI)**:
     - Create `.github/workflows/ci.yml` to automatically run `make compile-tb WARN=1` and execute tests via Verilator on every push/PR.
  2. **Targeted Pipeline Test Suite**:
     - Write targeted RISC-V assembly programs (`verif/tests/pipeline_tests/`):
       - `load_use.s`: Load followed immediately by dependent ALU instruction.
       - `raw_distance.s`: RAW dependencies spaced by 1, 2, and 3 instructions.
       - `branch_delay.s`: Taken and not-taken branches to verify delay slots are squashed and not executed.
       - `jalr_flush.s`: Indirect jump pipeline flush test.
       - `x0_hazard.s`: Repeated writes to `x0` to prove false hazards are not triggered.
  3. **SystemVerilog Extensions (Rubric 2%)**:
     - Write verification tasks (`check_reg_val()`, `step_cycle()`) in testbenches.
     - Implement SV assertion checkers (`assert property`):
       - *Assertion 1*: When `stall` is high, `pc` must remain constant on the next clock edge.
       - *Assertion 2*: When `flush` is asserted, the instruction reaching the next stage must decode as `NOP`.
       - *Assertion 3*: `x0` in the register file must always remain `0`.
* **Rubric Focus**:
  - **Testbench design (30%)**: Exhaustive test cases (trivial, corner, invalid, non-trivial sequences).
  - **SV extensions (2%)**: Extensive tasks, functions, and assertion checkers.
  - **Code revisioning (5%)**: CI pipeline, PR template, branch rules.

---

## 4. Integration & Merge Protocol & Live Progress Tracker

> ### ⚠️ CRITICAL MERGE RULE: TARGET `test-main` ONLY
> **DO NOT MERGE DIRECTLY INTO `main`!**
> A staging branch named **`test-main`** has been created from `main`. All feature branches and pull requests (Step 2, Step 3, Step 4, Step 5) **must strictly target `test-main`**. 
> The production `main` branch will only be updated once the full 5-stage pipelined core is completely assembled, verified, and passing all regression suites on `test-main`.

### Step-by-Step Status

| Step | Focus | Branch | Target Branch | Status | Details / Actions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Step 1** | Automated CI Workflow | `feat/verification-ci` | `main` | ✅ **DONE** | PR #1 merged (`4c17250`). Verilator lint check, standalone unit TB runner, and `_results.txt` verification active. |
| **Step 2** | Pipeline Registers & Core Integration | `feat/pipeline-registers` | `test-main` | 🔄 **IN PROGRESS (STAGED)** | Merged into `test-main`. Signal aliases (`stall`, `flush`, `f_insn`) added and `wb_wb1` restored for `top_tb` compatibility. Sync `flush_i` decoupled from async `rst`. Compiles cleanly with 0 errors/0 warnings. |
| **Step 3** | Hazard Detection & Stall/Flush Logic | `feat/stall-flush-logic` | `test-main` | 🟡 **READY FOR PR** | Logic and `tb_stall_flush.sv` unit testbench committed (`6e1bcb0`). Target PR to `test-main`. CI will automatically run unit testbench. |
| **Step 4** | Datapath & Hazard Core Wiring | Integration on `test-main` | `test-main` | ⏳ **PENDING** | Connect Member 2's `stall_flush_logic` outputs to pipeline register enables/flushes in `rv_core.sv`. |
| **Step 5** | Regression & Pipeline Assembly Tests | `feat/verification-tests` | `test-main` | 🟡 **TESTS READY** | Member 3 created 5 targeted assembly tests (`branch_delay`, `jalr_flush`, `load_use`, `raw_distance`, `x0_hazard`) and assertion checkers (`member3_pipeline_checks.sv`). Validate full core once Step 4 is integrated. |

---

## 5. Rubric 100/100 Compliance Checklist

| Rubric Dimension | Weight | Sophisticated Criteria Requirement | Team Implementation Standard |
| :--- | :--- | :--- | :--- |
| **Hardware Modeling** | 4% | Single-line `assign` and behavioral process blocks | Use `assign` for simple routing/multiplexing; behavioral `always_comb`/`always_ff` |
| **Sensitivity Lists** | 5% | Necessary and sufficient signals | Strictly `always_comb` (implicit optimal list) and `always_ff @(posedge clk or posedge rst)` |
| **Latch Inferences** | 8% | No latch inference; all branches/cases covered | Every combinational block sets default outputs at the top or in `default:` |
| **Synthesizable** | 15% | Strictly synthesizable hardware | No dynamic loop bounds, no `X` assignments, fully synthesizable SystemVerilog |
| **Process Definitions** | 5% | `always_comb`/`always_ff`, <= 10 lines per process | Keep every process block <= 10 lines. Split large blocks into sub-processes |
| **Datapath Design** | 8% | Asynchronous reset logic for all components | All pipeline registers and state elements have `posedge clk or posedge rst` |
| **Constants** | 3% | Defined in separate file and reused | All opcodes, functs, ALU ops, and control bits defined in `constants.svh` |
| **Naming Conventions**| 3% | Appropriate, descriptive, consistent style | Consistent snake_case: stage prefix (`id_`, `ex_`, `mem_`, `wb_`) + direction suffix (`_i`, `_o`) |
| **SV Extensions** | 2% | Extensive tasks, functions, and assertion checkers | Assertions for stall stability, flush behavior, and testbench checking tasks |
| **Testbench Design** | 30% | Exhaustive coverage (trivial, corner, invalid, non-trivial) | Unit testbench for stall/flush + full suite of pipeline hazard assembly tests |
| **Code Comments** | 7% | Comments on all signals/processes, proper grammar, TODOs | Clean descriptive block comments on every module, port, and process; future TODOs |
| **Code Revisioning** | 5% | Git branch, code review, merge to main, CI automation | GitHub Actions workflow, feature branches, pull request reviews, clean commits |
| **Delegation** | 3% | Fair delegation from beginning, deadlines met | 3 equal, decoupled streams (Datapath, Hazard Logic, Verification) |
| **Team Morale** | 2% | Camaraderie, mutual respect, zero friction | Clear interfaces avoid blocking and merge conflicts |

---

## 6. Stage 3 Recommendation

**Recommended Role:** **Performance Architect**
**Recommended Extension:** **Store Buffer with Data Forwarding**

### Why this is the best path:
1. **Direct Continuity from Stage 2**: In Stage 2, all data hazards are resolved by stalling (wasting cycles). Stage 3 forwarding naturally replaces those stall cycles with bypass paths from `EX/MEM` and `MEM/WB` into the ALU inputs in `EX`.
2. **Measurable Metric**: You can directly benchmark the speedup (IPC improvement) between your Stage 2 stall-only core and your Stage 3 forwarded core across standard benchmark programs.
3. **Work Division in Stage 3**:
   - Member A: ALU-to-ALU and MEM-to-ALU forwarding multiplexers and control logic.
   - Member B: Store buffer implementation (queuing store operations to prevent memory stalls).
   - Member C: Performance instrumentation (cycle counters, stall counters, and IPC comparison testbench).
