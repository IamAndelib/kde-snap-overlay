var LAYOUTS = [
    { id: "left",        slot: "slotWindowQuickTileLeft",        fx: 0,     fy: 0,     fw: 0.5, fh: 1 },
    { id: "right",       slot: "slotWindowQuickTileRight",       fx: 0.5,   fy: 0,     fw: 0.5, fh: 1 },
    { id: "top",         slot: "slotWindowQuickTileTop",         fx: 0,     fy: 0,     fw: 1,   fh: 0.5 },
    { id: "bottom",      slot: "slotWindowQuickTileBottom",      fx: 0,     fy: 0.5,   fw: 1,   fh: 0.5 },
    { id: "topLeft",     slot: "slotWindowQuickTileTopLeft",     fx: 0,     fy: 0,     fw: 0.5, fh: 0.5 },
    { id: "topRight",    slot: "slotWindowQuickTileTopRight",    fx: 0.5,   fy: 0,     fw: 0.5, fh: 0.5 },
    { id: "bottomLeft",  slot: "slotWindowQuickTileBottomLeft",  fx: 0,     fy: 0.5,   fw: 0.5, fh: 0.5 },
    { id: "bottomRight", slot: "slotWindowQuickTileBottomRight", fx: 0.5,   fy: 0.5,   fw: 0.5, fh: 0.5 }
];

// Compute the popup size for the given card metrics.
function popupSize(cardW, cardH, gap, pad) {
    var contentW = LAYOUTS.length * cardW + (LAYOUTS.length - 1) * gap;
    return { width: contentW + 2 * pad, height: cardH + 2 * pad };
}

// Look up a layout by id.
function layoutById(id) {
    for (var i = 0; i < LAYOUTS.length; i++) {
        if (LAYOUTS[i].id === id) {
            return LAYOUTS[i];
        }
    }
    return null;
}

// Screen-space rectangle of a card, relative to the popup origin.
function cardRect(index, popupX, popupY, cardW, cardH, gap, pad) {
    return {
        x: popupX + pad + index * (cardW + gap),
        y: popupY + pad,
        width: cardW,
        height: cardH
    };
}

// Return the layout id whose card contains the given position, or "" if none.
function hitTest(posX, posY, popupX, popupY, cardW, cardH, gap, pad) {
    for (var i = 0; i < LAYOUTS.length; i++) {
        var r = cardRect(i, popupX, popupY, cardW, cardH, gap, pad);
        if (posX >= r.x && posX <= r.x + r.width && posY >= r.y && posY <= r.y + r.height) {
            return LAYOUTS[i].id;
        }
    }
    return "";
}