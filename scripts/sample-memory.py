#!/usr/bin/env python3
"""Record Linux process memory/FD/thread trends without reading app content.

Example: python3 scripts/sample-memory.py --pid 123 --pid 456 --duration 7200
Run separately for visible, logs, and hidden-window scenarios on the same build.
"""
import argparse
import csv
from datetime import datetime, timezone
from pathlib import Path
import time


def sample(pid):
    root = Path(f"/proc/{pid}")
    values = {}
    for filename in ("status", "smaps_rollup"):
        try:
            for line in (root / filename).read_text().splitlines():
                key, sep, value = line.partition(":")
                fields = value.strip().split()
                if sep and fields and fields[0].isdigit():
                    values[key] = int(fields[0])
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            pass
    try:
        fd_count = len(list((root / "fd").iterdir()))
    except (PermissionError, FileNotFoundError, ProcessLookupError):
        fd_count = None
    return [pid, values.get("VmRSS"), values.get("Pss"),
            values.get("Private_Dirty"), values.get("Threads"), fd_count]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, action="append", required=True)
    parser.add_argument("--duration", type=float, default=600)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--output", type=Path, default=Path("build/memory.csv"))
    args = parser.parse_args()
    if args.interval <= 0 or args.duration < 0 or any(p <= 0 for p in args.pid):
        parser.error("PIDs and interval must be positive; duration must be nonnegative")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with args.output.open("w") as stream:
        writer = csv.writer(stream)
        writer.writerow(["utc", "elapsed_s", "pid", "rss_kib", "pss_kib",
                         "private_dirty_kib", "threads", "fds"])
        while True:
            elapsed = time.monotonic() - start
            for pid in args.pid:
                writer.writerow([datetime.now(timezone.utc).isoformat(), round(elapsed, 3), *sample(pid)])
            stream.flush()
            if elapsed >= args.duration:
                break
            time.sleep(min(args.interval, args.duration - elapsed))
    print(args.output)


if __name__ == "__main__":
    main()
