#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Baja una sola vez de PokeAPI las cadenas evolutivas y los movimientos que aprende
cada Pokémon del juego (los de js/data/pokedex.js) y los deja en:

    js/data/evolutions.js   G.EVO: familia, etapa, de quién evoluciona y cómo
    js/data/learnsets.js    G.LEARNSETS: movimientos del juego que aprende cada uno

    python tools/fetch_evolutions.py

Lo que baja se guarda recortado en tools/cache/pokeapi/ (no va al repositorio):
volver a ejecutarlo no toca internet salvo lo que falte. Al final imprime un
informe: familias, formas de evolucionar y cuántos movimientos del juego tiene
cada Pokémon (y qué movimientos de los juegos faltan para los que tienen pocos).

Son datos de los juegos, sin decisiones de diseño: todavía no los usa el juego.
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

API = 'https://pokeapi.co/api/v2'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tools', 'cache', 'pokeapi')
OUT_EVO = os.path.join(ROOT, 'js', 'data', 'evolutions.js')
OUT_LEARN = os.path.join(ROOT, 'js', 'data', 'learnsets.js')

# Grupos de versiones que no sirven de referencia para los movimientos por nivel
# (sistemas de movimientos distintos o listas recortadas).
SKIP_VG = {'legends-arceus', 'lets-go-pikachu-lets-go-eevee', 'colosseum', 'xd',
           'red-green-japan', 'blue-japan', 'legends-za'}


# ---------------- descarga con caché ----------------

def get(url, retries=4):
    for _ in range(retries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'pokesurvivor/1.0'})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
        except Exception:
            pass
    return None


def cached(kind, key, url, trim):
    """Lo bajado, recortado con `trim`, guardado en tools/cache/pokeapi/<kind>/<key>.json."""
    path = os.path.join(CACHE, kind, f'{key}.json')
    if os.path.exists(path):
        with io.open(path, encoding='utf-8') as f:
            return json.load(f)
    raw = get(url)
    if raw is None:
        return None
    data = trim(raw)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    return data


def id_of(url):
    return int(url.rstrip('/').split('/')[-1])


def trim_species(s):
    name_es = next((n['name'] for n in s.get('names', []) if n['language']['name'] == 'es'), s['name'])
    return {'id': s['id'], 'name': s['name'], 'es': name_es,
            'chain': id_of(s['evolution_chain']['url']) if s.get('evolution_chain') else None,
            'from': id_of(s['evolves_from_species']['url']) if s.get('evolves_from_species') else None}


def trim_pokemon(p):
    return {'id': p['id'], 'moves': [
        {'m': m['move']['name'],
         'd': [[v['level_learned_at'], v['move_learn_method']['name'], v['version_group']['name']]
               for v in m['version_group_details']]}
        for m in p['moves']]}


def trim_chain(c):
    def node(n):
        return {'sp': id_of(n['species']['url']), 'name': n['species']['name'],
                'det': [{k: (v['name'] if isinstance(v, dict) and 'name' in v else v)
                         for k, v in d.items() if v not in (None, False, '')}
                        for d in n.get('evolution_details', [])],
                'to': [node(t) for t in n.get('evolves_to', [])]}
    return {'id': c['id'], 'chain': node(c['chain'])}


def trim_vg(v):
    return {'name': v['name'], 'order': v['order'], 'gen': id_of(v['generation']['url'])}


def trim_move(m):
    name_es = next((n['name'] for n in m.get('names', []) if n['language']['name'] == 'es'), m['name'])
    return {'name': m['name'], 'es': name_es, 'type': m['type']['name'],
            'class': m['damage_class']['name'] if m.get('damage_class') else None,
            'power': m.get('power'), 'gen': id_of(m['generation']['url'])}


# ---------------- lo que ya tiene el juego ----------------

def game_dex():
    """{dex: {name, gen, types, rarity}} de js/data/pokedex.js."""
    out = {}
    with io.open(os.path.join(ROOT, 'js', 'data', 'pokedex.js'), encoding='utf-8') as f:
        for line in f:
            line = line.strip().rstrip(',')
            if line.startswith('{"dex"'):
                p = json.loads(line)
                out[p['dex']] = p
    return out


