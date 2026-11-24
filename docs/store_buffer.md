# Stage 4: store buffer (SB) with load forwarding

Owner: Zain. Measured 2026-11-24 with Verilator 5.020 (the CI version). The raw numbers are in
[store_buffer_results.csv](store_buffer_results.csv).

## Design

The SB is the store queue from lec13 slide 65 and the store half of the memory ordering buffer
(MOB) in lec10 slides 47–52. It sits between the MEM stage and the data port of main memory:

```
 IF -> F/D -> ID -> D/X -> EX -> X/M -> MEM -> M/W -> WB
  |                                     |  ^
  | fetch port                          |  | load data: forwarded word, or word read from memory
  |                     store allocate  v  | load search (youngest older store, == per entry)
  |                               +----------------------+
  |                               | store buffer (FIFO)  |
  |                               | head ......... tail  |
  |                               +----------------------+
  |                                   | head write (oldest store first)
  v                                   v
 +-------------------------------------------------------+
 | main memory: fetch port | one data port (loads first, |
 |                         | a started head write keeps it)
 +-------------------------------------------------------+
```

- **Store allocate (Store Execute):** a store in MEM is written at `sb_tail` and finishes at once,
  so the pipeline keeps going. It waits only when the SB is full.
- **Head write (Store Retire):** the store at `sb_head` is written to memory, oldest first.
- **Load search (Load Execute):** every entry compares its word address with `==`. The youngest
  matching store is chosen.
  - It covers every byte the load reads: **forward** its value; the load does not read memory.
  - It covers only some of those bytes: **partial match**, so the load waits (interlock) until
    that store is written, then reads memory.
  - No match: the load reads memory.
- Loads and head writes share one data port (a structural hazard). A load gets the port first,
  and a head write that has started keeps it until it finishes.
- The core is in order and stores reach MEM only after their branch resolves in EX, so the SB
  needs no flush and no memory disambiguation.

Files: `code/store_buffer.sv` (the FIFO, search, assertions), `code/memory.sv` (port sharing and
`data_ready_o`), `code/rv_core.sv` (wiring), `SB_DEPTH` in `code/constants.svh` (default 8).

## How it was measured

```
bash verif/sb_measure.sh <sb|base> <fetch latency> <data latency> <SB depth> <dir/test>...
```

`sb` is this branch. `base` is commit `665f355`, the same core without the SB. Both builds run
the same programs with the same `top_tb.sv`, which now prints stall-cause counters:

| Counter | Meaning |
|---|---|
| Store stalls | cycles a store in MEM waits (for memory without the SB, for a free entry with it) |
| Store-only stalls | store stalls while the next instruction is already fetched: the time an SB can save |
| Load stalls | cycles a load in MEM waits for its data |
| SB full / partial / port-busy stalls | why a store or load waited with the SB |
| SB forwards, head writes, peak count | events, and the most stores held at once |

Main memory has one latency for both waiters today, so the script edits a private copy to give
fetch and data their own latency. "(1,50)" means fetch 1 cycle, data 50 cycles.

## Results (SB depth 8)

Speedup = T_old / T_new (lec2). f = store-only stalls / cycles of the run without the SB.
Amdahl limit = 1 / (1 − f): the best any SB can do by hiding store time alone.

| Config | Program | Cycles, no SB | Cycles, SB | Speedup | f | Amdahl limit | Forwards | Peak |
|---|---|---|---|---|---|---|---|---|
| (50,50) | test1 | 1728 | 1711 | 1.010 | 0.008 | 1.008 | 2 | 1 |
| (50,50) | test2 | 2146 | 2127 | 1.009 | 0.008 | 1.008 | 2 | 1 |
| (50,50) | sb-burst-compute-b8 | 129961 | 129833 | 1.001 | 0.001 | 1.001 | 0 | 1 |
| (1,50) | test1 | 733 | 169 | 4.337 | 0.475 | 1.904 | 5 | 7 |
| (1,50) | test2 | 952 | 169 | 5.633 | 0.418 | 1.718 | 8 | 8 |
| (1,50) | sb-store-load | 2075 | 1489 | 1.394 | 0.217 | 1.277 | 8 | 5 |
| (1,50) | sb-burst | 2037 | 1241 | 1.641 | 0.194 | 1.241 | 8 | 8 |
| (1,50) | sb-burst-compute-b8 | 10999 | 7831 | 1.405 | 0.288 | 1.405 | 0 | 8 |
| (1,1) | test1 | 96 | 90 | 1.067 | 0.052 | 1.055 | 2 | 2 |
| (1,1) | test2 | 119 | 111 | 1.072 | 0.050 | 1.053 | 2 | 2 |

All 60 runs (both builds, three latency settings, four depths) pass their self-checks.

What the numbers say:
- **(50,50), the required baseline:** speedup is about 1.00–1.01, as Amdahl predicts. A store
  waits 50 cycles, but the next fetch also takes 50 cycles and runs at the same time, so almost
  none of the store time is on the critical path (f below 1%). Counting every store-stall cycle
  would give f up to 20% and overstate the possible gain.
- **(1,50):** store time is on the critical path, and the SB removes it. For a program that only
  stores (burst-then-compute), the measured speedup equals the Amdahl limit (1.405 vs 1.405).
- **Forwarding beats the store-only limit:** test1, test2, sb-burst and sb-store-load do better
  than 1 / (1 − f) because a forwarded load also skips its 50-cycle memory read, which f does not
  count.
- sb-store-load proves each search outcome on the core: 8 forwards, and 236 partial-match stall
  cycles that still return the right value.

## Size sweep: burst-then-compute at (1,50)

Cycles (full-SB stall cycles in brackets). Each round stores B words, then runs 100 iterations of a 3-instruction ALU loop.

| Burst B | No SB | Depth 2 | Depth 4 | Depth 8 | Depth 16 |
|---|---|---|---|---|---|
| 2 | 8203 | 7411 (0) | 7411 (0) | 7411 (0) | 7411 (0) |
| 4 | 9135 | 8319 (776) | 7551 (0) | 7551 (0) | 7551 (0) |
| 8 | 10999 | 10167 (2360) | 9351 (1536) | 7831 (0) | 7831 (0) |
| 16 | 14727 | 13863 (5528) | 13047 (4704) | 11415 (3056) | 8391 (0) |

- **Too small:** when the depth is less than the burst, full-SB stalls appear and the gain drops.
- **Too big:** once the depth reaches the burst, more entries buy nothing (B = 8: depth 8 and 16
  both take 7831 cycles), yet each entry still adds a comparator to the load search.
- Depth 8 covers the bursts we see in the samples (peak 7–8) and is the default.

## Not done yet

- TODO: synthesis area and timing at depths 2, 4, 8 and 16. `store_buffer.sv` is in
  `synthesis/synthesis.ys`, but the Slang plugin for Yosys is not installed locally.
- TODO: rerun with the real fetch/data latency split in `main_memory.sv` (Daksh), then drop the
  script's edit of the private copy.
- TODO: copy-loop, FENCE and load-heavy programs once FENCE decode lands (Prabhpreet).
