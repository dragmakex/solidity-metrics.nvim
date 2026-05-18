const fs = require('fs');
const zlib = require('zlib');

const PALETTE = [
  [0x4e, 0x79, 0xa7, 255],
  [0x59, 0xa1, 0x4f, 255],
  [0xf2, 0x8e, 0x2b, 255],
  [0xe1, 0x57, 0x59, 255],
  [0x76, 0xb7, 0xb2, 255],
  [0xed, 0xc9, 0x49, 255],
  [0xaf, 0x7a, 0xa1, 255],
  [0xff, 0x9d, 0xa7, 255],
  [0x9c, 0x75, 0x5f, 255],
  [0xba, 0xb0, 0xab, 255],
];
const BG = [255, 255, 255, 255];
const GRID = [229, 231, 235, 255];
const TEXT = [17, 24, 39, 255];
const MUTED = [107, 114, 128, 255];
const TOTAL = [0x4e, 0x79, 0xa7, 255];
const AVG = [0x59, 0xa1, 0x4f, 255];

const FONT = {
  ' ': ['00000','00000','00000','00000','00000','00000','00000'],
  '-': ['00000','00000','00000','11111','00000','00000','00000'],
  '_': ['00000','00000','00000','00000','00000','00000','11111'],
  '.': ['00000','00000','00000','00000','00000','01100','01100'],
  ':': ['00000','01100','01100','00000','01100','01100','00000'],
  '/': ['00001','00010','00100','01000','10000','00000','00000'],
  '(': ['00010','00100','01000','01000','01000','00100','00010'],
  ')': ['01000','00100','00010','00010','00010','00100','01000'],
  '%': ['11001','11010','00100','01000','10110','00110','00000'],
  '0': ['01110','10001','10011','10101','11001','10001','01110'],
  '1': ['00100','01100','00100','00100','00100','00100','01110'],
  '2': ['01110','10001','00001','00010','00100','01000','11111'],
  '3': ['11110','00001','00001','01110','00001','00001','11110'],
  '4': ['00010','00110','01010','10010','11111','00010','00010'],
  '5': ['11111','10000','10000','11110','00001','00001','11110'],
  '6': ['01110','10000','10000','11110','10001','10001','01110'],
  '7': ['11111','00001','00010','00100','01000','01000','01000'],
  '8': ['01110','10001','10001','01110','10001','10001','01110'],
  '9': ['01110','10001','10001','01111','00001','00001','01110'],
  'A': ['01110','10001','10001','11111','10001','10001','10001'],
  'B': ['11110','10001','10001','11110','10001','10001','11110'],
  'C': ['01110','10001','10000','10000','10000','10001','01110'],
  'D': ['11100','10010','10001','10001','10001','10010','11100'],
  'E': ['11111','10000','10000','11110','10000','10000','11111'],
  'F': ['11111','10000','10000','11110','10000','10000','10000'],
  'G': ['01110','10001','10000','10111','10001','10001','01110'],
  'H': ['10001','10001','10001','11111','10001','10001','10001'],
  'I': ['01110','00100','00100','00100','00100','00100','01110'],
  'J': ['00111','00010','00010','00010','00010','10010','01100'],
  'K': ['10001','10010','10100','11000','10100','10010','10001'],
  'L': ['10000','10000','10000','10000','10000','10000','11111'],
  'M': ['10001','11011','10101','10101','10001','10001','10001'],
  'N': ['10001','10001','11001','10101','10011','10001','10001'],
  'O': ['01110','10001','10001','10001','10001','10001','01110'],
  'P': ['11110','10001','10001','11110','10000','10000','10000'],
  'Q': ['01110','10001','10001','10001','10101','10010','01101'],
  'R': ['11110','10001','10001','11110','10100','10010','10001'],
  'S': ['01111','10000','10000','01110','00001','00001','11110'],
  'T': ['11111','00100','00100','00100','00100','00100','00100'],
  'U': ['10001','10001','10001','10001','10001','10001','01110'],
  'V': ['10001','10001','10001','10001','10001','01010','00100'],
  'W': ['10001','10001','10001','10101','10101','10101','01010'],
  'X': ['10001','10001','01010','00100','01010','10001','10001'],
  'Y': ['10001','10001','01010','00100','00100','00100','00100'],
  'Z': ['11111','00001','00010','00100','01000','10000','11111'],
};

