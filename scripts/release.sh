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
exec ../../scripts/release-macos.sh
