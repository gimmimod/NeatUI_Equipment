/*  genera-guardaroba.js - le texture del guardaroba ridisegnato.

    Escono in workshop/.../common/media/ui/NeatEquipment/:

      Card_BG.png      il fondo di un riquadro stondato, bianco pieno
      Card_Border.png  il suo bordo, bianco, stesso raggio

    I primi due sono nine-patch come quelle di Neat (InnerPanel_BG,
    SlotBoarder): 1 pixel di guida in alto e a sinistra, poi 64x64 di disegno.
    Il motore legge le guide dall'alfa (NinePatchTexture.setImageData): i pixel
    opachi della riga 0 dicono quali colonne si stirano, quelli della colonna 0
    quali righe. Tutto il resto resta alla sua misura: gli angoli sono sempre di
    CORNER pixel, qualunque sia il riquadro, ed e' questo che rende i bordi
    regolari - una riga bassa e un riquadro espanso hanno lo stesso raggio.

    Prima le righe erano il 3-slice dei tasti con i cappucci schiacciati al 42%
    della loro larghezza: gli angoli diventavano ellissi, e ogni altezza aveva
    un raggio suo.

    Fondo e bordo sono due file perche' si tingono diversamente: il fondo scuro,
    il bordo chiaro, e il bordo cambia colore da solo (passaggio del mouse,
    riquadro aperto).

    L'icona della cintura non e' piu' qui: la disegna genera-cintura.js da
    sorgenti/cintura.png.

    Esce anche art/anteprime/guardaroba-riquadri.png: i riquadri composti su un
    pannello scuro a tre altezze, ingranditi tre volte, per vedere gli angoli.

    Uso:  node MOD/NeatUI_Equipment/art/genera-guardaroba.js
*/
const fs = require('fs'), path = require('path');
const { writePNG } = require('../../ProjectWriting/strumenti/controlli/png.js');

const OUT = path.join(__dirname, '..', 'workshop', 'Contents', 'mods', 'NeatUI_Equipment',
    'common', 'media', 'ui', 'NeatEquipment');
const PREVIEW = path.join(__dirname, 'anteprime', 'guardaroba-riquadri.png');

const SIZE = 64;       // disegno, senza la guida
const RADIUS = 7;      // raggio dell'angolo
const CORNER = 10;     // pixel fissi per angolo (>= RADIUS + bordo)
const BORDER = 1.6;    // spessore del bordo

const clamp01 = v => Math.max(0, Math.min(1, v));

/** Distanza firmata da un rettangolo stondato centrato in (cx, cy). */
function sdRoundRect(px, py, cx, cy, hw, hh, r) {
    const qx = Math.abs(px - cx) - (hw - r);
    const qy = Math.abs(py - cy) - (hh - r);
    const ox = Math.max(qx, 0), oy = Math.max(qy, 0);
    return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) - r;
}

function sdCircle(px, py, cx, cy, r) { return Math.hypot(px - cx, py - cy) - r; }

/** Copertura di un pixel per una distanza firmata (antialiasing analitico). */
const fill = d => clamp01(0.5 - d);
const ring = (d, t) => clamp01(0.5 - d) - clamp01(0.5 - (d + t));

/** Un'immagine RGBA bianca con l'alfa data da `alpha(x, y)` su una tela w x h. */
function whiteImage(w, h, alpha) {
    const px = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const a = clamp01(alpha(x + 0.5, y + 0.5));
            const i = (y * w + x) * 4;
            px[i] = 255; px[i + 1] = 255; px[i + 2] = 255;
            px[i + 3] = Math.round(a * 255);
        }
    }
    return px;
}

/** La tela nine-patch: 1 px di guida, poi il disegno. */
function ninePatch(alpha) {
    const w = SIZE + 1, h = SIZE + 1;
    const body = whiteImage(SIZE, SIZE, alpha);
    const px = Buffer.alloc(w * h * 4);
    for (let y = 0; y < SIZE; y++) {
        body.copy(px, ((y + 1) * w + 1) * 4, y * SIZE * 4, (y + 1) * SIZE * 4);
    }
    // Guide: verdi e opache sul tratto che si stira, trasparenti sugli angoli.
    const guide = i => {
        px[i] = 0; px[i + 1] = 255; px[i + 2] = 0; px[i + 3] = 255;
    };
    for (let x = 1 + CORNER; x <= SIZE - CORNER; x++) guide(x * 4);
    for (let y = 1 + CORNER; y <= SIZE - CORNER; y++) guide((y * w) * 4);
    return { w, h, px };
}

