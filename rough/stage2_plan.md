# Stage 2 Plan: 5-Stage In-Order Pipelined RV-Core

This document outlines the plan to convert our single-cycle core into a 5-stage pipelined core, divided among 3 team members, adhering strictly to the **100/100 Sophisticated** rubric criteria.

## 1. Task Overview

The goal of Stage 2 is to introduce pipelining to increase the clock frequency of the core. The 5 stages are:
1. **Instruction Fetch (IF)**
2. **Instruction Decode (ID)**
3. **Execute (EX)**
4. **Memory Access (MEM)**
5. **Writeback (WB)**

**Key Architectural Changes Required:**
*   **Pipeline Registers:** We need to insert state elements (registers) between each stage: `IF/ID`, `ID/EX`, `EX/MEM`, and `MEM/WB`. These will propagate control signals, data, and PC values.
*   **Hazard Detection:** Since instructions are executing concurrently, we must handle data hazards (e.g., reading a register before a previous instruction writes to it) and control hazards (e.g., branching).
*   **Stall & Flush Logic:** We need to complete `stall_flush_logic.sv` to handle hazards by stalling the pipeline (inserting bubbles) or flushing incorrect instructions fetched after a branch/jump.

---

## 2. Work Breakdown Structure (3 Members)

To ensure fair delegation (3% Rubric) and high cohesiveness (2% Rubric), the work is divided based on component boundaries.

### Member 1: Datapath Integration & Pipeline Registers
**Responsibilities:**
*   Design and implement the pipeline registers (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`).
*   Modify `rv_core.sv` to instantiate these registers and connect the 5 stages.
*   Ensure all necessary signals (control bits from `control.sv`, register data, PC) are correctly propagated down the pipeline.
*   **Rubric Focus:**
    *   **Datapath design (8%):** Ensure *every* pipeline register uses **asynchronous reset logic**.
    *   **Process definitions (5%):** Use `always_ff` for sequential logic. Keep process blocks under 10 lines.

### Member 2: Hazard Detection, Stall, and Flush Logic
**Responsibilities:**
*   Implement `stall_flush_logic.sv`.
*   Detect **Data Hazards**: Specifically Load-Use hazards where a load instruction is followed immediately by an instruction needing its result.
*   Detect **Control Hazards**: Identify when a branch is taken or a jump occurs, requiring the fetched instructions to be discarded.
*   Generate `stall` and `flush` control signals for the pipeline registers and fetch stage.
*   **Rubric Focus:**
    *   **Programming constructs (4%):** Use single-line `assign` statements or concise `always_comb` blocks with behavioral modeling for hazard detection.
    *   **Latch inferences (8%):** Ensure absolutely NO latches. All `if-else` and `case` statements must have default cases covering all conditions.

### Member 3: Verification, CI/CD & Testbench Architecture (Heavy lifting for Rubric)
**Responsibilities:**
*   Refactor and expand `template_tb.sv` to handle pipeline-specific testing (e.g., testing back-to-back hazards, flush recovery).
*   Setup **Continuous Integration (CI)** (e.g., GitHub Actions) to run Verilator tests automatically on PRs.
*   Enforce Code Review practices for the team.
*   **Rubric Focus:**
    *   **Testbench design (30%):** Exhaustive coverage! Include tests for trivial, corner, invalid cases, and non-trivial pipeline hazard sequences.
    *   **SV extensions (2%):** Make *extensive* use of SV tasks, functions, and assertion checkers (`assert property`) within the testbenches.
    *   **Code revisioning (5%):** Manage branches, enforce PR reviews, and maintain descriptive commit messages.

---

## 3. Rubric 100/100 Checklist for ALL Members

Everyone must adhere to these coding standards while implementing their parts:

- [ ] **Hardware Modeling:** Use single-line `assign` statements where possible.
- [ ] **Sequential vs Combinational:** STRICTLY use `always_comb` for combinational and `always_ff` for sequential logic. No `always @(*)`.
- [ ] **Process Length:** Keep every `always` block under **10 lines**.
- [ ] **Resets:** ALL registers and memory components must use **asynchronous reset logic**.
- [ ] **Constants:** Define ALL constants in `constants.svh`. No magic numbers in the code.
- [ ] **Naming Conventions:** Use descriptive names with consistent snake_case (e.g., `hazard_detect_en`).
- [ ] **Comments:** Provide descriptive comments for ALL signals, variables, and process logic. Use correct grammar. Include `TODO:` placeholders for future optimizations.
- [ ] **No Latches / Synthesizable:** Provide default cases for all combinational logic. Do not initialize signals to `X`.

---

## 4. Stage 3 Recommendation

**Recommendation: Performance Architect - Store buffer with data forwarding**

**Why?**
In Stage 2, we are handling data hazards purely by stalling the pipeline. This significantly hurts performance (IPC). Moving into Stage 3, implementing **Data Forwarding (Bypassing)** is the most natural and rewarding progression.
1.  It builds directly on top of the hazard detection logic you will write in Stage 2.
2.  It teaches a fundamental concept used in all modern high-performance processors to minimize stalls.
3.  It allows us to measure a tangible performance improvement on the benchmarks compared to our Stage 2 stall-only core.

*Alternative:* If the team prefers control logic over data movement, **Branch Prediction** is an equally excellent choice, as flushing the pipeline on branches is the second biggest performance bottleneck we will face in Stage 2.
