"""Reject wrong/missing release notes before a public tag can publish assets."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('release_notes', Path(__file__).with_name('release-notes.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseNotesTests(unittest.TestCase):
    def test_extracts_only_the_requested_release(self):
        self.assertEqual(module.release_notes(
            'version: 0.4.2+23\n',
            '# Changelog\n\n## 0.4.2 — 2026-11-10\n\n### 中文\n修复\n\n### English\nFix\n\n## 0.4.1\nOld\n',
            'v0.4.2'), '### 中文\n修复\n\n### English\nFix\n')

    def test_rejects_mismatched_or_partial_tags(self):
        for tag in ['v0.4.1', 'v0.4.20', '0.4.2', 'v0.4.2-rc.1']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                module.release_notes('version: 0.4.2+23\n', '## 0.4.2\nNotes', tag)

    def test_rejects_missing_or_empty_section(self):
        for changelog in ['## 0.4.20\nOther', '## 0.4.2\n\n## 0.4.1\nOld']:
            with self.subTest(changelog=changelog), self.assertRaises(ValueError):
                module.release_notes('version: 0.4.2+23\n', changelog, 'v0.4.2')

    def test_requires_a_positive_android_build_number(self):
        for value in ['0.4.2', '0.4.2+0', '0.4.2+bad']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.release_notes('version: ' + value, '## 0.4.2\nNotes', 'v0.4.2')


if __name__ == '__main__':
    unittest.main()
