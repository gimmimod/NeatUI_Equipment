/*  confronto-strati.js - lo slot a strati, prima e dopo.

    Serve a guardare le proporzioni invece di ragionarci sopra: il difetto
    segnalato ("i sotto slot si accavallano e si compenetrano con quello
    principale") e' una cosa che si vede, non una che si deduce.

    Ridisegna qui la stessa geometria che disegna la mod - NEQ_State.applyScale,
    NEQ_SuperSlot.chipRect e NEQ_Style.countBadgeRect - nelle due versioni,
    vecchia e nuova, a tre misure di pannello. Se i conti qui cambiano, vanno
    cambiati anche di la': questo file e' un disegno, non la verita'.

    node "MOD/NeatUI_Equipment/art/confronto-strati.js"
*/
const path = require('path');
const { writePNG } = require(path.join(__dirname, '../../ProjectWriting/art/png.js'));

const ZOOM = 6;                 // uno slot da 34 px e' minuscolo sullo schermo
const FONT_H = 14;              // UIFont.Small a impostazioni normali
const CHAR_W = 6;               // larghezza media di una cifra a quel corpo

const ACCENT = [242, 128, 26];
const SLOT_BG = [38, 38, 40];
const SLOT_BRD = [150, 150, 150];
const EQUIP_BRD = [242, 128, 26];
const ICON = [120, 150, 190];
const BG = [24, 24, 26];
const TEXT = [15, 15, 15];

// --- la geometria della mod, ricopiata ---------------------------------------
const r = v => Math.floor(v + 0.5);

function metrics(scale) {
    const superSize = Math.max(24, r(34 * scale));
    return {
        scale,
        superSize,
        subStrip: Math.max(9, Math.floor(superSize / 2)),
    };
}

/** Le targhette com'erano: mezzo slot esatto, attaccate fra loro e al quadrato. */
function chipsBefore(m, chips, subSide) {
    const size = m.subStrip;
    const top = chips >= 2 ? 0 : Math.floor((m.superSize - size) / 2);
    const x = subSide === 'left' ? 0 : m.superSize;
    const out = [];
    for (let i = 0; i < chips; i++) out.push([x, top + i * size, size, size]);
    return out;
}

/** Le targhette adesso: uno stacco attorno, e centrate comunque siano. */
function chipsAfter(m, chips, subSide) {
    const gap = Math.max(1, Math.floor(2 * m.scale));
    const size = Math.max(6, m.subStrip - gap);
    const total = chips * size + Math.max(0, chips - 1) * gap;
    const top = Math.floor((m.superSize - total) / 2);
    const x = subSide === 'left' ? 0 : m.superSize + gap;
    const out = [];
    for (let i = 0; i < chips; i++) out.push([x, top + i * (size + gap), size, size]);
    return out;
}

/** La pastiglia com'era: misura decisa dal carattere, a filo dell'angolo. */
function badgeBefore(mainX, size, count) {
    const text = '+' + count;
    const w = text.length * CHAR_W + 6;
    const h = FONT_H + 1;
    return [mainX + size - w, size - h, w, h];
}

/** Il conteggio adesso: nessun riquadro, solo la scritta con il contorno. */
function badgeAfter(mainX, size, count) {
    const inset = Math.max(1, Math.floor(size * 0.06));
    const fh = FONT_H;                       // pickFont non puo' scendere sotto
    let text = String(count);
    if (('+' + text).length * CHAR_W <= size * 0.55) text = '+' + text;
    const w = text.length * CHAR_W;
    return [mainX + size - w - inset, size - fh - inset, w, fh, true];
}

// --- disegno -----------------------------------------------------------------
function makeCanvas(w, h) {
    const px = Buffer.alloc(w * h * 4);
    for (let i = 0; i < w * h; i++) {
        px[i * 4] = BG[0]; px[i * 4 + 1] = BG[1]; px[i * 4 + 2] = BG[2]; px[i * 4 + 3] = 255;
    }
    return px;
}

function rect(px, W, x, y, w, h, col, a) {
    a = a === undefined ? 1 : a;
    for (let yy = y; yy < y + h; yy++) {
        for (let xx = x; xx < x + w; xx++) {
            if (xx < 0 || yy < 0 || xx >= W) continue;
            const i = (yy * W + xx) * 4;
            if (i + 3 >= px.length) continue;
            px[i] = px[i] * (1 - a) + col[0] * a;
            px[i + 1] = px[i + 1] * (1 - a) + col[1] * a;
            px[i + 2] = px[i + 2] * (1 - a) + col[2] * a;
        }
    }
}

function frame(px, W, x, y, w, h, col, t) {
    t = t || 1;
    rect(px, W, x, y, w, t, col);
    rect(px, W, x, y + h - t, w, t, col);
    rect(px, W, x, y, t, h, col);
    rect(px, W, x + w - t, y, t, h, col);
}

