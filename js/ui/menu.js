/* ============ menu.js — menú principal, colección y mejoras ============ */
G.MenuUI = (() => {
  const $ = G.UI.$;
  const GEN_NAMES = ['Kanto', 'Johto', 'Hoenn', 'Sinnoh', 'Teselia', 'Kalos', 'Alola', 'Galar', 'Paldea'];
  let dexFilter = 'all', dexGen = 1, dexSel = null;

  function init() {
    const ICON = { play: 'ball', dex: 'book', upgrades: 'up', gacha: 'ball4', goals: 'medal3', friends: 'friends', rank: 'trophy', settings: 'gear' };
    document.querySelectorAll('#scr-menu [data-go]').forEach(b => {
      b.insertAdjacentHTML('afterbegin', `<span class="mi-ico">${G.Icons.html(ICON[b.dataset.go], 26)}</span>`);
      b.dataset.sfx = b.dataset.go === 'play' ? 'confirm' : 'click';
      b.onclick = () => {
        const go = b.dataset.go;
        if (go === 'play') { if (G.Social.room) G.LobbyUI.open(); else G.Flow.play(); }
        else if (go === 'dex') openDex();
        else if (go === 'upgrades') openUpgrades();
        else if (go === 'gacha') G.GachaUI.open();
        else if (go === 'goals') G.GoalsUI.open();
        else if (go === 'friends') G.FriendsUI.open();
        else if (go === 'rank') G.RankingUI.open();
        else if (go === 'settings') G.SettingsUI.open();
      };
    });
    document.querySelectorAll('[data-back]').forEach(b => { b.onclick = open; });
    G.Social.on(() => { if (G.UI.isOpen('scr-menu')) socialLine(); });
    $('btn-logout').onclick = () => {
      // El invitado sólo pierde la partida si el navegador no deja guardar.
      if (G.DB.guest && !G.DB.storageOk && !confirm('Eres invitado: se perderá todo el progreso. ¿Salir?')) return;
      G.Audio.music(null);
      G.DB.logout().then(() => G.Flow.toLogin());
    };
  }

  // ---------------- menú principal ----------------

  function open() {
    const s = G.DB.save;
    const mon = G.DEX_BY[s.partner];
    const shiny = !!s.partnerShiny && G.DB.ownsShiny(mon.dex);
    G.UI.chrome(true);
    G.UI.show('scr-menu');
    G.UI.sprite($('menu-partner'), mon.dex, { lively: true, scale: 4, hero: true, shiny });
    $('menu-partner').style.setProperty('--stage-c', shiny ? '#9ae6ff' : G.U.TYPE_COLOR[mon.types[0]]);
    $('menu-partner').classList.toggle('shiny', shiny);
    $('menu-partner-name').innerHTML = mon.name + (shiny ? ' ' + G.Icons.html('shiny', 24) : '');
    $('menu-partner-info').innerHTML = G.UI.typeChips(mon.types) + ' ' + G.UI.stars(mon.rarity);
    // Normal / shiny a mano, aquí mismo (en el móvil no se encontraba en la ficha).
    const seg = $('menu-shiny');
    seg.classList.toggle('hidden', !G.DB.ownsShiny(mon.dex));
    seg.lastChild.innerHTML = G.Icons.html('shiny', 12) + ' Shiny';
    seg.querySelectorAll('button').forEach(b => {
      b.classList.toggle('on', (b.dataset.v === '1') === shiny);
      b.onclick = () => {
        if ((b.dataset.v === '1') === shiny) return;
        s.partnerShiny = b.dataset.v === '1';
        G.DB.commit();
        G.Audio.sfx('confirm');
        open();
      };
    });

    const owned = Object.keys(s.owned).filter(d => G.DEX_BY[d]).length;
    const shinies = Object.keys(s.shiny || {}).length;
    $('menu-dex-count').textContent = `${owned} / ${G.DEX.length}` + (shinies ? ` · ${shinies} shiny` : '');

    const st = s.stats;
    $('menu-stats').innerHTML =
      `Runs <b style="color:#fff">${st.runs}</b> · Mejor tiempo <b style="color:#fff">${G.U.mmss(st.bestTime)}</b><br>` +
      `Mejor nivel <b style="color:#fff">${st.bestLevel}</b> · Derrotados <b style="color:#fff">${st.totalKills.toLocaleString('es')}</b>` +
      (!G.DB.guest || window.PS_APP ? '' : G.DB.storageOk ? '<br><span style="color:var(--muted)">Modo invitado: guardado sólo en este navegador</span>'
        : '<br><span style="color:#ffb0b8">Modo invitado: no se guarda</span>');

    socialLine();
    // Premios de misiones por recoger.
    G.Progress.checkAch();
    const pend = G.Progress.pending();
    $('menu-goals-sub').textContent = pend ? pend + (pend === 1 ? ' premio por recoger' : ' premios por recoger') : 'Misiones, logros y perfil';
    $('menu-goals-sub').classList.toggle('gold', pend > 0);
    // Con cuenta en la nube: amigos en línea, invitaciones y (una vez) el apodo.
    if (G.DB.online && !G.Social.started) {
      G.Social.start().then(r => {
        if (r === 'need-nick' && !G.NickUI.skipped && G.UI.isOpen('scr-menu')) G.NickUI.open();
        socialLine();
      });
    }
    G.InvitePop.refresh();
  }

  /** Texto bajo "Amigos" y "Jugar": quién está en línea, solicitudes, sala. */
  function socialLine() {
    const room = G.Social.room;
    const play = document.querySelector('#scr-menu [data-go=play] small');
    if (play) play.textContent = room ? 'Volver a tu sala (' + room.members.length + '/' + G.Social.MAX_PLAYERS + ')' : 'Entra en la mazmorra';
    const fr = G.Social.friends;
    const on = fr.filter(f => f.status === 'ok' && f.online).length;
    const req = fr.filter(f => f.status === 'in').length;
    const parts = [];
    if (on) parts.push(on + ' en línea');
    if (req) parts.push(req + (req === 1 ? ' solicitud' : ' solicitudes'));
    $('menu-friends-sub').textContent = parts.length ? parts.join(' · ') : 'Juega en grupo, hasta 4';
    $('menu-friends-sub').classList.toggle('gold', req > 0);
  }

  // ---------------- colección ----------------

  function openDex() {
    G.UI.show('scr-dex', true);
    const s = G.DB.save;
    if (dexSel == null) { dexSel = s.partner; dexGen = G.DEX_BY[s.partner].gen; }
    const owned = Object.keys(s.owned).filter(d => G.DEX_BY[d]).length;
    $('dex-total').textContent = `${owned} / ${G.DEX.length}`;

    // Pestañas de generación, con cuántos tienes de cada una.
    const tabs = $('dex-gens');
    tabs.innerHTML = '';
    GEN_NAMES.forEach((name, i) => {
      const g = i + 1;
      const total = G.DEX.filter(p => p.gen === g).length;
      const have = G.DEX.filter(p => p.gen === g && s.owned[p.dex]).length;
      const b = document.createElement('button');
      b.className = 'gen-tab' + (g === dexGen ? ' on' : '');
      b.innerHTML = `<b>${name}</b><small>${have}/${total}</small>`;
      b.onclick = () => { dexGen = g; openDex(); };
      tabs.appendChild(b);
    });

    const F = [['all', 'Todos'], ['own', 'Tengo'], ['miss', 'Me faltan'], ['shiny', 'Shiny'],
               ['5', 5], ['4', 4], ['3', 3], ['2', 2], ['1', 1]];
    const fb = $('dex-filters');
    fb.innerHTML = '';
    for (const [k, label] of F) {
      const c = document.createElement('button');
      c.className = 'chip' + (k === dexFilter ? ' on' : '');
      c.innerHTML = k === 'shiny' ? G.Icons.html('shiny', 12) + ' Shiny'
                  : typeof label === 'number' ? G.Icons.rarity(label, 12) + ' ' + G.Gacha.RARITY_NAME[label] : label;
      c.onclick = () => { dexFilter = k; openDex(); };
      fb.appendChild(c);
    }
    renderGrid();
    showDetail(dexSel);
  }

  function renderGrid() {
    const s = G.DB.save;
    const grid = $('dex-grid');
    grid.innerHTML = '';
    for (const p of G.DEX) {
      if (p.gen !== dexGen) continue;
      const own = !!s.owned[p.dex], sh = !!(s.shiny && s.shiny[p.dex]);
      if (dexFilter === 'own' && !own) continue;
      if (dexFilter === 'miss' && own) continue;
      if (dexFilter === 'shiny' && !sh) continue;
      if (/^\d$/.test(dexFilter) && p.rarity !== +dexFilter) continue;

      const cell = document.createElement('div');
      cell.className = 'cell' + (own ? '' : ' locked') + (p.dex === dexSel ? ' on' : '');
      cell.insertAdjacentHTML('beforeend', `<span class="no">${String(p.dex).padStart(3, '0')}</span>`);
      if (p.dex === s.partner) cell.insertAdjacentHTML('beforeend', `<span class="badge-r" title="Compañero">${G.Icons.html('crown', 14)}</span>`);
      else if (sh) cell.insertAdjacentHTML('beforeend', `<span class="badge-r" title="Tienes su shiny">${G.Icons.html('shiny', 12)}</span>`);
      const useShiny = sh && p.dex === s.partner && s.partnerShiny;
      cell.appendChild(G.UI.spriteCanvas(p.dex, 92, 80, { scale: 2, silhouette: !own, shadow: own, shiny: useShiny }));
      cell.insertAdjacentHTML('beforeend', `<b>${own ? p.name : '???'}</b>${G.UI.stars(p.rarity, 9)}`);
      cell.onclick = () => {
        dexSel = p.dex;
        grid.querySelectorAll('.cell').forEach(c => c.classList.remove('on'));
        cell.classList.add('on');
        showDetail(p.dex);
      };
      grid.appendChild(cell);
    }
    if (!grid.children.length) grid.innerHTML = '<p class="sub" style="grid-column:1/-1">Ninguno con este filtro.</p>';
  }

  // Variante que se está viendo en la ficha (normal o shiny).
  let viewShiny = false;

  function showDetail(dex) {
    const s = G.DB.save;
    const p = G.DEX_BY[dex];
    const own = !!s.owned[dex];
    const hasSh = G.DB.ownsShiny(dex);
    const isPartner = dex === s.partner;
    if (!hasSh) viewShiny = false;
    else if (isPartner && dex !== showDetail.last) viewShiny = !!s.partnerShiny;
    showDetail.last = dex;

    const max = { hp: 183, atk: 1.55, spd: 137 };
    const bar = (label, v, m, txt) =>
      `<div class="stat"><span>${label}</span><div class="bar"><i style="width:${Math.min(100, v / m * 100)}%"></i></div><span>${txt}</span></div>`;
    const usingThis = isPartner && (!hasSh || !!s.partnerShiny === viewShiny);
    // Familia: su nivel decide qué movimientos sabe y si esta forma se puede usar ya.
    const F = G.Families, fm = F.fam(s, F.famOf(dex)), req = F.reqLevel(dex), ok = own && F.usable(s, dex);

    const box = $('dex-detail');
    box.innerHTML = `
      <canvas id="dex-big" class="stage" width="220" height="190"></canvas>
      ${hasSh ? `<div class="seg">
          <button class="${viewShiny ? '' : 'on'}" data-v="0">Normal</button>
          <button class="${viewShiny ? 'on' : ''}" data-v="1">${G.Icons.html('shiny', 12)} Shiny</button></div>` : ''}
      <div class="center">
        <div style="color:var(--muted);font-size:13px">Nº ${String(p.dex).padStart(3, '0')} · ${GEN_NAMES[p.gen - 1]}</div>
        <h3>${own ? p.name : '???'}</h3>
        <div style="color:${G.Gacha.RARITY_COLOR[p.rarity]}">${G.UI.stars(p.rarity, 24)} ${G.Gacha.RARITY_NAME[p.rarity]}</div>
        <div style="margin:6px 0">${own ? G.UI.typeChips(p.types) : ''}</div>
      </div>
      ${own ? `
        ${bar('Vida', p.hp, max.hp, p.hp)}
        ${bar('Ataque', p.atk, max.atk, '×' + p.atk.toFixed(2))}
        ${bar('Velocidad', p.spd, max.spd, p.spd)}
        <p style="font-size:14px;margin:10px 0 4px"><span>Familia de ${F.famName(F.famOf(dex))}</span> · <b class="gold">Nv. ${fm.lv}</b></p>
        <p style="font-size:14px;margin:4px 0">Empieza con <b class="gold">${F.startMoves(s, dex).map(id => G.Moves.BY_ID[id].name).join(' + ')}</b></p>
        <p class="move-icons" title="Movimientos que aprende (los apagados, con más nivel de familia)">
          ${F.movesOf(dex).map(e => `<span class="${e[1] <= fm.lv ? '' : 'dim'}" title="${G.Moves.BY_ID[e[0]].name} · Nv. ${e[1]}">${G.Icons.html('move:' + e[0], 16)}</span>`).join('')}</p>
        ${usingThis
          ? '<button class="btn grow" disabled style="width:100%">Es tu compañero</button>'
          : ok ? `<button id="dex-pick" class="btn gold" data-sfx="confirm" style="width:100%">Elegir de compañero${viewShiny ? ' (shiny)' : ''}</button>`
          : `<button class="btn grow" disabled style="width:100%">Necesita su familia a nivel ${req}</button>`}
      ` : `<p class="center" style="color:var(--muted)">Aún no lo tienes.<br>Consíguelo en el banner de <b class="gold">${GEN_NAMES[p.gen - 1]}</b>
            o derrotándolo cuando salga shiny.${req > 1 ? `<br>También se desbloquea con fragmentos en Mejoras cuando su familia llega al nivel ${req}.` : ''}</p>`}
    `;
    $('dex-big').style.setProperty('--stage-c', !own ? '#5b83d6' : viewShiny ? '#9ae6ff' : G.U.TYPE_COLOR[p.types[0]]);
    $('dex-big').classList.toggle('shiny', own && viewShiny);
    G.UI.sprite($('dex-big'), dex, { lively: own, spin: own, silhouette: !own, scale: 3, hero: true, shiny: own && viewShiny });
    box.querySelectorAll('.seg button').forEach(b => {
      b.onclick = () => { viewShiny = b.dataset.v === '1'; showDetail(dex); };
    });
    const pick = $('dex-pick');
    if (pick) pick.onclick = () => {
      if (!G.Families.usable(s, dex)) return;
      s.partner = dex;
      s.partnerShiny = hasSh && viewShiny;
      G.DB.commit();
      G.UI.toast(p.name + (s.partnerShiny ? ' shiny' : '') + ' es ahora tu compañero');
      renderGrid(); showDetail(dex);
    };
  }

  // ---------------- mejoras: familia y entrenador (systems/families.js) ----------------

  let upgFam = null;      // familia que se está viendo

  /** La forma que representa a una familia: tu compañero si es de ella; si no, la más
   *  evolucionada que puedes usar (o la primera que tengas). */
  function famForm(f) {
    const s = G.DB.save, F = G.Families;
    if (F.famOf(s.partner) === f) return s.partner;
    const m = F.members(f).filter(d => G.DEX_BY[d]);
    const ok = m.filter(d => F.usable(s, d)).sort((a, b) => F.stage(b) - F.stage(a));
    return ok[0] || m.filter(d => s.owned[d])[0] || m[0];
  }

  function openUpgrades() {
    G.UI.show('scr-upgrades', true);
    const s = G.DB.save, F = G.Families;
    const mine = F.famOf(s.partner);
    const fams = [...new Set(Object.keys(s.owned).map(Number).filter(d => G.DEX_BY[d]).map(F.famOf))];
    if (upgFam == null || !fams.includes(upgFam)) upgFam = mine;
    const lv = f => F.fam(s, f).lv;
    fams.sort((a, b) => (b === mine) - (a === mine) || lv(b) - lv(a) || F.famName(a).localeCompare(F.famName(b), 'es'));
    const sel = $('upg-mon');
    sel.innerHTML = fams.map(f => `<option value="${f}">${F.famName(f)} · Nv. ${lv(f)}${f === mine ? ' (compañero)' : ''}</option>`).join('');
    sel.value = upgFam;
    sel.onchange = () => { upgFam = +sel.value; G.Audio.sfx('select'); renderUpgrades(); };
    renderUpgrades();
  }

  function renderUpgrades() {
    const s = G.DB.save, F = G.Families;
    const dex = famForm(upgFam);
    const mon = G.DEX_BY[dex];
    const shiny = dex === s.partner && !!s.partnerShiny && G.DB.ownsShiny(dex);
    G.UI.sprite($('upg-stage'), dex, { lively: true, scale: 2, hero: true, shiny });
    $('upg-stage').style.setProperty('--stage-c', shiny ? '#9ae6ff' : G.U.TYPE_COLOR[mon.types[0]]);
    const box = $('upg-list');
    box.innerHTML = '';
    box.appendChild(famPanel(upgFam, dex));
    box.insertAdjacentHTML('beforeend', `<div class="upg-title"><b>Entrenador</b>
      <p class="sub">Se compran con Pokémonedas y valen para todos tus Pokémon.</p></div>`);
    for (const u of G.Upgrades.LIST) {
      if (!F.R.trainer.includes(u.id)) continue;
      const lvl = (s.trainer || {})[u.id] || 0;
      const maxed = lvl >= u.max;
      const cost = maxed ? 0 : G.Upgrades.cost(u.id, lvl);
      const el = document.createElement('div');
      el.className = 'panel upg-item';
      el.innerHTML = `
        <div class="ic">${G.Icons.html(u.icon, 32)}</div>
        <div>
          <b>${u.name}</b> <span style="color:var(--muted);font-size:13px">${u.unit}</span>
          <div class="pips">${Array.from({ length: u.max }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('')}</div>
        </div>
        <div class="upg-btns">
          <button class="btn small ${maxed ? '' : 'gold'}" data-buy data-sfx="none" ${maxed || s.coins < cost ? 'disabled' : ''}>
          ${maxed ? 'Máx.' : `<span class="coin"></span> ${cost}`}</button></div>`;
      el.querySelector('[data-buy]').onclick = () => {
        // Se vuelve a leer todo al pulsar (la partida puede haber cambiado desde que se dibujó).
        const sv = G.DB.save;
        sv.trainer = sv.trainer || {};
        const now = sv.trainer[u.id] || 0;
        if (now >= u.max) { renderUpgrades(); return; }
        const price = G.Upgrades.cost(u.id, now);
        if (sv.coins < price) { renderUpgrades(); return; }
        sv.coins -= price;
        sv.trainer[u.id] = now + 1;
        G.DB.commit(true);
        G.Audio.sfx('buy');
        G.UI.refreshCoins();
        G.UI.toast(`Entrenador · ${u.name}: nivel ${now + 1}`);
        renderUpgrades();
      };
      box.appendChild(el);
    }
    box.appendChild(bindPanel(dex));
  }

  /** Nivel, experiencia, lo que da, fragmentos, formas (elegir / desbloquear) y movimientos. */
  function famPanel(f, dex) {
    const s = G.DB.save, F = G.Families, fm = F.fam(s, f), b = F.levelBonus(fm.lv);
    const need = F.xpNeed(fm.lv);
    const el = document.createElement('div');
    el.className = 'panel fam-panel';
    el.innerHTML = `
      <div class="row between"><b>Familia de ${F.famName(f)}</b><b class="gold">Nv. ${fm.lv} / ${F.R.cap}</b></div>
      ${fm.lv < F.R.cap ? `<div class="xpbar"><i style="width:${Math.min(100, fm.xp / need * 100).toFixed(1)}%"></i></div>
        <p class="sub" style="margin:0">Faltan ${Math.ceil(need - fm.xp)} de experiencia para el siguiente nivel.</p>
        <p class="sub" style="margin:0">Sube jugando con cualquier Pokémon de la familia.</p>` : ''}
      <p class="fam-bonus"><span>+${b.atk}% de daño</span> · <span>−${b.cd}% de recarga</span> ·
        <span>+${b.crit}% de críticos</span> · <span>${b.two ? 'Empieza con 2 movimientos'
          : `Empieza con 2 movimientos desde el nivel ${F.R.moves2Lv}`}</span>${fm.stars
          ? ` · <span>${fm.stars} estrellas: +${Math.round(fm.stars * F.R.starAtk * 100)}% de daño y de vida</span>` : ''}</p>
      <p class="sub fam-shards">${G.Icons.html('star', 12)} <span>Fragmentos: ${fm.shards}</span> ·
        <span>Universales: ${s.uni || 0}</span> <span>(${F.R.uniRate} valen 1)</span></p>
      <div class="fam-forms"></div>
      <div class="fam-moves"></div>`;
    // formas de la familia: la que puedes usar se elige, la que te falta se desbloquea
    const row = el.querySelector('.fam-forms');
    const forms = F.members(f).filter(d => G.DEX_BY[d])
      .sort((a, c) => F.reqLevel(a) - F.reqLevel(c) || F.stage(a) - F.stage(c) || a - c);
    for (const d of forms) {
      const p = G.DEX_BY[d], own = !!s.owned[d], ok = F.usable(s, d), req = F.reqLevel(d);
      const c = document.createElement('div');
      c.className = 'fam-form' + (ok ? ' ok' : '') + (d === s.partner ? ' on' : '');
      c.appendChild(G.UI.spriteCanvas(d, 84, 72, { scale: 2, silhouette: !own, shadow: own }));
      let status;
      if (d === s.partner) status = '<small class="gold">Compañero</small>';
      else if (ok) status = `<button class="btn small gold" data-pick="${d}">Elegir</button>`;
      else if (own) status = `<small>Necesita nivel ${req}</small>`;
      else if (fm.lv >= req) status = `<button class="btn small" data-unlock="${d}" ${F.canUnlock(s, d) ? '' : 'disabled'}>
        <span>Desbloquear</span> ${G.Icons.html('star', 12)} ${F.unlockCost(d)}</button>`;
      else status = `<small><span>Nivel ${req}</span> · ${G.Icons.html('star', 12)} ${F.unlockCost(d)}</small>`;
      // aquí sí el nombre aunque no lo tengas: es la meta de la familia
      c.insertAdjacentHTML('beforeend', `<b>${p.name}</b>${G.UI.stars(p.rarity, 8)}${status}`);
      row.appendChild(c);
    }
    if (F.complete(s, f) && fm.stars < F.R.stars) {
      row.insertAdjacentHTML('beforeend', `<div class="fam-form star"><b>${fm.stars} / ${F.R.stars}</b>
        <button class="btn small gold" data-star ${F.canStar(s, f) ? '' : 'disabled'}><span>Estrella</span>
        ${G.Icons.html('star', 12)} ${F.R.starCost}</button><small>+5% de daño y de vida</small></div>`);
    }
    // movimientos de esta forma, con el nivel de familia que los desbloquea
    el.querySelector('.fam-moves').innerHTML = `<p class="sub" style="margin:8px 0 4px">Movimientos de ${G.DEX_BY[dex].name}</p>
      <div class="ban-moves">${F.movesOf(dex).map(e => `<span class="chip${e[1] <= fm.lv ? ' on' : ' dim'}">${
        G.Icons.html('move:' + e[0], 14)} ${G.Moves.BY_ID[e[0]].name} <small>Nv. ${e[1]}</small></span>`).join('')}</div>`;

    el.querySelectorAll('[data-pick]').forEach(btn => {
      btn.onclick = () => {
        const d = +btn.dataset.pick;
        if (!F.usable(G.DB.save, d)) return;
        G.DB.save.partner = d;
        G.DB.save.partnerShiny = false;
        G.DB.commit();
        G.Audio.sfx('confirm');
        G.UI.toast(G.DEX_BY[d].name + ' es ahora tu compañero');
        openUpgrades();
      };
    });
    el.querySelectorAll('[data-unlock]').forEach(btn => {
      btn.onclick = () => {
        const d = +btn.dataset.unlock;
        if (!F.unlock(G.DB.save, d)) { G.Audio.sfx('error'); return; }
        G.DB.commit(true);
        G.Audio.sfx('legend');
        G.UI.toast(`¡${G.DEX_BY[d].name} desbloqueado!`);
        renderUpgrades();
      };
    });
    const st = el.querySelector('[data-star]');
    if (st) st.onclick = () => {
      if (!F.star(G.DB.save, f)) { G.Audio.sfx('error'); return; }
      G.DB.commit(true);
      G.Audio.sfx('legend');
      G.UI.toast(`Familia de ${F.famName(f)}: ${F.fam(G.DB.save, f).stars} estrellas`);
      renderUpgrades();
    };
    return el;
  }

  // ---------------- atajos: hueco fijo para cada movimiento ----------------
  // save.pbind[dex] = [movimiento del hueco 1, del 2, del 3, del 4] (o null).
  function bindPanel(dex) {
    const s = G.DB.save;
    s.pbind = s.pbind || {};
    const list = s.pbind[dex] || [null, null, null, null];
    const ids = G.Families.movesOf(dex).map(e => e[0])
      .sort((a, b) => G.Moves.BY_ID[a].name.localeCompare(G.Moves.BY_ID[b].name, 'es'));
    const el = document.createElement('div');
    el.className = 'panel bind-panel';
    el.innerHTML = `<b>Atajos de movimientos</b>
      <p class="sub" style="margin:2px 0 8px">Elige qué movimiento va siempre en cada hueco (teclas 1-4 o los iconos de abajo), para la memoria muscular. Si aún no tienes tantos movimientos, va al hueco más cercano.</p>
      <div class="bind-slots">${[0, 1, 2, 3].map(i => `<label class="bind-slot"><span>${i + 1}</span>
        <select class="field" data-slot="${i}"><option value="">Libre</option>${ids.map(id =>
          `<option value="${id}" ${list[i] === id ? 'selected' : ''}>${G.Moves.BY_ID[id].name}</option>`).join('')}</select></label>`).join('')}</div>`;
    el.querySelectorAll('select[data-slot]').forEach(sel => {
      sel.onchange = () => {
        const l = (s.pbind[dex] || [null, null, null, null]).slice(0, 4);
        while (l.length < 4) l.push(null);
        const i = +sel.dataset.slot, id = sel.value || null;
        // Un movimiento sólo puede estar en un hueco.
        for (let j = 0; j < 4; j++) if (id && l[j] === id) l[j] = null;
        l[i] = id;
        s.pbind[dex] = l;
        G.DB.commit();
        G.Audio.sfx('select');
        renderUpgrades();
      };
    });
    return el;
  }

  return { init, open, GEN_NAMES };
})();
