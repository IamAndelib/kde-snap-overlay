#!/usr/bin/env bash
#
# KDE Snap Overlay - KWin script packager
#
# Builds the distributable .kwinscript archive (a plain zip) from
# metadata.json + contents/, with the version taken from metadata.json.
#
# Usage:
#   ./package.sh             build kde-snap-overlay-<version>.kwinscript
#   ./package.sh --force     overwrite an existing archive with the same name
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA="$SCRIPT_DIR/metadata.json"
PKG_NAME="kde-snap-overlay"

FORCE=0
case "${1:-}" in
    --force|-f) FORCE=1 ;;
    help|-h|--help)
        echo "Usage: $0 [--force]"
        echo "  Builds $PKG_NAME-<version>.kwinscript from metadata.json + contents/."
        echo "  Refuses to overwrite an existing artifact unless --force is given."
        exit 0
        ;;
    "") ;;
    *) echo "Unknown option: $1 (use --force or nothing)" >&2; exit 1 ;;
esac

if [ ! -f "$METADATA" ] || [ ! -d "$SCRIPT_DIR/contents" ]; then
    echo "Error: metadata.json and contents/ must both exist in $SCRIPT_DIR" >&2
    exit 1
fi

command -v zip >/dev/null 2>&1 || { echo "Error: zip not found on PATH." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found on PATH." >&2; exit 1; }

VERSION="$(jq -r '.KPlugin.Version' "$METADATA")"
if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "Error: could not read KPlugin.Version from metadata.json" >&2
    exit 1
fi

OUTPUT="$SCRIPT_DIR/$PKG_NAME-$VERSION.kwinscript"

if [ -e "$OUTPUT" ] && [ "$FORCE" -ne 1 ]; then
    echo "Error: $OUTPUT already exists (use --force to overwrite)." >&2
    echo "  Hint: bump the version in metadata.json for a new release." >&2
    exit 1
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp "$METADATA" "$STAGE_DIR/"
cp -r "$SCRIPT_DIR/contents" "$STAGE_DIR/"

echo ">>> Building $OUTPUT ..."
(
    cd "$STAGE_DIR"
    zip -X -9 -r -q "$OUTPUT" metadata.json contents
)

echo ">>> Done."
unzip -l "$OUTPUT"