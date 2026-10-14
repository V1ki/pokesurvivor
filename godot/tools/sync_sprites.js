/* sync_sprites.js — puts the PMD sprite sheets into the Godot project (godot/assets/pokemon/, git-ignored).
 *
 *   node godot/tools/sync_sprites.js                 # default: ALL species as per-Pokémon atlases
 *   node godot/tools/sync_sprites.js --force         # repack every atlas
 *   node godot/tools/sync_sprites.js --files [--from=1] [--to=151] [--shiny] [--partner=4]
 *                                                    # legacy: copy a subset as individual sheets
 *
 * Atlas layout (default): godot/tools/pack_sprites.gd (run headless with Godot; set GODOT=/path/to/godot
 * if it is not on PATH) packs each species' 7 sheets into <dex>.png and its shiny sheets into <dex>s.png
 * (extra pages <dex>[s]_<k>.png above 2048x2048) plus assets/pokemon/atlas.json with every sheet's
 * [page, x, y]. Measured on the full set (966 species, 13,468 PNGs, 95 MB): Godot import 53 s -> 22 s,
 * .godot/imported 139 MB -> 67 MB, Android APK 108.3 MB -> 88.7 MB (see godot/README.md).
 * Only species whose source PNGs are newer than their atlas are repacked, so re-running is cheap.
 * Sprites.gd picks the layout at runtime (atlas.json present -> atlas mode). */
const fs = require('fs'), path = require('path'), cp = require('child_process');
const args = Object.fromEntries(process.argv.slice(2).map(a => {
  const m = a.match(/^--([^=]+)(?:=(.*))?$/);
  return m ? [m[1], m[2] == null ? true : m[2]] : [a, true];
}));
const REPO = path.join(__dirname, '..', '..');
const GODOT_DIR = path.join(__dirname, '..');
const SRC = path.join(REPO, 'assets', 'pokemon');
const DST = path.join(GODOT_DIR, 'assets', 'pokemon');
const GODOT = process.env.GODOT || 'godot';
const isDexDir = f => /^\d+$/.test(f);
const mtime = p => { try { return fs.statSync(p).mtimeMs; } catch (e) { return 0; } };

fs.mkdirSync(DST, { recursive: true });

if (args.files) {
  // ---------- legacy per-file subset ----------
  // remove the atlas layout so Sprites.gd falls back to per-file sheets
  for (const f of fs.readdirSync(DST)) if (/^(\d+s?|idle\d+s?)(_\d+)?\.png(\.import)?$/.test(f) || f === 'atlas.json') fs.rmSync(path.join(DST, f));
  const from = +(args.from || 1), to = +(args.to || 151);
  const partner = String(args.partner || 4).split(',').map(Number);
  const dexes = new Set();
  for (let d = from; d <= to; d++) dexes.add(d);
  for (const d of partner) dexes.add(d);
  if (args.clean) for (const f of fs.readdirSync(DST)) if (isDexDir(f) && !dexes.has(+f)) fs.rmSync(path.join(DST, f), { recursive: true, force: true });
  let copied = 0, kept = 0, bytes = 0;
  const copyDir = (src, dst) => {
    if (!fs.existsSync(src)) return;
    fs.mkdirSync(dst, { recursive: true });
    for (const f of fs.readdirSync(src)) {
      if (!f.endsWith('.png')) continue;
      const a = path.join(src, f), b = path.join(dst, f);
      const sa = fs.statSync(a);
      bytes += sa.size;
      if (fs.existsSync(b)) { const sb = fs.statSync(b); if (sb.size === sa.size && sb.mtimeMs >= sa.mtimeMs) { kept++; continue; } }
      fs.copyFileSync(a, b);
      copied++;
    }
  };
  for (const d of [...dexes].sort((a, b) => a - b)) {
    copyDir(path.join(SRC, String(d)), path.join(DST, String(d)));
    if (args.shiny || partner.includes(d)) copyDir(path.join(SRC, String(d), 's'), path.join(DST, String(d), 's'));
  }
  console.log(`sync_sprites (files): ${dexes.size} species, ${copied} copied, ${kept} up to date, ${(bytes / 1048576).toFixed(1)} MB -> ${path.relative(REPO, DST)}`);
  process.exit(0);
}

// ---------- atlas layout (full set) ----------
// drop the per-file layout (sub-folders) if present
for (const f of fs.readdirSync(DST)) if (isDexDir(f)) fs.rmSync(path.join(DST, f), { recursive: true, force: true });
const index = path.join(DST, 'atlas.json');
let haveIndex = fs.existsSync(index) && !args.force;
if (haveIndex) { try { haveIndex = !!JSON.parse(fs.readFileSync(index, 'utf8')).p; } catch (e) { haveIndex = false; } }
const species = fs.readdirSync(SRC).filter(isDexDir).map(Number).sort((a, b) => a - b);
let todo = [];
for (const d of species) {
  const newest = (dir) => fs.existsSync(dir) ? Math.max(0, ...fs.readdirSync(dir).filter(f => f.endsWith('.png')).map(f => mtime(path.join(dir, f)))) : 0;
  const srcT = Math.max(newest(path.join(SRC, String(d))), newest(path.join(SRC, String(d), 's')));
  const outT = Math.min(mtime(path.join(DST, d + '.png')), fs.existsSync(path.join(SRC, String(d), 's')) ? mtime(path.join(DST, d + 's.png')) : Infinity);
  if (!haveIndex || outT < srcT) todo.push(d);
}
if (!todo.length) { console.log('sync_sprites: all ' + species.length + ' atlases up to date'); process.exit(0); }
const full = todo.length === species.length;
const gargs = ['--headless', '--path', GODOT_DIR, '--script', 'res://tools/pack_sprites.gd', '--',
  '--src=' + SRC, '--dst=' + DST].concat(full ? [] : ['--merge', '--dex=' + todo.join(',')]);
console.log(`sync_sprites: packing ${todo.length} species with ${GODOT} ...`);
const r = cp.spawnSync(GODOT, gargs, { stdio: ['ignore', 'pipe', 'inherit'], encoding: 'utf8' });
const line = (r.stdout || '').split('\n').find(l => l.startsWith('pack_sprites:'));
if (r.status !== 0 || !line) { console.error('sync_sprites: packer failed', r.error || r.stdout); process.exit(1); }
console.log(line);
console.log('Next: godot --headless --path godot --import   (first import of the full set ~20 s)');
