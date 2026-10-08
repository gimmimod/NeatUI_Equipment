/*  genera-cintura.js - l'icona della cintura, dal disegno di Gimmi.

    Sorgente: sorgenti/cintura.png, 1254x1254, tratto bianco su nero pieno
    (RGB, senza alfa). Esce:

      workshop/.../common/media/ui/NeatEquipment/Icon_Belt.png   64x64
      art/anteprime/cintura.png                                   controllo

    Bianca su trasparente come le altre icone: e' il pannello a tingerla.
    L'alfa e' la luminanza della sorgente, cosi' il bordo antialiasato del
    disegno resta morbido invece di diventare una scaletta.

    Il disegno e' largo e basso (circa 922x370) con un tratto di 30 pixel:
    portato a 64 il tratto e' di due pixel scarsi, e sui tasti del guardaroba
    l'icona e' disegnata a 16-20 pixel, dove un tratto cosi' si sbiadisce.
    Per questo la sorgente viene ingrossata di INGROSSA pixel per lato prima di
    rimpicciolirla: il disegno resta lo stesso, il tratto arriva a circa tre
    pixel come le altre icone a contorno (lo zaino, la gruccia). L'anteprima
    mette a confronto le due versioni alle misure vere.

    Uso:  node MOD/NeatUI_Equipment/art/genera-cintura.js
*/
const fs = require('fs'), path = require('path');
const { readPNG, writePNG } = require('../../ProjectWriting/strumenti/controlli/png.js');

const SRC = path.join(__dirname, 'sorgenti', 'cintura.png');
const OUT = path.join(__dirname, '..', 'workshop', 'Contents', 'mods', 'NeatUI_Equipment',
    'common', 'media', 'ui', 'NeatEquipment', 'Icon_Belt.png');
const PREVIEW = path.join(__dirname, 'anteprime', 'cintura.png');
const OLD_BAG = path.join(path.dirname(OUT), 'Icon_Bag_Closed.png');

const SIZE = 64;
const WIDTH = 60;       // larghezza del disegno nell'icona: due pixel di margine
const INGROSSA = 7;     // pixel di sorgente aggiunti al tratto, per lato

// --- la sorgente come alfa -------------------------------------------------------
const src = readPNG(SRC);
const W = src.w, H = src.h;
let alpha = new Float32Array(W * H);
for (let i = 0; i < W * H; i++) {
    const r = src.rgba[i * 4], g = src.rgba[i * 4 + 1], b = src.rgba[i * 4 + 2];
    alpha[i] = Math.max(r, g, b) / 255;
}

/** Massimo su un disco di raggio `rad`: il tratto si allarga di `rad` per lato.
    Separabile in due passate su un quadrato sarebbe piu' svelto ma farebbe gli
    angoli squadrati; il disco tiene tondi i capi del tratto. */
function dilate(a, rad) {
    if (rad <= 0) return a;
    const out = new Float32Array(W * H);
    const offs = [];
    for (let dy = -rad; dy <= rad; dy++) {
        for (let dx = -rad; dx <= rad; dx++) {
            if (dx * dx + dy * dy <= rad * rad + rad) offs.push([dx, dy]);
        }
    }
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            let m = 0;
            for (const [dx, dy] of offs) {
                const xx = x + dx, yy = y + dy;
                if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
                const v = a[yy * W + xx];
                if (v > m) { m = v; if (m >= 1) break; }
            }
            out[y * W + x] = m;
        }
    }
    return out;
}

function bbox(a) {
    let x0 = W, y0 = H, x1 = -1, y1 = -1;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        if (a[y * W + x] > 0.2) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    }
    return { x0, y0, x1, y1 };
}