const half = SIZE / 2;
const cardShape = (x, y) => sdRoundRect(x, y, half, half, half - 0.25, half - 0.25, RADIUS);

const bg = ninePatch((x, y) => fill(cardShape(x, y)));
const border = ninePatch((x, y) => ring(cardShape(x, y), BORDER));

fs.mkdirSync(OUT, { recursive: true });
writePNG(path.join(OUT, 'Card_BG.png'), bg.w, bg.h, bg.px);
writePNG(path.join(OUT, 'Card_Border.png'), border.w, border.h, border.px);
console.log('scritte Card_BG.png e Card_Border.png in ' + OUT);

// --- anteprima ----------------------------------------------------------------
// Si ricompone come il motore: angoli alla loro misura, bordi e centro stirati.
function sampleNine(img, W, H) {
    // img: tela con guida. Ritorna una funzione (x, y) -> alfa in [0, 1].
    const s = SIZE, c = CORNER;
    const src = (sx, sy) => img.px[((sy + 1) * img.w + (sx + 1)) * 4 + 3] / 255;
    const map = (v, len) => {
        if (v < c) return v;
        if (v >= len - c) return s - (len - v);
        const t = (v - c) / Math.max(1, len - 2 * c);
        return c + Math.min(s - 2 * c - 1, Math.floor(t * (s - 2 * c)));
    };
    return (x, y) => src(map(x, W), map(y, H));
}

function compose() {
    const scale = 3;
    const boxes = [
        { w: 220, h: 28, fill: 0.13, line: 0.30 },
        { w: 220, h: 36, fill: 0.19, line: 0.95, accent: true },
        { w: 220, h: 150, fill: 0.13, line: 0.60 },
    ];
    const pad = 10;
    const W = 220 + pad * 2;
    const H = boxes.reduce((a, b) => a + b.h + pad, pad);
    const panel = [0.15 * 255, 0.15 * 255, 0.15 * 255];
    const out = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) { out[i * 3] = panel[0]; out[i * 3 + 1] = panel[1]; out[i * 3 + 2] = panel[2]; }

    const blend = (x, y, a, r, g, b) => {
        const i = (y * W + x) * 3;
        out[i] = out[i] * (1 - a) + r * 255 * a;
        out[i + 1] = out[i + 1] * (1 - a) + g * 255 * a;
        out[i + 2] = out[i + 2] * (1 - a) + b * 255 * a;
    };

    let oy = pad;
    for (const box of boxes) {
        const fa = sampleNine(bg, box.w, box.h);
        const ba = sampleNine(border, box.w, box.h);
        for (let y = 0; y < box.h; y++) {
            for (let x = 0; x < box.w; x++) {
                blend(pad + x, oy + y, fa(x, y) * 0.92, box.fill, box.fill, box.fill + 0.01);
                const lc = box.accent ? [0.95, 0.50, 0.10] : [box.line, box.line, box.line];
                blend(pad + x, oy + y, ba(x, y), lc[0], lc[1], lc[2]);
            }
        }
        oy += box.h + pad;
    }

    const bw = W * scale, bh = H * scale;
    const big = Buffer.alloc(bw * bh * 4);
    for (let y = 0; y < bh; y++) {
        for (let x = 0; x < bw; x++) {
            const s = (Math.floor(y / scale) * W + Math.floor(x / scale)) * 3;
            const d = (y * bw + x) * 4;
            big[d] = out[s]; big[d + 1] = out[s + 1]; big[d + 2] = out[s + 2]; big[d + 3] = 255;
        }
    }
    fs.mkdirSync(path.dirname(PREVIEW), { recursive: true });
    writePNG(PREVIEW, bw, bh, big);
    console.log('anteprima: ' + PREVIEW);
}
compose();
