#!/bin/bash
#
# release.sh — Config do MenubarHide; o fluxo de release (build fora do repo, assinatura
# Developer ID, DMG, notarização e staple) mora no script compartilhado do workspace:
# sparrow_workspace/scripts/release-macos.sh.
#
# Uso:
#   ./scripts/release.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

export APP_NAME="MenubarHide"
SHARED="../../scripts/release-macos.sh"
# the flow lives in the Sparrow workspace, two levels up; a clone elsewhere must not exec whatever sits there
[ -x "$SHARED" ] || { echo "shared release script not found: $SHARED (this wrapper only works inside sparrow_workspace)" >&2; exit 1; }
exec "$SHARED"
