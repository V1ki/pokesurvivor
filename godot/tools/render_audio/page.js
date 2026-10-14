/* render_audio/page.js — runs inside headless Chrome (driven by render.js).
 *
 * Loads the UNCHANGED js/core/audio.js + js/data/music.js of the web game and renders their
 * output through an OfflineAudioContext with the same graph (instruments, convolution reverb,
 * buses). audio.js keeps its context, buses and SFX table in a closure, so every render
 * re-evaluates its source with a few globals redirected:
 *   - window.AudioContext returns a Proxy of a fresh OfflineAudioContext whose currentTime is
 *     a fake clock and whose state is always 'running' (the sequencer and sfx() only run then);
 *   - setInterval (the 25 ms look-ahead sequencer) is captured and called by hand once the
 *     fake clock is moved to the end of the render, so the whole score is scheduled at once;
 *   - setTimeout runs callbacks synchronously while audio.js is called (the reverb impulse is
 *     filled "300 ms later" in the game);
 *   - performance.now (the MIN_GAP limiter) follows the fake clock;
 *   - Math.random is a seeded mulberry32 (noise, reverb IR): dry SFX re-render byte-identical;
 *   - the master DynamicsCompressor is replaced by a gain of 1/0.9 (cancels the 0.9 output gain):
 *     the compressor acts on the live music+SFX sum, so the Godot port applies it on its Master bus;
 *   - volumes come from localStorage 'ps.audio', read by audio.js itself.
 */