/** Il disegno rimpicciolito in una tela SIZE x SIZE, centrato: media per area. */
function toIcon(a) {
    const box = bbox(a);
    const bw = box.x1 - box.x0 + 1, bh = box.y1 - box.y0 + 1;
    const scale = WIDTH / bw;
    const ox = (SIZE - bw * scale) / 2, oy = (SIZE - bh * scale) / 2;
    const px = Buffer.alloc(SIZE * SIZE * 4);
    const SUB = 4;
    for (let y = 0; y < SIZE; y++) {
        for (let x = 0; x < SIZE; x++) {
            let sum = 0;
            for (let sy = 0; sy < SUB; sy++) {
                for (let sx = 0; sx < SUB; sx++) {
                    // Ogni sottocampione copre un quadratino di sorgente: se ne
                    // prende la media, non un punto solo.
                    const u0 = box.x0 + ((x + sx / SUB) - ox) / scale;
                    const v0 = box.y0 + ((y + sy / SUB) - oy) / scale;
                    const step = 1 / (scale * SUB);
                    let s = 0, n = 0;
                    for (let v = v0; v < v0 + step; v += 1) {
                        for (let u = u0; u < u0 + step; u += 1) {
                            const iu = Math.floor(u), iv = Math.floor(v);
                            if (iu >= 0 && iv >= 0 && iu < W && iv < H) s += a[iv * W + iu];
                            n++;
                        }
                    }
                    sum += n ? s / n : 0;
                }
            }
            const i = (y * SIZE + x) * 4;
            px[i] = px[i + 1] = px[i + 2] = 255;
            px[i + 3] = Math.round(255 * Math.min(1, sum / (SUB * SUB)));
        }
    }
    return px;
}

const thin = toIcon(alpha);
const bold = toIcon(dilate(alpha, INGROSSA));

fs.mkdirSync(path.dirname(OUT), { recursive: true });
writePNG(OUT, SIZE, SIZE, bold);
console.log('scritta ' + OUT);

// --- anteprima: le due versioni alle misure dei tasti, accanto allo zaino ------
function shrink(px, from, to) {
    const out = Buffer.alloc(to * to * 4);
    const k = from / to;
    for (let y = 0; y < to; y++) for (let x = 0; x < to; x++) {
        let a = 0, n = 0;
        for (let yy = Math.floor(y * k); yy < Math.floor((y + 1) * k); yy++) {
            for (let xx = Math.floor(x * k); xx < Math.floor((x + 1) * k); xx++) {
                a += px[(yy * from + xx) * 4 + 3]; n++;
            }
        }
        const i = (y * to + x) * 4;
        out[i] = out[i + 1] = out[i + 2] = 255;
        out[i + 3] = Math.round(a / Math.max(1, n));
    }
    return out;
}

const bag = readPNG(OLD_BAG);
const rows = [thin, bold, bag.rgba];
const sizes = [64, 32, 24, 18, 16];
const pad = 8, zoom = 3;
const cw = sizes.reduce((s, v) => s + v + pad, pad), ch = rows.length * (64 + pad) + pad;
const canvas = Buffer.alloc(cw * ch * 3, Math.round(0.15 * 255));
rows.forEach((icon, r) => {
    let x0 = pad;
    for (const s of sizes) {
        const img = s === 64 ? icon : shrink(icon, 64, s);
        const y0 = pad + r * (64 + pad) + Math.floor((64 - s) / 2);
        for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
            const a = img[(y * s + x) * 4 + 3] / 255 * 0.9;
            const i = ((y0 + y) * cw + (x0 + x)) * 3;
            for (let c = 0; c < 3; c++) canvas[i + c] = canvas[i + c] * (1 - a) + 230 * a;
        }
        x0 += s + pad;
    }
});
const big = Buffer.alloc(cw * zoom * ch * zoom * 4);
for (let y = 0; y < ch * zoom; y++) for (let x = 0; x < cw * zoom; x++) {
    const s = (Math.floor(y / zoom) * cw + Math.floor(x / zoom)) * 3, d = (y * cw * zoom + x) * 4;
    big[d] = canvas[s]; big[d + 1] = canvas[s + 1]; big[d + 2] = canvas[s + 2]; big[d + 3] = 255;
}
fs.mkdirSync(path.dirname(PREVIEW), { recursive: true });
writePNG(PREVIEW, cw * zoom, ch * zoom, big);
console.log('anteprima (sottile / ingrossata / zaino): ' + PREVIEW);
