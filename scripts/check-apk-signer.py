#!/usr/bin/env python3
"""Validate apksigner output after signature verification has succeeded.

Fingerprint independently read from the published v0.4.1 arm64 APK on
2026-11-10. Rotation requires an explicit update and signing-lineage review.
"""
import re
import sys

EXPECTED_SHA256 = "2e414a31434c01f6ad7cd0ed80dcdca3f9de9c3983644a150f5110ea6c7ebbcc"


def verify(output: str) -> None:
    fingerprints = re.findall(
        r"certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\b", output
    )
    signers = re.search(r"Number of signers:\s*(\d+)", output)
    if signers is None or signers[1] != "1" or not fingerprints:
        raise ValueError("Expected exactly one verified APK signer")
    if set(value.lower() for value in fingerprints) != {EXPECTED_SHA256}:
        raise ValueError("APK signer does not match the published release identity")


if __name__ == "__main__":
    try:
        verify(sys.stdin.read())
    except ValueError as error:
        sys.exit(str(error))
    print("APK signer matches the published release identity")
