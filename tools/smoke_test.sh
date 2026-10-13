#!/bin/sh
# Smoke-test a built sidtrace image end to end using a synthetic tune.
# Usage: tools/smoke_test.sh [image-tag]   (default: sidtrace)
set -eu

IMAGE=${1:-sidtrace}
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

python3 "$(dirname "$0")/make_test_sid.py" "$DIR/test.sid"

docker run --rm -v "$DIR:/work" "$IMAGE" trace.csv.zst test.sid -t5

csv="$DIR/trace.csv.zst"
[ -s "$csv" ] || { echo "FAIL: no trace produced"; exit 1; }

out=$(zstd -dc "$csv")

# Determinism: a second render of the same tune must produce a byte-identical
# trace (the power-on delay is pinned, not randomized from wall-clock time).
docker run --rm -v "$DIR:/work" "$IMAGE" trace2.csv.zst test.sid -t5
out2=$(zstd -dc "$DIR/trace2.csv.zst")
[ "$out" = "$out2" ] || { echo "FAIL: trace not reproducible across runs"; exit 1; }
header="cycle,cycle_since_nmi,cycle_since_video_irq,cycle_since_cia_irq,chip,reg,value"

echo "$out" | head -1 | grep -qx "$header" || { echo "FAIL: bad header"; exit 1; }

rows=$(echo "$out" | tail -n +2 | grep -v ",,[a-z_]*$" | grep -c . || true)
[ "$rows" -gt 20 ] || { echo "FAIL: too few rows ($rows)"; exit 1; }

# Constant volume write ($D418 = 15, reg 24) must be logged exactly once.
vol=$(echo "$out" | tail -n +2 | awk -F, '$6==24 && $7==15' | grep -c . || true)
[ "$vol" -eq 1 ] || { echo "FAIL: constant reg logged $vol times, expected 1"; exit 1; }

# At least one IRQ-delta column must be populated (this tune is CIA-driven).
irq=$(echo "$out" | tail -n +2 | awk -F, '$3!="" || $4!=""' | grep -c . || true)
[ "$irq" -gt 0 ] || { echo "FAIL: no IRQ deltas recorded"; exit 1; }

# Every CIA raise is a row.
cia=$(echo "$out" | grep -c ',0,,,cia_irq$' || true)
[ "$cia" -gt 200 ] || { echo "FAIL: too few CIA interrupt rows ($cia)"; exit 1; }

# Every RTI is a row, and handler entries and RTIs nest: the depth never goes
# negative and at most the handler running when the trace ends stays open.
rti=$(echo "$out" | grep -c ',,,rti$' || true)
[ "$rti" -gt 200 ] || { echo "FAIL: too few rti rows ($rti)"; exit 1; }
echo "$out" | awk -F, 'NR > 1 && $5 == "" {
        if ($7 ~ /_entry$/) d++; else if ($7 == "rti" && --d < 0) exit 1 }
    END { exit d > 1 }' || { echo "FAIL: interrupt entries and rti rows do not nest"; exit 1; }

# Each CIA raise is entered once.
entries=$(echo "$out" | grep -c ',,,cia_irq_entry$' || true)
[ $((cia - entries)) -le 1 ] && [ "$entries" -le "$cia" ] || {
    echo "FAIL: $cia CIA raises but $entries CIA entries"; exit 1; }

echo "PASS: $rows rows, volume logged once, $irq rows with IRQ timing, $rti nested rti rows, reproducible"
