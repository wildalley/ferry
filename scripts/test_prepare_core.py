"""Source provenance must reject stale or modified local replacements."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prepare_core', Path(__file__).with_name('prepare-core.py'))
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


class SourceProvenanceTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.source = Path(directory.name)
        self.module = self.source / 'ferry-patched/quic'
        self.module.mkdir(parents=True)
        (self.module / 'source.go').write_text('package quic\n')
        item = {'module': 'example.org/quic', 'version': 'v1.2.3',
                'directory': 'ferry-patched/quic', 'treeSha256': core.tree_digest(self.module)}
        (self.source / 'ferry-sources.json').write_text(json.dumps({'modules': [item]}))
        self.info = {'GoVersion': 'go' + core.PINS['goVersion'] + '-X:nojsonv2',
                     'Settings': [{'Key': 'GOEXPERIMENT', 'Value': 'nojsonv2'}],
                     'Deps': [{'Path': item['module'], 'Version': item['version'],
                               'Replace': {'Path': './ferry-patched/quic', 'Version': '(devel)'}}]}
        self.build_info = self.source / 'info.json'
        self.binary = self.source / 'core.bin'
        self.binary.write_bytes(b'fixture native binary')
        self.output = self.source / 'output.json'

    def record(self):
        self.build_info.write_text(json.dumps(self.info))
        with contextlib.redirect_stdout(io.StringIO()):
            core.record(self.source, self.build_info, self.binary, self.output)

    def test_record_binds_native_binary_and_build_info(self):
        self.record()
        output = json.loads(self.output.read_text())
        self.assertEqual(output['nativeBinarySha256'], hashlib.sha256(self.binary.read_bytes()).hexdigest())
        self.assertEqual(output['goBuildInfoSha256'], hashlib.sha256(self.build_info.read_bytes()).hexdigest())
        self.assertEqual(output['replacements'][0]['version'], 'v1.2.3')

    def test_changed_source_rejected(self):
        (self.module / 'source.go').write_text('package altered\n')
        with self.assertRaisesRegex(ValueError, 'changed after preparation'):
            self.record()

    def test_wrong_replacement_rejected(self):
        self.info['Deps'][0]['Replace']['Path'] = '../other'
        with self.assertRaisesRegex(ValueError, 'outside prepared'):
            self.record()

    def test_missing_linked_patch_rejected(self):
        self.info['Deps'] = []
        with self.assertRaisesRegex(ValueError, 'missing from the linked binary'):
            self.record()

    def test_existing_checkout_preserved(self):
        before = core.tree_digest(self.source)
        with self.assertRaisesRegex(ValueError, 'existing work is preserved'):
            core.prepare(self.source)
        self.assertEqual(before, core.tree_digest(self.source))

    def test_pinned_patch_digests(self):
        for item in [core.PINS['core'], *core.PINS['modulePatches']]:
            core.checked_patch(item)

    def test_patch_ignores_windows_checkout_newline_setting(self):
        repository = self.source / 'checkout'
        repository.mkdir()
        subprocess.run(['git', 'init', '-q', str(repository)], check=True)
        subprocess.run(['git', '-C', str(repository), 'config', 'core.autocrlf', 'true'], check=True)
        (repository / 'input.txt').write_bytes(b'old\n')
        patch = self.source / 'input.patch'
        patch.write_bytes(b'--- a/input.txt\n+++ b/input.txt\n@@ -1 +1 @@\n-old\n+new\n')
        core.apply_checked_patch(repository, {'patch': str(patch), 'patchSha256': core.digest(patch)})
        self.assertEqual((repository / 'input.txt').read_bytes(), b'new\n')

    def test_tree_digest_uses_case_sensitive_relative_names(self):
        (self.module / 'Z.go').write_bytes(b'upper')
        (self.module / 'a.go').write_bytes(b'lower')
        expected = hashlib.sha256()
        for name in ('Z.go', 'a.go', 'source.go'):
            expected.update(name.encode() + b'\0')
            expected.update(bytes.fromhex(core.digest(self.module / name)))
        self.assertEqual(core.tree_digest(self.module), expected.hexdigest())