function normalizeLabel(text) {
  text = String(text || '');
  const out = [];
  let prevLower = false;
  for (const ch of text) {
    if (/[A-Z]/.test(ch) && prevLower) out.push(' ');
    out.push(ch);
    prevLower = /[a-z]/.test(ch);
  }
  return out.join('').replace(/_/g, ' ').toUpperCase();
}

class Canvas {
  constructor(width, height, bg = BG) {
    this.width = width;
    this.height = height;
    this.pixels = Array.from({ length: width * height }, () => bg.slice());
  }

  setPx(x, y, color) {
    if (x >= 0 && y >= 0 && x < this.width && y < this.height) {
      this.pixels[y * this.width + x] = color.slice();
    }
  }

  fillRect(x, y, w, h, color) {
    for (let yy = Math.max(0, y); yy < Math.min(this.height, y + h); yy++) {
      for (let xx = Math.max(0, x); xx < Math.min(this.width, x + w); xx++) {
        this.pixels[yy * this.width + xx] = color.slice();
      }
    }
  }

  line(x0, y0, x1, y1, color, thickness = 1) {
    let dx = Math.abs(x1 - x0);
    let dy = -Math.abs(y1 - y0);
    let sx = x0 < x1 ? 1 : -1;
    let sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    while (true) {
      for (let ox = -(Math.floor(thickness / 2)); ox < thickness - Math.floor(thickness / 2); ox++) {
        for (let oy = -(Math.floor(thickness / 2)); oy < thickness - Math.floor(thickness / 2); oy++) {
          this.setPx(x0 + ox, y0 + oy, color);
        }
      }
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  circle(cx, cy, r, color, thickness = 1) {
    for (let angle = 0; angle < 360; angle++) {
      const rad = angle * Math.PI / 180;
      const x = Math.round(cx + Math.cos(rad) * r);
      const y = Math.round(cy + Math.sin(rad) * r);
      this.line(x, y, x, y, color, thickness);
    }
  }

  polyline(points, color, thickness = 1, closed = false) {
    if (points.length < 2) return;
    for (let i = 0; i < points.length - 1; i++) {
      this.line(points[i][0], points[i][1], points[i + 1][0], points[i + 1][1], color, thickness);
    }
    if (closed) {
      this.line(points[points.length - 1][0], points[points.length - 1][1], points[0][0], points[0][1], color, thickness);
    }
  }

  donut(cx, cy, outerR, innerR, values) {
    const total = values.reduce((a, b) => a + b, 0);
    if (total <= 0) return;
    let acc = -Math.PI / 2;
    const arcs = values.map((value) => {
      const start = acc;
      acc += (value / total) * Math.PI * 2;
      return [start, acc];
    });
    for (let y = Math.max(0, cy - outerR); y <= Math.min(this.height - 1, cy + outerR); y++) {
      for (let x = Math.max(0, cx - outerR); x <= Math.min(this.width - 1, cx + outerR); x++) {
        const dx = x - cx;
        const dy = y - cy;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist >= innerR && dist <= outerR) {
          let ang = Math.atan2(dy, dx);
          if (ang < -Math.PI / 2) ang += Math.PI * 2;
          for (let i = 0; i < arcs.length; i++) {
            if (ang >= arcs[i][0] && ang <= arcs[i][1]) {
              this.setPx(x, y, PALETTE[i % PALETTE.length]);
              break;
            }
          }
        }
      }
    }
  }

  text(x, y, text, color = TEXT, scale = 1, maxChars) {
    text = normalizeLabel(text);
    if (maxChars && text.length > maxChars) {
      text = text.slice(0, maxChars - 1) + '.';
    }
    let cursor = x;
    for (const ch of text) {
      const glyph = FONT[ch] || FONT[' '];
      glyph.forEach((row, gy) => {
        [...row].forEach((bit, gx) => {
          if (bit === '1') {
            this.fillRect(cursor + gx * scale, y + gy * scale, scale, scale, color);
          }
        });
      });
      cursor += 6 * scale;
    }
  }

  writePng(path) {
    const raw = [];
    for (let y = 0; y < this.height; y++) {
      raw.push(0);
      for (let x = 0; x < this.width; x++) {
        raw.push(...this.pixels[y * this.width + x]);
      }
    }
    const idat = zlib.deflateSync(Buffer.from(raw), { level: 9 });
    const chunks = [];
    const chunk = (tag, data) => {
      const len = Buffer.alloc(4);
      len.writeUInt32BE(data.length, 0);
      const type = Buffer.from(tag);
      const crcBuf = Buffer.concat([type, data]);
      const crc = Buffer.alloc(4);
      crc.writeUInt32BE(crc32(crcBuf), 0);
      chunks.push(len, type, data, crc);
    };
    const header = Buffer.alloc(13);
    header.writeUInt32BE(this.width, 0);
    header.writeUInt32BE(this.height, 4);
    header[8] = 8;
    header[9] = 6;
    header[10] = 0;
    header[11] = 0;
    header[12] = 0;
    chunk('IHDR', header);
    chunk('IDAT', idat);
    chunk('IEND', Buffer.alloc(0));
    fs.writeFileSync(path, Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), ...chunks]));
  }
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function scaleValue(value, maxValue, useLog = false) {
  if (maxValue <= 0 || value <= 0) return 0;
  if (useLog) return Math.log(value + 1) / Math.log(maxValue + 1);
  return value / maxValue;
}