'use strict';
(() => {
  const SR = 44100;

  // ---------- deterministic Math.random (mulberry32) ----------
  let rs = 1;
  const seed = s => { rs = s >>> 0; };
  Math.random = function () {
    rs = (rs + 0x6D2B79F5) >>> 0;
    let t = rs;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const hashStr = s => { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0; };

  // audio.js uses performance.now() only for MIN_GAP: drive it from the fake clock.
  let fakeNowMs = 1e6;
  performance.now = () => fakeNowMs;

  window.G = { U: { clamp: (v, a, b) => Math.max(a, Math.min(b, v)) } };
  let AUDIO_SRC = null;

  /** A fresh audio.js instance bound to a new OfflineAudioContext of `seconds`. */
  function engine(seconds, vol, seedVal, opts = {}) {
    seed(seedVal);
    const real = new OfflineAudioContext(2, Math.ceil(SR * seconds), SR);
    const st = { t: 0, mute: false, sched: null, real };
    const proxy = new Proxy(real, {
      get(target, k) {
        if (k === 'currentTime') return st.t;
        if (k === 'state') return 'running';
        if (k === 'resume') return () => Promise.resolve();
        if (k === 'createDynamicsCompressor' && !opts.realCompressor) {
          return () => {
            const g = target.createGain(); g.gain.value = 1 / 0.9;
            g.threshold = { value: 0 }; g.ratio = { value: 0 };     // audio.js sets these
            return g;
          };
        }
        if (k === 'createGain' && st.mute) {
          // warm-up calls (xp combo): build the nodes but never connect them to the output
          return () => { const g = target.createGain(); g.connect = () => g; return g; };
        }
        const v = Reflect.get(target, k, target);
        return typeof v === 'function' ? v.bind(target) : v;
      }
    });
    localStorage.setItem('ps.audio', JSON.stringify(vol));
    window.AudioContext = function () { return proxy; };
    const realSI = window.setInterval;
    window.setInterval = fn => { st.sched = fn; return 0; };       // the sequencer tick
    try { (0, eval)(AUDIO_SRC); } finally { window.setInterval = realSI; }
    st.A = G.Audio;
    st.sync = f => {
      const realST = window.setTimeout;
      window.setTimeout = fn => { fn(); return 0; };
      try { return f(); } finally { window.setTimeout = realST; }
    };
    return st;
  }

  function keep(buf) {
    window.__buf = [buf.getChannelData(0), buf.getChannelData(1)];
    return buf.length;
  }

  /** Base64 of channel `ch` samples [start, start+n) as little-endian float32. */
  window.__chunk = (ch, start, n) => {
    const d = window.__buf[ch].subarray(start, start + n);
    const u8 = new Uint8Array(d.buffer, d.byteOffset, d.byteLength);
    let s = '';
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  };

  // Volumes so that the rendered files need no extra gain in Godot:
  //   SFX: sfxBus = sfx*2.4 with sfx = 1 (the x2.4 is baked in, the Godot SFX bus is just `sfx`);
  //        musicBus (where the reverb sends of bells/pads land) = 0.55: that is music*0.7 / sfx at the
  //        default volumes (0.55*0.7 / 0.7), so tails keep their default balance with the dry sound.
  //   Music: musicBus = 1 (music = 1/0.7); the Godot Music bus applies music*0.7.
  const SFX_VOL = { music: 0.55 / 0.7, sfx: 1, muted: false };
  const MUSIC_VOL = { music: 1 / 0.7, sfx: 1, muted: false };

  /**
   * One SFX. `at` = when it fires (the bus gains ramp from t=0 with tau 0.05 s, so start late).
   * `warm` = earlier muted calls 40 ms apart (xp: the combo counter reaches `warm`).
   */
  window.renderSfx = async (name, opts, warm, at, seconds) => {
    const st = engine(at + seconds, SFX_VOL, hashStr('sfx:' + name + JSON.stringify(opts || null) + ':' + warm));
    st.sync(() => st.A.unlock());
    if (warm > 0) {
      st.mute = true;
      for (let i = 0; i < warm; i++) {
        st.t = at - 0.04 * (warm - i);
        fakeNowMs += 1000;
        st.sync(() => st.A.sfx(name, opts || undefined));
      }
      st.mute = false;
    }
    st.t = at;
    fakeNowMs += 1000;
    st.sync(() => st.A.sfx(name, opts || undefined));
    return keep(await st.real.startRendering());
  };

  /** A whole song: started at t = 0 (first step at 0.1 s), score scheduled up to `seconds`. */
  window.renderMusic = async (name, seconds, realChain) => {
    const vol = realChain ? { music: 0.55, sfx: 0.7, muted: false } : MUSIC_VOL;
    const st = engine(seconds, vol, hashStr('music:' + name), { realCompressor: !!realChain });
    st.A.music(name);                 // no context yet: only remembered
    st.sync(() => st.A.unlock());     // creates the graph and starts the song at t = 0
    // Like the game's look-ahead scheduler, but in 1 s slices: the render suspends every second
    // and the sequencer is run up to 1.2 s ahead (scheduling the whole score up front keeps
    // tens of thousands of idle nodes in the graph and renders ~10x slower).
    const STEP = 1;
    const tick = ts => { st.t = ts + STEP + 0.2; st.sched(); };
    tick(0);
    for (let ts = STEP; ts < seconds; ts += STEP) {
      st.real.suspend(ts).then(() => { tick(ts); st.real.resume(); });
    }
    const info = { track: st.A.track };
    info.len = keep(await st.real.startRendering());
    return info;
  };

  /** Song metadata from G.MUSIC (same rules as audio.js compile()). */
  window.songInfo = name => {
    const s = G.MUSIC[name];
    if (!s) return null;
    const bars = s.bars || s.chords.length;
    return { bpm: s.bpm, swing: s.swing || 0, bars, steps: bars * 16, loop: bars * 16 * 60 / s.bpm / 4, lead: (s.melody || [])[0] && s.melody[0].inst };
  };

  /** Static curve of Chrome's DynamicsCompressorNode as audio.js configures it (sine in, peak out). */
  window.measureCompressor = async (levelsDb, knee) => {
    const out = [];
    for (const db of levelsDb) {
      const c = new OfflineAudioContext(1, SR, SR);
      const o = c.createOscillator(); o.frequency.value = 997;
      const g = c.createGain(); g.gain.value = Math.pow(10, db / 20);
      const k = c.createDynamicsCompressor(); k.threshold.value = -14; k.ratio.value = 4;
      if (knee != null) k.knee.value = knee;
      o.connect(g).connect(k).connect(c.destination); o.start();
      const d = (await c.startRendering()).getChannelData(0);
      let pk = 0;
      for (let i = d.length - 11025; i < d.length; i++) pk = Math.max(pk, Math.abs(d[i]));
      out.push([db, +(20 * Math.log10(pk)).toFixed(3)]);
    }
    return out;
  };

  (async () => {
    AUDIO_SRC = await (await fetch('/js/core/audio.js')).text();
    (0, eval)(await (await fetch('/js/data/music.js')).text());
    window.__ready = true;
  })().catch(e => { window.__error = String(e && e.stack || e); });
})();
