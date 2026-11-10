#!/usr/bin/env bash
# Render every platform icon from the current paintBrandMark implementation.
# Review and commit the generated files after changing lib/ui/brand.dart.
set -euo pipefail
cd "$(dirname "$0")/.."
RENDER_ICONS=1 flutter test test/render_icons_test.dart
