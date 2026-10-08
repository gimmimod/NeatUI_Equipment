/*  genera-figura.js - la figura umana: il tasto di Equipment e l'icona della mod.

    Il tasto accanto all'inventario era uno zaino, aperto o chiuso. Lo zaino in
    un inventario vuol dire "borsa", e si confondeva con le borse vere: adesso e'
    una persona in piedi, cioe' "quello che hai addosso".

    La sagoma e' presa dall'immagine di riferimento scelta da Gimmi (una
    figura stilizzata, 800x1422), misurata riga per riga e ridisegnata qui con
    distanze firmate: niente pixel copiati - quell'immagine porta un copyright
    Rawpixel - e bordi puliti a qualunque misura, senza il rilievo e la
    compressione dell'originale. Le misure stanno in FIGURE, nelle coordinate
    dell'immagine di riferimento.

    Escono:
      workshop/.../common/media/ui/NeatEquipment/Icon_Figure.png   64x64, bianca
      workshop/.../42.20/icon.png                                  256x256
      art/icona.png                                                1080x1080
      art/anteprime/figura.png                                     controllo

    L'icona della mod e' ricostruita com'era, con la figura al posto dello
    zaino: cornice bianca stondata, quadrato arancione con il gradiente
    circolare (centro 249,93,15, bordo 235,134,80, misurati sull'icona vecchia).

    Uso:  node MOD/NeatUI_Equipment/art/genera-figura.js
*/
const fs = require('fs'), path = require('path');
const { writePNG } = require('../../ProjectWriting/strumenti/controlli/png.js');

const MOD = path.join(__dirname, '..', 'workshop', 'Contents', 'mods', 'NeatUI_Equipment');
const OUT_UI = path.join(MOD, 'common', 'media', 'ui', 'NeatEquipment', 'Icon_Figure.png');
const OUT_ICON = path.join(MOD, '42.20', 'icon.png');
const OUT_ART = path.join(__dirname, 'icona.png');
const OUT_PREVIEW = path.join(__dirname, 'anteprime', 'figura.png');

const clamp01 = v => Math.max(0, Math.min(1, v));
const mix = (a, b, t) => a + (b - a) * t;

// --- distanze firmate ---------------------------------------------------------
const len = (x, y) => Math.hypot(x, y);

function sdCircle(px, py, cx, cy, r) { return len(px - cx, py - cy) - r; }

function sdBox(px, py, cx, cy, hw, hh) {
    const qx = Math.abs(px - cx) - hw, qy = Math.abs(py - cy) - hh;
    return len(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0);
}

function sdRoundBox(px, py, cx, cy, hw, hh, r) {
    return sdBox(px, py, cx, cy, hw - r, hh - r) - r;
}

function sdCapsule(px, py, ax, ay, bx, by, r) {
    const pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
    const h = clamp01((pax * bax + pay * bay) / (bax * bax + bay * bay));
    return len(pax - bax * h, pay - bay * h) - r;
}

/** Superellisse |x/a|^n + |y/b|^n = 1. La distanza si stima dividendo la
    funzione per il suo gradiente, calcolato numericamente: esatta sul bordo,
    che e' dove conta per l'antialiasing. */
function sdSuperEllipse(px, py, cx, cy, a, b, n) {
    const f = (x, y) => Math.pow(Math.pow(Math.abs(x - cx) / a, n) + Math.pow(Math.abs(y - cy) / b, n), 1 / n) - 1;
    const e = 0.5;
    const gx = (f(px + e, py) - f(px - e, py)) / (2 * e);
    const gy = (f(px, py + e) - f(px, py - e)) / (2 * e);
    const g = len(gx, gy);
    const v = f(px, py);
    return g > 1e-9 ? v / g : v * Math.min(a, b);
}

// --- la figura -------------------------------------------------------------------
const CX = 399.5;

/** Una retta x = x0 + slope * (y - y0), come funzione di y. */
const lineX = (x0, y0, slope) => y => x0 + slope * (y - y0);

/* La figura, nelle coordinate dell'immagine di riferimento (800x1422). Tutti i
   numeri vengono dalle larghezze misurate riga per riga; il lato destro e'
   lo specchio del sinistro attorno a CX. */
