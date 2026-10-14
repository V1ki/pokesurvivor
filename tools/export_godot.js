/* ============ export_godot.js — static data for the Godot port ============
 *   node tools/export_godot.js [repoRoot] [outDir]      (default outDir: godot/data)
 * Loads the game's data files in a vm sandbox (like tools/export_data.js).
 * Module-private tables are exposed by patching the source text IN MEMORY;
 * no file on disk is modified. See godot/docs/PORTING.md §10.2 / Appendix A. */
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const OUT = path.resolve(process.argv[3] || path.join(ROOT, 'godot', 'data'));
const noop = () => {};
const fakeCtx = new Proxy({}, { get: () => noop });
const G = {};
const sandbox = {
  G, console, Math, JSON, Date, Map, Set, Object, Array, Number, String, RegExp, Promise, Symbol, Infinity, NaN, isFinite, parseInt, parseFloat,
  location: { pathname: '/', protocol: 'file:', search: '' }, navigator: { language: 'es', languages: ['es'] },
  localStorage: { getItem: () => null, setItem: noop },
  document: { documentElement: { style: { setProperty: noop } }, createElement: () => ({ getContext: () => fakeCtx, width: 0, height: 0 }),
              addEventListener: noop, querySelector: () => null, body: {} },
  addEventListener: noop, matchMedia: () => ({ matches: false }), CanvasRenderingContext2D: function () {}, Image: function () {},
  performance: { now: () => 0 }, setTimeout: noop, setInterval: noop, requestAnimationFrame: noop
};
sandbox.window = sandbox;
vm.createContext(sandbox);
const load = (f, patch) => {
  let src = fs.readFileSync(path.join(ROOT, f), 'utf8');
  if (patch) { const s2 = patch(src); if (s2 === src) throw new Error('patch did not apply: ' + f); src = s2; }
  vm.runInContext(src, sandbox, { filename: f });
};
const EN = {};
load('js/core/util.js'); load('js/core/i18n.js');
const add = G.I18n.add; G.I18n.add = (d, l = 'en') => { if (l === 'en') Object.assign(EN, d); add(d, l); };
load('js/data/lang-en.js'); load('js/core/settings.js'); load('js/data/music.js'); load('js/data/pokedex.js'); load('js/data/sprites-meta.js');
G.Sprites = { PX: 2, hovers: d => !!(G.SPRITE_META[d] && G.SPRITE_META[d].hv), hasShiny: d => !!(G.SPRITE_META[d] && G.SPRITE_META[d].sh) };
load('js/data/moves.js', s => s.replace('G.Moves = { ALL: RAW,', 'G.Moves = { LADDERS, EVO_MODS, START, MULT, ADD, ALL: RAW,'));
load('js/data/enemies.js', s => s.replace('TIERS, BOSS_SLOTS, LATE_FROM,', 'behaviorOf, defFor, HEAL: [...HEAL], SHIELD: [...SHIELD], BOMB: [...BOMB], SUMMON, TIERS, BOSS_SLOTS, LATE_FROM,'));
for (const f of ['js/data/types.js', 'js/data/starters.js', 'js/data/upgrades.js', 'js/data/items.js',
                 'js/data/missions.js', 'js/data/achievements.js', 'js/world/tiles.js']) load(f);
load('js/entities/vfx.js', s => s.replace('return { PAL, SHAPES, draw,', 'return { grid, MOVE, TYPE_SHAPE, PAL, SHAPES, draw,'));
load('js/ui/icons.js', s => s.replace('return { canvas, url,', 'return { KIND_GLYPH, canvas, url,'));
load('js/systems/levelup.js'); load('js/systems/gacha.js');
load('js/systems/weather.js', s => s.replace('KINDS, reset,', 'KINDS, BIOME_W, reset,'));
load('js/systems/interact.js');

const strip = o => JSON.parse(JSON.stringify(o));       // drops functions
const files = {};

files['pokedex.json'] = G.DEX;
files['sprite_meta.json'] = G.SPRITE_META;
const M = G.Moves;
files['moves.json'] = {
  moves: M.ALL.map(m => { const o = strip(m); delete o.ups; return o; }),   // post melee transform
  ladders: M.LADDERS, evo: M.EVO, evo_mods: M.EVO_MODS, need_name: M.NEED_NAME, start_by_type: M.START,
  mult_keys: M.MULT, add_keys: M.ADD, pool_by_type: M.POOL,
  vfx: Object.fromEntries(M.ALL.map(m => [m.id, G.VFX.forMove(m)]))
};
files['types.json'] = { chart: G.Types.CHART, soft: { '2': 1.6, '0.5': 0.6, '0': 0.3 }, min: 0.3, max: 2.4,
  order: Object.keys(G.U.TYPE_NAME), color: G.U.TYPE_COLOR, name_es: G.U.TYPE_NAME };
files['starters.json'] = { starters: G.STARTERS, test: G.PERSONALITY_TEST, trait_text: G.TRAIT_TEXT };
const E = G.Enemies;
files['enemies.json'] = { tiers: E.TIERS, boss_slots: E.BOSS_SLOTS, late_from: E.LATE_FROM,
  heal: E.HEAL, shield: E.SHIELD, bomb: E.BOMB, summon: E.SUMMON,
  behavior_by_dex: Object.fromEntries(G.DEX.map(p => [p.dex, E.behaviorOf(p)])),          // verification table
  candidates_by_tier: E.TIERS.map(t => E.candidates(t).map(p => p.dex)) };
files['upgrades.json'] = G.Upgrades.LIST;
files['items.json'] = strip(G.Items.LIST);
files['levelup_stats.json'] = strip(G.LevelUp.STATS);
files['missions.json'] = { daily: strip(G.MissionDefs.daily), weekly: strip(G.MissionDefs.weekly) };
files['achievements.json'] = { cats: G.AchDefs.CATS, list: strip(G.AchDefs.LIST) };
files['gacha.json'] = { banners: G.Gacha.BANNERS, rates: G.Gacha.RATES, pity: G.Gacha.PITY_5, shiny_rate: G.Gacha.SHINY_RATE,
  refund: G.Gacha.REFUND, rarity_name: G.Gacha.RARITY_NAME, rarity_color: G.Gacha.RARITY_COLOR };
files['world.json'] = { tile_px: G.Tiles.T, biomes: G.Tiles.BIOMES, arena_first: G.Tiles.ARENA, arena_types: G.Tiles.ARENA_TYPES,
  arena_themes: G.Tiles.ARENA_THEMES, weather: G.Weather.KINDS, weather_biome_w: G.Weather.BIOME_W, altar_powers: strip(G.Interact.POWERS) };
// VFX shapes as palette-letter grids (o d m l w L) per frame.
const shapes = {};
for (const [name, S] of Object.entries(G.VFX.SHAPES)) {
  const frames = [];
  for (let f = 0; f < (S.frames || 1); f++) { const P = G.VFX.grid(S.w, S.h); S.gen(P, f); frames.push(P.g.map(r => r.map(c => c || '.').join(''))); }
  shapes[name] = { w: S.w, h: S.h, dir: !!S.dir, spin: !!S.spin, frames };
}
files['vfx.json'] = { pal: G.VFX.PAL, type_shape: G.VFX.TYPE_SHAPE, shapes };
files['icons.json'] = { ui: G.Icons.UI, type_glyph: G.Icons.TYPE_GLYPH, kind_glyph: G.Icons.KIND_GLYPH, rarity_ball: G.Icons.RARITY_BALL };
files['music.json'] = { songs: G.MUSIC, biome_music: G.BIOME_MUSIC };
files['i18n_en.json'] = EN;

