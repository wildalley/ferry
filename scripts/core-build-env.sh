#!/usr/bin/env bash
# Shared inputs for Android and Windows source builds. Source this file.
CORE_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_PYTHON="${CORE_PYTHON:-python3}"
export GOWORK=off
export GOEXPERIMENT=nojsonv2
CORE_TAGS=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
CORE_BUILD_VERSION="$($CORE_PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["core"]["buildVersion"])' "$CORE_SCRIPT_ROOT/scripts/core-pins.json")"
CORE_LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$CORE_BUILD_VERSION -X internal/godebug.defaultGODEBUG=multipathtcp=0 -s -w -buildid= -checklinkname=0"

prepare_core() {
  local source_dir="$1"
  local args=(prepare --source "$source_dir")
  if [[ -n "${CORE_SOURCE_CACHE:-}" ]]; then args+=(--source-cache "$CORE_SOURCE_CACHE"); fi
  "$CORE_PYTHON" "$CORE_SCRIPT_ROOT/scripts/prepare-core.py" "${args[@]}"
}

record_core() {
  "$CORE_PYTHON" "$CORE_SCRIPT_ROOT/scripts/prepare-core.py" record \
    --source "$1" --binary "$2" --build-info "$3" --output "$4"
}
