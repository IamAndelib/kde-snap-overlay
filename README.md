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

Grab `kde-snap-overlay-2.2.2.kwinscript` from the repo root or the releases page (also published on the [KDE Store](https://store.kde.org)):

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
- The snap preview is **KWin's native outline**: hovering a card drives `Workspace.showOutline()`/`hideOutline()` — the same renderer native edge-dragging uses.
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
