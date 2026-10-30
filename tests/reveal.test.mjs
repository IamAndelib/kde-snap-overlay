// Popup reveal positions: Logic.revealPositions decides where the popup can
// hide above its screen (retracted) and peek from. KWin paints a window on
// every output it overlaps, so the space above a screen's top edge only
// hides the popup when no other output is there. Real-KWin counterparts:
// tests/kwin/scenarios.py (s_stacked_*, s_top_panel, s_peek_unchanged).
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import assert from 'node:assert/strict'

// KSO_ROOT=/path/to/copy: test another checkout (mutation checks).
const ROOT = process.env.KSO_ROOT || fileURLToPath(new URL('..', import.meta.url))
const Logic = new Function(readFileSync(ROOT + '/contents/code/main.js', 'utf8')
    .replace(/^\s*\.pragma library.*$/m, '') + '\nreturn { revealPositions }')()

const R = (x, y, width, height) => ({ x, y, width, height })
const W = 446, H = 106, PEEK = 15, C = 40
// The popup is centred on its screen: x = screen.x + (width - W) / 2.
const at = (screen, others) =>
    Logic.revealPositions(screen, others, screen.x + Math.floor((screen.width - W) / 2), W, H, PEEK, C)

test('single screen: retracted fully above the top (shadow included), peek sliver on screen', () => {
    assert.deepEqual(at(R(0, 0, 1920, 1080), []), { shared: false, retracted: -H - C, peek: -H + PEEK })
})

test('side-by-side and offset neighbours do not share the top edge', () => {
    assert.equal(at(R(1920, 0, 1920, 1080), [R(0, 0, 1920, 1080)]).shared, false)
    // B starts 300 px lower; A is beside it, not above the popup's spot.
    const b = at(R(1920, 300, 1920, 1080), [R(0, 0, 1920, 1080)])
    assert.deepEqual(b, { shared: false, retracted: 300 - H - C, peek: 300 - H + PEEK })
})

test('stacked: a monitor directly above shares the edge; park above all, no peek', () => {
    const lower = at(R(0, 1080, 1920, 1080), [R(0, 0, 1920, 1080)])
    assert.deepEqual(lower, { shared: true, retracted: -H - C, peek: -H - C })
    // The upper one's top edge is free.
    assert.equal(at(R(0, 0, 1920, 1080), [R(0, 1080, 1920, 1080)]).shared, false)
})

test('an upper monitor beside the popup\'s spot (not over it) leaves the edge free', () => {
    // Upper monitor covers x 0..700 only; the popup spans x 737..1183.
    assert.equal(at(R(0, 1080, 1920, 1080), [R(0, 80, 700, 1000)]).shared, false)
    // One pixel of overlap with the popup's columns is enough to share.
    assert.equal(at(R(0, 1080, 1920, 1080), [R(0, 80, 738, 1000)]).shared, true)
})

test('an upper monitor ending above the hidden spot leaves the edge free', () => {
    // Its bottom (y 900) is more than H + C above the lower screen's top (1080).
    assert.equal(at(R(0, 1080, 1920, 1080), [R(0, 0, 1920, 900)]).shared, false)
    assert.equal(at(R(0, 1080, 1920, 1080), [R(0, 0, 1920, 1000)]).shared, true)
})

test('parks above the topmost output, whichever is first', () => {
    const r = at(R(0, 1080, 1920, 1080), [R(1920, -500, 1920, 1080), R(0, 0, 1920, 1080)])
    assert.deepEqual(r, { shared: true, retracted: -500 - H - C, peek: -500 - H - C })
})
