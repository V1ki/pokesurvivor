#!/usr/bin/env node
/* render_audio/render.js — pre-renders the web game's procedural audio for the Godot port.
 *
 *   node godot/tools/render_audio/render.js                 # everything -> godot/assets/audio/
 *   node godot/tools/render_audio/render.js --only=xp_0,village   # a subset (ids or music names)
 *   node godot/tools/render_audio/render.js --reference=<dir>     # also: JS full-chain references
 *   node godot/tools/render_audio/render.js --out=<dir>           # write somewhere else (trials)
 *   node godot/tools/render_audio/render.js --check-loops --out=<tmp>   # loop periodicity check only
 *
 * Needs Node >= 18 (no npm packages), Google Chrome (CHROME=... to override the macOS path) and
 * sox with Vorbis (SOX=..., default /opt/homebrew/bin/sox). Then re-import in Godot:
 *   godot --headless --path godot --import
 *
 * How it works: a tiny HTTP server on 127.0.0.1 (ephemeral port) serves page.html/page.js and
 * the two unchanged game files js/core/audio.js + js/data/music.js to headless Chrome, which
 * is driven over the DevTools protocol through --remote-debugging-pipe (no port, no
 * WebSocket origin issues). page.js renders each job in an OfflineAudioContext (see its
 * header); the float PCM comes back in base64 chunks and is written here:
 *   - music: 3 loops are rendered and the 2nd one, [0.1 + L, 0.1 + 2L), is kept, so the start
 *     of the file already contains the reverb/release tails of the end of the previous loop:
 *     the OGG loops seamlessly at its end (L = steps * 60/bpm/4, rounded to whole samples);
 *   - SFX: rendered 1.5 s into the context (bus ramps settled), trimmed below -72 dBFS with a
 *     5 ms fade; mono when both channels are identical; short ones as 16-bit WAV, long ones
 *     (reverb tails, > 1 s) as OGG Vorbis;
 *   - parametric SFX are rendered per variant: shot per (kind, type) — 92 files, xp per combo
 *     step 0..24 (warm-up calls), burst/reveal per rarity 1..5;
 *   - manifest.json: files, durations, loop lengths, peaks/RMS, gains and the runtime constants.
 * Math.random is seeded: dry SFX come out byte-identical on every run; sounds that go through the
 * convolution reverb (music, bells, pads) differ by about -60 dB RMS between runs (Chrome's convolver).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const os = require('os');
const crypto = require('crypto');
const { spawn, execFileSync } = require('child_process');

const HERE = __dirname;
const GODOT = path.resolve(HERE, '../..');
const REPO = path.resolve(GODOT, '..');
const SR = 44100;
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SOX = process.env.SOX || (fs.existsSync('/opt/homebrew/bin/sox') ? '/opt/homebrew/bin/sox' : 'sox');
const MUSIC_Q = 4;          // Vorbis quality (sox -C): ~128 kbps stereo
const SFX_Q = 4;
const SFX_AT = 1.5;         // SFX fire time inside the render (xp warm-ups need >= 1.41 s)
const SFX_LEN = 6.0;        // render window after the trigger (rift/biome ring ~4.5 s with reverb)
const TRIM_DB = -72;
const OGG_MIN_DUR = 1.0;    // SFX longer than this are stored as OGG

const args = Object.fromEntries(process.argv.slice(2).map(a => { const [k, v] = a.replace(/^--/, '').split('='); return [k, v ?? true]; }));
const only = args.only ? new Set(String(args.only).split(',')) : null;
const OUT = args.out ? path.resolve(String(args.out)) : path.join(GODOT, 'assets/audio');   // --out=<dir> for trials

// ---------------- job list (ids = names used by the Godot side) ----------------

const MUSIC = ['village', 'forest', 'cave', 'volcano', 'boss', 'rift'];
const TYPES = ['fire', 'water', 'electric', 'psychic', 'grass', 'ice', 'poison', 'ghost', 'dragon', 'fairy',
  'normal', 'fighting', 'rock', 'ground', 'steel', 'bug', 'dark', 'flying'];
const SIMPLE = ['hover', 'click', 'back', 'confirm', 'select', 'error', 'hit', 'faint', 'bossDown', 'coin', 'heal',
  'levelup', 'hurt', 'boss', 'surge', 'shiny', 'shinyGet', 'break', 'chest', 'grass', 'ball', 'shake', 'rift',
  'legend', 'gameover', 'biome', 'pause', 'buy'];
const SFX_JOBS = [];
for (const n of SIMPLE) SFX_JOBS.push({ id: n, name: n, opts: null, warm: 0 });
for (const k of ['melee', 'nova']) SFX_JOBS.push({ id: 'shot_' + k, name: 'shot', opts: { kind: k, type: 'normal' }, warm: 0 });
for (const k of ['beam', 'aura', 'buff', 'orbit', 'projectile']) {
  for (const t of TYPES) SFX_JOBS.push({ id: `shot_${k}_${t}`, name: 'shot', opts: { kind: k, type: t }, warm: 0 });
}
for (let c = 0; c <= 24; c++) SFX_JOBS.push({ id: 'xp_' + c, name: 'xp', opts: null, warm: c });
for (let r = 1; r <= 5; r++) {
  SFX_JOBS.push({ id: 'burst_' + r, name: 'burst', opts: { rarity: r }, warm: 0 });
  SFX_JOBS.push({ id: 'reveal_' + r, name: 'reveal', opts: { rarity: r }, warm: 0 });
}

// ---------------- static server ----------------

const ROUTES = {
  '/page.html': path.join(HERE, 'page.html'),
  '/page.js': path.join(HERE, 'page.js'),
  '/js/core/audio.js': path.join(REPO, 'js/core/audio.js'),
  '/js/data/music.js': path.join(REPO, 'js/data/music.js')
};
function serve() {
  return new Promise(res => {
    const srv = http.createServer((req, rsp) => {
      const f = ROUTES[req.url.split('?')[0]];
      if (!f) { rsp.writeHead(404); rsp.end(); return; }
      rsp.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html' : 'text/javascript', 'cache-control': 'no-store' });
      rsp.end(fs.readFileSync(f));
    });
    srv.listen(0, '127.0.0.1', () => res(srv));
  });
}

// ---------------- Chrome over --remote-debugging-pipe ----------------

class CDP {
  constructor(proc) {
    this.w = proc.stdio[3];
    this.id = 0;
    this.pending = new Map();
    let parts = [];
    proc.stdio[4].on('data', chunk => {
      let i;
      while ((i = chunk.indexOf(0)) >= 0) {
        parts.push(chunk.subarray(0, i));
        const msg = JSON.parse(Buffer.concat(parts).toString('utf8'));
        parts = [];
        chunk = chunk.subarray(i + 1);
        if (msg.id && this.pending.has(msg.id)) {
          const p = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          if (msg.error) p.rej(new Error(msg.error.message)); else p.res(msg.result);
        }
      }
      if (chunk.length) parts.push(chunk);
    });
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    const msg = { id, method, params };
    if (sessionId) msg.sessionId = sessionId;
    this.w.write(JSON.stringify(msg) + '\0');
    return new Promise((res, rej) => this.pending.set(id, { res, rej }));
  }
}

async function openPage(port) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ps-render-audio-'));
  const proc = spawn(CHROME, ['--headless=new', '--remote-debugging-pipe', '--user-data-dir=' + tmp, '--no-first-run',
    '--no-default-browser-check', '--disable-extensions', '--mute-audio', '--autoplay-policy=no-user-gesture-required',
    'about:blank'], { stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
  proc.stderr.on('data', () => {});
  const cdp = new CDP(proc);
  const { targetId } = await cdp.send('Target.createTarget', { url: `http://127.0.0.1:${port}/page.html` });
  const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
  const evaluate = async expr => {
    const r = await cdp.send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }, sessionId);
    if (r.exceptionDetails) throw new Error('page: ' + (r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text));
    return r.result.value;
  };
  for (let i = 0; i < 200; i++) {
    const s = await evaluate('window.__error || (window.__ready === true)').catch(() => false);
    if (s === true) break;
    if (typeof s === 'string') throw new Error(s);
    await new Promise(r => setTimeout(r, 50));
  }
  const close = async () => {
    const gone = new Promise(r => proc.once('exit', r));
    try { proc.kill(); } catch (e) { /* gone */ }
    await Promise.race([gone, new Promise(r => setTimeout(r, 3000))]);
    fs.rmSync(tmp, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  };
  return { evaluate, close };
}

