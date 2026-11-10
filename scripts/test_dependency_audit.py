import importlib.util
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
