#!/usr/bin/env python3
"""Run upstream core regressions on loopback, without Docker or a host TUN.

Use only on the disposable source tree produced by prepare-core.py. The root
build sources are unchanged; the upstream test fixtures bind loopback and use
the same patched dependency as the actual binaries.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil

TAGS = 'with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0'


def run(args, cwd, env):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    manifest = json.loads((source / 'ferry-sources.json').read_text())
    env = {**os.environ, 'GOEXPERIMENT': 'nojsonv2', 'GOWORK': 'off',
           'DOCKER_HOST': 'unix://' + str(source / 'no-docker.sock')}
    # Network namespace creation is privileged and outside this loopback suite.
    options = ['-skip=^TestUnshareNamespace$', '-count=1', '-timeout=5m', '-tags=' + TAGS, '-ldflags=-checklinkname=0']
    regression = source / 'ferry-regression'
    regression.mkdir(exist_ok=True)
    for path in (Path(__file__).resolve().parent / 'core-tests').glob('*.go'):
        shutil.copyfile(path, regression / path.name)
    run(['go', 'test', *options, './common/...', './route/...', './dns/...',
         './experimental/libbox', './ferry-regression'], source, env)
    tests = source / 'test'
    for item in manifest['modules']:
        run(['go', 'mod', 'edit', '-replace=' + item['module'] + '=../' + item['directory']], tests, env)
    for path in tests.glob('*.go'):
        text = path.read_text()
        text = text.replace('netip.IPv4Unspecified()', 'netip.MustParseAddr("127.0.0.1")')
        text = text.replace('\":\"+F.ToString(port)', '\"127.0.0.1:\"+F.ToString(port)')
        if path.name == 'clash_test.go':
            # Do not connect to the user's Docker daemon or pull unrelated
            # images in init(), even when the machine has Docker installed.
            text = text.replace('func init() {', 'func ferryUnusedDockerInit() {', 1)
        path.write_text(text)
    (tests / 'ferry_self_test.go').write_text('''package main
import (
    "testing"
    C "github.com/sagernet/sing-box/constant"
    "github.com/sagernet/sing-box/option"
)
func TestFerryGRPCSelf(t *testing.T) {
    testV2RayTransportSelf(t, &option.V2RayTransportOptions{
        Type: C.V2RayTransportTypeGRPC,
        GRPCOptions: option.V2RayGRPCOptions{ServiceName: "FerryTest"},
    })
}
func TestFerryWebSocketSelf(t *testing.T) {
    testV2RayTransportSelf(t, &option.V2RayTransportOptions{Type: C.V2RayTransportTypeWebsocket})
}
''')
    selected = ['TestHTTPSelf', 'TestTrojanSelf', 'TestTrojanPlainSelf',
                'TestV2RayHTTPSelf', 'TestV2RayHTTPPlainSelf', 'TestHysteria2Self',
                'TestTUICSelf', 'TestFerryGRPCSelf', 'TestV2RayGRPCLite',
                'TestFerryWebSocketSelf']
    run(['go', 'test', '-mod=mod', '-v', *options,
         '-run=^(' + '|'.join(selected) + ')$', '.'], tests, env)


if __name__ == '__main__':
    main()
