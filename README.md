# KDE Snap Overlay

A small [KWin script](https://develop.kde.org/docs/plasma/kwin/) for KDE Plasma 6 (Wayland) that shows Plasma's built-in tiling layouts — like Windows' Snap Layouts — in a popup at the top of the screen while you drag a window.

When you drag a window into the top edge of the screen, a translucent panel with the 8 native layouts (left, right, top, bottom, and the four corners) appears near the top-center. Drop on a layout and KWin's **native quick-tiling** is applied via `Workspace.slotWindowQuickTile*()`, so window sticking and adjacent-resize-on-edge behavior work exactly as with KWin's own edge tiling.

## Demo

![Demo of KDE Snap Overlay](https://raw.githubusercontent.com/IamAndelib/kde-snap-overlay/main/screenshots/demo-compact.gif)

All native behaviors are left intact:

- Dragging to the very top edge (≤ 5px) still **maximizes** the window.
- Dropping on the screen corners still **quarter-tiles** the window.
- Left, right and bottom edge tiling still works normally.

## Requirements

- Plasma / KWin 6 (tested on 6.7)
- Wayland session (X11 is untested and edge behavior differs)
- `kpackagetool6` (Plasma 6) or `kpackagetool5` (Plasma 5)

## Install

### Option A: from the `.kwinscript` file

Grab `kde-snap-overlay-1.7.0.kwinscript` from the repo root or the releases page (also published on the [KDE Store](https://store.kde.org)):

1. Open **System Settings → Window Management → KWin Scripts**.
2. Press **Install from File…** and select the `.kwinscript` file.
3. Tick *KDE Snap Overlay* and press **Apply**.

### Option B: one-command installer

```sh
git clone https://github.com/IamAndelib/kde-snap-overlay.git
cd kde-snap-overlay
./install.sh
```

### Option C: manual

```sh
git clone https://github.com/IamAndelib/kde-snap-overlay.git
cd kde-snap-overlay

# install the package
kpackagetool6 --type KWin/Script --install .

# enable it
kwriteconfig6 --file kwinrc --group Plugins --key kde-snap-overlayEnabled true

# reload KWin's scripts
qdbus6 org.kde.KWin /KWin reconfigure
```

On Plasma 5, replace the tools with `kpackagetool5`, `kwriteconfig5` and `qdbus`.

### Option D: get new scripts

You can also install it from the **KDE Store** via **System Settings → Window Management → KWin Scripts → Get New Scripts…**, and enable/disable it any time by ticking *KDE Snap Overlay* and pressing *Apply*.

## Configuration

| Key                  | Default | Range | Meaning                                              |
| -------------------- | ------- | ----- | ---------------------------------------------------- |
| `activationDistance` | 150     | 100–400 | Band below the top edge (px) in which the popup appears |
| `topGap`             | 25      | 0–(activationDistance−84) | Resting offset between the top edge and the popup panel (25 replicates the old selector chrome) |
| `showDistance`       | 75      | topGap+10–activationDistance−10 | Cursor distance from the top edge below which the popup fully drops (beyond it, only the peek sliver shows). Default matches KZones' trigger distance |
| `peekHeight`         | 15      | 10–popupHeight−20 | Height of the popup sliver that peaks over the top edge while peeking |
| `edgeGapRatio`       | 0.25    | 0–0.5 | Fraction of the screen width ignored on each side of the trigger band (keeps the popup from opening over the corners) |
| `highlightDelay`     | 150     | 0–500 | Rest (ms) the cursor must hold on one layout before the fullscreen zone overlay engages. The popup cards highlight instantly either way; `0` engages the overlay instantly (FancyZones' own behavior) |
| `overlayFadeIn`      | 200     | 0–1000 | Fade-in duration (ms) of the zone overlay — FancyZones' 200ms linear alpha ramp, the overlay's only animation |
| `highlightOpacity`   | 50      | 5–100 | Opacity (%) of the overlay's accent fill (FancyZones' highlightOpacity); the border stays near-opaque |
| `debugLog`           | false   | — | Log the overlay state machine (engage/switch/disengage/map) to the journal: `journalctl --user -b \| grep kde-snap-overlay` |

```sh
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key activationDistance 150
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key topGap 25
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key edgeGapRatio 0.25
qdbus6 org.kde.KWin /KWin reconfigure
```

If `topGap` is raised too high it is clamped so the popup's card row always lands inside the trigger band.

Setting `edgeGapRatio` to `0.5` collapses the trigger zone to a single point in the center of the top edge, so the popup effectively stops opening — keep it well below `0.5`.

## Uninstall

```sh
./install.sh --uninstall
```

or manually:

```sh
kwriteconfig6 --file kwinrc --group Plugins --key kde-snap-overlayEnabled false
kpackagetool6 --type KWin/Script --remove kde-snap-overlay
qdbus6 org.kde.KWin /KWin reconfigure
```

## How it works

- Written as a declarative KWin script (`X-Plasma-API: declarativescript`), with the popup skins and two-stage reveal forked from [KZones](NOTICE).
- Window drag start/finish is detected via the `interactiveMoveResizeStarted/Finished` signals on each window; the popup dialog maps at grab time (KZones' activation), so the reveal is margin animation inside an already-mapped window.
- While dragging, a 16 ms poll of `Workspace.cursorPos` drives the two-stage reveal (peek sliver → full drop) based on cursor distance and selector hover; hovering the panel keeps it fully shown, and layout selection happens only over the popup's cards.
- The popup is a native Plasma dialog: theme translucency, KWin blur-behind and the theme's border/shadow — it follows the system look (no custom panel painting).
- The snap preview is **our own static overlay window** (v1.2.1's pattern): a fullscreen click-through OSD dialog hosting an accent highlight positioned by zone geometry. KWin's shared Outline is hidden by the interactive-move code on every pointer motion event during a drag — and every hide tears its visual's platform window down — so driving that shared outline can only flicker (settle-based re-show) or ghost (per-movement re-show). Our own window stays perfectly static while the cursor moves.
- The overlay follows **FancyZones' (MIT) animation model, forked exactly**: the popup cards highlight instantly, but the fullscreen zone overlay only engages after the cursor rests `highlightDelay` on one layout — sweeping across the cards never pops the overlay window. Its show is a 200ms linear fade (FancyZones' `FadeInDurationMillis`) — the overlay's only animation: zone switches redraw instantly and hiding is instant, exactly like upstream's `ZonesOverlay` (which never animates zone transitions or hide). The fill is drawn at `highlightOpacity` (FancyZones' default 50%). Drop semantics are untouched: a quick flick-and-drop still snaps from the *instant* hover zone, the dwell gates only the visuals.
- The preview geometry is **exact**: `Window.quickTileGeometry()` (the call native snapping itself makes, probed at runtime) with an exact fallback that reads the live tile tree via `Workspace.rootTile()` and `Tile.absoluteGeometry` — layered windows cannot skew the ratios.
- On release, the highlighted zone's `slotWindowQuickTile*` is called — KWin's **native quick-tiling**, so window sticking and adjacent-resize-on-edge behave exactly like KWin's own edge tiling. A short delay lets KWin commit the drop first.
- An effect (KWin *SceneEffect*) was deliberately **not** used: effects render opaquely and would require duplicating KWin's tiling machinery, breaking sticking/adjacent-resize.

## Color scheme

The popup's panel is the Plasma dialog's default theme background (theme translucency + KWin blur-behind), and the layout cards are painted with Kirigami theme tokens per `contents/ui/components/ColorHelper.qml` — everything follows the active Plasma color scheme live, with no hardcoded colors. (KWin's trimmed `org.kde.plasma.core` module does not export `FrameSvgItem` to scripts, so the cards are Qt Quick painted with the system palette.)

## Troubleshooting

- **Popup doesn't appear**: confirm it's enabled — `kreadconfig6 --file kwinrc --group Plugins --key kde-snap-overlayEnabled` should print `true` — then reconfigure. Check KWin's log: `journalctl --user -b | grep kwin_wayland`.
- **Loaded?**: `qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded kde-snap-overlay` should print `true`.
- **Config not applying**: make sure you use the `Script-kde-snap-overlay` group (that's where KWin scripts read their config) and reconfigure after changing values.

## Limitations

- Mouse drags only (no keyboard shortcuts).
- Single monitor only for now (the trigger area/popup follow the screen under the cursor at drag start).

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).

Part of this project (the KZones-inspired components and popup/overlay design)
is derived from [KZones](https://github.com/gerritdevriese/kzones)
(GPL-3.0-or-later, copyright Gerrit de Vries and contributors); see
[NOTICE](NOTICE).
