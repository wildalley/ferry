#!/usr/bin/env python3
"""Measure elapsed time and sampled Linux process-tree memory for a build.

Run with --no-daemon (and in-process Kotlin) so work stays in the measured
process tree. RSS sums count shared pages more than once; use PSS to compare.
Example: profile-build.py --output build/profile.json -- ./gradlew --no-daemon assembleRelease
"""
import argparse
import csv
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def sample(group, tracked):
    totals = dict(processes=0, rss_kib=0, pss_kib=0, pss_processes=0)
    processes = {}
    for root in Path('/proc').iterdir():
        if not root.name.isdigit():
            continue
        try:
            # comm may contain spaces or parentheses; fields after its final
            # ')' start at state (field 3), then ppid, pgrp, session.
            fields = (root / 'stat').read_text().rsplit(')', 1)[1].split()
            processes[int(root.name)] = (int(fields[1]), int(fields[2]), fields[19])
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    tracked.intersection_update((pid, info[2]) for pid, info in processes.items())
    while True:
        parents = {group, *(pid for pid, _ in tracked)}
        children = {(pid, info[2]) for pid, info in processes.items()
                    if info[0] in parents or info[1] == group}
        if children <= tracked:
            break
        tracked.update(children)
    for pid, _ in tracked:
        root = Path(f'/proc/{pid}')
        try:
            totals['processes'] += 1
            for line in (root / 'status').read_text().splitlines():
                if line.startswith('VmRSS:'):
                    totals['rss_kib'] += int(line.split()[1])
            for line in (root / 'smaps_rollup').read_text().splitlines():
                if line.startswith('Pss:'):
                    totals['pss_kib'] += int(line.split()[1])
                    totals['pss_processes'] += 1
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return totals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interval', type=float, default=1)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.interval <= 0:
        parser.error('Provide a command and a positive sampling interval')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    peaks = dict(processes=0, rss_kib=0, pss_kib=0)
    tracked = set()
    process = subprocess.Popen(command, start_new_session=True)
    try:
        with args.output.with_suffix('.csv').open('w') as stream:
            writer = csv.writer(stream)
            writer.writerow(['elapsed_s', 'processes', 'rss_kib', 'pss_kib', 'pss_processes'])
            while True:
                values = sample(process.pid, tracked)
                writer.writerow([round(time.monotonic() - start, 3), *values.values()])
                stream.flush()
                for key in peaks:
                    peaks[key] = max(peaks[key], values[key])
                code = process.poll()
                if code is not None:
                    break
                time.sleep(args.interval)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    result = {'elapsed_s': round(time.monotonic() - start, 3),
              'exit_code': code, 'interval_s': args.interval,
              'sampled_peaks': peaks}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