function drawTitle(canvas, title) {
  canvas.text(16, 12, title, TEXT, 2);
}
function drawSeriesLegend(canvas, x, y) {
  canvas.fillRect(x, y, 16, 10, TOTAL);
  canvas.text(x + 24, y + 1, 'TOTAL', TEXT, 1);
  canvas.fillRect(x + 110, y, 16, 10, AVG);
  canvas.text(x + 134, y + 1, 'AVERAGE', TEXT, 1);
}

function renderBar(canvas, dataset, title, useLog = false) {
  const keys = dataset.keys || [];
  const totals = dataset.totals || [];
  const avg = dataset.avg || [];
  drawTitle(canvas, title);
  drawSeriesLegend(canvas, canvas.width - 240, 18);
  canvas.text(16, 42, useLog ? 'LOG SCALE' : 'LINEAR SCALE', MUTED, 1);
  let maxValue = 0;
  for (let i = 0; i < keys.length; i++) maxValue = Math.max(maxValue, totals[i] || 0, avg[i] || 0);
  const left = 210;
  const top = 70;
  const valueX = canvas.width - 42;
  const barW = valueX - left - 10;
  const rowH = Math.max(22, Math.floor((canvas.height - top - 16) / Math.max(keys.length, 1)));
  for (let i = 0; i < keys.length; i++) {
    const y = top + i * rowH;
    canvas.text(16, y, keys[i], TEXT, 1, 30);
    const total = totals[i] || 0;
    const average = avg[i] || 0;
    const totalWidth = Math.floor(barW * scaleValue(total, maxValue, useLog));
    const avgWidth = Math.floor(barW * scaleValue(average, maxValue, useLog));
    canvas.fillRect(left, y, barW, 6, GRID);
    canvas.fillRect(left, y, totalWidth, 6, TOTAL);
    canvas.text(valueX, y - 1, String(total), TEXT, 1);
    canvas.fillRect(left, y + 9, barW, 6, GRID);
    canvas.fillRect(left, y + 9, avgWidth, 6, AVG);
    canvas.text(valueX, y + 8, String(average), MUTED, 1);
  }
}