const FIGURE = {
    head: { x: 400, y: 180, r: 138 },

    // La cupola delle spalle: la meta' alta di una superellisse (esponente
    // 2.2), che segue le larghezze misurate fra 340 e 440.
    dome: { y: 520, a: 230, b: 183, n: 2.2 },

    // Il bordo esterno del braccio e' la retta misurata (170 a y=480, 72 a
    // y=780), quello interno pure (262 a 580, 200 a 780). Fra `blend` e il
    // bordo della cupola si passa dall'una all'altra gradualmente, come
    // nel riferimento: nessun gomito sulla spalla.
    armOuter: lineX(170, 480, -0.3267),
    armInner: lineX(262, 580, -0.31),
    blend: [430, 480],

    // La punta del braccio: tonda, centrata sull'asse a y=785.
    hand: { x: 134.3, y: 785, r: 61, fromY: 700 },

    // Il busto si allarga appena scendendo; il suo bordo e' 266 a y=580.
    torsoEdge: lineX(266, 580, -0.045),
    torso: { top: 520, bottom: 880 },

    // L'ascella: dove il bordo interno del braccio incontra il busto.
    armpit: 565,

    // Le gambe: dritte in cima, dove continuano il busto, tonde in fondo.
    legs: { top: 860, bottom: 1378, r: 66, left: [252.5, 385], right: [413, 546.5] },

    // Lo spacco fra le gambe, tondo in cima.
    slit: { x: 399, top: 864, r: 14 },

    bbox: { x0: 72, x1: 727, y0: 42, y1: 1378 },
};

/** Distanza da "x a sinistra della retta" (positiva a sinistra, cioe' fuori
    se la retta e' un bordo sinistro). */
function leftOf(px, py, line, slope) {
    return (line(py) - px) / Math.hypot(1, slope);
}

/** Mezza larghezza della parte alta, dalla spalla in giu': la cupola che
    sfuma nella retta del braccio. */
function halfWidth(py) {
    const D = FIGURE.dome, [b0, b1] = FIGURE.blend;
    const t = Math.min(1, Math.abs(py - D.y) / D.b);
    const dome = py >= D.y ? D.a : D.a * Math.pow(1 - Math.pow(t, D.n), 1 / D.n);
    const arm = CX - FIGURE.armOuter(py);
    const s = clamp01((py - b0) / (b1 - b0));
    return mix(dome, arm, s * s * (3 - 2 * s));
}

/** Il lato sinistro della figura dalla spalla in giu', con px gia' riflesso a
    sinistra di CX. */
function leftSide(px, py) {
    const F = FIGURE;

    // Tra il bordo esterno e il centro, da dove la cupola comincia a sfumare.
    const slope = (halfWidth(py + 0.5) - halfWidth(py - 0.5));
    let side = Math.max((Math.abs(px - CX) - halfWidth(py)) / Math.hypot(1, slope), F.blend[0] - py);

    // Tagliato perpendicolare all'asse del braccio, alla punta: sotto ci
    // pensa la punta tonda.
    const ux = -0.3002, uy = 0.9539;
    side = Math.max(side, (px - F.hand.x) * ux + (py - F.hand.y) * uy);

    // Via lo spacco fra braccio e busto: a destra del bordo interno del
    // braccio, a sinistra del busto, sotto l'ascella.
    const wedge = Math.max(
        leftOf(px, py, F.armInner, -0.31),
        -leftOf(px, py, F.torsoEdge, -0.045),
        F.armpit - py);
    side = Math.max(side, -wedge);

    const hand = sdCapsule(px, py, F.hand.x + 0.3184 * (F.hand.y - F.hand.fromY), F.hand.fromY,
        F.hand.x, F.hand.y, F.hand.r);
    side = Math.min(side, hand);

    // Il busto.
    const torso = Math.max(leftOf(px, py, F.torsoEdge, -0.045),
        F.torso.top - py, py - F.torso.bottom);
    return Math.min(side, torso);
}

function figure(px, py) {
    const F = FIGURE;

    // Tutto quello che e' simmetrico si calcola sul lato sinistro.
    const lx = px > CX ? 2 * CX - px : px;

    const D = F.dome;
    // La cupola scende 30 unita' sotto l'inizio del fianco. Le due parti si
    // sovrappongono per piu' di un pixel anche a 64 px (1 px = 22 unita'):
    // senza, la giunta restava una riga semitrasparente sulle spalle. Nella
    // sovrapposizione la cupola e' tutta dentro il fianco, quindi il bordo e'
    // quello del fianco e non si gonfia. (Un raccordo morbido lo gonfiava.)
    const dome = Math.max(sdSuperEllipse(lx, py, CX, D.y, D.a, D.b, D.n), py - F.blend[0] - 30);

    let d = Math.min(sdCircle(px, py, F.head.x, F.head.y, F.head.r),
        dome, leftSide(lx, py));

    // Ogni gamba: un tratto dritto e, in fondo, un pezzo con gli angoli tondi.
    const L = F.legs, straightEnd = L.bottom - L.r, roundTop = L.bottom - 3 * L.r;
    for (const [x0, x1] of [L.left, L.right]) {
        const cx = (x0 + x1) / 2, hw = (x1 - x0) / 2;
        const straight = sdBox(px, py, cx, (L.top + straightEnd) / 2, hw, (straightEnd - L.top) / 2);
        const foot = sdRoundBox(px, py, cx, (roundTop + L.bottom) / 2, hw, (L.bottom - roundTop) / 2, L.r);
        d = Math.min(d, straight, foot);
    }

    const S = F.slit;
    d = Math.max(d, -sdCapsule(px, py, S.x, S.top, S.x, 5000, S.r));
    return d;
}

