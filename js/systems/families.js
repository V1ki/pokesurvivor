/* ============ families.js — entrenador, familias, evolución y fragmentos ============
 * (14-10-2026) Las mejoras ya no son de cada Pokémon:
 *   - ENTRENADOR: las mejoras que se compran con monedas (R.trainer: vida, defensa,
 *     regeneración, velocidad, imán, sabiduría, fortuna y cambio de cartas) valen para
 *     todos los Pokémon (save.trainer).
 *   - FAMILIA: cada línea evolutiva (data/evolutions.js) tiene un nivel (save.fams) que
 *     sube jugando con cualquiera de sus formas. Da lo que daban Fuerza, Reflejos, Golpe
 *     Crítico y Repertorio, y desbloquea los movimientos de su lista (data/learnsets.js):
 *     la partida empieza con el primer ataque que aprende y las cartas sólo ofrecen los
 *     que ya sabe.
 *   - EVOLUCIÓN: una forma se puede usar cuando la familia llega a su nivel de evolución
 *     (el de los juegos, o el estimado por sus stats base) y la tienes: sacada en el gacha
 *     o desbloqueada con fragmentos.
 *   - FRAGMENTOS: un Pokémon repetido en el gacha da fragmentos de la familia de tu
 *     compañero si es de esa familia; si no, fragmentos universales (save.uni: R.uniRate
 *     valen 1 de cualquier familia). Ya no devuelve monedas. Con la familia completa, los
 *     fragmentos dan estrellas (+5 % de daño y de vida cada una, hasta 5).
 * Los Pokémon que ya tenías antes del cambio se pueden usar siempre (los conseguidos antes de
 * save.stats.famAt).
 * Las mismas reglas están en el simulador de Godot (godot/debug/family_rules.gd).
 */
