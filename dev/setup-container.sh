#!/usr/bin/env bash
#
# KDE Snap Overlay - development container setup
#
# Installs everything development needs into a Fedora distrobox/toolbox
# (Fedora 44, whose KWin matches Plasma 6.7), so the host gets nothing:
#
#   distrobox create --name dev --image registry.fedoraproject.org/fedora-toolbox:44
#   distrobox enter dev -- ./dev/setup-container.sh
#
# Safe to re-run. Lint tools go into a venv in the container's own
# filesystem (/opt/kso-tools), not into $HOME, which distrobox shares.
#
set -euo pipefail

if [ ! -e /run/.containerenv ] && [ ! -e /.dockerenv ]; then
    echo "Error: run this inside the dev container, not on the host." >&2
    exit 1
fi

VENV=/opt/kso-tools

PACKAGES=(
    # unit tests, packaging and shell lint
    nodejs22 jq zip ShellCheck python3-pip
    # tests/kwin: a headless KWin with real decorations, test windows and a
    # layer-shell panel
    kwin plasma-breeze layer-shell-qt qt6-qtdeclarative qt6-qtwayland dbus-daemon
    # tests/kwin: the driver (fake input, D-Bus, outputctl.c)
    python3-pywayland python3-dbus gcc wayland-devel plasma-wayland-protocols-devel
)

echo ">>> Installing packages..."
sudo dnf install -y "${PACKAGES[@]}"

echo ">>> Installing lint tools into $VENV..."
if [ ! -x "$VENV/bin/pip" ]; then
    sudo python3 -m venv "$VENV"
    sudo chown -R "$(id -u):$(id -g)" "$VENV"
fi
"$VENV/bin/pip" install --quiet PySide6-Essentials==6.12.0 actionlint-py==1.7.12.25 pyflakes==4.1.0

echo
echo "Done. Tools: node $(node --version), kwin $(rpm -q --qf '%{VERSION}' kwin),"
echo "$VENV/bin/pyside6-qmllint, $VENV/bin/actionlint, $VENV/bin/pyflakes."
