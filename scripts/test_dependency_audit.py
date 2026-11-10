import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "audit", Path(__file__).with_name("dependency-audit.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class InventoryTests(unittest.TestCase):
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