def game_moves():
    """{id: {type, kind}} de los movimientos del juego (js/data/moves.js), en su orden,
    y {id: nombre al que evoluciona} (su tabla EVO)."""
    with io.open(os.path.join(ROOT, 'js', 'data', 'moves.js'), encoding='utf-8') as f:
        src = f.read()
    moves = {m: {'name': n, 'type': t, 'kind': k} for m, n, t, k in
             re.findall(r"\{ id: '([a-z0-9-]+)', name: '([^']+)', type: '([a-z]+)', kind: '([a-z]+)'", src)}
    evo = dict(re.findall(r"'([a-z0-9-]+)': \['([^']+)', '[a-z]+'\]", src))
    return moves, evo


def norm(name):
    return re.sub(r'[^a-z0-9áéíóúüñ]', '', (name or '').lower())


def resolve(game, evo, wanted):
    """{movimiento de los juegos: movimiento del juego} para todos los que aprenden los Pokémon.
    Por el nombre en español de PokeAPI, en este orden:
      1. el del juego que se llama igual (Tormenta Floral, aunque su id sea leaf-storm);
      2. el del juego que EVOLUCIONA a él (Derribo es Placaje evolucionado: take-down -> tackle);
      3. el del juego con el mismo id (Foco Resplandor / Cañón Resplandor: mismo movimiento).
    Devuelve también la información de cada movimiento (nombre, tipo, clase, poder)."""
    by_name = {norm(i['name']): m for m, i in game.items()}
    by_evo = {norm(n): base for base, n in evo.items()}
    todo = sorted(wanted)
    with ThreadPoolExecutor(max_workers=8) as ex:
        info = dict(zip(todo, ex.map(lambda m: cached('move', m, f'{API}/move/{m}', trim_move), todo)))
    out = {}
    for m in todo:
        es = norm(info[m]['es']) if info.get(m) else None
        if es in by_name:
            out[m] = by_name[es]
        elif es in by_evo:
            out[m] = by_evo[es]
        elif m in game:
            out[m] = m
    return out, info


# ---------------- evoluciones ----------------

def how_of(det):
    """Cómo se evoluciona, en corto: {'lv': 16} · {'item': 'water-stone'} · {'trade': ...}..."""
    if not det:
        return {'other': True}
    # si hay varias formas, la que va por nivel primero (es la que se puede usar en el juego)
    d = next((x for x in det if x.get('min_level')), det[0])
    out = {}
    trig = d.get('trigger')
    if d.get('min_level'):
        out['lv'] = d['min_level']
    elif trig == 'use-item':
        out['item'] = d.get('item')
    elif trig == 'trade':
        out['trade'] = d.get('held_item') or d.get('trade_species') or True
    elif d.get('min_happiness') or d.get('min_affection'):
        out['friend'] = True
    elif d.get('known_move') or d.get('known_move_type'):
        out['move'] = d.get('known_move') or d.get('known_move_type')
    elif d.get('location'):
        out['place'] = d['location']
    else:
        out['other'] = trig or True
    for k in ('time_of_day', 'held_item', 'gender', 'needs_overworld_rain', 'turn_upside_down'):
        if k in d and k not in out and not (k == 'held_item' and 'trade' in out):
            out[k] = d[k]
    return out


