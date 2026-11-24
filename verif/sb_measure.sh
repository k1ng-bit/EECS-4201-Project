#!/usr/bin/env bash
# Store buffer (SB) measurements. Runs programs through top_tb on a private copy
# of the core with a chosen fetch latency, data latency and SB depth, and prints
# one CSV row per program with the stall-cause counters (no waveforms).
#
# Usage: bash verif/sb_measure.sh <sb|base> <fetch lat> <data lat> <SB depth> <dir/test>...
#   sb   = this tree, with the SB
#   base = BASE_REF (default 665f355, the commit before the SB), run with this
#          tree's top_tb.sv and test programs so both builds see identical binaries
# Example: bash verif/sb_measure.sh sb 1 50 8 sb-bmarks/sb-burst sample-bmarks/test1
set -euo pipefail
MODE=$1; FLAT=$2; DLAT=$3; DEPTH=$4; shift 4
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ "$MODE" = sb ]; then
    cp -r "$REPO/code" "$REPO/verif" "$W/"
    FLAGS="-DNO_WAVES"
else
    git -C "$REPO" -c safe.directory='*' archive "${BASE_REF:-665f355}" code verif | tar -x -C "$W"
    cp "$REPO/verif/top_tb.sv" "$W/verif/"
    cp -r "$REPO/verif/tests/." "$W/verif/tests/"
    FLAGS="-DNO_WAVES -DNO_STORE_BUFFER"
fi

# shortcut: main_memory.sv uses MEM_LATENCY for both waiters, so this edits the private
# copy to give fetch and data their own latency; drop it once the waiters use
# FETCH_LATENCY and DATA_LATENCY from constants.svh.
sed -i -e "/f_wait_cnt\|insn_ready_o =/s/MEM_LATENCY/$FLAT/g" \
       -e "/d_wait_cnt\|data_ready_o =/s/MEM_LATENCY/$DLAT/g" "$W/code/main_memory.sv"
sed -i "s/parameter int SB_DEPTH = [0-9]*;/parameter int SB_DEPTH = $DEPTH;/" "$W/code/constants.svh"
grep -q "f_wait_cnt == $FLAT)" "$W/code/main_memory.sv" && grep -q "d_wait_cnt == $DLAT)" "$W/code/main_memory.sv" \
    || { echo "could not set the latencies" >&2; exit 1; }

KEYS="Total Cycles,Instructions,Final CPI,Store stalls,Store-only stalls,Load stalls,SB full stalls,SB partial stalls,SB port-busy stalls,SB forwards,SB head writes,SB peak count"
cd "$W/verif"
for t in "$@"; do
    out=$(make --no-print-directory run TEST_DIR="${t%/*}" TEST="${t#*/}" QUIET_BUILD=1 \
          EXTRA_FLAGS="$FLAGS -DTIMEOUT=20000000 -DHAS_STALL_SIGNAL -DHAS_FLUSH_SIGNAL" 2>&1 || true)
    grep -q "Test Passed" <<<"$out" && result=PASS || result=FAIL
    awk -F' *: *' -v keys="$KEYS" -v row="$MODE,$FLAT,$DLAT,$DEPTH,${t#*/},$result" \
        '{ v[$1] = $2 } END { n = split(keys, k, ","); for (i = 1; i <= n; i++) row = row "," v[k[i]]; print row }' <<<"$out"
done
