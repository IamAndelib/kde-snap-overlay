// Quick-tile geometry: Logic.quickZoneFor / Logic.quickTilesOf against a
// faithful replica of KWin's QuickRootTile (src/tiles/quicktile.cpp,
// src/tiles/tile.cpp). Scripts only see the Tile Q_PROPERTYs used here:
// parent, tiles, relativeGeometry, absoluteGeometry. See docs/kwin-notes.md.
import { readFileSync } from 'node:fs'
import test from 'node:test'
import assert from 'node:assert/strict'

const Logic = new Function(readFileSync(new URL('../contents/code/main.js', import.meta.url), 'utf8')
    .replace(/^\s*\.pragma library.*$/m, '') + '\nreturn { quickZoneFor, quickTilesOf, ZONE_IDS }')()

const MIN = 0.15 // Tile::m_minimumSize default: KWin clamps splits to [0.15, 0.85]

function makeQuickRoot(area) {
    const root = { parent: null, tiles: [] }
    const mk = (x, y, w, h) => {
        const t = {
            parent: root, _g: { x, y, width: w, height: h },
            get relativeGeometry() { return { ...this._g } },
            get absoluteGeometry() {
                const g = this._g
                return { x: Math.round(area.x + g.x * area.width), y: Math.round(area.y + g.y * area.height),
                         width: Math.round(g.width * area.width), height: Math.round(g.height * area.height) }
            }
        }
        root.tiles.push(t)
        return t
    }
    // KWin's constructor order: Left, Right, Top, Bottom, TL, TR, BL, BR.
    const [L, R, T, B, TL, TR, BL, BR] = [mk(0, 0, .5, 1), mk(.5, 0, .5, 1), mk(0, 0, 1, .5), mk(0, .5, 1, .5),
        mk(0, 0, .5, .5), mk(.5, 0, .5, .5), mk(0, .5, .5, .5), mk(.5, .5, .5, .5)]
    const setRight = (t, v) => { t._g.width = v - t._g.x }
    const setLeft = (t, v) => { const r = t._g.x + t._g.width; t._g.x = v; t._g.width = r - v }
    const setBottom = (t, v) => { t._g.height = v - t._g.y }
    const setTop = (t, v) => { const b = t._g.y + t._g.height; t._g.y = v; t._g.height = b - v }
    root.setHorizontalSplit = (s) => {
        s = Math.min(Math.max(s, MIN), 1 - MIN)
        setRight(L, s); setLeft(R, s); setRight(TL, s); setLeft(TR, s); setRight(BL, s); setLeft(BR, s)
    }
    root.setVerticalSplit = (s) => {
        s = Math.min(Math.max(s, MIN), 1 - MIN)
        setBottom(T, s); setTop(B, s); setBottom(TL, s); setBottom(TR, s); setTop(BL, s); setTop(BR, s)
    }
    root.byMode = { left: L, right: R, top: T, bottom: B, topLeft: TL, topRight: TR, bottomLeft: BL, bottomRight: BR }
    return root
}

test('quickZoneFor identifies every KWin quick tile across split pairs (incl. clamping)', () => {
    const area = { x: 0, y: 0, width: 1920, height: 1080 }
    for (let h = 0.05; h <= 0.95; h += 0.037) {
        for (let v = 0.05; v <= 0.95; v += 0.041) {
            const root = makeQuickRoot(area)
            root.setHorizontalSplit(h)
            root.setVerticalSplit(v)
            for (const [id, t] of Object.entries(root.byMode)) {
                const g = t.relativeGeometry
                assert.equal(Logic.quickZoneFor(g.x, g.y, g.width, g.height), id, `${id} @ h=${h} v=${v}`)
            }
        }
    }
})

test('quickZoneFor rejects non-quick shapes (custom layouts)', () => {
    assert.equal(Logic.quickZoneFor(0.25, 0.25, 0.5, 0.5), '')   // centre cell
    assert.equal(Logic.quickZoneFor(0.33, 0, 0.34, 1), '')       // middle column of 3
    assert.equal(Logic.quickZoneFor(0, 0, 1, 1), '')             // whole screen
    assert.equal(Logic.quickZoneFor(0.1, 0, 0.3, 1), '')         // inset column
})

test('quickTilesOf maps all 8 tiles from any quick tile, rejects custom/incomplete trees', () => {
    const root = makeQuickRoot({ x: 0, y: 0, width: 1920, height: 1080 })
    root.setHorizontalSplit(0.616)
    root.setVerticalSplit(0.395)
    for (const t of root.tiles) {
        const m = Logic.quickTilesOf(t)
        assert.ok(m)
        for (const id of Logic.ZONE_IDS) assert.equal(m[id], root.byMode[id])
    }
    assert.equal(Logic.quickTilesOf(null), null)
    assert.equal(Logic.quickTilesOf({ parent: null, relativeGeometry: {} }), null, 'no parent')
    const custom = Object.create(root.tiles[0])
    custom.layoutDirection = 1
    assert.equal(Logic.quickTilesOf(custom), null, 'CustomTile (layoutDirection) rejected')
    assert.equal(Logic.quickTilesOf({ parent: { parent: {}, tiles: root.tiles } }), null, 'parent is not a root')
    assert.equal(Logic.quickTilesOf({ parent: { parent: null, tiles: root.tiles.slice(1) } }), null, 'not exactly 8 children')
    assert.equal(Logic.quickTilesOf({ parent: { parent: null, tiles: [...root.tiles.slice(1), root.tiles[1]] } }), null,
        'duplicate zone')
})

// The layout that exposed the old 50/50 fallback: a left-tiled window (right
// edge at x=1183) and a bottom-right-tiled one (top edge at y=410).
function screenshotScene() {
    const area = { x: 0, y: 0, width: 1920, height: 1037 }
    const root = makeQuickRoot(area)
    root.setHorizontalSplit(1183 / 1920)
    root.setVerticalSplit(410 / 1037)
    const win = (tile) => ({ normalWindow: true, tile })
    return { root, stacking: [win(root.byMode.left), win(root.byMode.bottomRight), win(null)] }
}

test('overlay rect for topRight equals the KWin tile exactly (y 0..410)', () => {
    const { root, stacking } = screenshotScene()
    const tiles = stacking.map((w) => Logic.quickTilesOf(w.tile)).find(Boolean)
    const g = tiles.topRight.absoluteGeometry
    assert.deepEqual(g, root.byMode.topRight.absoluteGeometry)
    assert.equal(g.x, 1183)
    assert.equal(g.y, 0)
    assert.equal(g.height, 410)
    assert.equal(g.x + g.width, 1920)
})

test('live: KWin resetting the vertical split mid-drag is reflected', () => {
    const { root, stacking } = screenshotScene()
    const tiles = Logic.quickTilesOf(stacking[0].tile)
    root.setVerticalSplit(0.5) // QuickRootTile::tryReset after the bottom-right window leaves its tile
    assert.equal(tiles.topRight.absoluteGeometry.height, Math.round(0.5 * 1037))
})
