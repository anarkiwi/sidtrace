#!/bin/sh
# trace_hvsc.sh [HVSC_DIR=/scratch/datasets/hvsc] [JOBS=host physical cores]
#
# Traces every HVSC subtune to its Songlengths length, in parallel inside one
# sidtrace container (one worker per physical core). Each trace is written next to its
# tune as NAME.<subtune>.csv.zst. Resumable; failures -> <repo>/.run/failed.log.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
hvsc=$(realpath "${1:-/scratch/datasets/hvsc}")
[ -d "$hvsc/C64Music" ] && hvsc=$hvsc/C64Music
run=$here/../.run
jobs=${2:-$(lscpu -p=core,socket | grep -v "^#" | sort -u | wc -l)}
mkdir -p "$run"

python3 -I "$here/hvsc_jobs.py" "$hvsc" /hvsc >"$run/jobs.tsv"
total=$(wc -l <"$run/jobs.tsv")
echo "$total subtunes, $jobs workers -> $hvsc" >&2

docker run --rm -i --user "$(id -u):$(id -g)" --entrypoint sh \
    -v "$hvsc:/hvsc" -v "$here:/tools:ro" sidtrace -c \
    "OMP_NUM_THREADS=1 xargs -d '\n' -P $jobs -n 1 /tools/trace_one.sh /hvsc" \
    <"$run/jobs.tsv" 2>"$run/failed.log" &
pid=$!
# progress: count finished traces
while kill -0 $pid 2>/dev/null; do
    printf '\r%s / %s traces' "$(find "$hvsc" -name '*.csv.zst' | wc -l)" "$total" >&2
    sleep 15
done
echo >&2
echo "failures: $(wc -l <"$run/failed.log") (see $run/failed.log)" >&2
