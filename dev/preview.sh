#!/usr/bin/env bash
#
# KDE Snap Overlay - preview installer for development
#
# Development happens inside a distrobox (default name "dev"); only the
# finished preview touches the host. This script runs on the HOST:
#
#   1. runs the test suites inside the dev container (a failure aborts);
#   2. stages the working tree with a stamped version
#      (<version>-preview.<commit>[.dirty]) so System Settings shows which
#      build is loaded;
#   3. installs and enables that stage on the host with the repo's own
#      install.sh, so the real installer is exercised too.
#
# Usage:
#   dev/preview.sh            test in the container, then install the preview
#   dev/preview.sh --restore  reinstall the committed release .kwinscript
#   dev/preview.sh --status   show the version KWin has installed
#
# Environment:
#   KSO_DEVBOX   name of the dev container (default: dev)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_ID="kde-snap-overlay"
DEVBOX="${KSO_DEVBOX:-dev}"

# The install has to reach the host's KWin over the host session bus, and the
# point of the split is that the container never installs anything itself.
if [ -e /run/.containerenv ] || [ -e /.dockerenv ]; then
    echo "Error: run this on the host, not inside a container." >&2
    exit 1
fi

KPACKAGE="kpackagetool6"
QDBUS="$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)"

in_devbox() {
    distrobox enter "$DEVBOX" -- bash -c "cd \"\$1\" && shift && \"\$@\"" _ "$REPO_DIR" "$@"
}

# kpackagetool6 --show prints no version, so read it from the installed
# package's metadata.json (sed, to need no jq on the host).
installed_version() {
    local path
    path="$("$KPACKAGE" --type KWin/Script --show "$PKG_ID" 2>/dev/null \
        | sed -n 's/^[[:space:]]*Path[[:space:]]*:[[:space:]]*//p')"
    if [ -n "$path" ] && [ -f "$path/metadata.json" ]; then
        sed -n 's/^[[:space:]]*"Version":[[:space:]]*"\(.*\)".*/\1/p' "$path/metadata.json"
    else
        echo "not installed"
    fi
}

relog_note() {
    echo
    echo "Log out and back in to run it: KWin can keep a loaded script's old code"
    echo "until the session ends."
}

do_preview() {
    command -v distrobox >/dev/null 2>&1 || { echo "Error: distrobox not found." >&2; exit 1; }

    echo ">>> Running the tests in the '$DEVBOX' container..."
    in_devbox node --test --test-reporter=spec tests/*.test.mjs

    local sha dirty version
    sha="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    dirty=""
    [ -z "$(git -C "$REPO_DIR" status --porcelain -- metadata.json contents)" ] || dirty=".dirty"
    version="$(in_devbox jq -r '.KPlugin.Version' metadata.json)-preview.${sha}${dirty}"

    # /tmp is shared with the container, so the container can stamp the stage.
    STAGE="$(mktemp -d -p /tmp)"
    trap 'rm -rf "$STAGE"' EXIT
    # Everything install.sh stages from its own folder, plus install.sh.
    cp -r "$REPO_DIR/metadata.json" "$REPO_DIR/LICENSE" "$REPO_DIR/NOTICE" "$REPO_DIR/contents" \
        "$REPO_DIR/install.sh" "$STAGE/"
    # $1, $2 and $v expand in the inner shell and in jq, not here.
    # shellcheck disable=SC2016
    in_devbox sh -c 'jq --arg v "$1" ".KPlugin.Version = \$v" "$2/metadata.json" > "$2/metadata.json.new" \
        && mv "$2/metadata.json.new" "$2/metadata.json"' _ "$version" "$STAGE"

    echo ">>> Installing preview $version on the host..."
    "$STAGE/install.sh" install >/dev/null
    echo ">>> Installed: $(installed_version)"
    relog_note
}

do_restore() {
    local artifact
    artifact="$(find "$REPO_DIR" -maxdepth 1 -name "$PKG_ID-*.kwinscript" | sort -V | tail -n 1)"
    if [ -z "$artifact" ]; then
        echo "Error: no $PKG_ID-*.kwinscript release artifact in $REPO_DIR" >&2
        exit 1
    fi

    echo ">>> Restoring release $(basename "$artifact")..."
    if "$KPACKAGE" --type KWin/Script --list 2>/dev/null | grep -x "$PKG_ID" >/dev/null; then
        "$KPACKAGE" --type KWin/Script --upgrade "$artifact"
    else
        "$KPACKAGE" --type KWin/Script --install "$artifact"
    fi
    kwriteconfig6 --file kwinrc --group Plugins --key "${PKG_ID}Enabled" true
    [ -n "$QDBUS" ] && "$QDBUS" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    echo ">>> Installed: $(installed_version)"
    relog_note
}

case "${1:-}" in
    "")                 do_preview ;;
    --restore|restore)  do_restore ;;
    --status|status)    echo "Installed: $(installed_version)" ;;
    -h|--help|help)     awk 'NR > 2 && !/^#/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}" ;;
    *) echo "Unknown option: $1 (use --restore, --status or nothing)" >&2; exit 1 ;;
esac