/** Channels [start, start+n) of the last render as Float32Arrays. */
async function fetchPcm(page, start, n) {
  const CH = 1 << 19;
  const out = [new Float32Array(n), new Float32Array(n)];
  for (let ch = 0; ch < 2; ch++) {
    for (let o = 0; o < n; o += CH) {
      const m = Math.min(CH, n - o);
      const b = Buffer.from(await page.evaluate(`__chunk(${ch}, ${start + o}, ${m})`), 'base64');
      out[ch].set(new Float32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.length)), o);
    }
  }
  return out;
}

// ---------------- WAV / OGG / stats ----------------

function wav(chs, bits) {
  const nc = chs.length, n = chs[0].length, bps = bits / 8;
  const b = Buffer.alloc(44 + n * nc * bps);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * nc * bps, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(bits === 32 ? 3 : 1, 20); b.writeUInt16LE(nc, 22);
  b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * nc * bps, 28); b.writeUInt16LE(nc * bps, 32); b.writeUInt16LE(bits, 34);
  b.write('data', 36); b.writeUInt32LE(n * nc * bps, 40);
  let o = 44;
  for (let i = 0; i < n; i++) {
    for (let c = 0; c < nc; c++) {
      const v = chs[c][i];
      if (bits === 32) b.writeFloatLE(v, o);
      else b.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(v * 32767))), o);
      o += bps;
    }
  }
  return b;
}

