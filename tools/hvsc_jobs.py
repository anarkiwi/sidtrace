#!/usr/bin/env python3
"""Emit one tab-separated job per HVSC subtune: relpath, subtune, length, outpath.

Lengths come from DOCUMENTS/Songlengths.md5 (path comment line, then
md5=len1 len2 ...), so every subtune is rendered to its documented length.
"""
import argparse
import sys
from pathlib import Path


def jobs(hvsc, out):
    db = hvsc / "DOCUMENTS" / "Songlengths.md5"
    path = None
    for line in db.read_text(encoding="latin-1").splitlines():
        if line.startswith("; /"):
            path = line[3:]
        elif path and "=" in line and not line.startswith("["):
            for n, length in enumerate(line.split("=", 1)[1].split(), 1):
                yield path, n, length, f"{out}/{path[:-4]}.{n}.csv.zst"
            path = None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("hvsc", nargs="?", default="/scratch/datasets/hvsc")
    ap.add_argument("out", nargs="?", default="traces")
    a = ap.parse_args()
    root = Path(a.hvsc)
    if (root / "C64Music").is_dir():
        root = root / "C64Music"
    for j in jobs(root, a.out):
        sys.stdout.write("\t".join(map(str, j)) + "\n")


if __name__ == "__main__":
    main()
