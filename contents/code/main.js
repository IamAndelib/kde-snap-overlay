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

var ZONE_IDS = [
    "left", "right",
    "top", "bottom",
    "topLeft", "topRight", "bottomLeft", "bottomRight"
];

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

var ZONE_SLOT = {};
for (var li = 0; li < LAYOUTS.length; li++) {
    for (var zi = 0; zi < LAYOUTS[li].zones.length; zi++) {
        var z = LAYOUTS[li].zones[zi];
        ZONE_SLOT[z.id] = z.slot;
    }
}

// Compute the popup size for the given number of cards and card metrics.
function popupSize(nCards, cardW, cardH, gap, pad) {
    var contentW = nCards * cardW + (nCards - 1) * gap;
    return { width: contentW + 2 * pad, height: cardH + 2 * pad };
}

// The layout that owns a zone id, or "" if unknown.
function layoutOf(zoneId) {
    for (var i = 0; i < LAYOUTS.length; i++) {
        for (var j = 0; j < LAYOUTS[i].zones.length; j++) {
            if (LAYOUTS[i].zones[j].id === zoneId) {
                return LAYOUTS[i].id;
            }
        }
    }
    return "";
}

// Index of a zone within its layout, or -1 if it is not in that layout.
function zoneIndexInLayout(layoutId, zoneId) {
    for (var i = 0; i < LAYOUTS.length; i++) {
        if (LAYOUTS[i].id === layoutId) {
            for (var j = 0; j < LAYOUTS[i].zones.length; j++) {
                if (LAYOUTS[i].zones[j].id === zoneId) {
                    return j;
                }
            }
        }
    }
    return -1;
}

// KWin slot that applies a zone.
function zoneSlot(zoneId) {
    return ZONE_SLOT[zoneId] || "";
}

// Screen-space rectangle of a zone's mini render inside the popup.
function zoneRectInPopup(zoneId, popupX, popupY, cardW, cardH, gap, pad, hs, vs) {
    var li = 0;
    for (var i = 0; i < LAYOUTS.length; i++) {
        var found = -1;
        for (var j = 0; j < LAYOUTS[i].zones.length; j++) {
            if (LAYOUTS[i].zones[j].id === zoneId) {
                found = j;
                break;
            }
        }
        if (found !== -1) {
            li = i;
            break;
        }
    }
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
// KWin QuickTileMode flag values (QuickTileFlag): Left=1, Right=2, Top=4,
// Bottom=8, Maximize=16; corner modes are combinations. Stable across
// KWin 5/6 — used with Window.quickTileGeometry() for exact native geometry.
var ZONE_MODE = {
    left: 1, right: 2, top: 4, bottom: 8,
    topLeft: 5, topRight: 6, bottomLeft: 9, bottomRight: 10
};

// KWin QuickTileMode for a zone id, or 0 if unknown.
function zoneMode(zoneId) {
    return ZONE_MODE[zoneId] || 0;
}
