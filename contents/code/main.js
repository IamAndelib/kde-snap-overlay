.pragma library

// Types: JSDoc comments, checked by tests/typecheck.mjs (KWin ignores them).
/** @typedef {{x: number, y: number, width: number, height: number}} Rect */
/** @typedef {{fx: number, fy: number, fw: number, fh: number}} FracRect */
/** @typedef {{id: string, slot: string}} ZoneDef */
/** @typedef {{id: string, zones: ZoneDef[]}} LayoutDef */
/** @typedef {{slot: string, layout: number, index: number}} ZoneInfo */
/**
 * The parts of a KWin Tile read here: its Q_PROPERTYs (docs/kwin-notes.md).
 * Only custom (Meta+T) tiles have layoutDirection.
 * @typedef {{relativeGeometry?: Rect | null, parent?: Tile | null,
 *     tiles?: (Tile | null)[] | null, layoutDirection?: number}} Tile
 */

// The three combined layouts shown in the popup, KZones-style. Each layout is
// one diagram; hovering one of its zones snaps the window to that zone.
// Zone geometry is resolved live from the current KWin tile-grid splits
// (hSplit/vSplit) via zoneRectFrac, never from static percentages, so the
// diagrams and the overlay track the real grid while KWin re-tiles windows.
/** @type {LayoutDef[]} */
var LAYOUTS = [
    {
        id: "columns",
        zones: [
            { id: "left",  slot: "slotWindowQuickTileLeft"  },
            { id: "right", slot: "slotWindowQuickTileRight" }
        ]
    },
    {
        id: "rows",
        zones: [
            { id: "top",    slot: "slotWindowQuickTileTop"    },
            { id: "bottom", slot: "slotWindowQuickTileBottom" }
        ]
    },
    {
        id: "quadrants",
        zones: [
            { id: "topLeft",     slot: "slotWindowQuickTileTopLeft"     },
            { id: "topRight",    slot: "slotWindowQuickTileTopRight"    },
            { id: "bottomLeft",  slot: "slotWindowQuickTileBottomLeft"  },
            { id: "bottomRight", slot: "slotWindowQuickTileBottomRight" }
        ]
    }
];

// Lookups derived once from LAYOUTS: every zone id in layout order (the
// hit-test order), and per zone its KWin slot, owning layout index and
// index within that layout.
/** @type {string[]} */
var ZONE_IDS = [];
/** @type {Object<string, ZoneInfo>} */
var ZONES = {};
for (var li = 0; li < LAYOUTS.length; li++) {
    for (var zi = 0; zi < LAYOUTS[li].zones.length; zi++) {
        var z = LAYOUTS[li].zones[zi];
        ZONE_IDS.push(z.id);
        ZONES[z.id] = { slot: z.slot, layout: li, index: zi };
    }
}

// A config number clamped to [lo, hi]. A non-numeric value (e.g. a typo
// written with kwriteconfig6) falls back to the default instead of turning
// the setting into NaN.
/**
 * @param {*} value
 * @param {number} fallback
 * @param {number} lo
 * @param {number} hi
 * @returns {number}
 */
function clampNumber(value, fallback, lo, hi) {
    var n = Number(value);
    if (!isFinite(n)) {
        n = fallback;
    }
    return Math.min(Math.max(n, lo), hi);
}

// Screen-area fractions of a zone given the current grid splits.
/**
 * @param {string} zoneId
 * @param {number} hs
 * @param {number} vs
 * @returns {FracRect}
 */