function writeOgg(chs, file, q) {
  // raw little-endian float32 in, Vorbis out (no dither: the encoder takes the float signal)
  const n = chs[0].length, nc = chs.length, raw = Buffer.alloc(n * nc * 4);
  for (let i = 0, o = 0; i < n; i++) for (let c = 0; c < nc; c++, o += 4) raw.writeFloatLE(chs[c][i], o);
  const tmp = path.join(os.tmpdir(), `ps-audio-${process.pid}-${path.basename(file)}.f32`);
  fs.writeFileSync(tmp, raw);
  try {
    execFileSync(SOX, ['-q', '-D', '-t', 'raw', '-e', 'floating-point', '-b', '32', '-L', '-r', String(SR), '-c', String(nc), tmp,
      '-C', String(q), file]);
  } finally { fs.rmSync(tmp, { force: true }); }
}

/** Scales `chs` in place so the peak stays below 0.97 (Vorbis/16-bit); returns the gain to apply back, in dB. */
function headroom(chs) {
  const pk = stats(chs).peak;
  if (pk <= 0.97) return 0;
  const g = 0.97 / pk;
  for (const d of chs) for (let i = 0; i < d.length; i++) d[i] *= g;
  return +(-20 * Math.log10(g)).toFixed(3);
}

function stats(chs) {
  let pk = 0, ss = 0, n = 0;
  for (const d of chs) for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > pk) pk = a; ss += d[i] * d[i]; n++; }
  return { peak: +pk.toFixed(4), rms: +Math.sqrt(ss / Math.max(1, n)).toFixed(5) };
}
const db = v => +(20 * Math.log10(Math.max(v, 1e-9))).toFixed(2);

function isMono(chs) {
  const [l, r] = chs;
  for (let i = 0; i < l.length; i++) if (Math.abs(l[i] - r[i]) > 1e-6) return false;
  return true;
}

// ---------------- jobs ----------------

async function renderSfx(page, job) {
  const len = await page.evaluate(`renderSfx(${JSON.stringify(job.name)}, ${JSON.stringify(job.opts)}, ${job.warm}, ${SFX_AT}, ${SFX_LEN})`);
  const s0 = Math.round(SFX_AT * SR);
  let chs = await fetchPcm(page, s0, len - s0);
  const thr = Math.pow(10, TRIM_DB / 20);
  let last = -1;
  for (let i = chs[0].length - 1; i >= 0; i--) if (Math.abs(chs[0][i]) > thr || Math.abs(chs[1][i]) > thr) { last = i; break; }
  if (last < 0) throw new Error(`${job.id}: silent render`);
  const end = Math.min(chs[0].length, last + Math.round(0.01 * SR));
  if (end >= chs[0].length - 1) console.warn(`  ! ${job.id}: still sounding at the end of the ${SFX_LEN} s window`);
  chs = chs.map(d => d.slice(0, end));
  const fade = Math.min(end, Math.round(0.005 * SR));
  for (const d of chs) for (let i = 0; i < fade; i++) d[end - 1 - i] *= i / fade;
  const mono = isMono(chs);
  if (mono) chs = [chs[0]];
  const st = stats(chs);
  const gain = headroom(chs);
  const dur = end / SR;
  const ogg = dur > OGG_MIN_DUR;
  const rel = `sfx/${job.id}.${ogg ? 'ogg' : 'wav'}`;
  if (ogg) writeOgg(chs, path.join(OUT, rel), SFX_Q);
  else fs.writeFileSync(path.join(OUT, rel), wav(chs, 16));
  return { file: rel, dur: +dur.toFixed(4), ch: chs.length, gain_db: gain, peak: st.peak, rms: st.rms };
}

