/* ============ enemies.js — Pokémon salvajes de todas las generaciones ============
 *
 * Los tramos ya no son listas fijas: cada tramo recoge a todos los Pokémon
 * (de cualquier generación) cuyo total de stats base cae en su rango, y al
 * empezar una run se elige al azar un ELENCO de cada tramo. Así cada partida
 * trae Pokémon distintos sin tener que cargar cientos de sprites a la vez.
 *
 * Los stats de combate salen de la plantilla del tramo, ajustados con la
 * vida y la velocidad propias de cada Pokémon.
 *
 * behavior:
 *   chase    va directo a por ti
 *   charger  se para, apunta y embiste
 *   ranged   se mantiene a distancia y dispara
 *   tank     lento, mucha vida
 *   ---- con personalidad ----
 *   healer   cura a los de alrededor (Chansey, Blissey, Audino...)
 *   shielder pone escudos a sus compañeros (Shuckle, Bronzong, Mr. Mime...)
 *   summoner llama a su manada (Nidoqueen trae Nidoran, Vespiquen Combee...)
 *   bomber   se acerca y explota (Voltorb, Electrode, Koffing, Geodude...)
 *   beamer   rayo que avisa en el suelo antes de disparar
 *   zoner    zonas de daño bajo tus pies que estallan al poco
 *   fan      dispara en abanico
 *   jumper   salta y cae sobre ti (la caída se ve antes en el suelo)
 *   runner   corredor: muy rápido y frágil, va a donde vas a estar (corta el
 *            paso al que sólo huye). Uno por tramo: el más rápido del elenco.
 * Los ataques con aviso están en systems/hazards.js.
 *
 * Jefes: Pokémon fuertes NO legendarios (pseudolegendarios, Slaking...), al
 * azar por franjas de poder. Los legendarios sólo salen en las grietas
 * (systems/rift.js).
 *
 * NIVELES (desde 2026-10-15, MODE 'level'): los salvajes tienen nivel. Empieza en 3, sube 4 por
 * minuto y desde el minuto 6 cada vez más deprisa (51 al minuto 10, 104 al 15). La vida, el daño
 * y la velocidad de cada uno salen de SUS stats base y de su nivel con las fórmulas de los juegos;
 * cada forma sale desde su nivel de evolución (Charmeleon desde el 16) y deja de salir cuando ya
 * habría evolucionado. Con MODE 'tier' vuelve el sistema anterior (plantilla del tramo × curvas de
 * tiempo). Números elegidos con el simulador de Godot (godot/sim/enemy_defs.gd, el mismo cálculo).
 */