// Reference values computed by the JS code itself (used by the Godot unit tests).
const P = G.DEX.find(p => p.dex === 4);
// Mission RNG: verbatim copy of the private rng() in js/systems/progress.js (FNV-1a + mulberry32).
function rng(seedStr) {
  let h = 2166136261;
  for (let i = 0; i < seedStr.length; i++) { h ^= seedStr.charCodeAt(i); h = Math.imul(h, 16777619); }
  return () => { h += 0x6D2B79F5; let t = h; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const mr = rng('d20261013' + '1700000000000');
// IEEE-754 bits (little-endian hex) for bit-exact checks: Godot's JSON/String.to_float is
// not correctly rounded (can be 1-2 ulp off), so exact doubles are compared via their bits.
const bits = v => { const b = Buffer.alloc(8); b.writeDoubleLE(v); return b.toString('hex'); };
const inst = (id, lvl, evo) => { const m = M.instance(id, lvl); if (evo) M.evolve(m); const o = strip(m); delete o.def; return o; };
// Terrain dump (world.js is only read; its generation code runs unchanged in the sandbox).
load('js/entities/player.js'); load('js/systems/spawner.js');      // only class/IIFE definitions run
let terrain = null;
try {
  load('js/world/world.js');
  const W = G.World, KIND = ['floor', 'wall', 'liquid'];
  const dump = (seed, x0, y0, n) => {
    W.reset(seed); W.setBiome(0, true);
    const rows = [];
    for (let ty = y0; ty < y0 + n; ty++) {
      let s = '';
      for (let tx = x0; tx < x0 + n; tx++) s += 'fwl'[KIND.indexOf(W.kindAt(tx * W.TS + 16, ty * W.TS + 16))];
      rows.push(s);
    }
    return { seed, x0, y0, rows };
  };
  terrain = [dump(12345, -40, -40, 80), dump(777, 3000, -2000, 48), dump(1, -500, 260, 32)];
} catch (e) { console.warn('terrain dump skipped:', e.message); }
files['test_vectors.json'] = {
  hash: [[0, 0, 0], [1, 0, 0], [5, -3, 4242], [25, 7, 11], [-17, 123, 909], [1000, 7, 11], [123456, -654321, 2246822519], [-5, -9, 101]]
    .map(([x, y, s]) => ({ x, y, seed: s, v: G.U.hash(x, y, s), bits: bits(G.U.hash(x, y, s)) })),
  mulberry: (() => { const v = [mr(), mr(), mr(), mr(), mr()]; return { seed: 'd20261013' + '1700000000000', values: v, bits: v.map(bits) }; })(),
  enemy_scale: [0, 60, 180, 300, 600, 3600, 5400].map(t => {
    const sc = E.scale(t), bs = E.bossScale(t);
    return { t, scale: sc, boss: bs, bits: { hp: bits(sc.hp), dmg: bits(sc.dmg), spd: bits(sc.spd), bhp: bits(bs.hp), bdmg: bits(bs.dmg) } };
  }),
  def_for_dex4: E.TIERS.map((tier, ti) => E.defFor(P, tier, ti)),
  start_move_dex4: G.startMoveOf(4),
  move_instances: [['ember', 1], ['ember', 3], ['ember', 5], ['tackle', 5], ['giga-drain', 4], ['fire-spin', 5], ['vine-whip', 2]]
    .map(([id, lvl]) => ({ id, lvl, m: inst(id, lvl, false) }))
    .concat([['ember', 5], ['tackle', 5], ['fire-spin', 5]].map(([id, lvl]) => ({ id, lvl, evolved: true, m: inst(id, lvl, true) }))),
  xp_for: Array.from({ length: 60 }, (_, i) => G.Player.xpFor(i + 1)),
  spawn_rate: [0, 30, 60, 120, 300, 900].map(t => ({ t, v: G.Spawner.rate(t), bits: bits(G.Spawner.rate(t)) })),
  terrain
};

fs.mkdirSync(OUT, { recursive: true });
for (const [name, data] of Object.entries(files)) {
  const s = JSON.stringify(data);
  fs.writeFileSync(path.join(OUT, name), s);
  console.log(name.padEnd(22), (s.length / 1024).toFixed(1).padStart(7), 'KB');
}

// ============ Phase 4 (meta-progression) reference vectors -> test_vectors_p4.json ============
// Separate output so the core exports above stay untouched. Runs the unchanged db.js (newSave /
// migrate / sanitize exposed in memory), gacha.js, progress.js (+ ranking.js periodIds),
// achievements.js and starters.js with a seeded Math.random where the JS code draws randomly.
(function exportPhase4() {
  sandbox.Intl = Intl;
  sandbox.Buffer = Buffer;
  load('js/core/db.js', s => s.replace('owns, grant, ownsShiny, grantShiny, merge,', 'owns, grant, ownsShiny, grantShiny, merge, newSave, migrate, sanitize,'));
  load('js/net/ranking.js');
  load('js/systems/progress.js', s => s.replace('return { ensure, event,', 'return { rng, pickSet, ensure, event,'));
  const DB = G.DB, MD = G.MissionDefs;
  const seeded = seed => { const r = G.Progress.rng(seed); return () => r(); };
  const withRandom = (seed, fn) => { const old = Math.random; Math.random = seeded(seed); try { return fn(); } finally { Math.random = old; } };
  const clone = o => JSON.parse(JSON.stringify(o));
  const out = {};

  // --- save: migrate + sanitize on the real web save and on a hand-made legacy save ---
  const fixPath = path.join(ROOT, 'godot', 'tests', 'fixtures', 'web_guest_save.json');
  const legacy = {
    name: 'Viejo', created: 1700000000000, updated: 1700000500000, coins: -40, owned: { 4: { at: 1, from: 'starter' }, 9999: { at: 2, from: 'gacha' }, '025': { at: 3, from: 'gacha' }, 25: { at: 4, from: 'gacha' } },
    shiny: { 4: { at: 5, from: 'wild' }, 0: { at: 6, from: 'wild' } }, partner: 4, starter: 4, pity: 33, upgrades: { hp: 3, atk: 0, coins: 2 },
    tickets: { t1: '7', t10: 2.9 }, stats: { runs: 3, bestTime: 100 },
    pbind: { 4: ['ember', 'ember', 'nope', 'tackle', 'scratch'], 7: 'x' }, pban: { 4: ['tackle', 'tackle', 'growl', 'nope', 'ember', 'scratch'] },
    pupg: { 7: { hp: 99, zzz: 3, atk: -2, crit: '4' }, 1: null }
  };
  out.save = {
    fixture: fs.existsSync(fixPath) ? { input: JSON.parse(fs.readFileSync(fixPath, 'utf8')) } : null,
    legacy: { input: clone(legacy) },
    new_save_keys: Object.keys(DB.newSave('x')), new_save_stats: Object.keys(DB.newSave('x').stats)
  };
  if (out.save.fixture) out.save.fixture.output = DB.migrate(clone(out.save.fixture.input), 'Invitado');
  out.save.legacy.output = DB.migrate(clone(legacy), '');

  // --- end-of-run coins (formula copied from game.js endRun, evaluated by V8) ---
  const coinCase = ([time, kills, bosses, picked, mul]) => {
    const parts = { tiempo: Math.floor(time / 5), derrotados: Math.floor(kills * 0.25), jefes: bosses * 80, recogidas: picked };
    const coins = Math.round((parts.tiempo + parts.derrotados + parts.jefes + parts.recogidas) * mul);
    const breakdown = Object.entries(parts).filter(([, v]) => v).map(([k, v]) => `${k} ${v}`).join(' · ') + (mul > 1 ? ` · ×${mul.toFixed(2)} Fortuna` : '');
    return { time, kills, bosses, picked, mul, coins, breakdown };
  };
  const P0 = G.Upgrades.perks({}), P5 = G.Upgrades.perks({ coins: 5 }), P8 = G.Upgrades.perks({ coins: 8 });
  out.coins = [[0, 0, 0, 0, 1], [4.99, 3, 0, 0, 1], [279.6, 431, 1, 37, P5.coinMul], [612.3, 2500, 3, 220, P8.coinMul],
    [61, 77, 0, 12, P8.coinMul * 1.5], [1234.5, 9001, 7, 999, P0.coinMul * 1.5], [37.5, 2, 0, 3, 1 + 1 * 0.08]].map(coinCase);

  // --- upgrades ---
  out.upgrades = {
    cost: Object.fromEntries(G.Upgrades.LIST.map(u => [u.id, Array.from({ length: u.max }, (_, l) => G.Upgrades.cost(u.id, l))])),
    perks: [{}, { hp: 4, atk: 2, spd: 3, cd: 1, def: 1, regen: 2, magnet: 3, coins: 5, ban: 3 }, { hp: 99, atk: -3, moves: 1, crit: 10, reroll: 5, xp: 8 }]
      .map(l => ({ levels: l, perks: G.Upgrades.perks(l) }))
  };

  // --- gacha: deterministic pulls with a seeded Math.random ---
  const gsave = () => { const s = DB.newSave('Gacha'); s.created = 1; s.tickets = { t1: 200, t10: 3 }; s.owned = { 1: { at: 1, from: 'starter' }, 4: { at: 1, from: 'gacha' } }; s.pity = { 1: 60, 9: 68 }; return s; };
  out.gacha = [['g-a', 1, 10, 't1'], ['g-b', 9, 10, 't10'], ['g-c', 1, 1, 't1'], ['g-d', 5, 10, 't1'], ['g-e', 7, 10, 't1']].map(([seed, gen, n, use]) => {
    const s = gsave();
    const steps = [];
    withRandom(seed, () => { for (let k = 0; k < 6; k++) steps.push(G.Gacha.pull(s, n, gen, use)); });
    return { seed, gen, n, use, results: steps, pity: s.pity, coins: s.coins, tickets: s.tickets, pulls: s.stats.pulls,
             owned: Object.keys(s.owned).map(Number).sort((a, b) => a - b), shiny: Object.keys(s.shiny).map(Number).sort((a, b) => a - b) };
  });
  // shiny duplicates: a save that owns the shinies of every odd gen-1 dex, 1000 pulls (swap / turn normal paths)
  { const s = gsave(); s.tickets.t1 = 3000;
    for (const p of G.DEX) if (p.gen === 1 && p.dex % 2 === 1 && G.Sprites.hasShiny(p.dex)) s.shiny[p.dex] = { at: 1, from: 'gacha' };
    const n0 = Object.keys(s.shiny).length;
    const res = withRandom('g-shiny', () => { const r = []; for (let k = 0; k < 1000; k++) r.push(...G.Gacha.pull(s, 1, 1, 't1')); return r; });
    out.gacha_shiny = { seed: 'g-shiny', pulls: 1000, input_shiny: n0, shinies: res.filter(r => r.shiny), coins: s.coins, owned_n: Object.keys(s.owned).length,
                        shiny_n: Object.keys(s.shiny).length, pity: s.pity }; }
  out.gacha_pools = Object.fromEntries(G.Gacha.BANNERS.map(b => [b.gen, [1, 2, 3, 4, 5].map(r => G.Gacha.pool(r, b.gen).length)]));
  out.gacha_featured = Object.fromEntries(G.Gacha.BANNERS.map(b => [b.gen, G.Gacha.featured(b.gen)]));

  // --- missions: Madrid period ids and the generated sets ---
  const dates = ['2026-10-13T10:00:00Z', '2026-10-13T22:30:00Z', '2026-10-25T00:30:00Z', '2026-10-25T01:30:00Z', '2026-03-29T00:59:00Z',
    '2026-03-29T01:00:00Z', '2026-12-31T22:59:59Z', '2026-12-31T23:00:00Z', '2027-01-03T12:00:00Z', '2027-01-04T00:00:00Z',
    '2020-12-31T23:30:00Z', '2021-01-03T23:30:00Z', '2024-02-29T23:00:00Z', '2025-12-28T23:10:00Z', '2026-06-15T21:59:59Z', '2026-06-15T22:00:00Z'];
  out.periods = dates.map(d => ({ iso: d, ms: Date.parse(d), ids: (({ d: dd, w }) => ({ d: dd, w }))(G.Ranking.periodIds(new Date(d))) }));
  const created = [1700000000000, 1791894369798, 0, 1234567];
  out.missions = [];
  for (const p of out.periods.slice(0, 8)) for (const c of created) {
    out.missions.push({ ms: p.ms, created: c, daily: G.Progress.pickSet(MD.daily, 3, G.Progress.rng(p.ids.d + String(c))),
                        weekly: G.Progress.pickSet(MD.weekly, 2, G.Progress.rng(p.ids.w + String(c))) });
  }
  out.mission_text = [...MD.daily, ...MD.weekly].flatMap(d => d.goals.map(g => ({ id: d.id, goal: g, param: d.param ? 'fire' : null, text: d.text(g, d.param ? 'fire' : null) })));

  // --- achievements: values and grants ---
  const ach = s => Object.fromEntries(G.AchDefs.LIST.map(a => [a.id, a.value(s)]));
  const rich = DB.newSave('Rico'); rich.created = 5;
  for (const p of G.DEX.slice(0, 260)) rich.owned[p.dex] = { at: 1, from: 'gacha' };
  for (const d of [1, 4, 7, 25, 150, 151]) rich.shiny[d] = { at: 1, from: 'gacha' };
  for (const p of G.DEX.filter(p => p.leg).slice(0, 12)) rich.legends[p.dex] = 1;
  Object.assign(rich.stats, { runs: 51, bestTime: 1201, bestLevel: 31, totalKills: 10500, pulls: 100, bossesTotal: 25, riftWins: 10, evolutions: 26, missionsDone: 50, groupRuns: 1 });
  rich.arenas = { fire: 1, water: 1 }; rich.itemsFound = { a: 1, b: 1, c: 1, d: 1, e: 1 }; rich.evoMoves = { ember: 1 };
  const before = clone(rich);
  const granted = [];
  for (const a of G.AchDefs.LIST) { if (!rich.ach[a.id] && a.value(rich) >= a.goal) { granted.push(a.id); const r = a.reward; rich.coins += r.coins || 0; rich.tickets.t1 += r.t1 || 0; rich.tickets.t10 += r.t10 || 0; } }
  out.achievements = { count: G.AchDefs.LIST.length, titles: G.AchDefs.LIST.filter(a => a.title).length,
    fixture_values: out.save.fixture ? ach(out.save.fixture.output) : null, rich: { input: before, values: ach(before), granted, coins: rich.coins, tickets: rich.tickets } };

  // --- personality test result (G.personalityResult, ties picked with the seeded Math.random) ---
  const answersFor = idx => { const sc = {}; G.PERSONALITY_TEST.forEach((q, i) => { const a = q.a[idx[i]]; for (const k in a.p) sc[k] = (sc[k] || 0) + a.p[k]; }); return sc; };
  out.personality = [[0, 0, 0, 0, 0, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1, 1], [2, 2, 2, 2, 2, 2, 2, 2], [3, 3, 3, 3, 3, 3, 3, 3], [0, 1, 2, 3, 0, 1, 2, 3], [3, 2, 1, 0, 3, 2, 1, 0], [2, 0, 3, 1, 2, 0, 3, 1]]
    .map((idx, i) => { const scores = answersFor(idx); const r = withRandom('pers' + i, () => G.personalityResult(scores));
      const cand = []; let best = -1; for (const s of G.STARTERS) { const v = (scores[s.traits[0]] || 0) * 2 + (scores[s.traits[1]] || 0); if (v > best) { best = v; cand.length = 0; cand.push(s.dex); } else if (v === best) cand.push(s.dex); }
      return { answers: idx, scores, trait: r.trait, dex: r.dex, candidates: cand, seed: 'pers' + i }; });

  const s4 = JSON.stringify(out);
  fs.writeFileSync(path.join(OUT, 'test_vectors_p4.json'), s4);
  console.log('test_vectors_p4.json'.padEnd(22), (s4.length / 1024).toFixed(1).padStart(7), 'KB');
})();

// ============ Phase 2 (combat completeness) reference vectors -> test_vectors_p2.json ============
// Separate output. Runs the unchanged enemy.js, combat.js (reach exposed), hazards.js and
// pathing.js (field map exposed) with small stubs for the browser-only parts (sprites
// animator, camera, FX, audio); the stubbed G members are restored afterwards.
(function exportPhase2() {
  const KEYS = ['Sprites', 'Camera', 'FX', 'Audio', 'Coop', 'Hazards', 'Projectiles', 'Spawner', 'World', 'Path', 'Weather',
                'Game', 'Progress', 'Events', 'Rift', 'Pickups', 'Combat', 'Enemy', 'EnemyMgr', 'Interact'];
  const keep = {};
  for (const k of KEYS) keep[k] = G[k];
  const SM = G.SPRITE_META;
  const animMeta = (dex, anim) => { const m = SM[dex]; if (!m) return null; const nm = m.a[anim] ? anim : (m.a.Idle ? 'Idle' : 'Walk'); return m.a[nm] || null; };
  G.Sprites = Object.assign({}, keep.Sprites, {
    PX: 2, animMeta,
    bodyRadius: (d, s = 1) => { const m = animMeta(d, 'Idle'); return G.U.clamp((m ? m.w : 32) * 0.22, 5, 26) * 2 * s; },
    bodyHeight: (d, s = 1) => { const m = animMeta(d, 'Idle'); return (m ? m.ay : 24) * 2 * s; },
    Animator: class { constructor(dex, scale = 1) { this.dex = dex; this.scale = scale; this.dir = 0; } play() {} loop() {} busy() { return false; } progress() { return 1; } update() {} },
    preload: noop, hovers: d => !!(SM[d] && SM[d].hv), hasShiny: d => !!(SM[d] && SM[d].sh),
    dirFromAngle: a => ((Math.round((Math.PI / 2 - a) / (Math.PI / 4)) % 8) + 8) % 8
  });
  load('js/systems/hazards.js');
  const hazardInside = G.Hazards.inside;
  const hz = [], shots = [];
  G.Hazards = { add: h => { hz.push(Object.assign({}, h)); return h; } };
  G.Projectiles = { spawn: p => { shots.push({ x: p.x, y: p.y, vx: p.vx, vy: p.vy, dmg: p.dmg, r: p.r, life: p.life, friendly: p.friendly, mtype: p.mtype }); return p; },
                    nearest: () => null, all: () => [] };
  G.FX = new Proxy({}, { get: () => noop });
  G.Audio = { sfx: noop, music: noop };
  G.Coop = { isHost: false, active: false };
  G.Camera = { sees: () => true, kick: noop, outerRadius: () => 500 };
  G.Spawner = { say: noop, CAP: 64 };
  G.World = { collide: () => false, isLiquid: () => false, TS: 32 };
  G.Path = { dirFor: () => null };
  G.Weather = { speedFor: () => 1, mult: () => 1 };
  const plStub = { x: 300, y: 120, r: 12, atk: 1.5, baseAtk: 1, dead: false };
  G.Game = { everyone: () => [plStub], player: plStub };
  load('js/entities/enemy.js');
  load('js/systems/combat.js', s => s.replace('return { tick, resolve,', 'return { reach, tick, resolve,'));
  load('js/systems/pathing.js', s => s.replace('return { update, dirFor, clear };', 'return { fields, update, dirFor, clear };'));
  const out = {};

  // --- moves: every move at levels 1..5 and evolved; reach(); evolution conditions ---
  out.moves = M.ALL.map(m => ({ id: m.id, lv: [1, 2, 3, 4, 5].map(l => inst(m.id, l, false)), evo: inst(m.id, 5, true) }));   // ladders of every kind
  out.reach = M.ALL.map(m => [m.id, G.Combat.reach(M.instance(m.id, 1)), G.Combat.reach(M.instance(m.id, 5))]);
  out.evo_info = M.ALL.flatMap(m => {
    const e = M.EVO[m.id], needs = e ? e[1] : 'atk';
    const cases = [[5, {}], [5, { [needs]: 1 }], [4, { [needs]: 1 }], [5, { [needs === 'atk' ? 'hp' : 'atk']: 2 }]];
    return cases.map(([lvl, st]) => { const s = M.instance(m.id, lvl); const r = M.evoInfo(s, st); return { id: m.id, lvl, stats: st, r: r && { name: r.name, needs: r.needs, ready: r.ready } }; })
      .concat([(() => { const s = M.instance(m.id, 5); M.evolve(s); return { id: m.id, lvl: 5, evolved: true, stats: { [needs]: 1 }, r: M.evoInfo(s, { [needs]: 1 }) }; })()]);
  });

  // --- enemy defs for every species (tiers 1 and 4), compact rows ---
  const nn = v => v === undefined ? null : v;
  out.def_for = [1, 4].map(ti => ({ ti, rows: G.DEX.map(p => { const d = E.defFor(p, E.TIERS[ti], ti);
    return [d.dex, d.behavior, d.hp, d.spd, d.dmg, d.xp, nn(d.shotDmg), nn(d.shotCd), nn(d.range), nn(d.minion), nn(d.fanN), nn(d.zones)]; }) }));

  // --- bosses: rolled defs (slot -> def) and on-time stats of a boss Enemy ---
  const bossDefs = [];
  for (let i = 0; i < 12; i++) E.rollRun().bosses.forEach((b, slot) => bossDefs.push({ slot, def: Object.assign({}, b) }));
  out.boss_defs = bossDefs;
  const near = (e, x, y) => { e.x = x; e.y = y; };
  const caseShots = () => shots.map(s => ({ a: Math.atan2(s.vy, s.vx), sp: Math.hypot(s.vx, s.vy), dmg: s.dmg, r: s.r, life: s.life, mtype: s.mtype }));
  out.bosses = bossDefs.slice(0, 5).map(({ slot, def }) => {
    const sc = E.bossScale(def.at);
    const e = new G.Enemy(def, 0, 0, sc, true);
    e.bossInit();
    const casts = [];
    for (const fury of [false, true]) for (const id of ['slam', 'dash', 'leap', 'rain', 'beam', 'volley', 'nova']) {
      hz.length = 0; shots.length = 0;
      e.ai.fury = fury; e.ai.cast = null; e.jump = null; near(e, 0, 0);
      e.bossStart(id, plStub);
      const c = e.ai.cast ? Object.assign({}, e.ai.cast) : null;
      if (e.ai.cast && (id === 'volley' || id === 'nova')) e.bossCast(e.ai.cast.wind, plStub);
      casts.push({ id, fury, cast: c, jump: e.jump ? Object.assign({}, e.jump) : null, hazards: hz.map(h => Object.assign({}, h)), shots: caseShots() });
    }
    return { slot, def, maxHp: e.maxHp, dmg: e.dmg, spd: e.spd, scale: e.scale, r: e.r, shotDmg: e.shotDmg(),
             ai: { melee: e.ai.melee, ranged: e.ai.ranged, farLike: e.ai.farLike, mode: e.ai.mode }, casts };
  });

  // --- behaviors: specials, jumps, fuses with a spawn-like stat scale ---
  const ti = 2, tier = E.TIERS[ti];
  const firstOf = beh => G.DEX.find(p => E.behaviorOf(p) === beh && p.bst >= tier.bst[0] && p.bst <= tier.bst[1]) || G.DEX.find(p => E.behaviorOf(p) === beh);
  const sc = { hp: 3.7 * 1.9, dmg: 1.4, spd: 1.1 };
  out.behaviors = ['ranged', 'fan', 'beamer', 'zoner', 'jumper', 'bomber'].map(beh => {
    const p = firstOf(beh), def = E.defFor(p, tier, ti);
    const e = new G.Enemy(def, 100, 50, sc);
    e.dmg *= 2.4;
    hz.length = 0; shots.length = 0;
    const [dx, dy] = G.U.norm(plStub.x - e.x, plStub.y - e.y);
    if (beh === 'jumper') e.startJump(plStub); else if (beh === 'bomber') e.startFuse(); else e.special(plStub, dx, dy);
    return { beh, dex: p.dex, ti, sc, def, x: e.x, y: e.y, maxHp: e.maxHp, dmg: e.dmg, shotDmg: e.shotDmg(), hazards: hz.map(h => Object.assign({}, h)),
             shots: caseShots(), jump: e.jump ? Object.assign({}, e.jump) : null, phase: e.phase, pt: e.pt };
  });
  // supports: heal / shields / summon on a small known group
  {
    const mk = (beh, x, y) => { const p = firstOf(beh) || G.DEX[0]; const e = new G.Enemy(E.defFor(p, tier, ti), x, y, sc); e.dmg *= 2.4; return e; };
    // away from the origin: the JS grid key (cx*73856093 ^ cy*19349663) collides for cells (a,b)/(-a,-b) near it, and
    // queryCircle then returns some enemies twice (the Godot port uses an exact key; see README "Spec corrections")
    const O = [2600, 1300];
    const group = () => { G.EnemyMgr.clear(); const list = [[ 'healer', 0, 0], ['shielder', 40, 10], ['chase', -60, 30], ['chase', 100, 90],
      ['chase', 145, 20], ['chase', 20, -150], ['chase', -30, -35], ['chase', 70, -60], ['chase', 158, 0]].map(([b, x, y]) => mk(b, O[0] + x, O[1] + y));
      list.forEach((e, i) => { e.hp = Math.round(e.maxHp * (0.3 + 0.07 * i)); G.EnemyMgr.add(e); }); G.EnemyMgr.rebuildGrid(); return list; };
    let list = group();
    plStub.atk = 3.2; plStub.baseAtk = 1;
    const before = list.map(e => e.hp);
    list[0].healAround();
    const healed = list.map(e => ({ x: e.x, y: e.y, maxHp: e.maxHp, hp: e.hp }));
    list = group();
    list[1].castShields();
    const shielded = list.map(e => ({ shield: e.shield, shieldT: e.shieldT }));
    G.EnemyMgr.clear();
    const sp = firstOf('summoner'), sdef = E.defFor(sp, tier, ti);
    const s = new G.Enemy(sdef, 0, 0, sc);
    G.EnemyMgr.add(s);
    s.summon();
    const minions = s.minions.map(m => ({ dex: m.dex, def: m.def, maxHp: m.maxHp, dmg: m.dmg, spd: m.spd, xp: m.xp }));
    out.supports = { ti, sc, pl_atk: 3.2, group_start_hp: before, group: list.map(e => ({ dex: e.dex, behavior: e.behavior, x: e.x, y: e.y })), healed, shielded,
                     summoner: { dex: sp.dex, def: sdef, minions } };
    G.EnemyMgr.clear();
    plStub.atk = 1.5;
  }

  // --- hazards: inside() over a grid of points ---
  const H = [{ kind: 'zone', x: 10, y: -5, r: 44 }, { kind: 'zone', x: -20, y: 30, r: 96 }, { kind: 'beam', x: 0, y: 0, angle: 0.7, len: 360, w: 22 },
             { kind: 'beam', x: 50, y: -40, angle: -2.4, len: 400, w: 26 }];
  out.hazards_inside = H.map(h => { let bits = ''; for (const r of [8, 14]) for (let y = -320; y <= 320; y += 11) for (let x = -320; x <= 420; x += 13) bits += hazardInside(h, x, y, r) ? '1' : '0'; return { h, bits }; });

  // --- flow field on a known map ---
  const walk = (tx, ty) => !((tx === 4 && ty > -25 && ty < 20) || (ty === 9 && tx > -15 && tx < 4) || (tx === -6 && ty > -18 && ty < 5) || G.U.hash(tx, ty, 99) < 0.17);
  G.World = { TS: 32, walkable: walk };
  const pp = { x: 37.3, y: -12.9, dead: false };
  G.Path.clear(); G.Path.update(1, [pp]);
  const f = G.Path.fields.get(pp);
  const rows = []; for (let j = 0; j < 57; j++) { let s = ''; for (let i = 0; i < 57; i++) s += walk(f.ox + i, f.oy + j) ? '.' : '#'; rows.push(s); }
  const dirs = [];
  for (let k = 0; k < 220; k++) {
    // 160 anywhere in the field, 60 close to the player (line-of-sight shortcuts)
    const span = k < 160 ? 1700 : 260;
    const x = pp.x + (G.U.hash(k, 1, 7) - 0.5) * span, y = pp.y + (G.U.hash(k, 2, 7) - 0.5) * span, r = [8, 11, 15, 22][k % 4];
    const e = { x, y, r }, d = G.Path.dirFor(e, pp);
    dirs.push({ x, y, r, d, los: !!e.los });
  }
  out.flow = { pl: pp, ox: f.ox, oy: f.oy, rows, dist: Array.from(f.dist), dirs };

  // --- held items: stats after equip and after switching ---
  try {
    out.items = G.Items.LIST.map(it => {
      const p = new G.Player(G.DEX_BY[4], G.Upgrades.perks({}), false);
      const snap = () => ({ atkMul: p.atkMul, cdMul: p.cdMul, spdMul: p.spdMul, xpMul: p.xpMul, coinMul: p.coinMul, dmgReduce: p.dmgReduce, regenFlat: p.regenFlat });
      p.equip(it.id); const on = snap();
      p.equip(it.id === 'leftovers' ? 'choiceband' : 'leftovers'); const sw = snap();
      p.equip(it.id); const back = snap();
      return { id: it.id, maxHp: p.maxHp, on, sw, back };
    });
  } catch (err) { console.warn('items vectors skipped:', err.message); }

  for (const k of KEYS) G[k] = keep[k];
  const s2 = JSON.stringify(out);
  fs.writeFileSync(path.join(OUT, 'test_vectors_p2.json'), s2);
  console.log('test_vectors_p2.json'.padEnd(22), (s2.length / 1024).toFixed(1).padStart(7), 'KB');
})();

// ============ Phase 5 (i18n) dictionaries + reference translations ============
// Separate outputs: data/lang_en.json and data/lang_zh.json hold every G.I18n.add() call of
// js/data/lang-en.js / lang-zh.js in order, as [spanish, translation] pairs (the order of the
// pairs is the JS Object.entries order, so the Godot port replays add() exactly; lang-zh.js
// also adds the Pokémon names by dex). tests/fixtures/i18n_vectors.json holds strings
// translated by the unchanged js/core/i18n.js running in a fresh sandbox per language.
(function exportI18n() {
  const calls = [];
  const keepAdd = G.I18n.add;
  G.I18n.add = (d, l = 'en') => { calls.push({ l, pairs: Object.entries(d) }); };
  load('js/data/lang-en.js');
  const nEn = calls.length;
  load('js/data/lang-zh.js');
  G.I18n.add = keepAdd;
  const dict = { en: { adds: calls.slice(0, nEn).map(c => c.pairs) }, zh: { adds: calls.slice(nEn).map(c => c.pairs) } };
  for (const c of calls.slice(nEn)) if (c.l !== 'zh') throw new Error('lang-zh.js: unexpected add() language ' + c.l);
  for (const l of ['en', 'zh']) {
    const s = JSON.stringify(dict[l]);
    fs.writeFileSync(path.join(OUT, 'lang_' + l + '.json'), s);
    console.log(('lang_' + l + '.json').padEnd(22), (s.length / 1024).toFixed(1).padStart(7), 'KB');
  }

  // --- the real i18n.js per language (fresh sandbox: the language is chosen at load time) ---
  const make = lang => {
    const sb = {
      G: {}, console, Math, JSON, Map, Set, Object, Array, Number, String, RegExp, Infinity, NaN, isFinite, parseInt, parseFloat,
      localStorage: { getItem: k => (k === 'ps.lang' ? lang : null), setItem: noop },
      location: { pathname: '/', protocol: 'file:', search: '' }, navigator: { language: lang, languages: [lang] },
      document: { documentElement: {}, title: '', querySelectorAll: () => [] }, CanvasRenderingContext2D: function () {},
      confirm: noop, alert: noop
    };
    sb.window = sb;
    vm.createContext(sb);
    for (const f of ['js/data/pokedex.js', 'js/core/i18n.js', 'js/data/lang-en.js', 'js/data/lang-zh.js'])
      vm.runInContext(fs.readFileSync(path.join(ROOT, f), 'utf8'), sb, { filename: f });
    if (sb.G.I18n.lang !== lang) throw new Error('i18n sandbox language ' + sb.G.I18n.lang + ' != ' + lang);
    return s => sb.G.I18n.t(s);
  };
  const T = { es: make('es'), en: make('en'), zh: make('zh') };

  // --- test strings (deterministic) ---
  let seed = 12345;
  const rnd = () => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return seed / 4294967296; };
  const pick = a => a[Math.floor(rnd() * a.length)];
  const cases = new Set();
  const addc = s => { if (typeof s === 'string') cases.add(s); };
  const keysOf = l => dict[l].adds.flatMap(a => a.map(p => p[0]));
  const allKeys = [...new Set([...keysOf('en'), ...keysOf('zh')])];
  const exactKeys = allKeys.filter(k => !k.includes('{x}'));
  const patKeys = allKeys.filter(k => k.includes('{x}'));
  for (const k of exactKeys) addc(k);                                         // level 1
  exactKeys.forEach((k, i) => { if (i % 3 === 0) addc(k.toUpperCase()); if (i % 7 === 0) addc(k.toLowerCase()); });
  const names = G.DEX.map(p => p.name);
  const moveNames = M.ALL.map(m => m.name);
  const fillers = ['5', '12', '1.234', '0', '+40', '3/10', 'Pikachu', 'Charmander', 'Mr. Mime', 'Lanzallamas', 'Fuego', 'Planta',
    'Kanto', 'Nv. 3', 'Pradera', 'Grieta', 'xyz', 'Fuego y Agua', '¡Nivel 7!'];
  for (const k of patKeys) {                                                  // level 2 (+ nested + upper case)
    for (let v = 0; v < 4; v++) {
      const s = k.replace(/\{x\}/g, () => (v === 0 ? pick(fillers) : v === 1 ? pick(names) : v === 2 ? pick(moveNames) : pick(exactKeys)));
      addc(s);
      if (v === 1) addc(s.toUpperCase());
    }
    const inner = pick(patKeys).replace(/\{x\}/g, () => pick(fillers));
    addc(k.replace('{x}', inner).replace(/\{x\}/g, () => pick(fillers)));
  }
  const glue = [' ', ' de ', ' y ', ', ', ' · ', ': ', ' (', ') ', '! ', ' — ', '-', '2 '];
  const words = ['hola', 'mundo', 'Pokémon', 'el', 'la', 'contra', 'nuevo', 'XYZ', '12', 'ÁRBOL', 'Ñandú'];
  for (let i = 0; i < 1500; i++) {                                            // level 3: fragments in longer texts
    const n = 2 + Math.floor(rnd() * 4);
    let s = '';
    for (let j = 0; j < n; j++) s += (j ? pick(glue) : '') + (rnd() < 0.6 ? pick(exactKeys) : pick(words));
    if (rnd() < 0.15) s = s.toUpperCase();
    if (rnd() < 0.1) s = '  ' + s + ' ';
    addc(s);
  }
  for (let i = 0; i < 200; i++) addc(pick(exactKeys) + pick(['s', '2', 'ito', '']) + ' ' + pick(names));   // word boundaries
  // game data texts as the game builds them
  const MD = G.MissionDefs;
  for (const d of [...MD.daily, ...MD.weekly]) for (const g of d.goals) for (const t of [null, 'fire', 'water', 'dragon']) addc(d.text(g, t));
  for (const a of G.AchDefs.LIST) { addc(a.name); addc(a.desc); if (a.title) addc(a.title); }
  for (const m of M.ALL) { addc(m.name); addc(m.desc); }
  for (const it of G.Items.LIST) { addc(it.name); addc(it.desc); }
  for (const s of G.LevelUp.STATS) { addc(s.title); addc(s.desc); }
  for (const u of G.Upgrades.LIST) { addc(u.name); addc(u.desc); }
  for (const b of G.Tiles.BIOMES) { addc(b.name); addc(b.name.toUpperCase()); addc(`${b.name.toUpperCase()} · ${Math.floor(rnd() * 900)} DERROTADOS · ${Math.floor(rnd() * 90)} MONEDAS`); }
  for (const q of G.PERSONALITY_TEST) { addc(q.q); for (const a of q.a) addc(a.t); }
  for (const k in G.TRAIT_TEXT) { addc(G.TRAIT_TEXT[k]); addc(k); }
  // string literals of the Godot UI (format placeholders filled in)
  const gdDir = path.join(ROOT, 'godot');
  const walkGd = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? (['tests', '.godot', 'assets', 'data'].includes(e.name) ? [] : walkGd(path.join(d, e.name)))
    : e.name.endsWith('.gd') ? [path.join(d, e.name)] : []);
  for (const f of walkGd(gdDir)) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
      const s = m[1].replace(/\\"/g, '"');
      if (!/[A-Za-zÁÉÍÓÚáéíóúÑñ]/.test(s) || /^(res|user):\/\//.test(s) || /^[a-z0-9_:\/.#@-]*$/.test(s) || s.includes('\\')) continue;
      addc(s.replace(/%(\.\d)?[dsf]/g, () => pick(['3', 'Bulbasaur', 'Fuego', '12', 'Pradera'])).replace(/%%/g, '%'));
    }
  }
  for (const s of ['', ' ', '123', '12:34', '+5', '×2', '—', '  Volver  ', 'Volver   a   jugar', 'volver', 'VOLVER', 'Volver.', '¿Volver?',
    'Nv. 5', 'NV. 5', 'Fuego Fuego', 'FuegoAgua', 'Agua2', '2Agua', 'Agua-Fuego', 'Agua_Fuego', 'Ñ', 'ñandú fuego']) addc(s);

  const list = [...cases];
  const out = { cases: list, es: list.map(T.es), en: list.map(T.en), zh: list.map(T.zh) };
  // es is the identity (Spanish source): kept as a check of the early return
  const fx = path.join(ROOT, 'godot', 'tests', 'fixtures');
  fs.mkdirSync(fx, { recursive: true });
  const s5 = JSON.stringify(out);
  fs.writeFileSync(path.join(fx, 'i18n_vectors.json'), s5);
  console.log('i18n_vectors.json'.padEnd(22), (s5.length / 1024).toFixed(1).padStart(7), 'KB', list.length, 'cases');
})();