def estimate_levels(evo, dex):
    """Nivel para las evoluciones que en los juegos no son por nivel (objeto, intercambio,
    amistad...), a partir de los stats base de la forma evolucionada: la mediana del nivel de
    las evoluciones por nivel con un total de stats base parecido (±25; si hay menos de 5,
    la recta que mejor se ajusta). Nunca por debajo del nivel de la etapa anterior + 1.
    Lo deja en how['est']. Devuelve el ajuste (para el informe)."""
    pairs = [(dex[int(d)]['bst'], e['how']['lv']) for d, e in evo.items() if e.get('how', {}).get('lv')]
    n = len(pairs)
    mx = sum(b for b, _ in pairs) / n
    my = sum(l for _, l in pairs) / n
    sxx = sum((b - mx) ** 2 for b, _ in pairs)
    sxy = sum((b - mx) * (l - my) for b, l in pairs)
    syy = sum((l - my) ** 2 for _, l in pairs)
    b1 = sxy / sxx
    b0 = my - b1 * mx

    def est(bst):
        near = sorted(l for b, l in pairs if abs(b - bst) <= 25)
        if len(near) >= 5:
            k = len(near)
            return round(near[k // 2] if k % 2 else (near[k // 2 - 1] + near[k // 2]) / 2)
        return round(b0 + b1 * bst)

    def level_of(d):
        h = evo[str(d)].get('how') or {}
        return h.get('lv') or h.get('est') or 0

    # por etapas, para que la anterior ya tenga su nivel
    for e_d in sorted(evo, key=lambda d: evo[d]['s']):
        e = evo[e_d]
        h = e.get('how')
        if not h or h.get('lv'):
            continue
        prev = level_of(e['from']) if str(e.get('from')) in evo else 0
        h['est'] = max(est(dex[int(e_d)]['bst']), prev + 1)
    return {'n': n, 'r': sxy / (sxx * syy) ** 0.5, 'b0': b0, 'b1': b1}


def walk(node, fam, stage, frm, out):
    out[node['sp']] = {'f': fam, 's': stage, 'from': frm, 'how': how_of(node['det']) if frm else None,
                       'name': node['name']}
    for t in node['to']:
        walk(t, fam, stage + 1, node['sp'], out)


# ---------------- movimientos ----------------

MIN_MOVES = 4          # regla A: hasta cuántos se completa con MT / tutor / huevo
MIN_DAMAGE = 2         # ... y cuántos de ellos tienen que hacer daño (no potenciadores)


def learnset(pk, vg_order, game, alias, types):
    """Movimientos del juego que aprende:
      lv   por nivel en el último juego principal con datos por nivel (nivel 0 = al evolucionar)
      old  por nivel en juegos anteriores y en el de referencia ya no (Golpe Kárate...), con el
           nivel del juego más reciente que lo tenía
      tm / egg  por MT o tutor / sólo huevo, en cualquier juego
      fill regla A: los de tm (y si no, egg) con los que se completa hasta MIN_MOVES, con al
           menos MIN_DAMAGE que hagan daño: primero los de su tipo, luego otros, potenciadores al final
    Cada movimiento de los juegos cuenta como su equivalente del juego (`alias`, ver resolve):
    si es otro id se anota de dónde viene: [movimiento del juego, nivel, movimiento de los juegos].
    Devuelve también los movimientos por nivel que el juego no cubre ('missing')."""
    by_vg = defaultdict(dict)                  # vg -> move -> nivel más bajo
    other = defaultdict(set)                   # método -> moves
    for m in pk['moves']:
        for lvl, meth, vg in m['d']:
            if meth == 'level-up' and vg not in SKIP_VG and vg in vg_order:
                cur = by_vg[vg].get(m['m'])
                by_vg[vg][m['m']] = lvl if cur is None else min(cur, lvl)
            elif meth in ('machine', 'tutor'):
                other['tm'].add(m['m'])
            elif meth == 'egg':
                other['egg'].add(m['m'])
    if not by_vg:
        return None
    order = sorted(by_vg, key=lambda v: vg_order[v], reverse=True)

    def g(m):
        return alias.get(m)

    def entry(gm, lvl, m):
        return [gm, lvl] if gm == m else [gm, lvl, m]

    have = set()
    lv, evo_moves, old, missing = [], [], [], set()
    for m, l in sorted(by_vg[order[0]].items(), key=lambda kv: (kv[1], kv[0])):
        gm = g(m)
        if not gm:
            missing.add(m)
        elif gm not in have:
            have.add(gm)
            (evo_moves.append(gm) if l == 0 else lv.append(entry(gm, l, m)))
    for v in order[1:]:                        # del más reciente al más antiguo
        for m, l in sorted(by_vg[v].items(), key=lambda kv: (kv[1], kv[0])):
            gm = g(m)
            if not gm:
                missing.add(m)
            elif gm not in have:
                have.add(gm)
                old.append(entry(gm, l, m))
    old.sort(key=lambda e: (e[1], e[0]))
    tm = sorted({g(m) for m in other['tm'] if g(m)} - have)
    egg = sorted({g(m) for m in other['egg'] if g(m)} - have - set(tm))

    # regla A: completar con MT / tutor (y huevo) hasta MIN_MOVES, con MIN_DAMAGE de daño
    def dmg(m):
        return game[m]['kind'] != 'buff'
    def rank(m):
        return (0 if not dmg(m) else 1) * 10 + (1 if game[m]['type'] in types else 0)
    fill = []
    for pool in (tm, egg):
        for m in sorted(pool, key=lambda m: (-rank(m), m)):
            n = len(have) + len(fill)
            d = sum(1 for x in list(have) + fill if dmg(x))
            if n >= MIN_MOVES and d >= MIN_DAMAGE:
                break
            if n >= MIN_MOVES and not dmg(m):
                continue
            fill.append(m)
    return {'vg': order[0], 'lv': lv, 'evo': evo_moves, 'old': old, 'tm': tm, 'egg': egg, 'fill': fill,
            'missing': sorted(missing)}


# ---------------- salida ----------------

def write_js(path, header, var, obj):
    lines = ['/* ============ ' + os.path.basename(path) + ' — GENERADO, no editar a mano ============']
    lines += [' * ' + h if h else ' *' for h in header] + [' */', var + ' = {']
    keys = sorted(obj, key=int)
    for i, k in enumerate(keys):
        lines.append(f'  {k}: ' + json.dumps(obj[k], ensure_ascii=False, separators=(',', ':'))
                     + (',' if i < len(keys) - 1 else ''))
    lines += ['};', '']
    with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))


