# Trace CSV format

The trace is a zstd-compressed CSV. Decompress with `zstd -d file.csv.zst` or
read directly, e.g. `pandas.read_csv("file.csv.zst")`.

One row is emitted per SID register write **whose value differs from the last
value written to that register** (unchanged writes are omitted). The header row
is always present, so an all-silent run yields a header-only file.

| column | type | meaning |
|--------|------|---------|
| `cycle` | int | PHI1 clock cycles since the last C64 reset ("boot") |
| `cycle_since_nmi` | int / empty | cycles since the last NMI was raised; empty until the first NMI |
| `cycle_since_video_irq` | int / empty | cycles since the last VIC-II (raster) IRQ; empty until the first |
| `cycle_since_cia_irq` | int / empty | cycles since the last CIA (timer) IRQ; empty until the first |
| `chip` | int | SID index: `0` = base `$D400`, `1` = second SID, `2` = third |
| `reg` | int | register offset `0`–`31` |
| `value` | int | byte written (`0`–`255`) |

## Semantics

- **Cycle clock.** `cycle` is `EventScheduler::getTime(PHI1)`, which is reset to
  zero on every C64 reset (once per tune load), so it counts cycles since that
  tune's power-on/boot sequence began.
- **Interrupt deltas** are measured from the cycle at which the interrupt line
  was *raised* (asserted), not from when the CPU vectored to the handler — the
  two differ by the CPU's interrupt latency. For a typical CIA-timer-driven
  player, `cycle_since_cia_irq` is therefore the offset of the write into the
  current play frame.
- Video (VIC) and CIA IRQs are tracked separately because a tune may use either
  or both. A column stays empty until its source fires at least once.
- Change detection uses the same per-register last-written cache the emulator
  already maintains, across all 32 register offsets.
