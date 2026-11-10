#!/usr/bin/env bash
# Also supports a Linux cross-build; Flutter packaging still runs on Windows.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/core-build-env.sh"
WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/ferry-windows-core-build}"
OUT="${OUT:-$CORE_SCRIPT_ROOT/windows/runner/resources/sing-box.exe}"
mkdir -p "$WORK_DIR" "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
SRC="$(mktemp -d "$WORK_DIR/core.XXXXXX")"
trap 'rm -rf -- "$SRC"' EXIT
prepare_core "$SRC"
cd "$SRC"
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -mod=readonly -trimpath -buildvcs=false \
  -tags "$CORE_TAGS" -ldflags "$CORE_LDFLAGS" -o "$OUT" ./cmd/sing-box
go version -m -json "$OUT" > "$OUT.build-info.json"
record_core "$SRC" "$OUT" "$OUT.build-info.json" "$OUT.sources.json"
echo "Built $OUT"