def main():
    dex = game_dex()
    game, move_evo = game_moves()
    print(f'{len(dex)} Pokémon en el juego, {len(game)} movimientos del juego.')

    # orden de los grupos de versiones (para elegir el más reciente)
    vgl = get(f'{API}/version-group?limit=200') or {'results': []}
    with ThreadPoolExecutor(max_workers=8) as ex:
        vgs = [v for v in ex.map(lambda r: cached('version-group', r['name'], r['url'], trim_vg), vgl['results']) if v]
    vg_order = {v['name']: v['order'] for v in vgs}

    print('Bajando especies y movimientos (con caché)...')
    ids = sorted(dex)
    with ThreadPoolExecutor(max_workers=10) as ex:
        species = dict(zip(ids, ex.map(lambda d: cached('species', d, f'{API}/pokemon-species/{d}', trim_species), ids)))
        pokes = dict(zip(ids, ex.map(lambda d: cached('pokemon', d, f'{API}/pokemon/{d}', trim_pokemon), ids)))
        chains_ids = sorted({s['chain'] for s in species.values() if s and s['chain']})
        chains = dict(zip(chains_ids, ex.map(lambda c: cached('chain', c, f'{API}/evolution-chain/{c}', trim_chain), chains_ids)))
    bad = [d for d in ids if not species[d] or not pokes[d]]
    if bad:
        print(f'  ! sin datos: {bad} (vuelve a ejecutarlo)')

    # --- evoluciones ---
    allnodes = {}
    for c in chains.values():
        if c:
            walk(c['chain'], c['id'], 0, None, allnodes)
    evo = {}
    for d in ids:
        n = allnodes.get(d)
        if not n:
            continue
        e = {'f': n['f'], 's': n['s']}
        if n['from']:
            e['from'] = n['from']
            e['how'] = n['how']
            if n['from'] not in dex:
                e['fromMissing'] = True       # la forma anterior no está en el juego (sin sprite)
        evo[str(d)] = e
    fit = estimate_levels(evo, dex)
    write_js(OUT_EVO, [
        'Lo produce tools/fetch_evolutions.py con las cadenas evolutivas de PokeAPI.',
        'Clave: número de la Pokédex (sólo los Pokémon del juego).',
        '  f     familia (id de la cadena evolutiva de PokeAPI)',
        '  s     etapa: 0 = forma inicial, 1 = primera evolución, 2 = segunda...',
        '  from  de quién evoluciona (fromMissing: esa forma no está en el juego)',
        '  how   cómo: lv (nivel) · item (objeto) · trade (intercambio) · friend (amistad) ·',
        '        move (sabiendo un movimiento) · place (en un sitio) · other; y condiciones',
        '        extra como time_of_day o held_item.',
        '        est: si en los juegos no es por nivel, el nivel que le toca en este juego según',
        '        sus stats base (mediana de las evoluciones por nivel con un total parecido, ±25;',
        '        nunca por debajo de la etapa anterior). Todavía no lo usa el juego.',
    ], 'G.EVO', evo)

    # --- movimientos ---
    wanted = {m['m'] for d in ids if pokes[d] for m in pokes[d]['moves']}
    alias, minfo = resolve(game, move_evo, wanted)
    print(f'{len(alias)} movimientos de los juegos tienen equivalente en el juego '
          f'({sum(1 for m, g in alias.items() if g != m)} con otro id: evoluciones o nombres cambiados)')
    learn = {}
    missing_by = {}
    for d in ids:
        if not pokes[d]:
            continue
        ls = learnset(pokes[d], vg_order, game, alias, dex[d]['types'])
        if not ls:
            continue
        missing_by[d] = ls.pop('missing')
        learn[str(d)] = {k: v for k, v in ls.items() if v}
    write_js(OUT_LEARN, [
        'Lo produce tools/fetch_evolutions.py con los movimientos de PokeAPI.',
        'Sólo los movimientos que ya existen en el juego (js/data/moves.js).',
        '  vg   juego de referencia: el más reciente con movimientos por nivel',
        '  lv   [movimiento, nivel] por nivel en ese juego (1 = lo sabe desde el principio);',
        '       con un 3.º elemento si en los juegos es otro movimiento que aquí es su evolución',
        '       (["tackle", 15, "take-down"]: aprende Derribo, que aquí es Placaje evolucionado)',
        '  evo  los aprende al evolucionar a esta forma (nivel 0 en los juegos)',
        '  old  [movimiento, nivel] que aprendía por nivel en juegos anteriores y en el de',
        '       referencia ya no (p. ej. Golpe Kárate, que se quitó en la 8.ª generación)',
        '  tm   por MT o tutor en cualquier juego · egg  sólo como movimiento huevo',
        '  fill regla A: los de tm / egg con los que se completa hasta 4 movimientos (2 de daño)',
        'Todavía no lo usa el juego.',
    ], 'G.LEARNSETS', learn)
    print(f'\nEscritos {len(evo)} Pokémon en js/data/evolutions.js y {len(learn)} en js/data/learnsets.js')

    report(dex, evo, learn, missing_by, game, fit, minfo, alias)


