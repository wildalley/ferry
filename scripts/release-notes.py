#!/usr/bin/env python3
"""Validate a release tag against pubspec and extract its reviewed changelog."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def release_notes(pubspec, changelog, tag):
    version = re.search(r'^version: (\d+\.\d+\.\d+)\+([1-9]\d*)\s*$', pubspec, re.M)
    if not version or tag != 'v' + version[1]:
        raise ValueError('Release tag must match the stable version in pubspec.yaml')
    heading = re.search(r'^## ' + re.escape(version[1]) + r'(?: — [^\n]+)?\s*$', changelog, re.M)
    if not heading:
        raise ValueError('Release needs a matching CHANGELOG.md section')
    notes = re.split(r'^## ', changelog[heading.end():], maxsplit=1, flags=re.M)[0].strip()
    if not notes:
        raise ValueError('Release notes must not be empty')
    return notes + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    notes = release_notes((ROOT / 'pubspec.yaml').read_text(),
                          (ROOT / 'CHANGELOG.md').read_text(), args.tag)
    if args.output:
        args.output.write_text(notes)
    print('Release version and changelog verified: ' + args.tag)


if __name__ == '__main__':
    main()