G.Enemies = (() => {
  const TIERS = [
    { from: 0,   bst: [180, 330], hp: 17,  spd: 56, dmg: 6,  xp: 3.5, cast: 7 },
    { from: 70,  bst: [300, 405], hp: 32,  spd: 62, dmg: 8.5, xp: 5,  cast: 7 },
    { from: 160, bst: [385, 465], hp: 52,  spd: 60, dmg: 11, xp: 8,  cast: 7 },
    { from: 260, bst: [445, 515], hp: 88,  spd: 70, dmg: 14, xp: 13, cast: 7 },
    { from: 380, bst: [495, 560], hp: 150, spd: 66, dmg: 22, xp: 24, cast: 7 },
    { from: 500, bst: [530, 620], hp: 250, spd: 72, dmg: 28, xp: 38, cast: 7 }
  ];

  // Franjas de jefe: minuto en que salen, PV base y franja de BST.
  const BOSS_SLOTS = [
    { at: 180, hp: 1400,  dmg: 34, xp: 220,  bst: [490, 545] },
    { at: 360, hp: 3200,  dmg: 42, xp: 420,  bst: [520, 580] },
    { at: 540, hp: 5600,  dmg: 48, xp: 680,  bst: [540, 600] },
    { at: 720, hp: 9000,  dmg: 56, xp: 1000, bst: [580, 700] },
    { at: 900, hp: 16000, dmg: 68, xp: 1800, bst: [600, 700] }
  ];

  // Stats base aproximados a partir de los de juego (inverso de fetch_pokedex).
  const baseHp = p => (p.hp - 70) / 0.45;
  const baseSpd = p => (p.spd - 78) / 0.42;
  const baseAtk = p => (p.atk - 0.70) / 0.55 * 100;     // el mayor de Ataque y Ataque Especial
  const round2 = x => Math.floor(x * 100 + 0.5) / 100;

  const H = (d, s) => G.U.hash(d, 7, s);

  // Personalidades fijas de algunos Pokémon.
  const HEAL = new Set([35, 36, 113, 173, 183, 184, 242, 301, 440, 531, 594, 700, 764, 858]);
  const SHIELD = new Set([95, 122, 208, 213, 227, 306, 375, 410, 411, 436, 437, 439, 476, 703]);
  const BOMB = new Set([74, 75, 76, 100, 101, 102, 109, 110, 337, 338, 343, 344]);
  // Invocador -> Pokémon de su manada.
  const SUMMON = { 15: 13, 18: 16, 24: 23, 28: 27, 31: 29, 34: 32, 42: 41, 51: 50, 53: 52, 57: 56, 59: 58,
                   62: 60, 68: 66, 73: 72, 78: 77, 82: 81, 85: 84, 91: 90, 117: 116, 130: 129, 168: 167, 169: 41,
                   199: 79, 230: 116, 262: 261, 334: 333, 405: 403, 416: 415, 462: 81, 466: 239, 553: 551, 637: 636 };

  function behaviorOf(p) {
    const t = p.types, h = H(p.dex, 11);
    const has = (...xs) => xs.some(x => t.includes(x));
    if (HEAL.has(p.dex)) return 'healer';
    if (SHIELD.has(p.dex)) return 'shielder';
    if (BOMB.has(p.dex)) return 'bomber';
    if (SUMMON[p.dex] && G.SPRITE_META[SUMMON[p.dex]]) return 'summoner';
    // Enjambres: algunos Bicho llaman a más de los suyos (desde el principio).
    if (has('bug') && h >= 0.6 && h < 0.78) return 'summoner';
    if (has('electric', 'psychic', 'dragon', 'ice') && h < 0.18) return 'beamer';
    if (has('fire', 'ground', 'poison') && h < 0.18) return 'zoner';
    if (has('water', 'grass', 'bug', 'fairy') && h >= 0.18 && h < 0.32) return 'fan';
    if (has('fighting', 'ground', 'normal', 'rock') && h >= 0.42 && h < 0.56) return 'jumper';
    if (has('psychic', 'electric', 'ghost', 'fairy') && h < 0.4) return 'ranged';
    if (has('fire', 'water', 'poison', 'ice') && h < 0.22) return 'ranged';
    if (has('fighting', 'normal', 'ground', 'rock', 'dragon', 'steel', 'dark') && h < 0.4) return 'charger';
    if (baseHp(p) > 95 && baseSpd(p) < 50) return 'tank';
    return 'chase';
  }

  /** Construye la definición de enemigo de un Pokémon para un tramo. */
  function defFor(p, tier, ti) {
    const hpK = G.U.clamp(baseHp(p) / 65, 0.7, 1.6);
    const spdK = G.U.clamp(0.75 + baseSpd(p) / 260, 0.75, 1.3);
    const behavior = behaviorOf(p);
    const d = {
      dex: p.dex, name: p.name, behavior,
      hp: Math.round(tier.hp * hpK * (behavior === 'tank' ? 1.5 : 1)),
      spd: Math.round(tier.spd * spdK * (behavior === 'tank' ? 0.7 : 1)),
      dmg: Math.round(tier.dmg * (behavior === 'tank' ? 1.2 : 1)),
      xp: Math.max(3, Math.round(tier.xp * (behavior === 'tank' ? 1.3 : 1)))
    };
    // Los que pelean de lejos: daño del disparo, recarga y distancia.
    const CD = { ranged: 2.2 - ti * 0.15, fan: 3.2 - ti * 0.15, beamer: 4.4 - ti * 0.2, zoner: 4.6 - ti * 0.2,
                 healer: 3.5, summoner: 7 };
    if (CD[behavior]) {
      d.shotDmg = Math.round(tier.dmg * (behavior === 'fan' ? 0.7 : 0.8));
      d.shotCd = +CD[behavior].toFixed(2);
      d.range = (behavior === 'beamer' ? 260 : behavior === 'healer' || behavior === 'summoner' ? 230 : 190) + ti * 6;
    }
    if (behavior === 'summoner') d.minion = SUMMON[p.dex];
    if (behavior === 'fan') d.fanN = ti < 2 ? 3 : 5;             // abanico más ancho más adelante
    if (behavior === 'zoner') d.zones = ti < 2 ? 1 : ti < 4 ? 2 : 3;   // más zonas más adelante
    if (behavior === 'bomber') { d.spd = Math.round(d.spd * 1.25); d.hp = Math.round(d.hp * 0.8); }
    if (tier.lv) {
      // niveles: de qué salen sus stats; G.Spawner los calcula con el nivel con el que sale
      const tank = behavior === 'tank', bomb = behavior === 'bomber';
      Object.assign(d, {
        bhp: baseHp(p), batk: baseAtk(p), spd_k: spdK,
        hp_m: (tank ? 1.5 : 1) * (bomb ? 0.8 : 1), dmg_m: tank ? 1.2 : 1,
        spd_m: (tank ? 0.7 : 1) * (bomb ? 1.25 : 1), xp_m: tank ? 1.3 : 1,
        shot_m: behavior === 'fan' ? 0.7 : 0.8, appear: appearLevel(p.dex), leave: leaveLevel(p.dex)
      });
      return atLevel(d, tier.lv[0]);
    }
    return d;
  }

  /** Todos los candidatos de un tramo (sin legendarios ni míticos): por stats base o, con niveles,
   *  por el nivel desde el que salen. */
  function candidates(tier) {
    if (tier.lv) return G.DEX.filter(p => { const a = appearLevel(p.dex); return p.rarity < 5 && a >= tier.lv[0] && a < tier.lv[1] && G.SPRITE_META[p.dex]; });
    return G.DEX.filter(p => p.rarity < 5 && p.bst >= tier.bst[0] && p.bst <= tier.bst[1] && G.SPRITE_META[p.dex]);
  }

  // ---------------- elenco de la run ----------------

  const PLAIN = ['chase', 'charger', 'ranged', 'tank'];
  const SUPPORT = ['healer', 'shielder', 'summoner'];

  /**
   * Elenco de un tramo: siempre un "apoyo" (curandero, escudo o invocador)
   * y, desde el segundo tramo, también uno de los que atacan con aviso.
   * En el primero no hay más personalidades (para ir aprendiendo).
   */
  function castFor(tier) {
    const all = candidates(tier);
    const kind = p => behaviorOf(p);
    // Primero el tipo de apoyo (a partes iguales) y luego el Pokémon.
    const kinds = SUPPORT.filter(k => all.some(p => kind(p) === k));
    const sk = kinds.length ? kinds[Math.floor(Math.random() * kinds.length)] : null;
    const pick = sk ? G.U.pickN(all.filter(p => kind(p) === sk), 1) : [];
    if (tier.from > 0) pick.push(...G.U.pickN(all.filter(p => !PLAIN.includes(kind(p)) && !SUPPORT.includes(kind(p))), 1));
    if (tier.from === 0) return pick.concat(G.U.pickN(all.filter(p => !pick.includes(p) && PLAIN.includes(kind(p))), tier.cast - pick.length));
    return pick.concat(G.U.pickN(all.filter(p => !pick.includes(p)), tier.cast - pick.length));
  }

  let cast = null;      // [{ from, list: [def] }]
  let bosses = null;    // [def de jefe]

  /** Sortea el elenco de una run nueva. */
  function rollRun() {
    cast = tiers().map((tier, ti) => ({
      from: tier.from,
      list: castFor(tier).map(p => defFor(p, tier, ti))
    }));
    for (const tier of cast) {
      const plain = tier.list.filter(d => d.behavior === 'chase' || d.behavior === 'charger' || d.behavior === 'tank');
      const r = plain.sort((a, b) => b.spd - a.spd)[0];
      if (r) {
        r.behavior = 'runner'; r.spd = Math.round(r.spd * 1.6); r.hp = Math.round(r.hp * 0.7);
        if (r.hp_m != null) { r.spd_m *= 1.6; r.hp_m *= 0.7; }
      }
    }
    const used = new Set();
    bosses = BOSS_SLOTS.map(slot => {
      const ok = p => !p.leg && G.SPRITE_META[p.dex] && !used.has(p.dex);
      let pool = G.DEX.filter(p => ok(p) && p.bst >= slot.bst[0] && p.bst <= slot.bst[1]);
      if (!pool.length) pool = G.DEX.filter(p => ok(p) && p.bst >= 580);
      const p = G.U.pick(pool);
      used.add(p.dex);
      if (MODE === 'level') {
        const b = { at: slot.at, dex: p.dex, name: p.name, bhp: baseHp(p), batk: baseAtk(p), xp: slot.xp,
          spd: Math.round(G.U.clamp(40 + baseSpd(p) * 0.5, 40, 100)),
          behavior: behaviorOf(p) === 'ranged' ? 'ranged' : (baseSpd(p) > 90 ? 'charger' : 'chase'),
          shotCd: 1.1, range: 260 };
        return bossAtLevel(b, wildLevel(slot.at) + LV.boss_lv);
      }
      return {
        at: slot.at, dex: p.dex, name: p.name,
        // (Desde 2026-10-10 más duros: ×1,35 de vida y ×1,2 de daño.)
        hp: Math.round(slot.hp * 1.35), spd: Math.round(G.U.clamp(40 + baseSpd(p) * 0.5, 40, 100)),
        dmg: Math.round(slot.dmg * 1.2), xp: slot.xp,
        behavior: behaviorOf(p) === 'ranged' ? 'ranged' : (baseSpd(p) > 90 ? 'charger' : 'chase'),
        shotDmg: Math.round(slot.dmg * 0.55), shotCd: 1.1, range: 260
      };
    });
    return { cast, bosses };
  }

  function scale(t) {
    const k = late(t);
    return { hp: (1 + t / 95) * k, dmg: (1 + t / 420) * Math.pow(k, 0.7), spd: 1 + Math.min(0.35, t / 1400) };
  }

  /**
   * Tiempo extra (desde 2026-10-12). Hasta el minuto 60 todo sigue igual; desde
   * ahí la vida (y algo menos el daño) crece cada vez más deprisa, como en otros
   * "survivors". Antes crecía en línea recta y, con las mejoras ya al máximo,
   * las mejores builds aguantaban sin fin (runs de 2 a 4 horas).
   *   minuto   60    75    90    105   120   150
   *   vida    ×1   ×1,09 ×1,4  ×2,1  ×3,8  ×21    (además de la subida normal)
   */
  const LATE_FROM = 60, LATE_K = 0.000374;
  function late(t) { const m = Math.max(0, t / 60 - LATE_FROM); return Math.exp(Math.min(30, LATE_K * m * m)); }

  /**
   * Los jefes ya traen su vida base creciente (1.400 ... 16.000), así que
   * escalan mucho más suave: con la curva normal el último llegaba a 168.000 PV.
   */
  function bossScale(t) { const k = late(t); return { hp: (1 + t / 600) * k, dmg: (1 + t / 600) * Math.pow(k, 0.7), spd: 1 }; }

  /** Tramo que toca en el segundo `t`. */
  function tierAt(t) { let ti = 0; tiers().forEach((tr, i) => { if (t >= tr.from) ti = i; }); return ti; }

  const NO_HORDE = new Set(['bomber', 'healer', 'shielder', 'summoner']);
  /** Con niveles, sólo las formas que ya pueden salir a este nivel salvaje. */
  const wildOk = (p, t) => MODE !== 'level' || LV.gate <= 0 || appearLevel(p.dex) <= wildLevel(t);
  /** Tipos con bastantes Pokémon en el tramo actual para una horda (events.js). */
  function hordeTypes(t) {
    const all = candidates(tiers()[tierAt(t)]).filter(p => !NO_HORDE.has(behaviorOf(p)) && wildOk(p, t));
    return Object.keys(G.U.TYPE_COLOR).filter(ty => all.filter(p => p.types.includes(ty)).length >= 3);
  }
  /** Hasta 4 Pokémon de un tipo, con los stats del tramo actual. */
  function hordeDefs(type, t) {
    const ti = tierAt(t);
    const pool = candidates(tiers()[ti]).filter(p => p.types.includes(type) && !NO_HORDE.has(behaviorOf(p)) && wildOk(p, t));
    return G.U.pickN(pool, 4).map(p => defFor(p, tiers()[ti], ti));
  }

  /** Bolsa de enemigos disponibles en el segundo `t`. */
  function bagAt(t) {
    // Durante una horda de un tipo sólo salen los de ese tipo (systems/events.js).
    const horde = G.Events && G.Events.bag();
    if (horde) return horde;
    if (!cast) rollRun();
    const bag = [], wl = wildLevel(t);
    let last = cast[0].list;
    for (const tier of cast) {
      if (t < tier.from) continue;
      last = tier.list;
      const w = t - tier.from > 260 ? 3 : 10;       // los tramos viejos pierden peso
      for (const e of tier.list) {
        // con niveles: aún no ha evolucionado hasta esta forma, o ya habría evolucionado
        if (e.appear != null && ((LV.gate > 0 && wl < e.appear) || wl > e.leave)) continue;
        for (let i = 0; i < w; i++) bag.push(e);
      }
    }
    return bag.length ? bag : last;
  }

  /** dex del elenco que aparecerán pronto (para precargar sprites). */
  function upcomingDex(t, ahead = 60) {
    if (!cast) rollRun();
    const out = [];
    for (const tier of cast) if (tier.from <= t + ahead) for (const e of tier.list) out.push(e.dex);
    for (const b of bosses) if (b.at <= t + ahead) out.push(b.dex);
    return out;
  }

  // ---------------- niveles de los salvajes (MODE 'level') ----------------

  let MODE = 'level';
  // Los números que eligieron las pruebas del simulador (variante "M11", 2026-10-15): con los
  // nuevos se aguanta más y no se muere todo el mundo a la vez; con todo mejorado, como antes.
  const LV_DEFAULTS = {
    lv0: 3,          // nivel al empezar
    lv_min: 4,       // + niveles por minuto
    lv_acc: 0.5,     // + niveles por minuto² (cada vez más deprisa)...
    acc_from: 6,     //   ...contando desde este minuto
    spread: 2,       // cada uno sale hasta ± estos niveles
    hp_k: 2.8,       // vida = hp_k × el PS de los juegos para su PS base y su nivel
    dmg_k: 5.4,      // daño = dmg_k × factor de nivel (dmg_lv·Nv + 2) × su ataque base sobre uno medio
    dmg_lv: 0.2,     //   (2/5 en los juegos: sube demasiado deprisa para este juego)
    grow: 0.03,      // vida extra por nivel, acumulada (×1,03 cada nivel)
    xp0: 3.4,        // experiencia: xp0 + xp_lv × nivel (luego × XP_K del spawner)
    xp_lv: 0.17,
    bands: [1, 12, 22, 32, 42, 52],   // grupos del elenco según el nivel desde el que salen
    linger: 15,      // una forma que evoluciona sale hasta su nivel de evolución + esto
    gate: 1,         // 1: cada forma espera a su nivel de evolución · 0: sólo al de su grupo
    boss_lv: 8,      // jefes: nivel salvaje + esto,
    boss_hp: 5,      //   ×vida sobre uno salvaje de su especie y nivel,
    boss_dmg: 0.8,   //   ×daño
    cap: 0           // nivel máximo (0 = sin tope)
  };
  let LV = Object.assign({}, LV_DEFAULTS, { bands: LV_DEFAULTS.bands.slice() });
  let lvTiers = null, appear = null;

  /** Para pruebas y herramientas: 'tier' o 'level', y números distintos ({ lv_min: 5 }). */
  function setMode(m, over) {
    MODE = m;
    LV = Object.assign({}, LV_DEFAULTS, { bands: LV_DEFAULTS.bands.slice() }, over || {});
    lvTiers = null; cast = null; bosses = null;
  }

  const tiers = () => (MODE === 'level' ? levelTiers() : TIERS);

  /** Nivel salvaje en el segundo t (sin redondear). */
  function wildLevel(t) {
    const m = t / 60, u = Math.max(0, m - LV.acc_from);
    const l = LV.lv0 + LV.lv_min * m + LV.lv_acc * u * u;
    return LV.cap > 0 ? Math.min(l, LV.cap) : l;
  }

  /** Segundo en que el nivel salvaje llega a l (0 si ya empieza ahí o más). */
  function timeOfLevel(l) {
    const a = LV.lv_acc, b = LV.lv_min, f = LV.acc_from, c = LV.lv0 - l;
    if (c >= 0) return 0;
    if (a <= 0 || LV.lv0 + b * f >= l) return -c / Math.max(b, 0.001) * 60;
    const c2 = LV.lv0 + b * f - l;
    return (f + (-b + Math.sqrt(b * b - 4 * a * c2)) / (2 * a)) * 60;
  }

  /** Nivel de uno que sale ahora: el salvaje ± spread (enteros, mínimo 1). */
  function spawnLevel(t) {
    const s = Math.round(LV.spread);
    let l = Math.floor(wildLevel(t));
    if (s > 0) l += Math.floor(Math.random() * (2 * s + 1)) - s;
    return Math.max(1, l);
  }

  // Fórmulas de los juegos (IV 31, sin EV, naturaleza neutra).
  const hpStat = (b, l) => (2 * b + 31) * l / 100 + l + 10;
  /** Daño: factor de nivel (dmg_lv·Nv + 2, igual que en los juegos al nivel 3) × su ataque base sobre uno medio (75). */
  function dmgOf(batk, l) {
    const k = LV.dmg_lv;
    return (k * l + 2) * (3.2 / (k * 3 + 2)) * (2 * batk + 31) / 181;
  }

  /** La definición con sus stats a nivel l. */
  function atLevel(d, l) {
    const lv = Math.max(1, l), grow = Math.pow(1 + LV.grow, Math.max(0, lv - LV.lv0));
    const o = Object.assign({}, d);
    o.level = Math.floor(lv);
    o.hp = Math.max(1, Math.round(LV.hp_k * hpStat(d.bhp, lv) * d.hp_m * grow));
    o.dmg = round2(LV.dmg_k * dmgOf(d.batk, lv) * d.dmg_m);
    o.spd = Math.round((56 + Math.min(16, lv * 0.3)) * d.spd_k * d.spd_m);
    o.xp = Math.max(3, Math.round((LV.xp0 + LV.xp_lv * lv) * d.xp_m));
    if (d.shotDmg != null) o.shotDmg = round2(o.dmg * d.shot_m / d.dmg_m);
    return o;
  }

  /** Un jefe a nivel l: boss_hp × la vida de uno salvaje de su especie y nivel. */
  function bossAtLevel(b, l) {
    const lv = Math.max(1, l), grow = Math.pow(1 + LV.grow, Math.max(0, lv - LV.lv0));
    const o = Object.assign({}, b);
    o.level = Math.floor(lv);
    o.hp = Math.round(LV.hp_k * hpStat(b.bhp, lv) * LV.boss_hp * grow);
    o.dmg = round2(LV.dmg_k * dmgOf(b.batk, lv) * LV.boss_dmg);
    o.shotDmg = round2(o.dmg * 0.46);
    return o;
  }

  /**
   * Nivel desde el que sale cada especie: una forma evolucionada, desde su nivel de evolución (el
   * de los juegos o el estimado, data/evolutions.js); la primera de una familia que evoluciona,
   * desde el 1; una que no evoluciona, desde el de las formas evolucionadas con stats parecidos.
   * Deja de salir en el nivel de su siguiente forma + linger (nunca, si es la última).
   */
  function appearData() {
    if (appear) return appear;
    appear = {};
    const F = G.Families;
    // total de stats base -> nivel, ajustado con las evoluciones por nivel (como tools/fetch_evolutions.py)
    let n = 0, sx = 0, sy = 0, sxx = 0, sxy = 0;
    for (const k in G.EVO) {
      const lv = (G.EVO[k].how && G.EVO[k].how.lv) | 0;
      if (lv > 0 && G.DEX_BY[k]) { const x = G.DEX_BY[k].bst; n++; sx += x; sy += lv; sxx += x * x; sxy += x * lv; }
    }
    const b1 = (n * sxy - sx * sy) / (n * sxx - sx * sx), b0 = (sy - b1 * sx) / n;
    for (const p of G.DEX) {
      const d = p.dex, e = G.EVO[d] || {}, h = e.how || {};
      let from = 1;
      if ((h.lv | 0) > 0 || (h.est | 0) > 0) from = Math.min(60, (h.lv | 0) > 0 ? h.lv : h.est);
      else if (F.members(F.famOf(d)).length <= 1) from = G.U.clamp(Math.round(b0 + b1 * p.bst), 1, 60);
      let nxt = 999;
      for (const c of F.members(F.famOf(d))) if (G.EVO[c] && G.EVO[c].from === d) nxt = Math.min(nxt, F.reqLevel(c));
      appear[d] = [from, nxt];
    }
    return appear;
  }
  const appearLevel = dex => (appearData()[dex] || [1, 999])[0];
  function leaveLevel(dex) {
    const nxt = (appearData()[dex] || [1, 999])[1];
    return nxt + (nxt < 999 ? LV.linger : 0);
  }

  /** Grupos del elenco con niveles: uno por franja, desde que el nivel salvaje llega a ella. */
  function levelTiers() {
    if (lvTiers) return lvTiers;
    const b = LV.bands;
    lvTiers = b.map((lv, i) => Object.assign({}, TIERS[Math.min(i, TIERS.length - 1)], {
      from: i === 0 ? 0 : Math.round(timeOfLevel(lv)),
      lv: [i > 0 ? lv : -999, i + 1 < b.length ? b[i + 1] : 9999]
    }));
    return lvTiers;
  }

  return {
    TIERS, BOSS_SLOTS, LATE_FROM, rollRun, scale, bossScale, late, bagAt, upcomingDex, candidates, hordeTypes, hordeDefs,
    get MODE() { return MODE; }, get LV() { return LV; }, LV_DEFAULTS, setMode, tiers, wildLevel, timeOfLevel, spawnLevel,
    atLevel, bossAtLevel, appearLevel, leaveLevel, defFor, behaviorOf,
    get BOSSES() { if (!bosses) rollRun(); return bosses; },
    get cast() { if (!cast) rollRun(); return cast; }
  };
})();
