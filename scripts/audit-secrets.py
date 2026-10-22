#!/usr/bin/env python3
"""Fail on known local configuration values or common credential signatures.
Never print matched values. --history also checks every reachable Git blob.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = [
    rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    rb"\bgh[pousr]_[A-Za-z0-9]{30,}",
    rb"\bgithub_pat_[A-Za-z0-9_]{30,}",
    rb"\bAIza[A-Za-z0-9_-]{30,}",
    rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{30,}",
    rb"\bAKIA[A-Z0-9]{16}\b",
]

def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    local_values = []
    for file in ROOT.glob(".env*"):
        if file.name == ".env.example" or not file.is_file():
            continue
        for line in file.read_text().splitlines():
            if line.lstrip().startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            value = value.strip().strip("\"'")
            if len(value) >= 8 and (any(part in name.upper() for part in ("KEY", "TOKEN", "SECRET", "PASSWORD")) or name.strip() == "TRANSLATION_API_URL"):
                local_values.append(value.encode())
    def matches(data):
        return any(value in data for value in local_values) or any(re.search(pattern, data) for pattern in PATTERNS)
    failures = []
    files = git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0")
    for raw in set(files):
        if not raw:
            continue
        name = raw.decode(); file = ROOT / name
        if Path(name).name.startswith(".env") and Path(name).name != ".env.example":
            failures.append("tracked environment file: " + name)
        elif file.is_file() and matches(file.read_bytes()):
            failures.append("working file: " + name)
    objects = 0
    if args.history:
        for line in git("rev-list", "--objects", "--all").splitlines():
            oid, _, name = line.partition(b" ")
            if git("cat-file", "-t", oid.decode()).strip() != b"blob":
                continue
            objects += 1
            if matches(git("cat-file", "blob", oid.decode())):
                failures.append("Git history blob: " + name.decode(errors="replace"))
    bundle = args.bundle
    if bundle:
        if not bundle.is_dir():
            parser.error("bundle directory does not exist")
        for file in bundle.rglob("*"):
            if file.is_file() and (file.name.startswith(".env") or matches(file.read_bytes())):
                failures.append("app bundle: " + str(file.relative_to(bundle)))
    if failures:
        print("Secret audit FAILED (values redacted):", file=sys.stderr)
        print("\n".join(sorted(set(failures))), file=sys.stderr)
        return 1
    print(f"Secret audit passed: working files, {objects} history blobs, " + ("and app bundle." if bundle else "no bundle requested."))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