/** Uno slot completo, ingrandito ZOOM volte, disegnato a (ox, oy). */
function drawSlot(px, W, ox, oy, m, chips, badgeCount, mode, subSide) {
    const z = ZOOM;
    const mainX = subSide === 'left' ? m.subStrip : 0;
    const S = (v) => v * z;

    // quadrato grande
    rect(px, W, ox + S(mainX), oy, S(m.superSize), S(m.superSize), SLOT_BG);
    frame(px, W, ox + S(mainX), oy, S(m.superSize), S(m.superSize), EQUIP_BRD, Math.max(1, z / 3));
    const inset = Math.max(2, Math.floor(m.superSize * 0.12));
    rect(px, W, ox + S(mainX + inset), oy + S(inset),
        S(m.superSize - inset * 2), S(m.superSize - inset * 2), ICON, 0.9);

    // targhette
    const list = mode === 'before' ? chipsBefore(m, chips, subSide) : chipsAfter(m, chips, subSide);
    for (const [cx, cy, cw, ch] of list) {
        rect(px, W, ox + S(cx), oy + S(cy), S(cw), S(ch), SLOT_BG);
        frame(px, W, ox + S(cx), oy + S(cy), S(cw), S(ch), EQUIP_BRD, Math.max(1, z / 3));
        const ci = Math.max(1, Math.floor(cw * 0.12));
        rect(px, W, ox + S(cx + ci), oy + S(cy + ci), S(cw - ci * 2), S(ch - ci * 2), ICON, 0.9);
    }

    // il conteggio degli strati nascosti
    if (badgeCount > 0) {
        const [bx, by, bw, bh, textOnly] = mode === 'before'
            ? badgeBefore(mainX, m.superSize, badgeCount)
            : badgeAfter(mainX, m.superSize, badgeCount);

        // Prima: blocco arancione pieno con la scritta scura sopra.
        // Dopo: nessun blocco, la scritta arancione con il contorno.
        if (!textOnly) rect(px, W, ox + S(bx), oy + S(by), S(bw), S(bh), ACCENT);

        const glyph = textOnly ? ACCENT : TEXT;
        const outline = textOnly ? [10, 10, 10] : null;
        const tx = bx + Math.floor(bw / 2) - 4, ty = by + Math.floor(bh / 2);
        const strokes = [
            [tx, ty, 5, 0.5], [tx + 2, ty - 2, 0.5, 5], [tx + 6, ty - 3, 0.5, 7],
        ];
        for (const [sx, sy, sw, sh] of strokes) {
            if (outline) {
                for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
                    rect(px, W, ox + S(sx) + dx * z, oy + S(sy) + dy * z,
                        Math.max(1, S(sw)), Math.max(1, S(sh)), outline);
                }
            }
            rect(px, W, ox + S(sx), oy + S(sy), Math.max(1, S(sw)), Math.max(1, S(sh)), glyph);
        }
    }

    return S(m.superSize + m.subStrip);
}

const SCALES = [1.0, 0.7, 1.6];
const GAP = 40;

let W = 60, H = 60;
const cells = [];
for (const s of SCALES) {
    const m = metrics(s);
    cells.push(m);
    W = Math.max(W, 0);
}
// larghezza: due colonne (prima / dopo) per ogni scala, affiancate
let totalW = GAP;
for (const m of cells) totalW += (m.superSize + m.subStrip) * ZOOM * 2 + GAP * 2;
let totalH = GAP * 2 + Math.max(...cells.map(m => m.superSize)) * ZOOM;

const px = makeCanvas(totalW, totalH);
let ox = GAP;
for (const m of cells) {
    drawSlot(px, totalW, ox, GAP, m, 2, 2, 'before', 'right');
    ox += (m.superSize + m.subStrip) * ZOOM + GAP;
    drawSlot(px, totalW, ox, GAP, m, 2, 2, 'after', 'right');
    ox += (m.superSize + m.subStrip) * ZOOM + GAP;
}

const out = path.join(__dirname, 'anteprime', 'confronto-strati.png');
writePNG(out, totalW, totalH, px);
console.log('scritto ' + out + '  (' + totalW + 'x' + totalH + ')');
console.log('coppie prima/dopo alle scale ' + SCALES.join(', '));
for (const m of cells) {
    const b = badgeBefore(0, m.superSize, 2), a = badgeAfter(0, m.superSize, 2);
    const pct = (v) => Math.round(100 * v / m.superSize) + '%';
    console.log('  scala ' + m.scale + '  slot ' + m.superSize + 'px'
        + '  |  prima: blocco ' + b[2] + 'x' + b[3] + ' (' + pct(b[2]) + ' x ' + pct(b[3]) + ' dello slot), a filo'
        + '  |  dopo: scritta ' + a[2] + 'x' + a[3] + ' (' + pct(a[2]) + ' x ' + pct(a[3]) + '), nessun blocco');
}