/** RMS envelope (10 ms windows) of both channels, in dB. */
function envelope(chs, from, n) {
  const W = Math.round(0.01 * SR), out = [];
  for (let o = from; o + W <= from + n; o += W) {
    let ss = 0;
    for (const d of chs) for (let i = o; i < o + W; i++) ss += d[i] * d[i];
    out.push(10 * Math.log10(Math.max(ss / (W * chs.length), 1e-12)));
  }
  return out;
}

async function renderMusic(page, name) {
  const info = await page.evaluate(`songInfo(${JSON.stringify(name)})`);
  const L = info.loop;
  const total = 0.1 + 2 * L + 1.5;
  const tr = Date.now();
  const r = await page.evaluate(`renderMusic(${JSON.stringify(name)}, ${total}, false)`);
  if (process.env.TIMING) console.log(`  render ${name} ${total.toFixed(1)} s audio in ${Date.now() - tr} ms`);
  if (r.track !== name) throw new Error(`${name}: audio.js did not start the track (${r.track})`);
  const S = Math.round((0.1 + L) * SR), N = Math.round(L * SR), K = Math.round(1.0 * SR);
  const all = await fetchPcm(page, S, N + K);
  const seg = all.map(d => d.slice(0, N));
  // Loop check 1: the render goes on past the segment with the 3rd loop; its first second must
  // sound like the start of the segment. Compared as 10 ms RMS envelopes (waveforms differ by the
  // random noise offsets of drums/breath and, when L is not a whole number of samples, by a
  // sub-sample shift of every note).
  const e0 = envelope(all, 0, K), e1 = envelope(all, N, K);
  const ed = [];
  for (let i = 0; i < e0.length; i++) if (e0[i] > -50) ed.push(Math.abs(e1[i] - e0[i]));
  ed.sort((a, b) => a - b);
  // waveform difference (meaningful with --check-loops, where every noise burst is identical)
  let dd = 0, ss = 0;
  for (let c = 0; c < 2; c++) for (let i = 0; i < K; i++) { const e = all[c][N + i] - all[c][i]; dd += e * e; ss += all[c][i] * all[c][i]; }
  // Loop check 2: the step at the seam (last sample -> first sample) vs the typical sample step.
  const steps = [];
  for (let c = 0; c < 2; c++) for (let i = 1; i < N; i++) steps.push(Math.abs(seg[c][i] - seg[c][i - 1]));
  steps.sort((a, b) => a - b);
  const seam = Math.max(Math.abs(seg[0][0] - seg[0][N - 1]), Math.abs(seg[1][0] - seg[1][N - 1]));
  const st = stats(seg);
  const gain = headroom(seg);
  const rel = `music/${name}.ogg`;
  writeOgg(seg, path.join(OUT, rel), MUSIC_Q);
  const decoded = +execFileSync(SOX, ['--i', '-s', path.join(OUT, rel)]).toString().trim();
  return {
    file: rel, bpm: info.bpm, swing: info.swing, bars: info.bars, lead: info.lead, loop_len: +(N / SR).toFixed(5),
    loop_len_exact: +L.toFixed(6), samples: N, ogg_samples: decoded, gain_db: gain, peak: st.peak, rms: st.rms,
    check: {
      loop_env_p50_db: +ed[ed.length >> 1].toFixed(2), loop_env_max_db: +ed[ed.length - 1].toFixed(2),
      loop_wave_err_db: db(Math.sqrt(dd / Math.max(ss, 1e-12))), seam_step: +seam.toFixed(5), step_p50: +steps[steps.length >> 1].toFixed(5),
      step_p999: +steps[Math.floor(steps.length * 0.999)].toFixed(5)
    }
  };
}

async function references(page, dir) {
  // The real JS chain (default volumes 0.55 / 0.7, compressor, x0.9) for level comparisons.
  fs.mkdirSync(dir, { recursive: true });
  const res = {};
  for (const name of ['village', 'forest', 'boss']) {
    const info = await page.evaluate(`songInfo(${JSON.stringify(name)})`);
    const total = 0.1 + 2 * info.loop + 0.2;
    await page.evaluate(`renderMusic(${JSON.stringify(name)}, ${total}, true)`);
    const S = Math.round((0.1 + info.loop) * SR), N = Math.round(info.loop * SR);
    const seg = await fetchPcm(page, S, N);
    fs.writeFileSync(path.join(dir, `ref_${name}_jschain.wav`), wav(seg, 16));
    const st = stats(seg);
    res[name] = { peak_db: db(st.peak), rms_db: db(st.rms) };
  }
  return res;
}

