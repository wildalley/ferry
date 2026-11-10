"""Release guard regressions, using synthetic APKs without an Android SDK."""

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'check_apk', Path(__file__).with_name('check-apk.py'))
check_apk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_apk)


def elf(alignment=16384, address=0):
    header = bytearray(64)
    header[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<H', header, 18, 183)
    struct.pack_into('<Q', header, 32, 64)
    struct.pack_into('<HH', header, 54, 56, 1)
    segment = struct.pack('<IIQQQQQQ', 1, 5, 0, address, 0, 120, 120, alignment)
    return header + segment


class ApkChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'test.apk'
        self.entries = {
            f'lib/arm64-v8a/{name}': elf()
            for name in ('libbox.so', 'libapp.so', 'libflutter.so')
        }

    def check(self, core_provenance=None):
        with zipfile.ZipFile(self.path, 'w') as archive:
            for name, body in self.entries.items():
                archive.writestr(name, body)
        with contextlib.redirect_stdout(io.StringIO()):
            check_apk.check(self.path, core_provenance)

    def test_packaged_core_matches_audited_provenance(self):
        provenance = Path(self.directory.name) / 'sources.json'
        provenance.write_text(json.dumps({'schemaVersion': 1,
            'nativeBinarySha256': hashlib.sha256(self.entries['lib/arm64-v8a/libbox.so']).hexdigest()}))
        self.check(provenance)
        self.entries['lib/arm64-v8a/libbox.so'] += b'altered'
        with self.assertRaisesRegex(ValueError, 'does not match'):
            self.check(provenance)

    def test_complete_runtime(self):
        self.check()

    def test_missing_core(self):
        del self.entries['lib/arm64-v8a/libbox.so']
        with self.assertRaisesRegex(ValueError, 'missing runtime'):
            self.check()

    def test_extra_abi(self):
        self.entries['lib/x86_64/libflutter.so'] = elf()
        with self.assertRaisesRegex(ValueError, 'expected only arm64'):
            self.check()

    def test_empty_core(self):
        self.entries['lib/arm64-v8a/libbox.so'] = b''
        with self.assertRaisesRegex(ValueError, 'empty runtime'):
            self.check()

    def test_debug_kernel(self):
        self.entries['assets/flutter_assets/kernel_blob.bin'] = b'debug'
        with self.assertRaisesRegex(ValueError, 'debug kernel_blob'):
            self.check()

    def test_plugin_with_4k_pages(self):
        self.entries['lib/arm64-v8a/libplugin.so'] = elf(4096)
        with self.assertRaisesRegex(ValueError, 'not 16 KiB aligned'):
            self.check()

    def test_misaligned_load_address(self):
        self.entries['lib/arm64-v8a/libbox.so'] = elf(address=4096)
        with self.assertRaisesRegex(ValueError, 'not 16 KiB aligned'):
            self.check()

    def test_truncated_program_header(self):
        self.entries['lib/arm64-v8a/libbox.so'] = elf()[:-1]
        with self.assertRaisesRegex(ValueError, 'invalid ELF program headers'):
            self.check()

    def test_wrong_machine(self):
        self.entries['lib/arm64-v8a/libbox.so'][18] = 62  # x86-64
        with self.assertRaisesRegex(ValueError, 'expected arm64 ELF64'):
            self.check()


if __name__ == '__main__':
    unittest.main()
