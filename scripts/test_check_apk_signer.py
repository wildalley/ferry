import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "signer", Path(__file__).with_name("check-apk-signer.py"))
signer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signer)


class SignerTests(unittest.TestCase):
    def test_old_and_new_formats(self):
        for prefix in ("Signer #1", "V2 Signer:"):
            signer.verify(f"Number of signers: 1\n{prefix} certificate SHA-256 digest: {signer.EXPECTED_SHA256}")

    def test_rejects_missing_debug_other_and_multiple_signers(self):
        for output in ("", "CN=Android Debug", "Number of signers: 1\ncertificate SHA-256 digest: " + "0" * 64,
                       "Number of signers: 2\ncertificate SHA-256 digest: " + signer.EXPECTED_SHA256):
            with self.assertRaises(ValueError):
                signer.verify(output)