function renderRadar(canvas, dataset, title) {
  const keys = dataset.keys || [];
  const totals = dataset.totals || [];
  const avg = dataset.avg || [];
  if (!keys.length) return;
  drawTitle(canvas, title);
  drawSeriesLegend(canvas, canvas.width - 240, 18);
  const cx = Math.floor(canvas.width / 2);
  const cy = Math.floor(canvas.height / 2) + 24;
  const r = Math.floor(Math.min(canvas.width, canvas.height) / 2) - 72;
  for (let ring = 1; ring <= 7; ring++) {
    canvas.circle(cx, cy, Math.floor(r * ring / 7), GRID, 1);
    canvas.text(cx + Math.floor(r * ring / 7) + 6, cy - 4, String(ring), MUTED, 1);
  }
  const totalPts = [];
  const avgPts = [];
  for (let i = 0; i < keys.length; i++) {
    const ang = -Math.PI / 2 + (i / keys.length) * Math.PI * 2;
    const ox = Math.round(cx + Math.cos(ang) * r);
    const oy = Math.round(cy + Math.sin(ang) * r);
    canvas.line(cx, cy, ox, oy, GRID, 1);
    const lx = Math.round(cx + Math.cos(ang) * (r + 26));
    const ly = Math.round(cy + Math.sin(ang) * (r + 26));
    canvas.text(lx - 20, ly - 3, keys[i], TEXT, 1, 14);
    const t = totals[i] || 0;
    const a = avg[i] || 0;
    totalPts.push([Math.round(cx + Math.cos(ang) * r * scaleValue(t, 7, false)), Math.round(cy + Math.sin(ang) * r * scaleValue(t, 7, false))]);
    avgPts.push([Math.round(cx + Math.cos(ang) * r * scaleValue(a, 7, false)), Math.round(cy + Math.sin(ang) * r * scaleValue(a, 7, false))]);
  }
  canvas.polyline(totalPts, TOTAL, 2, true);
  canvas.polyline(avgPts, AVG, 2, true);
}

function renderSloc(canvas, dataset, title) {
  const keys = dataset.keys || [];
  const sloc = dataset.sloc || [];
  const nsloc = dataset.nsloc || [];
  drawTitle(canvas, title);
  const leftCx = Math.floor(canvas.width / 4);
  const rightCx = Math.floor(canvas.width * 3 / 4);
  const cy = Math.floor(canvas.height / 2) + 10;
  const outerR = Math.min(Math.floor(canvas.width / 6), Math.floor(canvas.height / 3));
  const innerR = Math.floor(outerR / 2);
  canvas.donut(leftCx, cy, outerR, innerR, sloc);
  canvas.donut(rightCx, cy, outerR, innerR, nsloc);
  canvas.text(leftCx - 18, cy - 4, 'SLOC', TEXT, 1);
  canvas.text(rightCx - 22, cy - 4, 'NSLOC', TEXT, 1);
  const legendY = canvas.height - Math.max(14 * keys.length, 40);
  for (let i = 0; i < keys.length; i++) {
    canvas.fillRect(16, legendY + i * 14, 10, 10, PALETTE[i % PALETTE.length]);
    canvas.text(34, legendY + i * 14 + 1, `${keys[i]} ${sloc[i] || 0}/${nsloc[i] || 0}`, TEXT, 1, 42);
  }
}

function main() {
  if (process.argv.length !== 7) {
    console.error('usage: chart_png.js <type> <title> <dataset.json> <width> <output.png>');
    process.exit(1);
  }
  const [, , chartType, title, datasetPath, widthRaw, output] = process.argv;
  const dataset = JSON.parse(fs.readFileSync(datasetPath, 'utf8'));
  const width = Number(widthRaw);
  const rows = Math.max((dataset.keys || []).length, 1);
  let height;
  if (chartType === 'sloc') height = 320;
  else if (chartType === 'radar') height = 360;
  else height = Math.max(150, 80 + rows * 24);
  const canvas = new Canvas(width, height);
  if (chartType === 'radar') renderRadar(canvas, dataset, title);
  else if (chartType === 'sloc') renderSloc(canvas, dataset, title);
  else if (chartType === 'bar') renderBar(canvas, dataset, title, false);
  else if (chartType === 'bar_log') renderBar(canvas, dataset, title, true);
  else {
    console.error('unsupported chart type');
    process.exit(1);
  }
  canvas.writePng(output);
}

main();