function zoneRectFrac(zoneId, hs, vs) {
    switch (zoneId) {
    case "left":        return { fx: 0,     fy: 0,     fw: hs,     fh: 1 };
    case "right":       return { fx: hs,    fy: 0,     fw: 1 - hs, fh: 1 };
    case "top":         return { fx: 0,     fy: 0,     fw: 1,      fh: vs };
    case "bottom":      return { fx: 0,     fy: vs,    fw: 1,      fh: 1 - vs };
    case "topLeft":     return { fx: 0,     fy: 0,     fw: hs,     fh: vs };
    case "topRight":    return { fx: hs,    fy: 0,     fw: 1 - hs, fh: vs };
    case "bottomLeft":  return { fx: 0,     fy: vs,    fw: hs,     fh: 1 - vs };
    case "bottomRight": return { fx: hs,    fy: vs,    fw: 1 - hs, fh: 1 - vs };
    default:            return { fx: 0,     fy: 0,     fw: 0,      fh: 0 };
    }
}

// Index of a zone within its layout, or -1 if it is not in that layout.
/**
 * @param {string} layoutId
 * @param {string} zoneId
 * @returns {number}
 */
function zoneIndexInLayout(layoutId, zoneId) {
    var zone = ZONES[zoneId];
    return zone && LAYOUTS[zone.layout].id === layoutId ? zone.index : -1;
}

// KWin slot that applies a zone.
/**
 * @param {string} zoneId
 * @returns {string}
 */
function zoneSlot(zoneId) {
    var zone = ZONES[zoneId];
    return zone ? zone.slot : "";
}

// Screen-space rectangle of a zone's mini render inside the popup.
/**
 * @param {string} zoneId
 * @param {number} popupX
 * @param {number} popupY
 * @param {number} cardW
 * @param {number} cardH
 * @param {number} gap
 * @param {number} pad
 * @param {number} hs
 * @param {number} vs
 * @returns {Rect}
 */
function zoneRectInPopup(zoneId, popupX, popupY, cardW, cardH, gap, pad, hs, vs) {
    var zone = ZONES[zoneId];
    var li = zone ? zone.layout : 0;
    var f = zoneRectFrac(zoneId, hs, vs);
    var cardX = popupX + pad + li * (cardW + gap);
    var cardY = popupY + pad;
    return {
        x: cardX + f.fx * cardW,
        y: cardY + f.fy * cardH,
        width: f.fw * cardW,
        height: f.fh * cardH
    };
}

// Zone id of one of KWin's quick tiles, from its relativeGeometry: which
// screen edges it touches identifies it (left touches left+top+bottom,
// topLeft only left+top, ...), independent of KWin's child order. "" for
// anything that is not a quick-tile shape.
/**
 * @param {number} x
 * @param {number} y
 * @param {number} w
 * @param {number} h
 * @returns {string}
 */
function quickZoneFor(x, y, w, h) {
    var eps = 0.001;
    var l = x < eps;
    var t = y < eps;
    var r = x + w > 1 - eps;
    var b = y + h > 1 - eps;
    if (l && t && b && !r) return "left";
    if (r && t && b && !l) return "right";
    if (l && r && t && !b) return "top";
    if (l && r && b && !t) return "bottom";
    if (l && t && !r && !b) return "topLeft";
    if (r && t && !l && !b) return "topRight";
    if (l && b && !r && !t) return "bottomLeft";
    if (r && b && !l && !t) return "bottomRight";
    return "";
}

// KWin's eight quick tiles, keyed by zone id, reached through one
// quick-tiled window's tile, or null if that tile is not a quick tile.
// Scripts see the tile tree through the Q_PROPERTYs `parent` and `tiles`.
// The quick tiles are plain Tiles directly under the parentless
// QuickRootTile; custom (Meta+T) layout tiles are CustomTiles, the only
// tiles exposing `layoutDirection`, so they are rejected.
/**
 * @param {Tile | null | undefined} tile
 * @returns {Object<string, Tile | null> | null}
 */
