#!/usr/bin/env python3
"""Check the arm64 runtime is complete and expose APK size regressions in CI."""

import argparse
from pathlib import Path
import struct
import zipfile


def check_native_alignment(archive: zipfile.ZipFile, entry: zipfile.ZipInfo) -> None:
    """Check ELF load segments; ZIP alignment alone cannot detect a 4 KiB .so."""
    with archive.open(entry) as library:
        header = library.read(64)
        if (len(header) != 64 or header[:6] != b'\x7fELF\x02\x01'
                or struct.unpack_from('<H', header, 18)[0] != 183):
            raise ValueError(f'{entry.filename}: expected arm64 ELF64 library')
        offset = struct.unpack_from('<Q', header, 32)[0]
        size, count = struct.unpack_from('<HH', header, 54)
        if size != 56 or count == 0 or offset + size * count > entry.file_size:
            raise ValueError(f'{entry.filename}: invalid ELF program headers')
        library.seek(offset)
        loads = 0
        for _ in range(count):
            segment = library.read(size)
            if struct.unpack_from('<I', segment)[0] != 1:  # PT_LOAD
                continue
            loads += 1
            file_offset, address = struct.unpack_from('<QQ', segment, 8)
            alignment = struct.unpack_from('<Q', segment, 48)[0]
            if (alignment < 16384 or alignment & (alignment - 1)
                    or (address - file_offset) % 16384):
                raise ValueError(f'{entry.filename}: LOAD segment is not 16 KiB aligned')
        if not loads:
            raise ValueError(f'{entry.filename}: no ELF LOAD segments')


def check(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = {entry.filename for entry in entries}
        abis = {
            name.split('/')[1]
            for name in names
            if name.startswith('lib/') and name.endswith('.so')
        }
        if abis != {'arm64-v8a'}:
            raise ValueError(f'expected only arm64-v8a, found {sorted(abis)}')
        required = {
            f'lib/arm64-v8a/{name}'
            for name in ('libbox.so', 'libapp.so', 'libflutter.so')
        }
        if required - names:
            raise ValueError(f'missing runtime libraries: {sorted(required - names)}')
        if any(archive.getinfo(name).file_size == 0 for name in required):
            raise ValueError('empty runtime library')
        if any(name.endswith('/kernel_blob.bin') for name in names):
            raise ValueError('debug kernel_blob.bin in release APK')
        for entry in entries:
            if entry.filename.startswith('lib/') and entry.filename.endswith('.so'):
                check_native_alignment(archive, entry)
        print(f'{path.name}: {path.stat().st_size / 2**20:.2f} MiB APK')
        print('  arm64 runtime complete; all ELF LOAD segments support 16 KiB pages')
        print('  MiB in APK / unpacked MiB / entry')
        for entry in sorted(entries, key=lambda item: item.compress_size, reverse=True)[:10]:
            print(f'  {entry.compress_size / 2**20:8.2f} / '
                  f'{entry.file_size / 2**20:12.2f} / {entry.filename}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apks', type=Path, nargs='+')
    args = parser.parse_args()
    for path in args.apks:
        try:
            check(path)
        except (OSError, ValueError, zipfile.BadZipFile) as error:
            parser.exit(1, f'{path.name}: {error}\n')


if __name__ == '__main__':
    main()