// ============ Phase 3a (world visuals & terrain) reference vectors -> test_vectors_p3.json ============
// Separate output. Runs the unchanged tiles.js painters (paintChunk via world.js chunkImage,
// propSprite) on real pixel buffers, world.js chunk data / collision, weather.js with a recorded
// seeded Math.random. Pixel data is compared through SHA-256 (whole chunk + one per tile row).
// P3_DUMP=<dir> also writes the raw RGBA of every painted chunk there (debugging).
(function exportPhase3() {
  const crypto = require('crypto');
  const KEYS = ['World', 'Weather', 'Spawner', 'Audio', 'FX', 'Coop', 'Rift', 'EnemyMgr', 'Pickups', 'Game', 'Interact', 'Progress', 'Camera'];
  const keep = {};
  for (const k of KEYS) keep[k] = G[k];
  const createKeep = sandbox.document.createElement;
  // tiles.js Pix(): a canvas whose ImageData is a real buffer (kept on the canvas by putImageData)
  sandbox.document.createElement = () => {
    const cv = { width: 0, height: 0, _img: null };
    cv.getContext = () => ({ createImageData: (w, h) => ({ width: w, height: h, data: new Uint8ClampedArray(w * h * 4) }),
                             putImageData: img => { cv._img = img; } });
    return cv;
  };
  const sha = d => crypto.createHash('sha256').update(Buffer.from(d.buffer, d.byteOffset, d.byteLength)).digest('hex');
  const bits = v => { const b = Buffer.alloc(8); b.writeDoubleLE(v); return b.toString('hex'); };
  const dumpDir = process.env.P3_DUMP;
  if (dumpDir) fs.mkdirSync(dumpDir, { recursive: true });
  const out = {};
  try {
    G.Coop = { active: false, isHost: false }; G.Audio = { sfx: noop, music: noop }; G.FX = new Proxy({}, { get: () => noop });
    load('js/world/world.js', s => s.replace('TS, CW, reset, setBiome,', 'chunkImage, chunkData, terrainAt, TS, CW, reset, setBiome,'));
    const W = G.World;

    // --- ground painter: (seed, chunk, biome) -> sha256 of the 256x256 RGBA + 16 tile-row hashes ---
    const CASES = [[12345, [[0, 0], [1, 1], [-2, 1], [3, -2], [-1, -1], [2, 2]]], [777, [[5, 5], [-4, -3], [2, 0], [-3, 4]]],
                   [4242, [[0, 0], [1, -1], [-1, 1]]], [1, [[-30, 17], [40, -41]]]];
    out.chunks = [];
    let bk = 0;
    for (const [seed, list] of CASES) {
      W.reset(seed); W.setBiome(0, true);
      for (const [cx, cy] of list) {
        let kinds = [0, 0, 0];
        for (let j = 0; j < 16; j++) for (let i = 0; i < 16; i++) kinds[W.terrainAt(cx * 16 + i, cy * 16 + j)]++;
        for (const b of [bk % 21, (bk + 8) % 21]) {
          const cv = W.chunkImage(cx, cy, b, new Map());
          const d = cv._img.data, rows = [];
          for (let r = 0; r < 16; r++) rows.push(sha(d.subarray(r * 16 * 256 * 4, (r + 1) * 16 * 256 * 4)));
          out.chunks.push({ seed, cx, cy, biome: b, kinds, sha: sha(d), rows });
          if (dumpDir) fs.writeFileSync(path.join(dumpDir, `chunk_${seed}_${cx}_${cy}_${b}.rgba`), Buffer.from(d.buffer));
        }
        bk += 3;
      }
    }

    // --- prop placement (world.js placeProps) ---
    out.props = [];
    for (const [seed, x0, y0, n] of [[12345, -3, -3, 7], [777, -2, -2, 5], [4242, -2, -2, 5], [1, 20, -12, 3]]) {
      W.reset(seed);
      const list = [];
      for (let cy = y0; cy < y0 + n; cy++) for (let cx = x0; cx < x0 + n; cx++)
        for (const p of W.chunkData(cx, cy).props) list.push([p.type, p.tx, p.ty, p.kind]);
      out.props.push({ seed, x0, y0, n, list });
    }

    // --- collision / queries next to solid props and walls (seed 12345) ---
    W.reset(12345);
    const solids = [];
    for (let cy = -2; cy <= 2; cy++) for (let cx = -2; cx <= 2; cx++) for (const p of W.chunkData(cx, cy).props) if (p.solid) solids.push(p);
    out.collide = [];
    const offs = [[0, 0], [5, -3], [-14, 2], [20, 9], [-9, -18], [0.3, 25], [13, 13]];
    for (let i = 0; i < Math.min(30, solids.length); i++) {
      const p = solids[i];
      for (const [dx, dy] of offs) {
        const e = { x: p.x + dx, y: p.y + dy, r: 12 };
        const x0 = e.x, y0 = e.y, hit = W.collide(e);
        const pb = W.projectileBlock(x0, y0, 6);
        out.collide.push({ x: x0, y: y0, xb: bits(x0), yb: bits(y0), r: 12, hit, bx: bits(e.x), by: bits(e.y), free: W.isFree(x0, y0, 12), freeL: W.isFree(x0, y0, 14, true),
                           pb: pb === 'wall' ? 'wall' : pb ? 'prop:' + pb.type : '', walk: W.walkable(Math.floor(x0 / 32), Math.floor(y0 / 32)) });
      }
    }
    for (let k = 0; k < 120; k++) {               // walls and water: a sweep across the map
      const x0 = -900 + k * 15.37, y0 = 400 - k * 9.11;
      const e = { x: x0, y: y0, r: 14 };
      const hit = W.collide(e);
      out.collide.push({ x: x0, y: y0, xb: bits(x0), yb: bits(y0), r: 14, hit, bx: bits(e.x), by: bits(e.y), free: W.isFree(x0, y0, 14), freeL: W.isFree(x0, y0, 14, true),
                         pb: (b => b === 'wall' ? 'wall' : b ? 'prop:' + b.type : '')(W.projectileBlock(x0, y0, 6)), walk: W.walkable(Math.floor(x0 / 32), Math.floor(y0 / 32)) });
    }
    out.near = [[0, 0, 600], [700, -300, 900]].map(([x, y, r]) => ({ x, y, r,
      breakable: (p => p ? [p.type, p.tx, p.ty] : null)(W.nearestBreakable(x, y, r)),
      specials: W.specialsNear(x, y, r).map(p => [p.type, p.tx, p.ty, p.kind]).sort(),
      inCircle: W.propsInCircle(x, y, r).map(p => [p.type, p.tx, p.ty]).sort() }));

    // --- prop sprites: every biome x type x variant (+ the rift portal frames) ---
    G.Tiles.clearProps();
    const VAR = { tree: [0], rock: [0, 1], grass: [0, 1], chest: [0], altar: [0, 1, 2, 3, 4, 5, 6, 7], spring: [0, 1], bigchest: [0], trap: [0, 1, 2] };
    out.sprites = [];
    for (let bi = 0; bi < G.Tiles.BIOMES.length; bi++) for (const t in VAR) for (const v of VAR[t]) {
      const cv = G.Tiles.propSprite(bi, t, v);
      out.sprites.push({ bi, type: t, v, w: cv.width, h: cv.height, sha: sha(cv._img.data) });
    }
    for (let f = 0; f < 4; f++) { const cv = G.Tiles.propSprite(0, 'rift', f); out.sprites.push({ bi: 0, type: 'rift', v: f, w: cv.width, h: cv.height, sha: sha(cv._img.data) }); }

    // --- liquid effects per biome and types ---
    const TYPES = [[], ['water'], ['fire'], ['poison'], ['steel'], ['electric'], ['ground'], ['ice'], ['grass', 'poison'], ['normal']];
    out.liquids = [];
    for (let b = 0; b < G.Tiles.BIOMES.length; b++) {
      W.setBiome(b, true);
      out.liquids.push({ biome: b, kind: W.liquidKind(), fx: TYPES.map(t => ({ types: t, e: strip(W.liquidEffect(t)) })) });
    }
  } catch (e) { console.warn('phase3 world vectors skipped:', e.stack); }

  // --- weather: schedule, intensity, multipliers and chip damage with a recorded seeded Math.random ---
  try {
    let h = 0x9e3779b9 >>> 0;
    const draws = [];
    const oldRandom = Math.random;
    Math.random = () => { h = (h + 0x6D2B79F5) >>> 0; let t = h; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                          const k = (t ^ (t >>> 14)) >>> 0; draws.push(k); return k / 4294967296; };
    let biomeNow = 0;
    const banners = [];
    G.World = { get biome() { return biomeNow; } };
    G.Spawner = { say: (txt, d) => banners.push(txt) };
    G.Rift = { inArena: false };
    G.Coop = { active: false, isHost: false };
    G.FX = { dmgText: noop };
    const mk = (types, hp, boss = false) => ({ types, hp, maxHp: hp, dead: false, boss, flash: 0, die() { this.dead = true; } });
    const enemies = [mk(['rock'], 400), mk(['water'], 400), mk(['ice'], 400), mk(['bug'], 40), mk(['fire'], 9000, true)];
    G.EnemyMgr = { all: () => enemies };
    load('js/systems/weather.js', s => s.replace('KINDS, reset,', 'KINDS, BIOME_W, reset,'));
    const WX = G.Weather;
    WX.reset();
    const pl = { dead: false, maxHp: 180, hp: 180, x: 0, y: 0, bodyH: 30, mon: { types: ['fire'] } };
    const dt = 1 / 60;
    let time = 0;
    const samples = [], starts = [];
    let prev = null;
    for (let f = 0; f < 60 * 3600; f++) {
      time += dt;
      biomeNow = Math.floor(time / 240) % 21;
      if (f === 60 * 30) WX.force('snow', 40);
      if (f === 60 * 1000) pl.mon.types = ['ice'];
      WX.update(dt, time, pl);
      const c = WX.current;
      if (c && (!prev || prev !== c.kind + c.dur)) { starts.push({ f, kind: c.kind, dur: c.dur }); }
      prev = c ? c.kind + c.dur : null;
      if (f % 1200 === 0) {
        samples.push({ f, cur: c ? c.kind : null, left: c ? bits(c.left) : null, vig: bits(WX.vignette),
          m: ['fire', 'water', 'electric', 'rock', 'ice', 'ghost', 'grass'].map(t => bits(WX.mult(t))),
          sp: [bits(WX.speedFor(['fire'])), bits(WX.speedFor(['ice']))], hurts: [WX.hurts(['fire']), WX.hurts(['rock']), WX.hurts(['ice'])],
          hp: bits(pl.hp), ehp: enemies.map(e => bits(e.hp)), edead: enemies.map(e => e.dead) });
      }
    }
    Math.random = oldRandom;
    out.weather = { frames: 60 * 3600, dt_bits: bits(dt), force: { f: 60 * 30, kind: 'snow', dur: 40 }, ice_at: 60 * 1000,
      player: { maxHp: 180, types: ['fire'] }, enemies: [['rock', 400], ['water', 400], ['ice', 400], ['bug', 40], ['fire', 9000, true]],
      draws, starts, samples, banners };
  } catch (e) { console.warn('phase3 weather vectors skipped:', e.stack); }

  sandbox.document.createElement = createKeep;
  for (const k of KEYS) G[k] = keep[k];
  const s3 = JSON.stringify(out);
  fs.writeFileSync(path.join(OUT, 'test_vectors_p3.json'), s3);
  console.log('test_vectors_p3.json'.padEnd(22), (s3.length / 1024).toFixed(1).padStart(7), 'KB');
})();

