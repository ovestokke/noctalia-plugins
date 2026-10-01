#!/usr/bin/env python3
"""Build the bundled Linux helpers, or verify their reproducibility with --check."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "nodus/helper"
BUNDLE = ROOT / "nodus/bin"
VERSION = (HELPER / "toolchain.txt").read_text().strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="rebuild and compare without changing the bundle")
    args = parser.parse_args()
    env = os.environ | {
        "GOTOOLCHAIN": "go" + VERSION,
        "GOENV": "off",
        "GOFLAGS": "",
        "GOWORK": "off",
        "GOEXPERIMENT": "",
        "CGO_ENABLED": "0",
        "GOOS": "linux",
        "GOAMD64": "v1",
        "GOARM64": "v8.0",
    }
    with tempfile.TemporaryDirectory(prefix="nodus-build-") as tmp:
        output = Path(tmp)
        names = []
        for arch in ("amd64", "arm64"):
            name = f"nodus-noctalia-linux-{arch}"
            subprocess.run(
                ["go", "build", "-trimpath", "-buildvcs=false", "-ldflags=-s -w", "-o", str(output / name), "."],
                cwd=HELPER, env=env | {"GOARCH": arch}, check=True,
            )
            (output / name).chmod(0o755)
            names.append(name)
        goroot = subprocess.check_output(["go", "env", "GOROOT"], cwd=HELPER, env=env, text=True).strip()
        shutil.copyfile(Path(goroot) / "LICENSE", output / "GO-LICENSE")
        sums = "".join(f"{hashlib.sha256((output / name).read_bytes()).hexdigest()}  {name}\n" for name in names)
        (output / "SHA256SUMS").write_text(sums)
        for name in [*names, "GO-LICENSE", "SHA256SUMS"]:
            built, bundled = output / name, BUNDLE / name
            if args.check:
                if not bundled.is_file() or bundled.read_bytes() != built.read_bytes():
                    raise SystemExit(f"Stale or missing {bundled.relative_to(ROOT)}; run python3 tools/build_nodus.py")
                if name in names and bundled.stat().st_mode & 0o111 != 0o111:
                    raise SystemExit(f"Not executable: {bundled.relative_to(ROOT)}")
            else:
                BUNDLE.mkdir(parents=True, exist_ok=True)
                shutil.copy2(built, bundled)
    print("Nodus bundle verified." if args.check else "Nodus bundle built. Commit nodus/bin with the source changes.")


if __name__ == "__main__":
    main()
