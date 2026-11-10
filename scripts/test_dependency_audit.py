import importlib.util
import copy
import hashlib
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "audit", Path(__file__).with_name("dependency-audit.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class InventoryTests(unittest.TestCase):
    def patched_fixture(self, replacement_version='(devel)'):
        info = json.dumps({'GoVersion': 'go1.27.3-X:nojsonv2', 'Deps': [{
            'Path': 'example.org/quic', 'Version': 'v1.2.3',
            'Replace': {'Path': './ferry-patched/quic', 'Version': replacement_version},
        }]})
        provenance = {'schemaVersion': 1,
                      'goBuildInfoSha256': hashlib.sha256(info.encode()).hexdigest(),
                      'replacements': [{'module': 'example.org/quic', 'version': 'v1.2.3',
                                        'replacePath': './ferry-patched/quic',
                                        'patchSha256': 'a' * 64, 'treeSha256': 'b' * 64}]}
        return info, provenance

    def test_local_patch_keeps_the_base_module_in_scans(self):
        for version in ('(devel)', '', None):
            info, provenance = self.patched_fixture(version)
            self.assertEqual(audit.linked_packages(info, provenance),
                             [('Go', 'example.org/quic', 'v1.2.3'), ('Go', 'stdlib', '1.27.3')])
            with self.assertRaises(ValueError):
                audit.linked_packages(info)

    def test_mismatched_patch_provenance_fails_closed(self):
        info, provenance = self.patched_fixture()
        cases = []
        for key, value in [('version', 'v1.0.0'), ('replacePath', '../other'),
                           ('treeSha256', ''), ('module', 'other.org/module')]:
            altered = copy.deepcopy(provenance)
            altered['replacements'][0][key] = value
            cases.append(altered)
        altered = copy.deepcopy(provenance)
        altered['goBuildInfoSha256'] = '0' * 64
        cases.append(altered)
        altered = copy.deepcopy(provenance)
        altered['replacements'] *= 2
        cases.append(altered)
        for item in cases:
            with self.subTest(item=item), self.assertRaises(ValueError):
                audit.linked_packages(info, item)

    def test_only_hosted_pinned_pub_packages(self):
        packages = audit.pub_packages('''packages:
  http:
    dependency: "direct main"
    description:
      name: http
    source: hosted
    version: "1.6.0"
  flutter:
    dependency: "direct main"
    source: sdk
    version: "0.0.0"
sdks:
  dart: ">=3.8.0"
''')
        self.assertEqual(packages, [("Pub", "http", "1.6.0")])

    def test_go_replacements_and_concatenated_json(self):
        result = audit.go_packages('''{"Path":"main","Main":true}
{"Path":"old","Version":"v1.0.0","Replace":{"Path":"new","Version":"v1.2.3"}}
''')
        self.assertEqual(result, [("Go", "new", "v1.2.3")])

    def test_inventory_is_deduplicated(self):
        data = audit.inventory([("Pub", "http", "1.6.0")] * 2)
        self.assertEqual(len(data["components"]), 1)
        self.assertEqual(data["components"][0]["purl"], "pkg:pub/http@1.6.0")

    def test_module_inventory_rejects_unverified_local_replacements(self):
        for version in ('(devel)', '', None):
            module = {'Path': 'example.org/quic', 'Version': 'v1.2.3',
                      'Replace': {'Path': '../local', 'Version': version}}
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'Unversioned'):
                audit.go_packages(json.dumps(module))

    def test_resolved_android_dependencies_use_maven_coordinates(self):
        report = {"configuration": "releaseRuntimeClasspath", "modules": [
            {"group": "androidx.core", "name": "core-ktx", "version": "1.15.0"},
            {"group": "com.google.guava", "name": "guava", "version": "33.4.0-android"},
        ]}
        packages = audit.maven_packages(json.dumps(report))
        self.assertEqual(packages[0], ("Maven", "androidx.core:core-ktx", "1.15.0"))
        self.assertEqual(audit.inventory(packages)["components"][0]["purl"],
                         "pkg:maven/androidx.core/core-ktx@1.15.0")

    def test_incomplete_or_unresolved_android_graph_fails_closed(self):
        invalid = [
            {"configuration": "debugRuntimeClasspath", "modules": []},
            {"configuration": "releaseRuntimeClasspath", "modules": []},
        ]
        for version in ("", "1.+", "[1,2)", "latest.release", "1.0 bad"):
            invalid.append({"configuration": "releaseRuntimeClasspath", "modules": [
                {"group": "example", "name": "library", "version": version},
            ]})
        for report in invalid:
            with self.subTest(report=report), self.assertRaises(ValueError):
                audit.maven_packages(json.dumps(report))
