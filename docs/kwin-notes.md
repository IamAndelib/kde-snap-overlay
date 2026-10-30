# KWin behaviour this script depends on

Verified against KWin's source, branches `Plasma/6.4`, `Plasma/6.5`, `Plasma/6.6` and `master` (September 2026). Read files via the GitHub mirror: `https://raw.githubusercontent.com/KDE/kwin/<branch>/<path>`. References use function names, not line numbers, because lines drift. Re-check this page when the user moves to a new Plasma version.

## Tiles

**`Window::quickTileGeometry(mode, pos)`** (`src/window.h`) is `protected` and not `Q_INVOKABLE`. From QML, `window.quickTileGeometry` is `undefined`, so don't try to use it.

**Tile scripting surface** (`src/tiles/tile.h`): scripts see only the Q_PROPERTYs:
- `parent` (Tile, the C++ getter is `parentTile()`)
- `tiles` (list, C++ `childTiles()`)
- `relativeGeometry` (0..1 fractions of the output's MaximizeArea)
- `absoluteGeometry` (global px)
- `padding`, `minimumSize`, `windows`, `isLayout`

`tile.parentTile` and `tile.childTiles` are `undefined` in QML. Before 1.7.1 this made the preview fall back to 50/50 for any split that a single tile didn't touch. `KWin::RectF` (6.6+) is a `Q_GADGET`, so `.x/.y/.width/.height` are readable.

**QuickRootTile** (`src/tiles/quicktile.cpp`):
- It has no parent and exactly 8 child tiles, created in the order Left, Right, Top, Bottom, TopLeft, TopRight, BottomLeft, BottomRight. We identify them by geometry (`Logic.quickZoneFor`), not by order.
- They share **one horizontal split** (`setHorizontalSplit`) and **one vertical split** (`setVerticalSplit`), each clamped to [minimumSize, 1 − minimumSize]. The default minimumSize is 0.15 (`Tile::m_minimumSize`).
- `relayoutToFit` moves the shared split when a tile is resized.
- `tryReset` (on a window leaving a tile) resets the horizontal split to 0.5 when Left, Right and all corners are empty, and the vertical split to 0.5 when Top, Bottom and all corners are empty.
- Quick tiles have padding 0. A tiled window gets `Tile::windowGeometry()` = `absoluteGeometry` ∩ the output geometry (MaximizeArea-based and rounded, `Tile::absoluteGeometry`).

**Reaching the quick-tile root:** `TileManager::quickRootTile()` isn't invokable, and `Workspace.rootTile(output, desktop)` returns the *custom* (Meta+T) layout root. The only way in from a script is a quick-tiled window's `window.tile.parent`. `CustomTile` is the only tile type exposing `layoutDirection`, which is how custom tiles are rejected.

**`window.tile`** (`src/window.h`) is `Q_PROPERTY(Tile *tile READ requestedTile … NOTIFY tileChanged)`:
- `Window::requestTile` updates `m_requestedTile` synchronously and emits **`requestedTileChanged`** synchronously.
- `tileChanged` is emitted later (`Window::setTile`), once the client acknowledges.

## The drag/drop lifecycle

**Start:** `Window::startInteractiveMoveResize` records the initial geometry, maximize mode and quick-tile mode, then emits `interactiveMoveResizeStarted`. At that point `window.move` is true.

**During the drag** (`Window::handleInteractiveMoveResize`): on the first real step, a maximized window is unmaximized and a quick-tiled window is untiled (`setQuickTileModeAtCurrentPosition(None)`), while `move` is still true. By drop time the window is never tiled or maximized.

**Finish** (`Window::finishInteractiveMoveResize(bool cancel)`), in this order:
1. `leaveInteractiveMoveResize()`, after which `window.move` is **false**;
2. `doFinishInteractiveMoveResize()`;
3. if **cancel** (Escape): `moveResize(initialGeometry)`, then restore the maximize state (`setMaximize`, which emits `maximizedAboutToChange`) or the quick-tile mode (`setQuickTileMode`, which leads to `requestTile` and `requestedTileChanged`);
4. otherwise, if the output changed: `sendToOutput(moveResizeOutput())`. That returns early, because the window is already on that output, so the geometry isn't changed;
5. if electric-border maximizing: KWin applies its own quick tile or maximize. Shift-drop gives a custom tile;
6. `Q_EMIT interactiveMoveResizeFinished()`. **This is emitted for cancels too.**

So any of these for the dragged window between steps 1 and 6 means KWin handled the drop: `requestedTileChanged`, `maximizedAboutToChange`, or a `frameGeometryChanged` landing back on the start position. That is the `dropHandled` logic in `connectWindow`.

**Geometry timing** (`XdgSurfaceWindow::moveResizeInternal` in `src/xdgshellwindow.cpp`):
- a pure move (same size) updates `frameGeometry` **synchronously**;
- a size change waits for the client to acknowledge (asynchronous).

X11 moves are synchronous too.

## Tiling and activation

**`Workspace.slotWindowQuickTile*`** (`src/scripting/workspace_wrapper.cpp`) calls `Workspace::quickTileWindow` (`src/placement.cpp`), which runs `m_activeWindow->handleQuickTileShortcut(mode)`. It acts on the **active** window, with shortcut semantics: modes can combine, and tiling to the same side again moves the window to the next screen. That's safe here because the window is untiled by drop time.

**Meta+LMB** defaults to `Options::defaultCommandAll1()` = `MouseUnrestrictedMove` (`src/options.h`). In `Window::performMousePressCommand`, only the `MouseActivateRaiseAnd…` commands activate. So a Meta+drag moves the window **without activating it**.

**`Workspace.activeWindow`** is writable: `WorkspaceWrapper::setActiveWindow` calls `Workspace::activateWindow`. Activation is synchronous on Wayland; on X11 it may not be, in which case `onCommit` skips rather than tiling the wrong window.

## Other scripting facts
- `Workspace.cursorPos` notifies (`cursorPosChanged`), but the script polls every 16 ms by design.
- These signals exist in 6.4 and master: `windowAdded`, `windowRemoved`, `currentDesktopChanged` and `screensChanged` on Workspace; `frameGeometryChanged`, `requestedTileChanged`, `tileChanged`, `maximizedAboutToChange`, `quickTileModeChanged` and `interactiveMoveResize{Started,Stepped,Finished}` on Window.
- `Window.move` and `Window.resize` are Q_PROPERTYs (`isInteractiveMove`/`isInteractiveResize`).
- KWin's trimmed `org.kde.plasma.core` module for scripts lacks `FrameSvgItem` and `PlasmaCore.Types.NormalBackground`, so the cards are painted with Kirigami colours.
