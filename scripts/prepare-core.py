#!/usr/bin/env python3
"""Prepare pinned native sources and record local module patches explicitly.

Only a fresh/empty source directory is accepted. Go's shared module cache is
never modified. Local replacements retain their base version in security scans
and carry source/patch digests; unknown replacements fail the inventory step.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PINS = json.loads((ROOT / 'scripts/core-pins.json').read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root):
    result = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Unexpected symlink in patched module: {path}')
        if path.is_file():
            result.update(path.relative_to(root).as_posix().encode() + b'\0')
            result.update(bytes.fromhex(digest(path)))
    return result.hexdigest()


def run(*args, cwd=None, capture=False):
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def checked_patch(item):
    path = ROOT / item['patch']
    if digest(path) != item['patchSha256']:
        raise ValueError(f'Patch digest mismatch: {item["patch"]}')
    return path


def prepare(source, cache=None):
    if source.exists() and any(source.iterdir()):
        raise ValueError('Use a fresh/empty source directory; existing work is preserved')
    version = run('go', 'env', 'GOVERSION', capture=True)
    if version.split('-X:', 1)[0] != 'go' + PINS['goVersion']:
        raise ValueError(f'Expected Go {PINS["goVersion"]}, found {version}')
    core = PINS['core']
    for variable, expected in [('SINGBOX_TAG', core['tag']),
                               ('SINGBOX_COMMIT', core['commit']),
                               ('GOMOBILE_VERSION', PINS['gomobileVersion'])]:
        if os.environ.get(variable, expected) != expected:
            raise ValueError(f'{variable} must match scripts/core-pins.json')
    if cache:
        run('git', '-c', 'core.autocrlf=false', 'clone', '--no-hardlinks',
            '--no-checkout', str(cache), str(source))
        run('git', '-c', 'core.autocrlf=false', 'checkout', '--detach', core['commit'], cwd=source)
    else:
        run('git', '-c', 'core.autocrlf=false', 'clone', '--depth', '1',
            '--branch', core['tag'], 'https://github.com/SagerNet/sing-box', str(source))
    if run('git', 'rev-parse', 'HEAD', cwd=source, capture=True) != core['commit']:
        raise ValueError('Core source commit mismatch')
    patch = checked_patch(core)
    run('git', 'apply', '--check', str(patch), cwd=source)
    run('git', 'apply', str(patch), cwd=source)
    modules = []
    for item in PINS['modulePatches']:
        module = json.loads(run('go', 'mod', 'download', '-json',
                               item['module'] + '@' + item['version'], cwd=source, capture=True))
        if module.get('Sum') != item['sum']:
            raise ValueError(f'Module checksum mismatch: {item["module"]}')
        target = source / item['directory']
        shutil.copytree(module['Dir'], target)
        target.chmod(0o755)
        for path in target.rglob('*'):
            path.chmod(0o755 if path.is_dir() else 0o644)
        patch = checked_patch(item)
        run('git', 'apply', '--check', '--directory=' + item['directory'], str(patch), cwd=source)
        run('git', 'apply', '--directory=' + item['directory'], str(patch), cwd=source)
        replacement = './' + item['directory']
        run('go', 'mod', 'edit', '-replace=' + item['module'] + '=' + replacement, cwd=source)
        modules.append({**item, 'treeSha256': tree_digest(target)})
    manifest = {'schemaVersion': 1, 'goVersion': version, 'core': core, 'modules': modules}
    (source / 'ferry-sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Prepared {core["buildVersion"]}: {source}')


def record(source, build_info, binary, output):
    manifest = json.loads((source / 'ferry-sources.json').read_text())
    info = json.loads(build_info.read_text())
    if info['GoVersion'].split('-X:', 1)[0] != 'go' + PINS['goVersion']:
        raise ValueError('Binary toolchain differs from prepared sources')
    settings = {item['Key']: item['Value'] for item in info.get('Settings', [])}
    if settings.get('GOEXPERIMENT') != 'nojsonv2':
        raise ValueError('Binary must use the validated nojsonv2 experiment setting')
    manifest['binaryGoVersion'] = info['GoVersion']
    modules = {item['module']: item for item in manifest.pop('modules')}
    replacements = []
    for dependency in info['Deps']:
        replacement = dependency.get('Replace')
        if not replacement or replacement.get('Version') not in (None, '', '(devel)'):
            continue
        item = modules.get(dependency['Path'])
        if item is None or dependency['Version'] != item['version']:
            raise ValueError('Unknown local module replacement in binary')
        target = source / item['directory']
        if (source / replacement['Path']).resolve() != target.resolve():
            raise ValueError('Binary replacement points outside prepared module')
        if tree_digest(target) != item['treeSha256']:
            raise ValueError('Patched module changed after preparation')
        replacements.append({**item, 'replacePath': replacement['Path']})
    if {item['module'] for item in replacements} != set(modules):
        raise ValueError('Prepared patch is missing from the linked binary')
    manifest.update(goBuildInfoSha256=digest(build_info), nativeBinarySha256=digest(binary),
                    replacements=replacements)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Recorded native source provenance: {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prep = commands.add_parser('prepare')
    prep.add_argument('--source', type=Path, required=True)
    prep.add_argument('--source-cache', type=Path)
    rec = commands.add_parser('record')
    rec.add_argument('--source', type=Path, required=True)
    rec.add_argument('--build-info', type=Path, required=True)
    rec.add_argument('--binary', type=Path, required=True)
    rec.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'prepare':
        prepare(args.source.resolve(), args.source_cache)
    else:
        record(args.source.resolve(), args.build_info, args.binary, args.output)


if __name__ == '__main__':
    main()