// ============ Phase 3b (interactables, events, rifts, bonds) -> test_vectors_p3b.json ============
// Separate output. Runs the unchanged world.js (interactable placement, arena terrain/props of the
// 18 themes), rift.js (chance escalation, legendary choice + arena cfg + legendary def), events.js
// (schedule of events / thieves / lost Pokémon) and player.js (bondOptions / fuse) with stubs for
// the browser-only parts. Math.random is replaced by a recorded mulberry32 stream: the uint32
// values are exported and Godot feeds k / 2^32 (exact) to the same systems (sim/stream_rng.gd).
(function exportPhase3b() {
  const KEYS = ['World', 'Weather', 'Spawner', 'Audio', 'FX', 'Coop', 'Rift', 'Events', 'EnemyMgr', 'Enemy', 'Pickups', 'Game',
                'Progress', 'Camera', 'Sprites', 'Projectiles', 'Combat', 'Hazards', 'DB'];
  const keep = {};
  for (const k of KEYS) keep[k] = G[k];
  const oldRandom = Math.random;
  const bits = v => { const b = Buffer.alloc(8); b.writeDoubleLE(v); return b.toString('hex'); };
  let stream = [], si = 0;
  const mul = seed => { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return (t ^ (t >>> 14)) >>> 0; }; };
  const useStream = (seed, n) => { const g = mul(seed); stream = Array.from({ length: n }, g); si = 0;
    Math.random = () => { if (si >= stream.length) throw new Error('stream exhausted'); return stream[si++] / 4294967296; }; };
  const useValues = ks => { stream = ks.slice(); si = 0; Math.random = () => { if (si >= stream.length) throw new Error('stream exhausted'); return stream[si++] / 4294967296; }; };
  const SPECIAL = ['altar', 'spring', 'bigchest', 'trap'];
  const out = { consts: { chest_time: G.Interact.CHEST_TIME, powers: JSON.parse(JSON.stringify(G.Interact.POWERS)) } };
  try {
    G.Coop = { active: false, isHost: false, scaleRate: () => 1, scaleHp: () => 1 };
    G.Audio = { sfx: noop, music: noop };
    G.FX = new Proxy({}, { get: () => noop });
    load('js/world/world.js', s => s.replace('TS, CW, reset, setBiome,', 'chunkData, terrainAt, TS, CW, reset, setBiome,'));
    const W = G.World;

    // --- interactables placed by world.js placeProps in a 12x12-chunk square ---
    out.specials = [12345, 777, 4242].map(seed => {
      W.reset(seed); W.setBiome(0, true);
      const list = [];
      for (let cy = -6; cy < 6; cy++) for (let cx = -6; cx < 6; cx++)
        for (const p of W.chunkData(cx, cy).props) if (SPECIAL.includes(p.type)) list.push([p.tx, p.ty, p.type, p.kind, p.r, p.solid, p.flat]);
      return { seed, c0: -6, c1: 6, list };
    });

    // --- the 18 arena themes: terrain (41x41 tiles around the centre) and props ---
    const R = 20;
    out.arenas = G.Tiles.ARENA_TYPES.map((type, i) => {
      W.reset(4242); W.setBiome(0, true);
      const a = { tx: 5000 + 97 * i, ty: 6000 + 53 * i, r: 11, type };
      const pre = i % 2 === 1;                  // half of them: the area was generated before (purge)
      if (pre) for (let ty = a.ty - R; ty <= a.ty + R; ty += 4) for (let tx = a.tx - R; tx <= a.tx + R; tx += 4) W.terrainAt(tx, ty);
      W.setArena(a);
      const rows = [];
      for (let ty = a.ty - R; ty <= a.ty + R; ty++) { let s = ''; for (let tx = a.tx - R; tx <= a.tx + R; tx++) s += 'fwl'[W.terrainAt(tx, ty)]; rows.push(s); }
      const props = [];
      for (let cy = Math.floor((a.ty - R) / 16); cy <= Math.floor((a.ty + R) / 16); cy++)
        for (let cx = Math.floor((a.tx - R) / 16); cx <= Math.floor((a.tx + R) / 16); cx++)
          for (const p of W.chunkData(cx, cy).props) if (Math.abs(p.tx - a.tx) <= R && Math.abs(p.ty - a.ty) <= R) props.push([p.tx, p.ty, p.type]);
      return { type, seed: 4242, tx: a.tx, ty: a.ty, r: 11, R, pre, rows, props, biome: G.Tiles.arenaBiome(type) };
    });

    // --- rift.js: chance escalation (no boss, the rift is never entered) ---
    const pl = { x: 0, y: 0, dead: false, r: 12, bonds: 0, bodyH: 30, spd: 100 };
    G.Game = { everyone: () => [pl], player: pl, st: { time: 0 }, flash: noop, offerBond: noop };
    const added = [];
    G.EnemyMgr = { bossAlive: () => false, stash: noop, restore: noop, clearRemote: noop, all: () => [], queryCircle: () => [],
                   add: e => { added.push(e); return e; }, get: () => null };
    G.Projectiles = { clear: noop, clearOrbs: noop }; G.Combat = { clearFields: noop }; G.Hazards = { clear: noop };
    G.Weather = { force: noop, clear: noop, speedFor: () => 1 };
    G.Camera = { x: 0, y: 0, kick: noop };
    G.Spawner = { say: noop, burst: noop };
    G.Pickups = { pullAll: noop, drop: noop };
    G.Progress = { event: noop };
    G.Enemy = class { constructor(def, x, y, sc, boss = false) { this.def = def; this.x = x; this.y = y; this.boss = boss; this.id = 1; this.name = def.name; this.shiny = false; }
                      makeShiny() { this.shiny = true; } };
    const isFreeKeep = W.isFree;
    W.isFree = () => true;
    load('js/systems/rift.js');
    useStream(20261014, 400);
    G.Rift.reset();
    const opens = [];
    let had = false;
    const FR = 4000;
    for (let f = 1; f <= FR; f++) {
      G.Rift.update(0.5, pl, f * 0.5);
      const r = G.Rift.rift;
      if (r && !had) opens.push([f, bits(r.x), bits(r.y), si]);
      had = !!r;
    }
    out.rift_chance = { dt: 0.5, frames: FR, seq: stream.slice(0, si), opens };

    // --- rift.js: legendary choice, arena cfg and the legendary's def ---
    G.DB = { save: { legends: { 150: 1, 144: 1, 249: 1, 384: 1, 643: 1 } } };
    const LCASES = [['', 100, 1], ['fire', 300, 2], ['water', 1300, 3], ['', 3700, 4], ['psychic', 4100, 5], ['dragon', 600, 6],
                    ['bug', 50, 7], ['ghost', 900, 8], ['', 200, 9], ['', 5000, 10], ['ice', 3601, 11], ['electric', 2400, 12]];
    out.legends = LCASES.map(([type, t, seed]) => {
      G.Game.st.time = t;
      useStream(seed * 7919, 8);
      added.length = 0;
      G.Rift.reset();
      G.Rift.debugArena(type || undefined);
      const a = G.Rift.arena, e = added[0];
      return { type, t, beaten: G.DB.save.legends, seq: stream.slice(0, si),
               arena: { tx: a.tx, ty: a.ty, r: a.r, dex: a.dex, shiny: a.shiny, type: a.type, x: a.x, y: a.y },
               def: e.def, ex: e.x, ey: e.y, shiny: e.shiny };
    });
    // a shiny legendary (crafted stream: pick, tx, ty, shiny roll 0.001 < 1/512, type)
    {
      G.Game.st.time = 777;
      useValues([0.31, 0.5, 0.25, 0.001, 0.9].map(v => Math.floor(v * 4294967296)));
      added.length = 0;
      G.Rift.reset();
      G.Rift.debugArena(undefined);
      const a = G.Rift.arena, e = added[0];
      out.legends.push({ type: '', t: 777, beaten: G.DB.save.legends, seq: stream.slice(0, si),
        arena: { tx: a.tx, ty: a.ty, r: a.r, dex: a.dex, shiny: a.shiny, type: a.type, x: a.x, y: a.y }, def: e.def, ex: e.x, ey: e.y, shiny: e.shiny });
    }
    G.Rift.reset();

    // --- events.js: 3000 s of schedule (player still at the origin, no boss, free ground) ---
    G.Sprites = Object.assign({}, keep.Sprites, { preload: noop, bodyRadius: () => 10, dirFromAngle: () => 0,
      Animator: class { constructor() { this.dir = 0; } update() {} loop() {} } });
    load('js/systems/events.js');
    pl.x = 0; pl.y = 0;                         // (the arena cases moved it)
    out.events = [3, 99].map(seed => {
      useStream(seed, 5000);
      added.length = 0;
      G.Events.reset();
      const recs = [];
      let prev = null, nT = 0;
      const EFR = 6000;
      for (let f = 1; f <= EFR; f++) {
        G.Events.update(0.5, [pl], f * 0.5);
        const cur = G.Events.current;
        if (cur !== prev) {
          if (!cur) recs.push([f, 'end', si]);
          else if (cur === 'horde') recs.push([f, cur, si, G.Events.bag().map(d => d.dex)]);
          else if (cur === 'lost') { const L = G.Events._dbg(); recs.push([f, cur, si, [bits(L.x), bits(L.y), bits(L.tx), bits(L.ty)]]); }
          else recs.push([f, cur, si]);
          prev = cur;
        }
        while (added.length > nT) { const e = added[nT++]; recs.push([f, 'thief', si, e.def.dex, e.def.hp, bits(e.x), bits(e.y)]); }
      }
      return { seed, dt: 0.5, frames: EFR, seq: stream.slice(0, si), recs };
    });
    // horde types per tier start (no randomness)
    out.horde_types = [0, 100, 200, 400, 700, 1000].map(t => ({ t, types: G.Enemies.hordeTypes(t) }));
    W.isFree = isFreeKeep;
  } catch (e) { console.warn('phase3b rift/events vectors skipped:', e.stack); }
  Math.random = oldRandom;

  // --- player.js: bondOptions / fuse (Atajos binds, Choice Band) ---
  try {
    G.Projectiles = { clearOrbs: noop };
    G.Sprites = Object.assign({}, keep.Sprites, { bodyRadius: () => 10, bodyHeight: () => 30,
      Animator: class { constructor() { this.dir = 0; } } });
    const IDS = ['ember', 'water-gun', 'thunder-shock', 'vine-whip', 'tackle', 'gust'];
    const BCASES = [
      { n: 2, slots: [[0], [1]], active: 1 },
      { n: 1, slots: [[0]], active: 0 },
      { n: 4, slots: [[0], [1], [2], [3]], active: 2, pick: [1, 3] },
      { n: 4, slots: [[0, 1], [2], [3]], active: 0, pick: [3] },
      { n: 4, slots: [[0, 1, 2], [3]], active: 1, pick: [3] },
      { n: 4, slots: [[0, 1, 2, 3]], active: 0 },
      { n: 6, slots: [[0, 1, 2, 3], [4], [5]], active: 2, pick: [5, 4] },
      { n: 4, slots: [[0], [1], [2], [3]], active: 0, pick: [2, 0], bind: { 'thunder-shock': 3, 'vine-whip': 0 } },
      { n: 4, slots: [[0], [1], [2], [3]], active: 3, pick: [0, 1], item: 'choiceband' },
      { n: 4, slots: [[0, 1], [2], [3]], active: 2, pick: [2], item: 'choiceband', bind: { ember: 2 } },
      { n: 3, slots: [[2], [0, 1]], active: 0, pick: [2] },
    ];
    out.bonds = BCASES.map(c => {
      const p = new G.Player(G.DEX_BY[4], {}, false);
      p.moves = IDS.slice(0, c.n).map(id => M.instance(id, 1));
      p.slots = c.slots.map(g => g.map(i => p.moves[i]));
      p.active = c.active; p.bonds = 2; p.item = c.item || null; p.bind = c.bind || {};
      const ids = g => g.map(m => m.id);
      const opt = p.bondOptions();
      const r = { case: c, opt: opt && { mode: opt.mode, group: opt.group ? ids(opt.group) : null, loose: ids(opt.loose) } };
      if (opt && c.pick) {
        const picked = c.pick.map(i => p.moves[i]);
        const g = p.fuse(picked, opt.group);
        r.after = { slots: p.slots.map(ids), active: p.active, bonds: p.bonds, group: ids(g) };
      }
      return r;
    });
  } catch (e) { console.warn('phase3b bond vectors skipped:', e.stack); }

  for (const k of KEYS) G[k] = keep[k];
  const s3b = JSON.stringify(out);
  fs.writeFileSync(path.join(OUT, 'test_vectors_p3b.json'), s3b);
  console.log('test_vectors_p3b.json'.padEnd(22), (s3b.length / 1024).toFixed(1).padStart(7), 'KB');
})();

