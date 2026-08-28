# Snap Layout Popup

A small [KWin script](https://develop.kde.org/docs/plasma/kwin/) for KDE Plasma 6 (Wayland) that shows Plasma's built-in tiling layouts — like Windows' Snap Layouts — in a popup at the top of the screen while you drag a window.

When you drag a window into the top edge of the screen, a translucent panel with the 8 native layouts (left, right, top, bottom, and the four corners) appears near the top-center. Drop on a layout and KWin's **native quick-tiling** is applied via `Workspace.slotWindowQuickTile*()`, so window sticking and adjacent-resize-on-edge behavior work exactly as with KWin's own edge tiling.

## Demo

![Demo](https://raw.githubusercontent.com/IamAndelib/kde-snap-overlay/main/screenshots/demo.mp4)

<details>
<summary>Or download the demo video</summary>

[`screenshots/demo.mp4`](screenshots/demo.mp4)

</details>

All native behaviors are left intact:

- Dragging to the very top edge (≤ 5px) still **maximizes** the window.
- Dropping on the screen corners still **quarter-tiles** the window.
- Left, right and bottom edge tiling still works normally.

## Requirements

- Plasma / KWin 6 (tested on 6.7)
- Wayland session (X11 is untested and edge behavior differs)
- `kpackagetool6` (Plasma 6) or `kpackagetool5` (Plasma 5)

## Install

### Option A: one-command installer

```sh
git clone https://github.com/IamAndelib/kde-snap-overlay.git
cd kde-snap-overlay
./install.sh
```

### Option B: manual

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

### Option C: System Settings

You can also enable/disable it any time under **System Settings → Window Management → KWin Scripts** (tick *Snap Layout Popup* and press *Apply*). Use *Install New Scripts…* if you have a packaged `.kwinscript` archive.

## Configuration

| Key                  | Default | Range | Meaning                                              |
| -------------------- | ------- | ----- | ---------------------------------------------------- |
| `activationDistance` | 150     | 100–400 | Band below the top edge (px) in which the popup appears |
| `topGap`             | 60      | 20–200 | Gap between the top edge and the popup, keeping the native maximize zone clear |
| `edgeGapRatio`       | 0.25    | 0–0.5 | Fraction of the screen width ignored on each side of the trigger band (keeps the popup from opening over the corners) |

```sh
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key activationDistance 150
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key topGap 60
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key edgeGapRatio 0.25
qdbus6 org.kde.KWin /KWin reconfigure
```

> The System Settings *Configure* button is not wired up yet; config is edited via `kwriteconfig6` as above.

If `topGap` is raised above the trigger band it is clamped so the popup always lands inside the band.

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

- Written as a declarative KWin script (`X-Plasma-API: declarativescript`).
- Window drag start/finish is detected via the `interactiveMoveResizeStarted/Finished` signals on each window.
- While dragging, a 16 ms poll of `Workspace.cursorPos` shows the popup (a `PlasmaCore.Dialog`, click-through via `outputOnly`) whenever the cursor is in the top band.
- On release, the highlighted layout's `slotWindowQuickTile*` is called. A short delay lets KWin commit the drop first.
- An effect (KWin *SceneEffect*) was deliberately **not** used: effects render opaquely and would require duplicating KWin's tiling machinery, breaking sticking/adjacent-resize.

## Color scheme

The popup follows the active Plasma color scheme, and updates **live** — no relog needed. Colors come from `Kirigami.Theme` (per `contents/ui/components/ColorHelper.qml`), which is wired the same way as KZones: a `ColorHelper` instance owned by each consumer, with the script root being the `PlasmaCore.Dialog` itself. There are no hardcoded colors in the UI.

## Troubleshooting

- **Popup doesn't appear**: confirm it's enabled — `kreadconfig6 --file kwinrc --group Plugins --key kde-snap-overlayEnabled` should print `true` — then reconfigure. Check KWin's log: `journalctl --user -b | grep kwin_wayland`.
- **Loaded?**: `qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded kde-snap-overlay` should print `true`.
- **Config not applying**: make sure you use the `Script-kde-snap-overlay` group (that's where KWin scripts read their config) and reconfigure after changing values.

## Limitations

- Mouse drags only (no keyboard shortcuts).
- Single monitor only for now.
- Dragging with the window maximized or snapped uses KWin's normal behavior.

## License

MIT — see [LICENSE](LICENSE).