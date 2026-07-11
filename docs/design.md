# Design

## Goal

Add a "trace every changing SID write, with cycle/interrupt timing" feature to
`sidplayfp` in a way that is trivial to keep current with upstream.

## Maintenance model

The fork is a **single patch** (`patches/0001-sid-write-trace.patch`) applied to
a pinned upstream `libsidplayfp` commit during the Docker build. The `sidplayfp`
frontend and the `libresidfp` engine are built **unmodified** from pinned
commits. To follow upstream, bump the `*_SHA` build args in the `Dockerfile`
and, if the patch no longer applies, refresh it.

Upstream revisions are pinned via `Dockerfile` build args:

- `LIBRESIDFP_SHA`, `LIBSIDPLAYFP_SHA`, `SIDPLAYFP_SHA`.

## Where the patch hooks in

All logic lives inside `libsidplayfp`; the frontend is untouched. The tracer is
enabled by the `SIDTRACE` environment variable (path to the output file), so no
CLI/config/public-API surface changes are needed.

| Concern | Location | Change |
|---------|----------|--------|
| Compressed CSV writer | `src/sidtrace.h` (new, header-only) | Streams rows through zstd; header-only so no build source-list edits. |
| Register change detection + row emit | `src/c64/c64sid.h` `poke()` | Already caches `lastpoke[]`; log only when `value != lastpoke[reg]`. |
| Chip cycle clock | `src/c64/c64sid.h` | `EventScheduler::getTime(PHI1)`. |
| NMI timestamp | `src/c64/c64.h` `interruptNMI()` | Record cycle when NMI raised. |
| IRQ source split | `src/c64/c64env.h`, `c64cia.h`, `c64vic.h`, `c64.h` | `interruptIRQ()` gains an `irq_source_t` so VIC vs CIA IRQs are timed separately. |
| Trace ownership / wiring | `src/c64/c64.cpp` | Creates the tracer from `$SIDTRACE`, attaches it to each SID with its chip index, clears interrupt history on reset. |
| Build | `configure.ac`, `Makefile.am` | `PKG_CHECK_MODULES(libzstd)`, link `-lzstd`. |

The tracer pointer is null unless `$SIDTRACE` is set, so an un-traced run keeps
the original hot-path cost (one extra null-pointer test per write).

## Why the environment variable

Threading a real CLI flag would require forking the frontend and touching
`SidConfig`, the player, and the C64 core. The env var keeps the entire feature
inside `libsidplayfp`, so a stock `sidplayfp` binary linked against the patched
library gains tracing transparently — the smallest possible maintenance surface.

## Headless rendering

SID writes are produced by the emulation regardless of the audio backend. To run
without a sound card, render to a WAV (`sidplayfp -w<file>`) — the emulation runs
to completion and the WAV can be discarded. The `sidtrace` wrapper does this and
cleans up automatically.
