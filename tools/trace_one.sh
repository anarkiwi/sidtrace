#!/bin/sh
# trace_one.sh HVSC_ROOT "RELPATH<TAB>SUBTUNE<TAB>LENGTH<TAB>OUTPATH"   (runs inside the sidtrace image)
# Skips work already done; writes atomically so interrupted runs resume cleanly.
hvsc=$1
IFS="$(printf '\t')" read -r rel n len out <<EOT
$2
EOT
[ -s "$out" ] && exit 0
mkdir -p "$(dirname "$out")"
tmp="$out.part"
if SIDTRACE="$tmp" sidplayfp -w/dev/null -os"$n" -t"$len" "$hvsc/$rel" >/dev/null 2>&1 && [ -s "$tmp" ]; then
    mv "$tmp" "$out"
else
    rm -f "$tmp"
    echo "FAIL $rel $n" >&2
    exit 1
fi