// ---------------- main ----------------

(async () => {
  for (const d of ['music', 'sfx']) fs.mkdirSync(path.join(OUT, d), { recursive: true });
  const manifestPath = path.join(OUT, 'manifest.json');
  const prev = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : null;
  const srv = await serve();
  const page = await openPage(srv.address().port);
  if (args['check-loops']) {
    // validation only (nothing is written): every noise burst starts at the same offset, so a
    // periodic render must repeat sample by sample -> loop_wave_err_db shows the residual
    await page.evaluate('Math.random = () => 0.37, true');
  }
  const t0 = Date.now();
  try {
    const music = only && prev ? prev.music : {};
    for (const name of MUSIC) {
      if (only && !only.has(name)) continue;
      const tj = Date.now();
      const m = await renderMusic(page, name);
      m.render_ms = Date.now() - tj;
      music[name] = m;
      console.log(`music ${name.padEnd(8)} ${m.loop_len.toFixed(3)} s  peak ${db(m.peak)} dB  rms ${db(m.rms)} dB  ` +
        `gain ${m.gain_db} dB  loop: env diff p50 ${m.check.loop_env_p50_db} / max ${m.check.loop_env_max_db} dB, wave err ${m.check.loop_wave_err_db} dB, seam step ${m.check.seam_step} (p50 ${m.check.step_p50}, p99.9 ${m.check.step_p999})`);
    }
    const sfx = only && prev ? prev.sfx : {};
    for (const job of SFX_JOBS) {
      if (only && !only.has(job.id)) continue;
      const tj = Date.now();
      const s = await renderSfx(page, job);
      if (only) console.log(`  (${Date.now() - tj} ms)`);
      sfx[job.id] = s;
      if (!only || only.size < 20) console.log(`sfx ${job.id.padEnd(22)} ${s.dur.toFixed(3)} s  ch ${s.ch}  peak ${db(s.peak)} dB  ${s.file}`);
    }
    const comp = await page.evaluate('measureCompressor([-40, -30, -20, -14, -10, -6, -3, 0])');
    const compHard = await page.evaluate('measureCompressor([-40, -20, -14, -10, -6, -3, 0], 0)');
    const sha = f => crypto.createHash('sha1').update(fs.readFileSync(path.join(REPO, f))).digest('hex').slice(0, 12);
    const manifest = {
      version: 1,
      note: 'Generated by godot/tools/render_audio/render.js from js/core/audio.js + js/data/music.js. Do not edit.',
      source: { 'js/core/audio.js': sha('js/core/audio.js'), 'js/data/music.js': sha('js/data/music.js') },
      sample_rate: SR,
      mix: {
        music_bus: 'music * 0.7 (files rendered with musicBus = 1)',
        sfx_bus: 'sfx (x2.4 baked into the files; SFX reverb tails mixed at the default music/sfx balance)',
        out_gain: 0.9, smooth_tau: 0.05, fade_out: 0.7, fade_in: 0.8, start_delay: 0.1,
        compressor: { threshold_db: -14, ratio: 4, knee_db: 30, attack_ms: 3, release_ms: 250,
          chrome_curve_in_out_db: comp, chrome_curve_hard_knee: compHard,
          makeup_db: +(comp[0][1] - comp[0][0]).toFixed(2) }
      },
      biome_music: ['forest', 'cave', 'volcano'],
      music,
      sfx
    };
    if (args['check-loops']) return;
    if (args.reference) manifest.reference_jschain = await references(page, String(args.reference));
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 1) + '\n');
    let bytes = 0;
    for (const d of ['music', 'sfx']) for (const f of fs.readdirSync(path.join(OUT, d))) if (/\.(ogg|wav)$/.test(f)) bytes += fs.statSync(path.join(OUT, d, f)).size;
    console.log(`compressor (Chrome, knee 30): ${comp.map(([a, b]) => `${a}->${b}`).join(' ')} dB; makeup ${manifest.mix.compressor.makeup_db} dB`);
    console.log(`${Object.keys(music).length} tracks, ${Object.keys(sfx).length} sfx, ${(bytes / 1048576).toFixed(2)} MB in ${OUT} (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
  } finally {
    await page.close();
    srv.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
