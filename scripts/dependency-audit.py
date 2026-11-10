#!/usr/bin/env python3
"""Generate a CycloneDX inventory from pinned Pub/Go/Maven dependencies; query OSV.

Only public package names/versions are sent. A failed scan fails closed.
This inventories dependency versions, not vulnerable-function reachability.
"""
import argparse
import hashlib
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
        if module.get('Main'):
            continue
        module = module.get("Replace", module)
        if module.get('Version') in (None, '', '(devel)'):
            raise ValueError('Unversioned Go dependency; use build-info and provenance: ' + module['Path'])
        packages.append(("Go", module["Path"], module["Version"]))
    return packages


def linked_packages(text, provenance=None):
    info = json.loads(text)
    packages = []
    origins = {}
    if provenance is not None:
        if (provenance.get('schemaVersion') != 1 or
                provenance.get('goBuildInfoSha256') != hashlib.sha256(text.encode()).hexdigest()):
            raise ValueError('Native provenance does not match this build-info report')
        for item in provenance['replacements']:
            if item['module'] in origins:
                raise ValueError('Duplicate patched module origin')
            if not all(re.fullmatch(r'[0-9a-f]{64}', item[field])
                       for field in ('patchSha256', 'treeSha256')):
                raise ValueError('Missing patched source digests')
            origins[item['module']] = item
    used = set()
    for module in info["Deps"]:
        replacement = module.get('Replace')
        if replacement and replacement.get('Version') in (None, '', '(devel)'):
            origin = origins.get(module['Path'])
            if (origin is None or origin['version'] != module['Version'] or
                    origin['replacePath'] != replacement['Path']):
                raise ValueError('Unverified local Go replacement: ' + module['Path'])
            # Query the original module/version conservatively. A local patch
            # must never erase its base module or waive its version advisories.
            used.add(module['Path'])
        elif replacement:
            module = replacement
        if module.get('Version') in (None, '', '(devel)'):
            raise ValueError('Unversioned linked Go dependency: ' + module['Path'])
        packages.append(("Go", module["Path"], module["Version"]))
    if used != set(origins):
        raise ValueError('Native provenance contains a replacement absent from the binary')
    # The Go runtime itself is part of the native library too.
    runtime = re.match(r"go(\d+\.\d+\.\d+)", info["GoVersion"])
    if runtime:
        packages.append(("Go", "stdlib", runtime[1]))
    return packages


def maven_packages(text):
    report = json.loads(text)
    if report.get("configuration") != "releaseRuntimeClasspath":
        raise ValueError("Expected the resolved releaseRuntimeClasspath graph")
    packages = []
    for module in report["modules"]:
        group, name, version = (module[field] for field in ("group", "name", "version"))
        if not all(isinstance(value, str) and value for value in (group, name, version)):
            raise ValueError("Incomplete resolved Maven coordinate")
        if not all(re.fullmatch(r"[\w.-]+", value) for value in (group, name)):
            raise ValueError("Invalid Maven group or artifact")
        if (re.search(r"\s|[\[\](),]", version) or version.endswith("+")
                or version.lower().startswith("latest.")):
            raise ValueError("Maven version must be resolved, not a selector")
        packages.append(("Maven", f"{group}:{name}", version))
    if not packages:
        raise ValueError("No resolved Maven modules")
    return packages


def package_url(ecosystem, name, version):
    kind = {"Pub": "pub", "Go": "golang", "Maven": "maven"}[ecosystem]
    if ecosystem == "Maven":
        group, artifact = name.split(":")
        name = f"{group}/{artifact}"
    return f"pkg:{kind}/{quote(name, safe='/')}@{quote(version, safe='')}"


def inventory(packages):
    return {
        "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
        "components": [
            {"type": "library", "name": name, "version": version,
             "purl": package_url(ecosystem, name, version),
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
    parser.add_argument("--go-provenance", type=Path, help="Verified native source/patch manifest")
    parser.add_argument("--maven", type=Path, help="Resolved release Maven graph exported by Gradle")
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
        provenance = json.loads(args.go_provenance.read_text()) if args.go_provenance else None
        packages += linked_packages(args.go_build_info.read_text(), provenance)
    elif args.go_provenance:
        parser.error('--go-provenance requires --go-build-info')
    if args.maven:
        packages += maven_packages(args.maven.read_text())
    if args.core_version:
        packages.append(("Go", "github.com/sagernet/sing-box", args.core_version))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = inventory(packages)
    if args.go_provenance:
        origins = {item['module']: item for item in provenance['replacements']}
        for component in report['components']:
            origin = origins.get(component['name'])
            if origin and component['purl'].startswith('pkg:golang/'):
                component['properties'] += [
                    {'name': 'ferry:source-patch-sha256', 'value': origin['patchSha256']},
                    {'name': 'ferry:patched-tree-sha256', 'value': origin['treeSha256']},
                ]
    args.output.write_text(json.dumps(report, indent=2) + "\n")
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
