#!/usr/bin/env python3
"""Generate a tiny, non-copyrighted PSID used to smoke-test SID write tracing.

The tune's play routine runs once per driver IRQ and:
  * writes an incrementing counter to $D400 (changes every frame -> always logged)
  * writes a constant $0F to $D418 (unchanged after the first frame -> logged once)

This exercises both the register change-detection and the cycle/IRQ columns.
"""
import struct
import sys

LOAD = 0x1000
INIT = 0x1000
PLAY = 0x1010

# 6502 machine code laid out from LOAD.
INIT_CODE = bytes(
    [
        0xA9, 0x00,        # lda #$00
        0x85, 0x10,        # sta $10        ; frame counter
        0x8D, 0x00, 0xD4,  # sta $d400      ; silence voice 1 freq lo
        0x60,              # rts
    ]
)
PLAY_CODE = bytes(
    [
        0xE6, 0x10,        # inc $10
        0xA5, 0x10,        # lda $10
        0x8D, 0x00, 0xD4,  # sta $d400      ; changes every frame
        0xA9, 0x0F,        # lda #$0f
        0x8D, 0x18, 0xD4,  # sta $d418      ; volume, constant -> logged once
        0x60,              # rts
    ]
)


def build() -> bytes:
    body = bytearray(INIT_CODE)
    body += b"\xea" * (PLAY - INIT - len(INIT_CODE))  # pad to PLAY with NOPs
    body += PLAY_CODE
    data = struct.pack("<H", LOAD) + bytes(body)  # C64 load address, little-endian

    header = struct.pack(
        ">4sHHHHHHHI32s32s32sHBBBB",
        b"PSID",   # magic
        2,         # version
        0x7C,      # data offset
        0,         # load address (0 -> taken from first two data bytes)
        INIT,      # init address
        PLAY,      # play address
        1,         # songs
        1,         # start song
        1,         # speed: bit0 set -> CIA1 timer drives the play IRQ
        b"sidtrace test tune",
        b"sidtrace",
        b"2026 public domain",
        0,         # flags
        0, 0,      # start page, page length
        0, 0,      # second/third SID address
    )
    assert len(header) == 0x7C, len(header)
    return header + data


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "test.sid"
    with open(out, "wb") as fh:
        fh.write(build())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
