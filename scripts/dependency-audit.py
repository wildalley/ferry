#!/usr/bin/env python3
"""Generate a CycloneDX inventory from pinned Pub/Go dependencies; query OSV.

Only public package names/versions are sent. A failed scan fails closed.
This inventories dependencies, not reachability or Android transitive artifacts.
"""
import argparse
import json
from pathlib import Path
import re
import sys
from urllib.parse import quote
from urllib.request import Request, urlopen


def pub_packages(text):
    # pubspec.lock has a fixed generated structure. Avoid a YAML dependency in CI.
    packages = []
    for match in re.finditer(r"^  ([\w-]+):\n((?:^    .*\n|^\n)+)", text, re.M):
        name, block = match.groups()
        if not re.search(r"^    source: hosted$", block, re.M):
            continue
        version = re.search(r'^    version: "([^"]+)"$', block, re.M)
        if version is None:
            raise ValueError(f"No pinned version for {name}")
        packages.append(("Pub", name, version[1]))
    if not packages:
        raise ValueError("No hosted Pub packages parsed")
    return packages


def go_packages(text):
    decoder, offset, packages = json.JSONDecoder(), 0, []
    while text[offset:].strip():
        offset += len(text[offset:]) - len(text[offset:].lstrip())
        module, offset = decoder.raw_decode(text, offset)
        module = module.get("Replace", module)
        if module.get("Version"):
            packages.append(("Go", module["Path"], module["Version"]))
    return packages


def linked_packages(text):
    info = json.loads(text)
    packages = []
    for module in info["Deps"]:
        module = module.get("Replace", module)
        packages.append(("Go", module["Path"], module["Version"]))
    # The Go runtime itself is part of the native library too.
    runtime = re.match(r"go(\d+\.\d+\.\d+)", info["GoVersion"])
    if runtime:
        packages.append(("Go", "stdlib", runtime[1]))
    return packages


def inventory(packages):
    return {
        "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
        "components": [
            {"type": "library", "name": name, "version": version,
             "purl": f"pkg:{'pub' if ecosystem == 'Pub' else 'golang'}/{quote(name, safe='/')}@{quote(version, safe='')}",
             "properties": [{"name": "ferry:ecosystem", "value": ecosystem}]}
            for ecosystem, name, version in sorted(set(packages))
        ],
    }


def scan(packages):
    findings = []
    packages = sorted(set(packages))
    for start in range(0, len(packages), 100):
        batch = packages[start:start + 100]
        query = {"queries": [{"package": {"ecosystem": e, "name": n}, "version": v}
                              for e, n, v in batch]}
        request = Request("https://api.osv.dev/v1/querybatch",
                          data=json.dumps(query).encode(),
                          headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
        if len(result.get("results", [])) != len(batch):
            raise ValueError("Incomplete OSV response")
        for package, result in zip(batch, result["results"]):
            ids = [v["id"] for v in result.get("vulns", [])]
            if ids:
                findings.append({"ecosystem": package[0], "name": package[1],
                                 "version": package[2], "vulnerabilities": ids})
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path("pubspec.lock"))
    parser.add_argument("--go-modules", type=Path)
    parser.add_argument("--go-build-info", type=Path)
    parser.add_argument("--core-version", help="Pinned sing-box source/release tag")
    parser.add_argument("--output", type=Path, default=Path("build/dependencies.cdx.json"))
    parser.add_argument("--scan", action="store_true")
    parser.add_argument("--report-only", action="store_true",
                        help="Report known advisories without failing a development build")
    args = parser.parse_args()
    packages = pub_packages(args.lock.read_text())
    if args.go_modules:
        packages += go_packages(args.go_modules.read_text())
    if args.go_build_info:
        packages += linked_packages(args.go_build_info.read_text())
    if args.core_version:
        packages.append(("Go", "github.com/sagernet/sing-box", args.core_version))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory(packages), indent=2) + "\n")
    print(f"Inventoried {len(set(packages))} pinned dependencies: {args.output}")
    if args.scan:
        findings = scan(packages)
        report = args.output.with_suffix(".osv.json")
        report.write_text(json.dumps({"findings": findings}, indent=2) + "\n")
        if findings:
            print(json.dumps(findings, indent=2))
            print("::warning::Pinned dependency advisories require review before release")
            return 0 if args.report_only else 1
        print("OSV: no known advisories returned for these pinned versions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
