// Air Tracts Live — local caching server
//
// Serves air_tracts_live.html and a tiny CSV read/write API under /api/csv,
// backed by the same data/<zip>/*.csv files Get-LandComps.ps1 -Persist writes.
// The browser tool talks to this instead of re-fetching everything from
// Nashville's live ArcGIS endpoints on every run. No dependencies — plain
// Node built-ins only.
//
// Run:  node server.js
// Then open http://localhost:5757/

const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const PORT = process.env.PORT || 5757;

function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }

function csvEscape(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
function toCsv(rows) {
  if (!rows.length) return '';
  const cols = Object.keys(rows[0]);
  const lines = [cols.map(csvEscape).join(',')];
  rows.forEach(r => lines.push(cols.map(c => csvEscape(r[c])).join(',')));
  return lines.join('\n') + '\n';
}
// small RFC4180-ish parser — handles quoted fields, embedded commas/newlines, "" escapes
function parseCsv(text) {
  const rows = [];
  let i = 0, field = '', row = [], inQuotes = false;
  const pushField = () => { row.push(field); field = ''; };
  const pushRow = () => { rows.push(row); row = []; };
  while (i < text.length) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++; continue;
      }
      field += c; i++; continue;
    }
    if (c === '"') { inQuotes = true; i++; continue; }
    if (c === ',') { pushField(); i++; continue; }
    if (c === '\r') { i++; continue; }
    if (c === '\n') { pushField(); pushRow(); i++; continue; }
    field += c; i++;
  }
  if (field.length || row.length) { pushField(); pushRow(); }
  if (!rows.length) return [];
  const header = rows[0];
  return rows.slice(1)
    .filter(r => r.length === header.length && r.some(v => v !== ''))
    .map(r => { const o = {}; header.forEach((h, idx) => { o[h] = r[idx]; }); return o; });
}

function safeDataPath(relPath) {
  if (!relPath) throw new Error('missing path');
  const p = path.normalize(path.join(DATA_DIR, relPath));
  if (!p.startsWith(DATA_DIR)) throw new Error('path escapes data dir');
  return p;
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.csv': 'text/csv'
};

const server = http.createServer((req, res) => {
  const u = new URL(req.url, `http://${req.headers.host}`);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  if (u.pathname === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  if (u.pathname === '/api/csv' && req.method === 'GET') {
    try {
      const p = safeDataPath(u.searchParams.get('path'));
      const rows = fs.existsSync(p) ? parseCsv(fs.readFileSync(p, 'utf8')) : [];
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(rows));
    } catch (e) { res.writeHead(400, { 'Content-Type': 'text/plain' }); res.end(String(e.message)); }
    return;
  }

  if (u.pathname === '/api/csv' && req.method === 'POST') {
    let body = '';
    req.on('data', d => { body += d; });
    req.on('end', () => {
      try {
        const p = safeDataPath(u.searchParams.get('path'));
        ensureDir(path.dirname(p));
        const rows = JSON.parse(body || '[]');
        fs.writeFileSync(p, toCsv(rows));
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, rows: rows.length }));
      } catch (e) { res.writeHead(400, { 'Content-Type': 'text/plain' }); res.end(String(e.message)); }
    });
    return;
  }

  // static file serving (the tool itself, plus anything else in the repo root)
  let filePath = u.pathname === '/' ? '/air_tracts_live.html' : decodeURIComponent(u.pathname);
  filePath = path.normalize(path.join(ROOT, filePath));
  if (!filePath.startsWith(ROOT)) { res.writeHead(403); res.end('Forbidden'); return; }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`Air Tracts Live cache server running at http://localhost:${PORT}/`);
  console.log(`Cache files live under ${DATA_DIR}`);
});
