# Trace CSV format

The trace is a zstd-compressed CSV. Decompress with `zstd -d file.csv.zst` or
read directly, e.g. `pandas.read_csv("file.csv.zst")`.

One row is emitted per SID register write **whose value differs from the last
value written to that register** (unchanged writes are omitted), and one per
interrupt raise, interrupt entry and RTI. The header row
is always present, so an all-silent run yields a header-only file.

| column | type | meaning |
|--------|------|---------|
| `cycle` | int | PHI1 clock cycles since the last C64 reset ("boot") |
| `cycle_since_nmi` | int / empty | cycles since the last NMI was raised; empty until the first NMI |
| `cycle_since_video_irq` | int / empty | cycles since the last VIC-II (raster) IRQ; empty until the first |
| `cycle_since_cia_irq` | int / empty | cycles since the last CIA (timer) IRQ; empty until the first |
| `chip` | int | SID index: `0` = base `$D400`, `1` = second SID, `2` = third |
| `reg` | int | register offset `0`–`31` |
| `value` | int / name | byte written (`0`–`255`), or an interrupt event name |

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
- **Interrupt rows.** Every interrupt raise is also a row with empty `chip`
  and `reg` and `value` = `nmi`, `video_irq` or `cia_irq`; its own delta
  column is `0`. A play call that changes no register still shows its
  interrupt, so frames are the interrupts themselves.
- **Interrupt entry rows.** When the CPU commits to an interrupt sequence (the
  cycle it pushes the return address low byte and picks the vector) it logs
  `nmi_entry` (vector `$FFFA`), `video_irq_entry` or `cia_irq_entry` (a hardware
  IRQ through `$FFFE`) or `brk_entry` (a `BRK` instruction through `$FFFE`).
  An NMI that arrives before that cycle hijacks an IRQ or `BRK` sequence and is
  logged as `nmi_entry`. An IRQ entry names the source that pulled the line
  low: the earliest raise still asserting it, or the last source to assert it if
  the line was released during the interrupt latency.
- **Raise versus entry.** A raise is the line assertion; the entry follows it
  after the current instruction completes (an NMI is edge-triggered and always
  taken; an IRQ is level-triggered and held while the I flag is set, so it can
  be entered long after its raise, e.g. after the running handler's `RTI`, or
  never, if it is acknowledged first). A raise that arrives while another IRQ
  source already holds the line is logged but causes no entry of its own.
- **RTI rows.** Every `RTI` instruction is a row with value `rti`, logged before
  the CPU checks for a pending interrupt, so an interrupt taken straight after
  the return follows its `rti` row.
- **Handler nesting.** Pushing each `*_entry` and popping on each `rti` rebuilds
  the stack of running handlers; the innermost (top) one executes every write
  until the next interrupt row. A `brk_entry` frame runs on behalf of the
  context that executed the `BRK`.
- Change detection uses the same per-register last-written cache the emulator
  already maintains, across all 32 register offsets.