function quickTilesOf(tile) {
    if (!tile || tile.layoutDirection !== undefined) return null;
    var root = tile.parent;
    if (!root || root.parent) return null;
    var kids = root.tiles;
    if (!kids || kids.length !== ZONE_IDS.length) return null;
    /** @type {Object<string, Tile | null>} */
    var tiles = {};
    for (var i = 0; i < kids.length; i++) {
        var g = kids[i] ? /** @type {Tile} */ (kids[i]).relativeGeometry : null;
        var id = g ? quickZoneFor(g.x, g.y, g.width, g.height) : "";
        if (id === "" || tiles[id]) return null;
        tiles[id] = kids[i];
    }
    return tiles;
}

// Return the zone id whose card zone contains the given position, or "".
/**
 * @param {number} posX
 * @param {number} posY
 * @param {number} popupX
 * @param {number} popupY
 * @param {number} cardW
 * @param {number} cardH
 * @param {number} gap
 * @param {number} pad
 * @param {number} hs
 * @param {number} vs
 * @returns {string}
 */
function hitTestZones(posX, posY, popupX, popupY, cardW, cardH, gap, pad, hs, vs) {
    for (var i = 0; i < ZONE_IDS.length; i++) {
        var r = zoneRectInPopup(ZONE_IDS[i], popupX, popupY, cardW, cardH, gap, pad, hs, vs);
        if (posX >= r.x && posX <= r.x + r.width && posY >= r.y && posY <= r.y + r.height) {
            return ZONE_IDS[i];
        }
    }
    return "";
}

// How far the trigger band reaches sideways on a screen whose area starts
// at areaX and is areaWidth wide: the popup's width plus `margin` on each
// side, centred like the popup, and never beyond the area. Measured from
// the popup rather than as a share of the screen, so the band hugs the
// popup on any screen width, always contains it (its outer cards can never
// fall outside the band), and drags toward the top corners, where KWin
// quarter-tiles, leave it alone (unless popup + 2 * margin is about as wide
// as the screen, when the band is clamped to the whole area).
/**
 * @param {number} areaX
 * @param {number} areaWidth
 * @param {number} popupWidth
 * @param {number} margin
 * @returns {{left: number, right: number}}
 */
function bandSpan(areaX, areaWidth, popupWidth, margin) {
    var centre = areaX + areaWidth / 2;
    var half = popupWidth / 2 + margin;
    return {
        left: Math.max(areaX, centre - half),
        right: Math.min(areaX + areaWidth, centre + half)
    };
}

// Where the popup sits outside its resting position, for a popup of size
// popupW x popupH at x = popupX on the screen with full output geometry
// `screen` (`others`: the other outputs' geometries). The reveal slides the
// dialog in from above the screen's real top edge (retracted, then a peek
// sliver); that hides it only while nothing is drawn above that edge, and
// KWin paints a window on every output it overlaps. With another output
// directly above the popup's spot (stacked monitors: a "shared" top edge)
// there is no hidden room, so the dialog parks above every output and the
// peek stage is skipped (peek = retracted). The real top, not the
// MaximizeArea, is used so a retracted popup never covers a top panel.
// `clearance` keeps the retracted dialog that far above the edge too: the
// theme's shadow is drawn outside the window and would otherwise leave a
// faint line along the top of the screen below.
/**
 * @param {Rect} screen
 * @param {Rect[]} others
 * @param {number} popupX
 * @param {number} popupW
 * @param {number} popupH
 * @param {number} peekHeight
 * @param {number} clearance
 * @returns {{shared: boolean, retracted: number, peek: number}}
 */
function revealPositions(screen, others, popupX, popupW, popupH, peekHeight, clearance) {
    var shared = false;
    var top = screen.y;
    for (var i = 0; i < others.length; i++) {
        var r = others[i];
        top = Math.min(top, r.y);
        if (r.x < popupX + popupW && r.x + r.width > popupX &&
            r.y < screen.y && r.y + r.height > screen.y - popupH - clearance) {
            shared = true;
        }
    }
    var retracted = (shared ? top : screen.y) - popupH - clearance;
    return {
        shared: shared,
        retracted: retracted,
        peek: shared ? retracted : screen.y - popupH + peekHeight
    };
}