// ============ Credits & licences -> godot/CREDITS.md + godot/assets/fonts/ ============
// Separate step (parity audit): copies the attribution files the port ships verbatim — the
// SpriteCollab artists (CC BY-NC 4.0) of CREDITS.md and the SIL OFL 1.1 licences of Pixelify
// Sans and Fusion Pixel Font — to the same relative paths, so the links inside CREDITS.md stay
// valid, Settings › Acerca de can list them and export_presets.cfg packs them into the APK.
(function exportCredits() {
  const GD = path.dirname(OUT);
  const cp = rel => {
    const dst = path.join(GD, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(ROOT, rel), dst);
    return rel;
  };
  const FP = 'assets/fonts/fusion-pixel';
  const done = [cp('CREDITS.md'), cp('assets/fonts/OFL.txt'), cp(FP + '/OFL.txt')];
  const lic = path.join(ROOT, FP, 'LICENSES');
  for (const d of fs.readdirSync(lic).sort()) {
    for (const f of fs.readdirSync(path.join(lic, d)).sort()) done.push(cp(`${FP}/LICENSES/${d}/${f}`));
  }
  console.log('credits/licences'.padEnd(22), String(done.length).padStart(7), 'files');
})();

// ============ Parity audit reference values -> godot/tests/fixtures/parity_vectors.json ============
// Separate output: the move names in the order of `localeCompare(b, 'es')` (menu.js ban picker and
// hotkey selects) and goals-ui.js fmt() (profile times; verbatim copy of the private one-liner).
(function exportParity() {
  const fmt = t => (t >= 3600 ? Math.floor(t / 3600) + ':' + G.U.mmss(t % 3600).padStart(5, '0') : G.U.mmss(t));
  const ids = M.ALL.map(m => m.id).sort((a, b) => M.ALL.find(m => m.id === a).name.localeCompare(M.ALL.find(m => m.id === b).name, 'es'));
  const out = { moves_es: ids, fmt: [0, 59, 61, 600, 3599, 3600, 3725, 7322, 36000].map(t => [t, fmt(t)]) };
  const fx = path.join(path.dirname(OUT), 'tests', 'fixtures');
  fs.mkdirSync(fx, { recursive: true });
  const s = JSON.stringify(out);
  fs.writeFileSync(path.join(fx, 'parity_vectors.json'), s);
  console.log('parity_vectors.json'.padEnd(22), (s.length / 1024).toFixed(1).padStart(7), 'KB');
})();
