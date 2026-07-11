# sidtrace

`sidplayfp`, built from pinned upstream sources with a small patch that streams
a zstd-compressed CSV of every register-changing SID chip write, annotated with
cycles since boot, since the last NMI, since the last VIC (video) IRQ, and since
the last CIA (timer) IRQ.

The fork is a single patch on a pinned `libsidplayfp` commit; the `sidplayfp`
frontend and `libresidfp` engine build unmodified. See [docs/design.md](docs/design.md).

## Build

```sh
docker build -t sidtrace .
```

## Use

```sh
# TUNE.sid in the current dir -> trace.csv.zst, 30 seconds of emulation
docker run --rm -v "$PWD:/work" sidtrace trace.csv.zst TUNE.sid -t30
```

`sidtrace OUTPUT.csv.zst TUNE.sid [sidplayfp args...]` renders the tune headlessly
and writes the trace. Equivalently, set `SIDTRACE` on a normal `sidplayfp` run:

```sh
docker run --rm -v "$PWD:/work" --entrypoint sidplayfp \
    -e SIDTRACE=/work/trace.csv.zst sidtrace -w/work/out.wav -t30 /work/TUNE.sid
```

Copyrighted C64 ROMs are not bundled; most PSID tunes play without them. Mount
your own and pass `--kernal/--basic/--chargen` if a tune needs them.

## Output

CSV columns: `cycle,cycle_since_nmi,cycle_since_video_irq,cycle_since_cia_irq,chip,reg,value`.
Unchanged writes are omitted. Full spec: [docs/csv-format.md](docs/csv-format.md).

```python
import pandas as pd
df = pd.read_csv("trace.csv.zst")
```

## Docs

- [docs/design.md](docs/design.md) — how the fork is structured and maintained.
- [docs/csv-format.md](docs/csv-format.md) — trace column reference.
- [patches/](patches) — the upstream patch.
- [tools/make_test_sid.py](tools/make_test_sid.py) — generates the CI smoke-test tune.