G.Families = (() => {
  const R = {
    trainer: ['hp', 'def', 'regen', 'spd', 'magnet', 'xp', 'coins', 'reroll'],
    cap: 60,                 // nivel máximo de una familia
    xpBase: 100, xpStep: 20, // experiencia del nivel L al L+1: xpBase + xpStep * L
    xpPerS: 0.5,             // experiencia de familia por segundo aguantado,
    xpPerKill: 1,            //   por Pokémon derrotado
    xpPerBoss: 60,           //   y por jefe
    atkLv: 0.0068,           // por nivel por encima de 1: ×daño (+40 % al 60, como Fuerza 10/10)
    cdLv: 0.0041,            //   −recarga (−24 % al 60, como Reflejos 8/8)
    critLv: 0.0051,          //   +críticos (30 % al 60, como Golpe Crítico 10/10)
    moves2Lv: 20,            // desde este nivel la partida empieza con 2 movimientos
    shard: [1, 3, 5, 10, 30],        // fragmentos que da un repetido de rareza 1..5
    uniRate: 2,                      // universales por fragmento de una familia
    unlock: [10, 20, 40, 60, 100],   // fragmentos para desbloquear una forma de rareza 1..5
    stars: 5, starCost: 30,          // estrellas de una familia completa y su precio
    starAtk: 0.05, starHp: 0.05,     // por estrella: ×daño y ×vida
    minKnown: 0,             // los N primeros movimientos de su lista se saben desde el nivel 1
    pool: 'learnset',        // 'learnset': las cartas sólo dan los que sabe · 'hybrid': + los de su tipo
    stabStart: true,         // empieza con el primer ataque de su tipo que sepa (si sabe alguno)
    minAttacks: 4            // si sabe menos ataques, se completa con los básicos de su tipo
  };

  // ---------------- familias (data/evolutions.js) ----------------

  const MEMBERS = {};            // familia -> [dex] (sólo los del juego)
  for (const d in G.EVO) (MEMBERS[G.EVO[d].f] = MEMBERS[G.EVO[d].f] || []).push(+d);

  const famOf = dex => (G.EVO[dex] ? G.EVO[dex].f : -dex);
  const members = f => MEMBERS[f] || (f < 0 ? [-f] : []);
  const stage = dex => (G.EVO[dex] ? G.EVO[dex].s : 0);

  /** Nivel de familia para poder usar esta forma: 1 la primera, si no su nivel de evolución. */
  function reqLevel(dex) {
    const e = G.EVO[dex];
    if (!e || !e.from || !G.EVO[e.from]) return 1;
    return Math.min(R.cap, (e.how && (e.how.lv || e.how.est)) || 1);
  }

  /** La forma y aquellas de las que evoluciona (en el juego), la primera al final. */
  function chain(dex) {
    const out = [dex];
    for (let d = dex; G.EVO[d] && G.EVO[d].from && G.EVO[G.EVO[d].from]; ) out.push(d = G.EVO[d].from);
    return out;
  }

  const isFinal = dex => !members(famOf(dex)).some(d => G.EVO[d] && G.EVO[d].from === dex);

  /** Nombre de la familia: el de su primera forma. */
  function famName(f) {
    const m = members(f).slice().sort((a, b) => stage(a) - stage(b) || a - b);
    return G.DEX_BY[m[0]] ? G.DEX_BY[m[0]].name : '?';
  }

  // ---------------- la partida guardada ----------------

  /** Datos de una familia en la partida (se crean al pedirlos). */
  function fam(save, f) {
    save.fams = save.fams || {};
    return save.fams[f] || (save.fams[f] = { lv: 1, xp: 0, shards: 0, stars: 0 });
  }
  const famOfDex = (save, dex) => fam(save, famOf(dex));
  const owns = (save, dex) => !!(save.owned && save.owned[dex]);

  /** ¿Lo tenías desde antes de las familias? (entonces se puede usar siempre) */
  const legacy = (save, dex) => owns(save, dex) && (save.owned[dex].at || 0) < ((save.stats && save.stats.famAt) || 0);

  /** ¿Se puede elegir de compañero? Hay que tenerlo y que su familia llegue a su nivel. */
  function usable(save, dex) {
    return owns(save, dex) && (legacy(save, dex) || famOfDex(save, dex).lv >= reqLevel(dex));
  }

  // ---------------- movimientos (data/learnsets.js) ----------------

  /**
   * Todos los movimientos de esta forma con el nivel de familia que los desbloquea, del
   * primero al último: los de su lista y los de las formas de las que evoluciona (el que
   * evoluciona no los olvida); los "evo" al llegar a esa forma; los "fill" (MT con los que
   * se completa una lista corta) desde el principio. [[id, nivel, id de los juegos?]]
   */
  function movesOf(dex) {
    const at = new Map();
    const add = (id, lv, src) => {
      if (!G.Moves.BY_ID[id]) return;
      const cur = at.get(id);
      if (!cur || lv < cur[1]) at.set(id, [id, lv, src]);
    };
    for (const d of chain(dex)) {
      const ls = G.LEARNSETS[d] || {};
      for (const e of (ls.lv || []).concat(ls.old || [])) add(e[0], Math.max(1, e[1]), e[2]);
      for (const id of ls.evo || []) add(id, reqLevel(d));
    }
    for (const id of (G.LEARNSETS[dex] || {}).fill || []) add(id, 1);
    // Sin ningún ataque al nivel 1 (su primer movimiento no está en el juego: Malicioso,
    // Constricción...), empieza con el de su tipo, como antes.
    if (![...at.values()].some(e => e[1] <= 1 && G.Moves.BY_ID[e[0]].kind !== 'buff')) add(G.startMoveOf(dex), 1);
    const byLv = (a, b) => a[1] - b[1] || a[0].localeCompare(b[0]);
    // R.minKnown: los primeros de la lista se saben ya al nivel 1 (en el orden en que los aprendía)
    return [...at.values()].sort(byLv).map((e, i) => (i < R.minKnown ? [e[0], 1, e[2]] : e)).sort((a, b) => a[1] - b[1]);
  }

  /**
   * Ataques básicos de su tipo para completar una lista corta: el de inicio de cada tipo suyo
   * (Ascuas, Látigo Cepa...), luego los demás de sus tipos y por último los normales.
   */
  function basics(dex) {
    const mon = G.DEX_BY[dex], out = [];
    const add = id => { if (G.Moves.BY_ID[id] && G.Moves.BY_ID[id].kind !== 'buff' && !out.includes(id)) out.push(id); };
    for (const t of mon.types) add(G.Moves.START[t]);
    for (const t of mon.types) for (const id of G.Moves.POOL[t] || []) add(id);
    for (const id of G.Moves.POOL.normal || []) add(id);
    return out;
  }

  /** Los que ya sabe con el nivel actual de su familia; si son menos de R.minAttacks ataques,
   *  se completan con los básicos de su tipo (marcados 'basic'), que dejan paso a los suyos. */
  function known(save, dex) {
    const list = movesOf(dex).filter(e => e[1] <= famOfDex(save, dex).lv);
    let atk = list.filter(e => G.Moves.BY_ID[e[0]].kind !== 'buff').length;
    for (const id of basics(dex)) {
      if (atk >= R.minAttacks) break;
      if (list.some(e => e[0] === id)) continue;
      list.push([id, 1, 'basic']);
      atk++;
    }
    return list;
  }

  /** Para enseñarlos: su lista y, delante, los básicos que la completan ahora (sin repetirlos). */
  function shown(save, dex) {
    const basic = known(save, dex).filter(e => e[2] === 'basic');
    return basic.concat(movesOf(dex).filter(e => !basic.some(b => b[0] === e[0])));
  }

  /** Lo que pueden ofrecer las cartas: los que sabe (con R.pool 'hybrid', también los de su tipo). */
  function poolOf(dex, list) {
    const ids = list.map(e => e[0]);
    if (R.pool === 'hybrid') for (const id of G.Moves.poolFor(G.DEX_BY[dex])) if (!ids.includes(id)) ids.push(id);
    return ids;
  }

  /** Con qué empieza la partida: el primer ataque que sabe (2 desde R.moves2Lv); con
   *  R.stabStart, primero el de su tipo (en 'hybrid', el de su tipo de siempre si aún no sabe). */
  function startMoves(save, dex, list = known(save, dex)) {
    const n = famOfDex(save, dex).lv >= R.moves2Lv ? 2 : 1;
    const atk = list.filter(e => G.Moves.BY_ID[e[0]].kind !== 'buff').map(e => e[0]);
    if (R.stabStart) {
      const types = G.DEX_BY[dex].types;
      let own = atk.find(id => types.includes(G.Moves.BY_ID[id].type));
      if (!own && R.pool === 'hybrid') own = G.startMoveOf(dex);
      if (own) { const i = atk.indexOf(own); if (i >= 0) atk.splice(i, 1); atk.unshift(own); }
    }
    const out = atk.slice(0, n);
    return out.length ? out : [G.startMoveOf(dex)];
  }

  // ---------------- lo que da en la partida ----------------

  /** Mejoras para G.Player: las del entrenador más lo que dan el nivel y las estrellas. */
  function perks(save, dex) {
    const p = G.Upgrades.perks(save.trainer || {});
    const f = famOfDex(save, dex);
    const l = f.lv - 1;
    p.atkMul *= (1 + R.atkLv * l) * (1 + R.starAtk * f.stars);
    p.cdMul *= Math.max(0.4, 1 - R.cdLv * l);
    p.crit += R.critLv * l;
    p.hp += Math.round(G.DEX_BY[dex].hp * R.starHp * f.stars);
    p.startMoves = 1;
    p.bans = 0;
    return p;
  }

  /** Qué da cada nivel, para enseñarlo: { atk, cd, crit } en % y si ya empieza con 2. */
  function levelBonus(lv) {
    const l = lv - 1;
    return { atk: Math.round(R.atkLv * l * 100), cd: Math.round(Math.min(0.6, R.cdLv * l) * 100),
             crit: Math.round(R.critLv * l * 100), two: lv >= R.moves2Lv };
  }

  // ---------------- entre partidas ----------------

  const xpNeed = lv => R.xpBase + R.xpStep * lv;

  /** Experiencia de una partida para la familia del compañero. → { f, lv, ups, xp, need, gained } */
  function gainXp(save, dex, run) {
    const fm = famOfDex(save, dex);
    const gained = Math.round(run.time * R.xpPerS + run.kills * R.xpPerKill + run.bosses * R.xpPerBoss);
    fm.xp += gained;
    let ups = 0;
    while (fm.lv < R.cap && fm.xp >= xpNeed(fm.lv)) { fm.xp -= xpNeed(fm.lv); fm.lv++; ups++; }
    if (fm.lv >= R.cap) fm.xp = 0;
    return { f: famOf(dex), lv: fm.lv, ups, xp: fm.xp, need: xpNeed(fm.lv), gained };
  }

  /**
   * Después de una tirada (G.Gacha.pull): cada repetido da fragmentos en vez de monedas.
   * Si es de la familia del compañero, fragmentos de esa familia; si no, universales.
   * Anota en cada resultado { shards, uni } y quita las monedas que devolvió.
   */
  function afterPull(save, results) {
    const f = famOf(save.partner);
    for (const r of results) {
      r.shards = 0; r.uni = 0;
      if (r.isNew) continue;
      const v = R.shard[Math.min(4, Math.max(0, r.rarity - 1))];
      if (famOf(r.dex) === f) { fam(save, f).shards += v; r.shards = v; }
      else { save.uni = (save.uni || 0) + v; r.uni = v; }
      save.coins = Math.max(0, save.coins - (r.refund || 0));
      r.refund = 0;
    }
  }

  /** Fragmentos que tiene una familia contando los universales. */
  const shardsFor = (save, f) => fam(save, f).shards + Math.floor((save.uni || 0) / R.uniRate);

  /** Paga con los de la familia y, si faltan, con universales. */
  function pay(save, f, cost) {
    const fm = fam(save, f);
    if (shardsFor(save, f) < cost) return false;
    const own = Math.min(fm.shards, cost);
    fm.shards -= own;
    save.uni = (save.uni || 0) - (cost - own) * R.uniRate;
    return true;
  }

  const unlockCost = dex => R.unlock[Math.min(4, Math.max(0, G.DEX_BY[dex].rarity - 1))];

  /** ¿Se puede desbloquear con fragmentos esta forma que te falta? (su familia llega al nivel) */
  const canUnlock = (save, dex) => !owns(save, dex) && famOfDex(save, dex).lv >= reqLevel(dex)
    && shardsFor(save, famOf(dex)) >= unlockCost(dex);

  function unlock(save, dex) {
    if (!canUnlock(save, dex) || !pay(save, famOf(dex), unlockCost(dex))) return false;
    save.owned[dex] = { at: Date.now(), from: 'shards' };
    return true;
  }

  const complete = (save, f) => members(f).every(d => !G.DEX_BY[d] || owns(save, d));
  const canStar = (save, f) => complete(save, f) && fam(save, f).stars < R.stars && shardsFor(save, f) >= R.starCost;

  function star(save, f) {
    if (!canStar(save, f) || !pay(save, f, R.starCost)) return false;
    fam(save, f).stars++;
    return true;
  }

  // ---------------- partidas de antes del cambio ----------------

  /**
   * Las mejoras de antes (de la cuenta, y luego de cada Pokémon: save.upgrades / save.pupg, que ya
   * no cambian) pasan al nuevo sistema sin perder nada. Se repite en cada carga (es idempotente),
   * así también se recupera si una versión antigua del juego pisara estos campos al fusionar:
   *   - entrenador: de cada mejora, el nivel más alto que tuviera cualquiera de tus Pokémon;
   *   - familia: el nivel que da al menos lo que daban su Fuerza, Reflejos, Golpe Crítico y
   *     Repertorio (el de la mejor forma de la familia).
   * Sólo la primera vez (`first`): Veto ya no existe y se devuelven las monedas que costó.
   * Lo que ya tenías se puede usar siempre: ver legacy (save.stats.famAt la pone db.js).
   */
  function migrate(s, first) {
    s.trainer = s.trainer || {};
    s.fams = s.fams || {};
    const all = Object.assign({ _acc: s.upgrades || {} }, s.pupg || {});
    for (const d in all) {
      const u = all[d] || {};
      for (const id of R.trainer) s.trainer[id] = Math.max(s.trainer[id] || 0, +u[id] || 0);
      if (d === '_acc' || !G.DEX_BY[d]) continue;
      const lv = Math.max(1,
        1 + Math.ceil((+u.atk || 0) * 0.04 / R.atkLv),
        1 + Math.ceil((+u.cd || 0) * 0.03 / R.cdLv),
        1 + Math.ceil((+u.crit || 0) * 0.03 / R.critLv),
        u.moves ? R.moves2Lv : 1);
      if (lv > 1) {
        const fm = fam(s, famOf(+d));
        fm.lv = Math.min(R.cap, Math.max(fm.lv, lv));
      }
      if (first) for (let l = 0; l < Math.min(3, +u.ban || 0); l++) s.coins += G.Upgrades.cost('ban', l);
    }
  }

  return { R, famOf, members, stage, reqLevel, chain, isFinal, famName, fam, legacy, usable, movesOf, known,
           basics, shown, poolOf, startMoves, perks, levelBonus, xpNeed, gainXp, afterPull, shardsFor, unlockCost, canUnlock,
           unlock, complete, canStar, star, migrate };
})();
