# Changelog

Notable changes to KDE Snap Overlay. Each release's GitHub notes are published from its section here.

## [1.8.0] - 2026-10-30

Multi-monitor done right, plus a round of drag fixes, every one found and verified against a real KWin.

**Multi-monitor**
- **The snap lands where the preview showed.** KWin tiles on the monitor under a window's centre, so a wide window grabbed far from its centre could be previewed on one monitor and snapped onto the other. It is now moved to the popup's monitor first, onto the desktop that monitor shows.
- **Monitors stacked vertically:** the hidden popup of the lower monitor no longer shows along the bottom of the upper one during every drag. Where a monitor sits directly above, the popup stays out of sight and appears without the peek stage and the slide, which would be drawn on that monitor.
- **Per-monitor virtual desktops (Plasma 6.7):** each monitor's own desktop and tiles drive its preview, and switching the desktop on another monitor mid-drag no longer blinks the preview off.
- Moving to another monitor mid-drag, the popup jumps there instead of sliding across the others.

**Fixes**
- **First drag after login:** the popup no longer flashes onto the screen and slides away.
- **Escape:** a press held until KWin starts the move, then cancelled (or released) without moving, no longer snaps the window.
- **Fixed-size windows** (and fullscreen ones) no longer get a popup whose drop does nothing: KWin can't tile them, so they get no popup, as with KWin's own edge tiling.
- **Top panel:** the hidden popup no longer shows over a top panel during every drag; the peek sliver hangs off the screen's real top edge.
- **Shadow line:** the hidden popup's theme shadow no longer leaves a faint line at the top centre of the screen during every drag.
- **`topGap` at its maximum:** the bottom row of cards is inside the trigger band again, so it snaps.

**Hardening**
- The drag screen's desktop is asked for explicitly (`currentDesktopForScreen`) instead of KWin's "current" desktop, which follows the active window's monitor.
- One handler less on every window's geometry changes.

**Under the hood**
- `tests/kwin`: 23 scenarios run against a real, headless KWin with virtual monitors (stacked, offset, 150 % scale, three monitors, a top panel, per-monitor desktops, hotplug mid-drag, Escape, the first drag, pixel checks). On 1.7.1, the twelve bug scenarios fail.
- The unit harness (34 tests) reads `main.qml`'s own settings and `main.js`'s exports instead of copies.
- CI lints every script, the test bed and the workflows; a release fails if the committed package doesn't match the source.
- The package ships `LICENSE` and `NOTICE`.
- For contributors: `CONTRIBUTING.md`, `docs/architecture.md`, issue and PR templates, and `dev/setup-container.sh` for a reproducible development container.

**Requirements:** Plasma / KWin 6 (tested on 6.7.5), Wayland. Per-monitor virtual desktops need Plasma 6.7.

Install via System Settings → Window Management → KWin Scripts → *Install from File…*, or clone and run `./install.sh` (log out and back in after an upgrade).

## [1.7.1] - 2026-09-28

Exact snap previews, multi-monitor support, and a hardened drop path.

**Snap preview — now exact**
- The fullscreen zone overlay and the card diagrams show KWin's own quick-tile geometry, read live from its tiles: the preview is exactly where the window will land, including resized splits and KWin re-balancing the grid mid-drag. Previously the tile tree was read through property names scripts cannot see, so any split not touched by a single tile fell back to 50/50.
- **Multi-monitor:** the popup, trigger band and preview follow the screen under the cursor during the drag, and the current virtual desktop if it switches mid-drag.

**Fixes**
- **Escape cancels:** cancelling the move while hovering a card no longer snaps the window. KWin's own edge tiling/maximize and Shift-drop tiling are never overridden either.
- **Meta+drag:** a window moved without being activated is now the one that snaps (KWin's tile slots act on the active window). If it can't be activated, nothing is tiled.
- Dropping off the cards no longer snaps to the last hovered zone — selection happens only over the cards.
- Hover areas line up with the drawn cards on themes with asymmetric dialog shadows.
- A second drop within 80 ms no longer commits early.
- `install.sh`: an upgrade is no longer misdetected as a fresh install, and the installer says when a re-login is needed.
- The package metadata now declares the correct licence (GPL-3.0-or-later).

**Hardening**
- A drag whose finish KWin never reports is ended by a watchdog instead of leaving the popup up.
- One misbehaving window at startup can no longer stop the script from following new windows; all signal hookups are guarded.
- Invalid config values fall back to their defaults instead of disabling the popup.

**Under the hood**
- Dead code removed (an unreachable native-geometry branch, unused helpers and properties); about 150 lines of tile-classifying heuristics replaced by two small, tested functions; the overlay rect is a plain binding instead of a 60 Hz recompute.
- `debugLog` also reports the grid source per drag/screen and any skipped snap.
- Plasma 6 only (the Plasma 5 install path could never load the script).

**Requirements:** Plasma / KWin 6 (tested on 6.7), Wayland.

Install via System Settings → Window Management → KWin Scripts → *Install from File…*, or clone and run `./install.sh` (log out and back in after an upgrade).
