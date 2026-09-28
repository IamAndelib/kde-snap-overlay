.pragma library

// The three combined layouts shown in the popup, KZones-style. Each layout is
// one diagram; hovering one of its zones snaps the window to that zone.
// Zone geometry is resolved live from the current KWin tile-grid splits
// (hSplit/vSplit) via zoneRectFrac, never from static percentages, so the
// diagrams and the overlay track the real grid while KWin re-tiles windows.
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
var ZONE_IDS = [];
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
function clampNumber(value, fallback, lo, hi) {
    var n = Number(value);
    if (!isFinite(n)) {
        n = fallback;
    }
    return Math.min(Math.max(n, lo), hi);
}

// Screen-area fractions of a zone given the current grid splits.
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
function zoneIndexInLayout(layoutId, zoneId) {
    var zone = ZONES[zoneId];
    return zone && LAYOUTS[zone.layout].id === layoutId ? zone.index : -1;
}

// KWin slot that applies a zone.
function zoneSlot(zoneId) {
    var zone = ZONES[zoneId];
    return zone ? zone.slot : "";
}

// Screen-space rectangle of a zone's mini render inside the popup.
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
function quickTilesOf(tile) {
    if (!tile || tile.layoutDirection !== undefined) return null;
    var root = tile.parent;
    if (!root || root.parent) return null;
    var kids = root.tiles;
    if (!kids || kids.length !== ZONE_IDS.length) return null;
    var tiles = {};
    for (var i = 0; i < kids.length; i++) {
        var g = kids[i] ? kids[i].relativeGeometry : null;
        var id = g ? quickZoneFor(g.x, g.y, g.width, g.height) : "";
        if (id === "" || tiles[id]) return null;
        tiles[id] = kids[i];
    }
    return tiles;
}

// Return the zone id whose card zone contains the given position, or "".
function hitTestZones(posX, posY, popupX, popupY, cardW, cardH, gap, pad, hs, vs) {
    for (var i = 0; i < ZONE_IDS.length; i++) {
        var r = zoneRectInPopup(ZONE_IDS[i], popupX, popupY, cardW, cardH, gap, pad, hs, vs);
        if (posX >= r.x && posX <= r.x + r.width && posY >= r.y && posY <= r.y + r.height) {
            return ZONE_IDS[i];
        }
    }
    return "";
}
