# Git Revision History and Repository Record

## Repository Information
- URL: https://github.com/k1ng-bit/EECS-4201-Project
- Primary branch: main
- Integration branch: test-main

## Team Roles and Responsibilities
| Teammate | Focus Area | Branch | Main Deliverables |
| :--- | :--- | :--- | :--- |
| zain | Datapath and Pipeline Registers | feat/pipeline-registers | 4 pipeline registers (if_id_reg, id_ex_reg, ex_mem_reg, mem_wb_reg), rv_core datapath integration, register file bypass |
| prabhpreet | Hazard Detection Unit | feat/stall-flush-logic | stall_flush_logic module, RAW hazard detection, load-use stall logic, branch flush logic, standalone unit testbench (tb_stall_flush.sv) |
| daksh | Verification and Automation | feat/verification-ci, feat/verification-tests | GitHub Actions CI workflow (ci.yml), assembly test programs, pipeline assertions (paradoxtests_pipeline_checks.sv), automated test runner |

## Branch Architecture and Merge Flow
The project followed an integration strategy where individual work was reviewed and tested on a staging branch before reaching production.

1. Feature branches:
   - feat/verification-ci: initial CI pipeline setup.
   - feat/pipeline-registers: pipeline register implementation and datapath restructuring.
   - feat/stall-flush-logic: hazard detection logic and unit testbench.
   - feat/verification-tests: pipeline hazard assembly suite and assertion checker.
2. Staging branch (test-main):
   - Used to integrate independent feature branches and run full simulation passes.
   - Prevented broken builds from touching the main branch.
3. Production branch (main):
   - Received the completed and verified Stage 2 processor after all regression tests passed.

## Pull Requests
| PR Number | Title | Source Branch | Target Branch | Status | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| #1 | Continuous Integration Setup | feat/verification-ci | main | Merged | Automated Verilator linting, unit test discovery, and sample benchmark runner. |
| #2 | Hazard Detection Logic | feat/stall-flush-logic | test-main | Merged | Stall and flush logic module with standalone 8-case testbench. |
| #3 | Full Core Integration | test-main | main | Merged | Integrated 5-stage pipelined processor combining datapath, hazard unit, and test suite. |

## Automated CI Verification
GitHub Actions runs on every push and pull request to validate hardware correctness.

- Workflow file: .github/workflows/ci.yml
- Environment: Ubuntu 24.04 with Verilator and Make
- Automated checks executed:
  1. Standalone unit testbenches (make tb-tb_stall_flush): 8/8 tests pass.
  2. Official sample benchmarks (make run-all TEST_DIR=sample-bmarks): test1 and test2 pass.
  3. Verilator lint check: compile-tb with zero warnings and zero errors.
  4. SVA assertion syntax check: paradoxtests_pipeline_checks.sv validated with --assert.
  5. Pipeline hazard functional suite: run_tests.py runs load_use, raw_distance, branch_delay, jalr_flush, and x0_hazard.

## Visual Commit Graph
```text
* 0ac3c4a (HEAD -> main, origin/main, origin/HEAD) final edits for stage 2
*   dcb297c Merge pull request #3 from k1ng-bit/test-main
|\  
| *   99ced7a (origin/test-main, test-main) Merge branch 'feat/verification-tests' into test-main (Step 5)
| |\  
| | * d3caada (origin/feat/verification-tests, feat/verification-tests) docs: mark Step 2 as DONE in Stage 2 plan
| | * fe2e7ff docs: update Stage 2 plan with live progress tracker and test-main merge protocol
| | * 00ea769 Update #2 to ci.yml
| | * 2836013 Update ci.yml
| | * 93da537 Added hazard tests, verification test,  and assertions
| * |   e8e8810 Merge pull request #2 from k1ng-bit/feat/stall-flush-logic
| |\ \  
| | * | fd06194 (origin/feat/stall-flush-logic) Update fix register_file.sv
| | * |   fbf6a7c Merge branch 'test-main' into feat/stall-flush-logic
| | |\ \  
| | |/ /  
| |/| |   
| * | | 5e34d06 docs: mark Step 2 as DONE in Stage 2 plan
| * | | e08f3ab docs: update Stage 2 plan with live progress tracker and test-main merge protocol
| * | | f62cfee fix(pipeline): restore testbench signal probes and decouple sync flush from async reset
| * | |   3c6a915 Merge branch 'feat/pipeline-registers' into test-main
| |\ \ \  
| | |_|/  
| |/| |   
| | | * 527169d (feat/stall-flush-logic) docs: mark Step 2 as DONE in Stage 2 plan
| | | * f25f8ac docs: update Stage 2 plan with live progress tracker and test-main merge protocol
| | | * 6e1bcb0 Add stall flush unit testbench
| | | * b0e81d9 Implement hazard detection and stall flush logic
* | | | 5e48176 docs: mark Step 2 as DONE in Stage 2 plan
* | | | b39b8c7 docs: update Stage 2 plan with live progress tracker and test-main merge protocol
|/ / /  
* | |   4c17250 Merge pull request #1 from k1ng-bit/feat/verification-ci
|\ \ \  
| |_|/  
|/| |   
| | | * 465b29e (origin/feat/verification-ci, feat/verification-ci) docs: mark Step 2 as DONE in Stage 2 plan
| | | * 2e64062 docs: update Stage 2 plan with live progress tracker and test-main merge protocol
| | |/  
| |/|   
| * | f5f586d ci: add unit test discovery, results table verification, and lint check
| * | 0cb0c6a Fix Verilator CI benchmark coverage
| * | 311978e Added Verilator CI
|/ /  
| | * 99acfad (origin/feat/pipeline-registers, feat/pipeline-registers) docs: mark Step 2 as DONE in Stage 2 plan
| | * 969f97b docs: update Stage 2 plan with live progress tracker and test-main merge protocol
| |/  
| * 895e9f6 feat: implement 5-stage pipeline registers and core datapath integration
|/  
```
