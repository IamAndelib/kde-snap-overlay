#!/usr/bin/env bash
#
# KDE Snap Overlay - KWin script installer
#
# Installs (or removes) the kde-snap-overlay KWin script and enables it.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ID="kde-snap-overlay"

# The script uses Qt 6 / KWin 6 APIs only, so Plasma 5 is not supported.
KPACKAGE="kpackagetool6"
KWRITE="kwriteconfig6"
for tool in "$KPACKAGE" "$KWRITE"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: $tool not found on PATH (KDE Plasma 6 is required)." >&2
        exit 1
    fi
done
QDBUS="$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)"

# Whether the package is installed. grep reads the whole list on purpose:
# with pipefail, an early-exiting `grep -q` can SIGPIPE kpackagetool and
# make the pipeline report "not installed".
is_installed() {
    "$KPACKAGE" --type KWin/Script --list 2>/dev/null | grep -x "$PKG_ID" >/dev/null
}

reconfigure_kwin() {
    if [ -n "$QDBUS" ]; then
        "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true
    else
        echo "Note: qdbus not found; reopen/restart KWin or use System Settings to apply." >&2
    fi
}

do_install() {
    echo ">>> Staging runtime files for installation..."
    STAGE_DIR="$(mktemp -d)"
    trap 'rm -rf "$STAGE_DIR"' EXIT
    cp -r "$SCRIPT_DIR/metadata.json" "$SCRIPT_DIR/contents" "$STAGE_DIR/"

    echo ">>> Installing KWin script package..."
    if is_installed; then
        "$KPACKAGE" --type KWin/Script --upgrade "$STAGE_DIR"
    else
        "$KPACKAGE" --type KWin/Script --install "$STAGE_DIR"
    fi

    echo ">>> Enabling $PKG_ID..."
    "$KWRITE" --file kwinrc --group Plugins --key "${PKG_ID}Enabled" true

    echo ">>> Reloading KWin scripts..."
    reconfigure_kwin

    echo
    echo "Done! To verify:"
    echo "  ${QDBUS:-qdbus6} org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded $PKG_ID"
    echo
    echo "You can also toggle it in System Settings -> Window Management -> KWin Scripts."
}

do_uninstall() {
    echo ">>> Disabling $PKG_ID..."
    "$KWRITE" --file kwinrc --group Plugins --key "${PKG_ID}Enabled" false

    echo ">>> Removing KWin script package..."
    if is_installed; then
        "$KPACKAGE" --type KWin/Script --remove "$PKG_ID"
    else
        echo ">>> Package not installed; skipping removal."
    fi

    echo ">>> Reloading KWin scripts..."
    reconfigure_kwin

    echo
    echo "Done! $PKG_ID has been uninstalled."
}

case "${1:-install}" in
    install|-i|--install)   do_install ;;
    uninstall|-r|--uninstall) do_uninstall ;;
    help|-h|--help)
        echo "Usage: $0 [install|uninstall]"
        echo "  install   (default) Install and enable the KWin script."
        echo "  uninstall           Disable and remove the KWin script."
        ;;
    *) echo "Unknown option: $1 (use install or uninstall)" >&2; exit 1 ;;
esac