def report(dex, evo, learn, missing_by, game, fit, minfo, alias):
    print('\n================ INFORME ================')
    # familias
    fam = defaultdict(list)
    for d, e in evo.items():
        fam[e['f']].append(int(d))
    sizes = Counter(len(v) for v in fam.values())
    branched = sum(1 for v in fam.values() if len({evo[str(d)].get('from') for d in v if evo[str(d)].get('from')}) < sum(1 for d in v if evo[str(d)].get('from')))
    multi_gen = sum(1 for v in fam.values() if len({dex[d]['gen'] for d in v}) > 1)
    print(f'Familias: {len(fam)} · por número de Pokémon del juego: '
          + ', '.join(f'{k}: {sizes[k]}' for k in sorted(sizes)))
    print(f'  con ramas (varias evoluciones de la misma forma): {branched} · repartidas en varias generaciones: {multi_gen}')
    print(f'  Pokémon que evolucionan de una forma que no está en el juego: {sum(1 for e in evo.values() if e.get("fromMissing"))}')
    # cómo se evoluciona
    hows = Counter()
    lvls = []
    for e in evo.values():
        h = e.get('how')
        if not h:
            continue
        k = next(iter(h))
        hows[k] += 1
        if k == 'lv':
            lvls.append(h['lv'])
    print('Cómo evolucionan las ' + str(sum(hows.values())) + ' evoluciones: '
          + ', '.join(f'{k} {v}' for k, v in hows.most_common()))
    print(f'  por nivel: nivel ≈ {fit["b0"]:.1f} + {fit["b1"]:.3f} × stats base (r = {fit["r"]:.2f}, {fit["n"]} evoluciones)')
    ests = [e['how']['est'] for e in evo.values() if e.get('how', {}).get('est')]
    if ests:
        b = Counter(min(4, (l - 1) // 15) for l in ests)
        print(f'  nivel estimado de las {len(ests)} que no son por nivel: ' + ' · '.join(
            f'{lab}: {b[i]}' for i, lab in enumerate(['1-15', '16-30', '31-45', '46-60', '61+'])))
    if lvls:
        b = Counter(min(4, (l - 1) // 15) for l in lvls)
        print('  por nivel: ' + ' · '.join(f'{lab}: {b[i]}' for i, lab in
                                            enumerate(['1-15', '16-30', '31-45', '46-60', '61+'])))
        print(f'  nivel más alto: {max(lvls)}')
    # cobertura de movimientos
    def dist(counts):
        c = Counter(min(5, n) for n in counts)
        return ' · '.join(f'{lab}: {c[i]}' for i, lab in enumerate(['0', '1', '2', '3', '4', '5+']))

    def count(l, keys, direct_only=False):
        n = 0
        for k in keys:
            for e in l.get(k, []):
                if isinstance(e, list):
                    n += 0 if (direct_only and len(e) > 2) else 1
                else:
                    n += 1
        return n
    steps = [
        ('por nivel en el juego de referencia', lambda l: count(l, ['lv', 'evo'], True)),
        ('+ por nivel en juegos anteriores', lambda l: count(l, ['lv', 'evo', 'old'], True)),
        ('+ los que aquí son una evolución', lambda l: count(l, ['lv', 'evo', 'old'])),
        ('+ regla A (MT / tutor / huevo)', lambda l: count(l, ['lv', 'evo', 'old', 'fill'])),
    ]
    print(f'\nMovimientos del juego que aprende cada Pokémon ({len(learn)} con datos) · ≤2 = pocos:')
    for lab, f in steps:
        v = [f(l) for l in learn.values()]
        print(f'  {lab:38s} {dist(v)}   (≤2: {sum(1 for x in v if x <= 2)})')
    base = {int(d): count(l, ['lv', 'evo', 'old']) for d, l in learn.items()}
    thin = sorted((d for d in base if base[d] <= 2), key=lambda d: (base[d], d))
    print(f'  con 2 o menos por nivel (sin regla A): {len(thin)}; ejemplos: '
          + ', '.join(f'{dex[d]["name"]}({base[d]})' for d in thin[:20]))
    vgs = Counter(l['vg'] for l in learn.values())
    print('  juego de referencia: ' + ', '.join(f'{k} {v}' for k, v in vgs.most_common()))
    print(f'  equivalencias por nombre o evolución: ' + ', '.join(f'{m}->{g}' for m, g in sorted(alias.items()) if g != m and m in game))

    # movimientos de ataque de los juegos que faltan, por cuántos de los que tienen menos de 4 por nivel
    need = Counter()
    for d in base:
        if base[d] < 4:
            for m in missing_by.get(d, []):
                need[m] += 1
    top = [m for m, _ in need.most_common(200) if (minfo.get(m) or {}).get('class') in ('physical', 'special')
           and (minfo.get(m) or {}).get('power')][:25]
    print('\nAtaques de los juegos que el juego no tiene, por cuántos de los que tienen menos de 4 por nivel los aprenden:')
    for m in top:
        i = minfo.get(m) or {}
        print(f'  {need[m]:4d}  {m:18s} {i.get("es", ""):22s} {i.get("type", ""):9s} {i.get("class") or "":9s} '
              f'poder {i.get("power") or "-"}')


if __name__ == '__main__':
    sys.exit(main())