/** Alfa della figura in un pixel di destinazione. `k` = pixel per unita'. */
function figureAlpha(x, y, map) {
    const s = map(x + 0.5, y + 0.5);
    return clamp01(0.5 - figure(s.x, s.y) * map.k);
}

/** Mette la figura alta `h` pixel con il centro della sua scatola in (cx, cy). */
function placement(h, cx, cy) {
    const B = FIGURE.bbox;
    const k = h / (B.y1 - B.y0);
    const map = (x, y) => ({
        x: (B.x0 + B.x1) / 2 + (x - cx) / k,
        y: (B.y0 + B.y1) / 2 + (y - cy) / k,
    });
    map.k = k;
    return map;
}

// --- l'icona del tasto ----------------------------------------------------------
function uiIcon(size) {
    const px = Buffer.alloc(size * size * 4);
    const map = placement(size - 4, size / 2, size / 2);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const i = (y * size + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = 255;
        px[i + 3] = Math.round(figureAlpha(x, y, map) * 255);
    }
    return px;
}

// --- l'icona della mod ------------------------------------------------------------
// Misure dell'icona vecchia, a 1080: cornice 27..1052 raggio 287, quadrato
// arancione 87..992 raggio 225, figura alta quanto lo zaino (circa 700).
function modIcon(size) {
    const s = size / 1080;
    const C = (size - 1) / 2 + 0.5;
    const frame = { half: (1052 - 27 + 1) / 2 * s, r: 287 * s };
    const plate = { half: (992 - 87 + 1) / 2 * s, r: 225 * s };
    const map = placement(700 * s, C, C);
    const INNER = [249, 93, 15], OUTER = [235, 134, 80];

    const px = Buffer.alloc(size * size * 4);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const fx = x + 0.5, fy = y + 0.5;
        const aFrame = clamp01(0.5 - sdRoundBox(fx, fy, C, C, frame.half, frame.half, frame.r));
        const aPlate = clamp01(0.5 - sdRoundBox(fx, fy, C, C, plate.half, plate.half, plate.r));
        const aFig = figureAlpha(x, y, map);

        const t = clamp01((len(fx - C, fy - C) / s - 40) / 360);
        let r = 255, g = 255, b = 255;
        // arancione sopra il bianco della cornice, poi la figura bianca sopra
        r = mix(r, mix(INNER[0], OUTER[0], t), aPlate);
        g = mix(g, mix(INNER[1], OUTER[1], t), aPlate);
        b = mix(b, mix(INNER[2], OUTER[2], t), aPlate);
        r = mix(r, 255, aFig); g = mix(g, 255, aFig); b = mix(b, 255, aFig);

        const i = (y * size + x) * 4;
        px[i] = Math.round(r); px[i + 1] = Math.round(g); px[i + 2] = Math.round(b);
        px[i + 3] = Math.round(aFrame * 255);
    }
    return px;
}

// --- anteprima: il tasto a tre misure su fondo scuro, e l'icona -----------------
function preview(ui) {
    const sizes = [16, 22, 30, 64];
    const W = 220, H = 80;
    const canvas = new Float64Array(W * H).fill(0.15);
    let ox = 8;
    for (const s of sizes) {
        // riduzione ad area dall'icona da 64
        for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
            let a = 0, n = 0;
            const x0 = Math.floor(x * 64 / s), x1 = Math.max(x0 + 1, Math.floor((x + 1) * 64 / s));
            const y0 = Math.floor(y * 64 / s), y1 = Math.max(y0 + 1, Math.floor((y + 1) * 64 / s));
            for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) { a += ui[(yy * 64 + xx) * 4 + 3] / 255; n++; }
            a /= n;
            const i = (8 + y) * W + ox + x;
            canvas[i] = canvas[i] * (1 - a) + 0.95 * a;
        }
        ox += s + 10;
    }
    const S = 3, bw = W * S, bh = H * S;
    const out = Buffer.alloc(bw * bh * 4);
    for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
        const v = Math.round(canvas[Math.floor(y / S) * W + Math.floor(x / S)] * 255);
        const d = (y * bw + x) * 4;
        out[d] = out[d + 1] = out[d + 2] = v; out[d + 3] = 255;
    }
    fs.mkdirSync(path.dirname(OUT_PREVIEW), { recursive: true });
    writePNG(OUT_PREVIEW, bw, bh, out);
}

const ui = uiIcon(64);
writePNG(OUT_UI, 64, 64, ui);
writePNG(OUT_ICON, 256, 256, modIcon(256));
writePNG(OUT_ART, 1080, 1080, modIcon(1080));
preview(ui);
console.log('scritte: Icon_Figure.png, 42.20/icon.png, art/icona.png, anteprime/figura.png');
