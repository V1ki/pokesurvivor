class_name Phase3bTests
extends RefCounted
## Phase 3b (interactables, events, rifts, bonds) checks, called from run_tests.gd with
## `Phase3bTests.run(self)` (or alone: res://tests/run_p3b_tests.gd). Reference values come from
## data/test_vectors_p3b.json, computed by the unchanged world.js / rift.js / events.js /
## player.js in tools/export_godot.js (exportPhase3b): interactable placement, the 18 arena
## themes (terrain + props), rift chance escalation, legendary choice + arena + legendary def and
## the event / thief / lost-Pokémon schedule replayed with the same Math.random stream (k / 2^32),
## bond options + fusion. The runtime checks drive a headless Sim with the spec numbers (§7.8-7.11).

static var V: Dictionary = {}

## The JS stubs say "there is always room" (World.isFree): the replays use the same answer.
class FreeWorld extends WorldMap:
	func is_free(_x: float, _y: float, _r := 12.0, _allow_liquid := false) -> bool:
		return true

static func run(t: Object) -> void:
	V = Data._json("test_vectors_p3b.json") if FileAccess.file_exists("res://data/test_vectors_p3b.json") else {}
	if V.is_empty():
		t.check("test_vectors_p3b.json present", false, "run: node tools/export_godot.js")
		return
	_consts(t)
	_specials(t)
	_arenas(t)
	_rift_chance(t)
	_legends(t)
	_events(t)
	_horde_types(t)
	_bonds(t)
	_rt_interact(t)
	_rt_events(t)
	_rt_rift(t)
	_rt_bond(t)

# ---------------- helpers ----------------

static func bits(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.hex_encode()

## A double from its little-endian IEEE bits (exact).
static func from_bits(h: String) -> float:
	return h.hex_decode().decode_double(0)

static func rel(a: float, b: float, eps := 1e-12) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

## The JS Math.random stream: uint32 values -> k / 2^32 (exact doubles).
static func stream(ks: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in ks:
		out.append(float(k) / 4294967296.0)
	return out

static func new_sim(seed := 1, free := false) -> Sim:
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, seed)
	sim.enemies.clear()
	if free:
		sim.world = FreeWorld.new()
		sim.world.reset(seed)
	return sim

## One frame of the game loop: level-up cards / item swaps are answered like the bot does.
static func frame(sim: Sim, dt := 1.0 / 60.0) -> void:
	if sim.state == "levelup" or (sim.state == "choice" and sim.bond_opt.is_empty()):
		Bot.pick(sim)
	sim.update(dt)

static func ids(g: Array) -> Array:
	return g.map(func(m): return str(m["id"]))

# ---------------- data ----------------

static func _consts(t: Object) -> void:
	print("-- Phase 3b: interactables data --")
	var c: Dictionary = V["consts"]
	t.check("CHEST_TIME = %.1f (interact.js)" % Interact.CHEST_TIME, rel(Interact.CHEST_TIME, float(c["chest_time"])))
	t.check("altar powers = interact.js POWERS (id, name, desc, colour)", JSON.stringify(Interact.POWERS) == JSON.stringify(c["powers"]),
		JSON.stringify(Interact.POWERS))

## Interactables placed by the world (altar / spring / bigchest / trap, kind, radius, flags).
static func _specials(t: Object) -> void:
	print("-- Phase 3b: interactable placement (world.js placeProps) --")
	var w := WorldMap.new()
	for sp in V["specials"]:
		w.reset(int(sp["seed"]))
		w.set_biome(0, true)
		var mine: Array = []
		var counts := {}
		for cy in range(int(sp["c0"]), int(sp["c1"])):
			for cx in range(int(sp["c0"]), int(sp["c1"])):
				for p: WorldProp in w.chunk_data(cx, cy).props:
					if WorldMap.SPECIAL.has(p.type):
						mine.append("%d,%d,%s,%d,%d,%s,%s" % [p.tx, p.ty, p.type, p.kind, int(p.r), p.solid, p.flat])
						counts[p.type] = int(counts.get(p.type, 0)) + 1
		var js: Array = (sp["list"] as Array).map(func(e): return "%d,%d,%s,%d,%d,%s,%s" % [int(e[0]), int(e[1]), e[2], int(e[3]), int(e[4]), e[5], e[6]])
		mine.sort()
		js.sort()
		var miss := js.filter(func(k): return not mine.has(k))
		var extra := mine.filter(func(k): return not js.has(k))
		t.check("seed %d: %d interactables in 12x12 chunks identical %s" % [int(sp["seed"]), js.size(), str(counts)],
			miss.is_empty() and extra.is_empty(), "missing %s extra %s" % [str(miss.slice(0, 4)), str(extra.slice(0, 4))])

## The 18 rift arenas: wall ring, corridor, pillars, pools, props (and the chunk purge).
static func _arenas(t: Object) -> void:
	print("-- Phase 3b: rift arenas (world.js setArena + terrainRaw + placeProps) --")
	var w := WorldMap.new()
	var ok_all := 0
	for a in V["arenas"]:
		w.reset(int(a["seed"]))
		w.set_biome(0, true)
		var R := int(a["R"])
		var tx := int(a["tx"])
		var ty := int(a["ty"])
		if a["pre"]:
			for y in range(ty - R, ty + R + 1, 4):
				for x in range(tx - R, tx + R + 1, 4):
					w.terrain_at(x, y)
		w.set_arena({"tx": tx, "ty": ty, "r": int(a["r"]), "type": a["type"]})
		var bad_rows := 0
		var first_bad := ""
		for j in (a["rows"] as Array).size():
			var s := ""
			for x in range(tx - R, tx + R + 1):
				s += "fwl"[w.terrain_at(x, ty - R + j)]
			if s != a["rows"][j]:
				bad_rows += 1
				if first_bad == "":
					first_bad = "row %d: %s vs %s" % [j, s, a["rows"][j]]
		var mine: Array = []
		for cy in range(floori((ty - R) / 16.0), floori((ty + R) / 16.0) + 1):
			for cx in range(floori((tx - R) / 16.0), floori((tx + R) / 16.0) + 1):
				for p: WorldProp in w.chunk_data(cx, cy).props:
					if absi(p.tx - tx) <= R and absi(p.ty - ty) <= R:
						mine.append("%d,%d,%s" % [p.tx, p.ty, p.type])
		var js: Array = (a["props"] as Array).map(func(e): return "%d,%d,%s" % [int(e[0]), int(e[1]), e[2]])
		mine.sort()
		js.sort()
		var ok: bool = bad_rows == 0 and mine == js and WorldMap.arena_biome(a["type"]) == int(a["biome"])
		if ok:
			ok_all += 1
		t.check("arena %-8s%s: 41x41 tiles + %d props + biome %d identical" % [a["type"], " (purged)" if a["pre"] else "", js.size(), int(a["biome"])],
			ok, "%d bad rows %s; props %d vs %d" % [bad_rows, first_bad, mine.size(), js.size()])
	t.check("all 18 arena themes identical to JS", ok_all == 18, "%d/18" % ok_all)

# ---------------- rifts ----------------

## Chance escalation: every 30 s after 75 s, p = 0.2 * (1 + misses), placement 380-560 wu.
static func _rift_chance(t: Object) -> void:
	print("-- Phase 3b: rift chance escalation (rift.js update) --")
	var rc: Dictionary = V["rift_chance"]
	var sim := new_sim(1, true)
	var rift := sim.rift
	rift.reset()
	rift.rng.feed(stream(rc["seq"]))
	var pl := sim.player
	pl.x = 0.0
	pl.y = 0.0
	var opens: Array = []
	var had := false
	var dt: float = rc["dt"]
	for f in range(1, int(rc["frames"]) + 1):
		sim.time = f * dt
		rift.update(dt, pl, f * dt)
		if not rift.portal.is_empty() and not had:
			opens.append([f, float(rift.portal["x"]), float(rift.portal["y"]), rift.rng.i])
		had = not rift.portal.is_empty()
	var js: Array = rc["opens"]
	var same := opens.size() == js.size()
	var pos_ok := same
	for i in mini(opens.size(), js.size()):
		if int(opens[i][0]) != int(js[i][0]) or int(opens[i][3]) != int(js[i][3]):
			same = false
		if not (rel(opens[i][1], from_bits(js[i][1])) and rel(opens[i][2], from_bits(js[i][2]))):
			pos_ok = false
	t.check("%d rifts in %d s open at the same frames with the same draws (escalating 20/40/60/80/100 %%)" % [js.size(), int(int(rc["frames"]) * dt)],
		same, "%s vs %s" % [str(opens.slice(0, 3)), str(js.slice(0, 3))])
	t.check("rift positions identical (380-560 wu, y x0.85)", pos_ok)
	t.check("whole stream consumed (%d draws)" % (rc["seq"] as Array).size(), rift.rng.left() == 0, "%d left" % rift.rng.left())
	# the escalation itself: misses never exceed 4 (the 5th check is a sure hit)
	var gaps: Array = []
	for i in range(1, js.size()):
		gaps.append((int(js[i][0]) - int(js[i - 1][0])) * dt)
	var max_gap: float = gaps.max() if not gaps.is_empty() else 0.0
	t.check("never more than 4 misses: max gap between rifts %.0f s <= 45 + 5 x 30" % max_gap, max_gap <= 45.0 + 150.0 + 0.001)

## Legendary choice (weighted by beaten), arena cfg, the legendary's def and spawn point.
static func _legends(t: Object) -> void:
	print("-- Phase 3b: legendary choice + arena cfg + legendary def (rift.js start/spawnLegend) --")
	for c in V["legends"]:
		var sim := new_sim(3, true)
		sim.time = float(c["t"])
		sim.rift.rng.feed(stream(c["seq"]))
		var beaten: Dictionary = c["beaten"]
		sim.rift.start(str(c["type"]), beaten)
		var a := sim.rift.arena
		var ja: Dictionary = c["arena"]
		var bad: Array = []
		for k in ["tx", "ty", "r", "dex"]:
			if int(a.get(k, -1)) != int(ja[k]):
				bad.append("%s %s!=%s" % [k, str(a.get(k)), str(ja[k])])
		if bool(a.get("shiny", false)) != bool(ja["shiny"]) or str(a.get("type", "")) != str(ja["type"]):
			bad.append("shiny/type %s/%s" % [str(a.get("shiny")), str(a.get("type"))])
		if not (rel(float(a.get("x", 0)), float(ja["x"])) and rel(float(a.get("y", 0)), float(ja["y"]))):
			bad.append("centre")
		var e := sim.enemies.get_enemy(int(a.get("boss_id", 0)))
		if e == null:
			bad.append("no legendary")
		else:
			var jd: Dictionary = c["def"]
			for k in jd:
				if jd[k] is String:
					if str(e.def.get(k)) != str(jd[k]):
						bad.append("def.%s" % k)
				elif not rel(float(e.def.get(k, NAN)), float(jd[k])):
					bad.append("def.%s %s!=%s" % [k, str(e.def.get(k)), str(jd[k])])
			if not (rel(e.x, float(c["ex"])) and rel(e.y, float(c["ey"]))):
				bad.append("spawn point")
			if e.shiny != bool(c["shiny"]) or not e.boss or not e.legend or e.flying:
				bad.append("flags boss %s legend %s flying %s shiny %s" % [e.boss, e.legend, e.flying, e.shiny])
		if sim.rift.rng.left() != 0:
			bad.append("%d draws left" % sim.rift.rng.left())
		t.check("rift %-8s t=%-5d -> %s (dex %d, %s arena, hp %d, %s)%s" % [c["type"] if c["type"] != "" else "(any)", int(c["t"]),
			Data.dex_by[int(ja["dex"])]["name"], int(ja["dex"]), ja["type"], int(c["def"]["hp"]), c["def"]["behavior"], " SHINY" if ja["shiny"] else ""],
			bad.is_empty(), ", ".join(bad))

# ---------------- events ----------------

## 3000 s of events / thieves / lost Pokémon replayed with the JS draws.
static func _events(t: Object) -> void:
	print("-- Phase 3b: event schedule (events.js update/start/spawnThief/spawnLost) --")
	for ev in V["events"]:
		var sim := new_sim(5, true)
		var E := sim.events
		E.rng.feed(stream(ev["seq"]))
		E.reset()
		var pl := sim.player
		pl.x = 0.0
		pl.y = 0.0
		var recs: Array = []
		var prev := ""
		var n_thief := 0
		var dt: float = ev["dt"]
		for f in range(1, int(ev["frames"]) + 1):
			sim.time = f * dt
			E.update(dt, pl, f * dt)
			var cur := E.current()
			if cur != prev:
				if cur == "":
					recs.append([f, "end", E.rng.i])
				elif cur == "horde":
					recs.append([f, cur, E.rng.i, E.bag().map(func(d): return int(d["dex"]))])
				elif cur == "lost":
					recs.append([f, cur, E.rng.i, [E.lost.x, E.lost.y, E.lost.tx, E.lost.ty]])
				else:
					recs.append([f, cur, E.rng.i])
				prev = cur
			var thieves := sim.enemies.list.filter(func(e: Enemy): return e.behavior == "thief")
			while thieves.size() > n_thief:
				var e: Enemy = thieves[n_thief]
				n_thief += 1
				recs.append([f, "thief", E.rng.i, e.dex, int(e.def["hp"]), e.x, e.y])
		var js: Array = ev["recs"]
		var bad: Array = []
		if recs.size() != js.size():
			bad.append("%d records vs %d" % [recs.size(), js.size()])
		for i in mini(recs.size(), js.size()):
			var a: Array = recs[i]
			var b: Array = js[i]
			var ok: bool = int(a[0]) == int(b[0]) and str(a[1]) == str(b[1]) and int(a[2]) == int(b[2])
			if ok and a[1] == "horde":
				ok = JSON.stringify(a[3]) == JSON.stringify((b[3] as Array).map(func(v): return int(v)))
			elif ok and a[1] == "lost":
				for k in 4:
					ok = ok and rel(a[3][k], from_bits(b[3][k]))
			elif ok and a[1] == "thief":
				ok = int(a[3]) == int(b[3]) and int(a[4]) == int(b[4]) and rel(a[5], from_bits(b[5])) and rel(a[6], from_bits(b[6]))
			if not ok:
				bad.append("#%d %s vs %s" % [i, str(a), str(b)])
				break
		var kinds := {}
		for r in js:
			kinds[r[1]] = int(kinds.get(r[1], 0)) + 1
		t.check("seed %d: %d s of events identical (frames, kinds, draws, horde casts, lost spots, thieves) %s" % [int(ev["seed"]),
			int(int(ev["frames"]) * dt), str(kinds)], bad.is_empty(), ", ".join(bad))
		t.check("seed %d: whole stream consumed (%d draws)" % [int(ev["seed"]), (ev["seq"] as Array).size()], E.rng.left() == 0, "%d left" % E.rng.left())

static func _horde_types(t: Object) -> void:
	var bad: Array = []
	for h in V["horde_types"]:
		if JSON.stringify(EnemyDefs.horde_types(float(h["t"]))) != JSON.stringify(h["types"]):
			bad.append(str(h["t"]))
	t.check("horde types (>= 3 non-support candidates of the tier) at 6 times", bad.is_empty(), ", ".join(bad))

# ---------------- bonds ----------------

static func _bonds(t: Object) -> void:
	print("-- Phase 3b: bond options + fusion (player.js bondOptions/fuse) --")
	var sim := new_sim(1)
	var IDS := ["ember", "water-gun", "thunder-shock", "vine-whip", "tackle", "gust"]
	for b in V["bonds"]:
		var c: Dictionary = b["case"]
		var p := Player.new(Data.dex_by[4])
		sim.player = p
		p.moves = []
		for i in int(c["n"]):
			p.moves.append(Moves.instance(IDS[i], 1))
		p.slots = []
		for g in c["slots"]:
			p.slots.append((g as Array).map(func(i): return p.moves[int(i)]))
		p.active = int(c["active"])
		p.bonds = 2
		p.item = str(c.get("item", ""))
		p.bind = {}
		for k in c.get("bind", {}):
			p.bind[k] = int(c["bind"][k])
		var opt := p.bond_options()
		var jo: Variant = b["opt"]
		var ok := true
		var detail := ""
		if jo == null:
			ok = opt.is_empty()
			detail = "expected none, got %s" % str(opt.get("mode", ""))
		else:
			var mine := {"mode": opt.get("mode", ""), "group": ids(opt["group"]) if opt.get("mode", "") == "add" else null,
				"loose": ids(opt.get("loose", []))}
			ok = JSON.stringify(mine) == JSON.stringify(jo)
			detail = JSON.stringify(mine) + " vs " + JSON.stringify(jo)
			if ok and c.has("pick"):
				var picked: Array = (c["pick"] as Array).map(func(i): return p.moves[int(i)])
				var g := p.fuse(picked, opt["group"])
				var ja: Dictionary = b["after"]
				var after := {"slots": p.slots.map(func(s): return ids(s)), "active": p.active, "bonds": p.bonds, "group": ids(g)}
				ok = JSON.stringify(after["slots"]) == JSON.stringify(ja["slots"]) and int(after["active"]) == int(ja["active"]) \
					and int(after["bonds"]) == int(ja["bonds"]) and JSON.stringify(after["group"]) == JSON.stringify(ja["group"])
				detail = JSON.stringify(after) + " vs " + JSON.stringify(ja)
		t.check("bond %s%s%s -> %s" % [JSON.stringify(c["slots"]), (" bind " + JSON.stringify(c["bind"])) if c.has("bind") else "",
			(" " + str(c["item"])) if c.has("item") else "", "none" if jo == null else (jo["mode"] + (" + fuse" if c.has("pick") else ""))], ok, detail)

# ---------------- runtime: interactables ----------------

static func _find(sim: Sim, type: String, kind := -1) -> WorldProp:
	var best: WorldProp = null
	var bd := INF
	for p: WorldProp in sim.world.specials_near(0.0, 0.0, 3200.0):
		if p.type == type and (kind < 0 or p.kind == kind):
			var d := p.x * p.x + p.y * p.y
			if d < bd:
				bd = d
				best = p
	return best

static func _rt_interact(t: Object) -> void:
	print("-- Phase 3b runtime: altars, springs, locked chests, traps (§7.8) --")
	# power on/off for every altar kind, exact revert
	var sim := new_sim(12345)
	var pl := sim.player
	var base := [pl.atk_mul, pl.spd_mul, pl.magnet, pl.cd_mul]
	var want := [[2.0, 1.0, 1.0, 1.0], [1.0, 1.45, 1.0, 1.0], [1.0, 1.0, 4.0, 1.0], [1.0, 1.0, 1.0, 0.6]]
	var ok := true
	for k in 4:
		pl.add_power(Interact.POWERS[k], 25.0)
		var now := [pl.atk_mul, pl.spd_mul, pl.magnet, pl.cd_mul]
		for i in 4:
			ok = ok and rel(now[i], base[i] * want[k][i])
	pl.add_power(Interact.POWERS[0], 25.0)          # replaces the active power
	ok = ok and rel(pl.cd_mul, base[3]) and rel(pl.atk_mul, base[0] * 2.0)
	t.check("altar powers: Furia atk x2, Rayo spd x1.45, Imán magnet x4, Prisa cd x0.6; a new one replaces the old", ok)
	# live altar: touch -> power for 25 s, used; then reverted
	sim = new_sim(12345)
	pl = sim.player
	var alt := _find(sim, "altar")
	if alt == null:
		t.check("an altar near the start (seed 12345)", false)
	else:
		var a0 := pl.atk_mul
		var s0 := pl.spd_mul
		pl.x = alt.x
		pl.y = alt.y + pl.r + alt.r + 6.0
		sim.interact.update(1.0 / 60.0, pl)
		var pw: Dictionary = Interact.POWERS[alt.kind]
		var on: bool = alt.used and not pl.power.is_empty() and pl.power["def"]["id"] == pw["id"] and sim.spawner.announce.begins_with("¡Poder " + str(pw["name"]))
		pl.x = alt.x + 400.0
		for i in 25 * 60 - 2:
			pl.update(1.0 / 60.0)
		var still := not pl.power.is_empty()
		for i in 3:
			pl.update(1.0 / 60.0)
		t.check("altar (kind %d, %s): used at %.0f wu, banner \"%s\", lasts 25 s then reverts" % [alt.kind, pw["name"], alt.r + pl.r + 6.0, sim.spawner.announce],
			on and still and pl.power.is_empty() and rel(pl.atk_mul, a0) and rel(pl.spd_mul, s0))
	# spring: +14 % max HP / s, charge -0.09 / s, refills in 45 s
	sim = new_sim(12345)
	pl = sim.player
	var sp := _find(sim, "spring")
	if sp == null:
		t.check("a spring near the start (seed 12345)", false)
	else:
		pl.hp = pl.max_hp * 0.3
		pl.x = sp.x
		pl.y = sp.y - 8.0
		var h0 := pl.hp
		for i in 60:
			sim.interact.update(1.0 / 60.0, pl)
		var healed := (pl.hp - h0) / pl.max_hp
		var ch := sp.charge
		var want_c := 1.0
		for i in 60:
			if want_c < 1.0:
				want_c = minf(1.0, want_c + (1.0 / 60.0) / 45.0)
			want_c = maxf(0.0, want_c - (1.0 / 60.0) * 0.09)
		t.check("spring: +%.4f max HP in 1 s (14 %%/s), charge %.4f (-0.09/s, +1/45 per s refill)" % [healed, ch],
			rel(healed, 0.14, 1e-9) and rel(ch, want_c, 1e-12))
		sp.charge = 0.0
		pl.hp = pl.max_hp * 0.3
		pl.x += 100.0
		for i in 45 * 60:
			sim.interact.update(1.0 / 60.0, pl)
		t.check("spring: dry -> full again after 45 s within 720 wu (%.3f)" % sp.charge, sp.charge > 0.999)
	# locked chest: 3.5 s next to it, decays at 1.5x when you leave, loot + Progress chest
	sim = new_sim(12345)
	pl = sim.player
	var bc := _find(sim, "bigchest")
	if bc == null:
		t.check("a locked chest near the start (seed 12345)", false)
	else:
		pl.x = bc.x
		pl.y = bc.y + bc.r + pl.r + 10.0
		for i in 120:
			sim.interact.update(1.0 / 60.0, pl)
		var o2 := bc.open
		pl.x += 300.0
		for i in 60:
			sim.interact.update(1.0 / 60.0, pl)
		var decayed := bc.open
		pl.x -= 300.0
		var n0 := sim.pickups.count()
		var lvl_xp := WorldMap.level_xp()
		var steps := 0
		while not sim.world.broken.has(Vector2i(bc.tx, bc.ty)) and steps < 600:
			sim.interact.update(1.0 / 60.0, pl)
			steps += 1
		var coins := 0
		var tickets := 0
		var xp := 0.0
		for p in sim.pickups.list:
			if p.kind == "coin":
				coins += 1
			elif p.kind == "ticket":
				tickets += 1
			elif Pickups.is_xp(p):
				xp += float(p.value)
		t.check("locked chest: open %.2f s after 2 s, decays to %.2f after 1 s away (x1.5)" % [o2, decayed], rel(o2, 2.0, 1e-6) and rel(decayed, 0.5, 1e-6))
		t.check("locked chest: opens after %.2f more s (3.5 s in total); %d pickups (9 coins %d, tickets %d in 1-3, XP %.0f = one level %.0f)" % [
			steps / 60.0, sim.pickups.count() - n0, coins, tickets, xp, lvl_xp],
			absf(steps / 60.0 - 3.0) < 0.02 and coins == 9 and tickets >= 1 and tickets <= 3 and rel(xp, lvl_xp) and sim.interact.stats["chest"] == 1)
	# traps: each kind on the player (god off) and on enemies; walking enemies set them off
	for k in 3:
		sim = new_sim(12345)
		pl = sim.player
		var tr := _find(sim, "trap", k)
		if tr == null:
			t.check("a trap of kind %d near the start" % k, false)
			continue
		var e := Phase2Tests.enemy_of(19, tr.x + 30.0, tr.y - 8.0)
		e.max_hp = 5000.0
		e.hp = 5000.0
		sim.enemies.add(e)
		sim.enemies.rebuild_grid()
		pl.x = tr.x
		pl.y = tr.y - 8.0
		pl.invuln = 0.5
		var hp0 := pl.hp
		sim.interact.update(1.0 / 60.0, pl)
		var gone := sim.world.broken.has(Vector2i(tr.tx, tr.ty))
		var lost_hp := hp0 - pl.hp
		var ok_k := false
		var what := ""
		match k:
			0:
				ok_k = rel(lost_hp, maxf(1.0, pl.max_hp * 0.1 * (1.0 - pl.reduction()))) and e.poison == 5.0 and rel(5000.0 - e.hp, 14.0 + pl.level * 3.0)
				what = "poison: you -10 %% max HP (%.1f), enemy poison 5 + %d" % [lost_hp, int(5000.0 - e.hp)]
			1:
				ok_k = pl.slow_t == 3.5 and rel(e.slow, 0.65) and rel(e.slow_t, 4.5) and rel(5000.0 - e.hp, 4.0)
				what = "sticky: you slowed 3.5 s, enemy slow 0.65 for 4.5 s + 4"
			2:
				ok_k = rel(lost_hp, maxf(1.0, pl.max_hp * 0.2 * (1.0 - pl.reduction()))) and rel(5000.0 - e.hp, 90.0 + pl.level * 18.0) and e.kx != 0.0
				what = "explosive: you -20 %% max HP (%.1f), enemy %d + knockback" % [lost_hp, int(5000.0 - e.hp)]
		t.check("trap kind %d stepped on (i-frames ignored): %s" % [k, what], gone and ok_k)
	sim = new_sim(12345)
	var tr2 := _find(sim, "trap")
	var walker := Phase2Tests.enemy_of(19, tr2.x, tr2.y - 8.0)
	walker.flying = false
	sim.enemies.add(walker)
	sim.enemies.rebuild_grid()
	sim.player.x = tr2.x + 400.0
	sim.player.y = tr2.y
	sim.interact.update(1.0 / 60.0, sim.player)
	var by_enemy := sim.world.broken.has(Vector2i(tr2.tx, tr2.ty))
	sim = new_sim(12345)
	tr2 = _find(sim, "trap")
	var flyer := Phase2Tests.enemy_of(19, tr2.x, tr2.y - 8.0)
	flyer.flying = true
	sim.enemies.add(flyer)
	sim.enemies.rebuild_grid()
	sim.player.x = tr2.x + 400.0
	sim.player.y = tr2.y
	sim.interact.update(1.0 / 60.0, sim.player)
	t.check("a walking enemy sets a trap off; a flying one doesn't", by_enemy and not sim.world.broken.has(Vector2i(tr2.tx, tr2.ty)))

# ---------------- runtime: events ----------------

static func _rt_events(t: Object) -> void:
	print("-- Phase 3b runtime: hordes, golden hour, thieves, lost Pokémon (§7.9) --")
	var sim := new_sim(7)
	var pl := sim.player
	sim.time = 400.0
	sim.events.debug_start("horde")
	var defs := sim.events.bag()
	var type: String = sim.events.cur.get("type", "")
	var all_type := not defs.is_empty() and defs.all(func(d): return (Data.dex_by[int(d["dex"])]["types"] as Array).has(type))
	var spawned := sim.enemies.list.size()
	var e := sim.spawner.spawn_one(pl, sim.time)
	t.check("horde of %s: %d defs of that type, burst of %d, every spawn from the horde bag (%s)" % [type, defs.size(), spawned, e.name if e else "-"],
		all_type and defs.size() <= 4 and spawned > 0 and e != null and defs.any(func(d): return int(d["dex"]) == e.dex)
		and sim.spawner.announce == "¡Horda de tipo " + str(Data.type_name[type]) + "!")
	for i in 1799:
		sim.events.update(1.0 / 60.0, pl, sim.time)
	var running := sim.events.current() == "horde"
	sim.events.update(1.0 / 60.0, pl, sim.time)
	sim.events.update(1.0 / 60.0, pl, sim.time)
	t.check("the horde lasts 30 s", running and sim.events.current() == "")
	# golden hour
	sim = new_sim(7)
	pl = sim.player
	var a := Phase2Tests.enemy_of(19, 200.0, 0.0)
	a.xp = 10.0
	var b := Phase2Tests.enemy_of(19, 220.0, 0.0)
	b.boss = true
	b.xp = 10.0
	sim.enemies.add(a)
	sim.enemies.add(b)
	sim.events.debug_start("gold")
	var n := sim.spawner.spawn_one(pl, 100.0)
	t.check("golden hour: current enemies and new spawns golden (xp x2), bosses not", a.golden and rel(a.xp, 20.0) and not b.golden
		and rel(b.xp, 10.0) and n != null and n.golden and sim.spawner.announce == "¡Hora dorada! Doble de experiencia")
	var coins := 0
	for i in 400:
		var g := Phase2Tests.enemy_of(19, 0.0, 0.0)
		g.make_golden()
		sim.pickups.clear()
		g.die()
		for p in sim.pickups.list:
			if p.kind == "coin":
				coins += 1
	t.check("golden enemies drop a coin 35 %% of the time (%.1f %% of 400)" % (coins / 4.0), absf(coins / 400.0 - 0.35) < 0.08)
	# thieves
	sim = new_sim(7)
	pl = sim.player
	sim.time = 190.0
	sim.events.rng.feed(PackedFloat64Array([0.9]))          # not gold -> Meowth
	sim.events.spawn_thief(pl, 190.0)
	var th: Enemy = sim.enemies.list.back() if not sim.enemies.list.is_empty() else null
	var ok_th := th != null and th.dex == 52 and th.behavior == "thief" and rel(th.max_hp, U.jround(60.0 * (1.0 + 190.0 / 95.0))) and rel(th.life, 15.0) \
		and th.dmg == 0.0 and rel(th.spd, 92.0)
	var d0 := U.dist(pl.x, pl.y, th.x, th.y) if th else 0.0
	t.check("thief Meowth: hp round(60 (1 + t/95)) = %d, 92 wu/s, no damage, 15 s, %.0f wu away (230-300)" % [int(th.max_hp) if th else 0, d0],
		ok_th and d0 >= 230.0 * 0.8 - 0.01 and d0 <= 300.0 + 0.01)
	th.x = pl.x + 120.0
	th.y = pl.y
	for i in 60:
		sim.enemies.update(1.0 / 60.0, pl)
	var fled := U.dist(pl.x, pl.y, th.x, th.y) > 120.0 + 40.0
	for i in 14 * 60 + 5:
		sim.enemies.update(1.0 / 60.0, pl)
	t.check("the thief runs away (%.0f wu in 1 s) and escapes after 15 s" % (U.dist(pl.x, pl.y, th.x, th.y) - 120.0),
		fled and not sim.enemies.list.has(th) and sim.spawner.announce == "¡" + th.name + " se ha escapado!")
	sim.events.rng.feed(PackedFloat64Array([0.1]))          # gold -> Gholdengo with a x10 ticket
	sim.events.spawn_thief(pl, 300.0)
	var gh: Enemy = sim.enemies.list.back()
	var c1 := sim.pickups.count()
	gh.die()
	var kinds := {}
	for p in sim.pickups.list.slice(c1):
		kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
	t.check("thief Gholdengo (25 %%): hp x1.5, drops 6 coins + a x10 ticket %s" % str(kinds),
		gh.dex == 1000 and rel(gh.max_hp, U.jround(60.0 * (1.0 + 300.0 / 95.0) * 1.5)) and int(kinds.get("coin", 0)) == 6 and int(kinds.get("ticket10", 0)) == 1)
	var me := Phase2Tests.enemy_of(52, 0.0, 0.0)
	me.behavior = "thief"
	me.def["loot"] = "coins"
	c1 = sim.pickups.count()
	me.die()
	var mc := sim.pickups.list.slice(c1).filter(func(p): return p.kind == "coin").size()
	t.check("thief Meowth drops 20 coins (x5)", mc == 20)
	# lost Pokémon: follow, enemies hurt it, rescue (heal 50 %, 12 coins + a ticket), timeout
	sim = new_sim(7)
	pl = sim.player
	sim.events.thieves = 2                  # no thief banner in the middle of these checks
	sim.events.debug_start("lost")
	var L := sim.events.lost
	var d_spawn := U.dist(pl.x, pl.y, L.x, L.y)
	var d_goal := U.dist(L.x, L.y, L.tx, L.ty)
	t.check("lost Pokémon %s: %.0f wu away, mark %.0f wu from it, banner" % [L.name, d_spawn, d_goal],
		d_spawn >= 220.0 * 0.8 - 0.01 and d_spawn <= 300.0 + 0.01 and d_goal >= 700.0 * 0.85 - 0.01 and d_goal <= 850.0 + 0.01
		and sim.spawner.announce == "¡Un " + L.name + " se ha perdido! Búscalo y llévalo a la marca")
	pl.x = L.x + pl.r + L.r + 10.0
	pl.y = L.y
	sim.events.update(1.0 / 60.0, pl, 10.0)
	var follows := L.state == "follow"
	pl.x += 200.0
	for i in 60:
		sim.events.update(1.0 / 60.0, pl, 10.0)
	var gap := U.dist(pl.x, pl.y, L.x, L.y)
	t.check("touch -> it follows (step max(120, spd x1.15)/s, keeps r + r + 14: gap %.1f)" % gap, follows and gap < 200.0 and gap >= pl.r + L.r + 14.0 - 0.01)
	# stand still right next to it (it stops) and let an enemy touch it
	var keep := pl.r + L.r + 14.0
	pl.x = L.x + keep - 1.0
	pl.y = L.y
	var foe := Phase2Tests.enemy_of(19, L.x, L.y)
	foe.dmg = 50.0
	sim.enemies.add(foe)
	sim.enemies.rebuild_grid()
	var h0 := L.hp
	for i in 32:
		sim.events.update(1.0 / 60.0, pl, 10.0)
	t.check("an enemy touching it: -%.1f HP per 0.5 s (4 + 12 %% dmg)" % ((h0 - L.hp) / 2.0), rel(h0 - L.hp, 2.0 * (4.0 + 50.0 * 0.12)))
	sim.enemies.clear()
	sim.enemies.rebuild_grid()
	pl.hp = pl.max_hp * 0.2
	var hp_before := pl.hp
	pl.x = L.tx
	pl.y = L.ty
	L.x = L.tx + 40.0
	L.y = L.ty
	L.grant = false
	var pk0 := sim.pickups.count()
	sim.events.update(1.0 / 60.0, pl, 10.0)
	var dropped := sim.pickups.list.slice(pk0)
	t.check("rescued within 56 wu of the mark: heal 50 %% (%.0f -> %.0f), 12 coins x5 + 1 ticket, event over" % [hp_before, pl.hp],
		sim.events.lost == null and sim.events.current() == "" and rel(pl.hp, minf(pl.max_hp, hp_before + pl.max_hp * 0.5))
		and dropped.filter(func(p): return p.kind == "coin").size() == 12 and dropped.filter(func(p): return p.kind == "ticket").size() == 1)
	sim.events.debug_start("lost")
	L = sim.events.lost
	var steps := 0
	while sim.events.lost != null and steps < 130 * 60:
		sim.events.update(1.0 / 60.0, pl, 10.0)
		steps += 1
	t.check("left waiting: it leaves after 120 s (%.2f s)" % (steps / 60.0), absf(steps / 60.0 - 120.0) < 0.05
		and sim.spawner.announce == L.name + " se ha cansado de esperar y se ha ido…")
	# rescue that joins the collection (Save.grant(dex, "rescue"))
	if Save.loaded:
		var owned_before := Save.owns(L.dex)
		var coins0 := pl.coins
		sim.on_rescue(L.dex, L.name)
		t.check("rescue grant: %s joins the collection (Save.grant rescue) or +150 coins if owned" % L.name,
			Save.owns(L.dex) and (owned_before == (pl.coins == coins0 + 150)))
	# no events, thieves or rift checks in the arena; none with a boss alive
	sim = new_sim(7)
	pl = sim.player
	sim.events.next_t = 0.1
	sim.events.thief_t = 0.1
	var boss := Phase2Tests.enemy_of(19, 300.0, 0.0)
	boss.boss = true
	sim.enemies.add(boss)
	sim.events.update(0.5, pl, 300.0)
	t.check("boss alive: event retried in 10 s, thief in 8 s", sim.events.current() == "" and rel(sim.events.next_t, 10.0) and rel(sim.events.thief_t, 8.0))

# ---------------- runtime: rifts ----------------

static func _rt_rift(t: Object) -> void:
	print("-- Phase 3b runtime: rift portal, arena, legendary, win / loss (§7.11) --")
	var sim := new_sim(11)
	var pl := sim.player
	sim.time = 80.0
	# a few map enemies to stash
	for i in 5:
		sim.enemies.add(Phase2Tests.enemy_of(19, 150.0 + i * 30.0, 50.0))
	sim.rift.debug_open()
	var r := sim.rift.portal
	var dr := U.dist(pl.x, pl.y, r["x"], r["y"])
	t.check("rift opens 380-560 wu away (%.0f), ttl 45 s, no enter from afar" % dr, not r.is_empty() and dr >= 380.0 * 0.85 - 0.01 and dr <= 560.0 + 0.01 and rel(r["ttl"], 45.0))
	pl.x = r["x"]
	pl.y = float(r["y"]) - 10.0 + 29.0
	var b0 := sim.world.biome
	pl.god = true
	sim.update(1.0 / 60.0)
	var A := sim.rift.arena
	var n_map := sim.enemies._stashed.size()
	t.check("walking within 30 wu of (x, y-10) enters: arena %s (dex %d) at tile (%d, %d), map enemies stashed, Progress.in_arena" % [A.get("type", "?"), int(A.get("dex", 0)), int(A.get("tx", 0)), int(A.get("ty", 0))],
		sim.rift.in_arena and Progress.in_arena and sim.rift.portal.is_empty() and sim.enemies.list.size() == 1 and sim.enemies.list[0].legend
		and sim.world.biome == WorldMap.arena_biome(A["type"]) and not sim.world.arena.is_empty()
		and rel(pl.x, float(A["x"])) and rel(pl.y, float(A["y"]) + 96.0) and int(A["tx"]) >= 5000 and int(A["tx"]) < 8000)
	var leg := sim.enemies.list[0]
	t.check("legendary: boss, legend, walks (flying = false), north of the arena (cy - 112)", leg.boss and leg.legend and not leg.flying and rel(leg.y, float(A["y"]) - 112.0))
	# keep_inside: an enemy pushed out is clamped to (r - 1.4) * 32
	leg.x = float(A["x"]) + 500.0
	sim.rift.keep_inside()
	t.check("keepInside clamps to %.1f wu from the centre" % ((11.0 - 1.4) * 32.0), rel(U.dist(leg.x, leg.y, A["x"], A["y"]), (11.0 - 1.4) * 32.0, 1e-9))
	leg.x = float(A["x"])
	leg.y = float(A["y"]) - 112.0
	# nothing spawns, no events, the clock runs, no biome change
	sim.events.next_t = 0.1
	var t0 := sim.time
	for i in 120:
		frame(sim)
	t.check("inside: no spawns, no events, run clock keeps going", sim.enemies.list.size() == 1 and sim.events.current() == "" and sim.time > t0 + 1.9)
	# win: legendary down -> won, 5 s, back with a bond and the picker
	pl.add_move("water-gun")
	leg.hurt(leg.hp + 10.0, Color.WHITE)
	sim.update(1.0 / 60.0)
	var won: bool = sim.rift.arena.get("phase", "") == "won" and pl.bonds == 1
	var steps := 0
	while sim.rift.in_arena and steps < 600:
		frame(sim)
		steps += 1
	t.check("win: phase won, +1 bond, back after %.2f s (5 s) where you were, %d map enemies back, old biome" % [steps / 60.0, n_map],
		won and absf(steps / 60.0 - 5.0) < 0.05 and rel(pl.x, float(r["x"])) and n_map >= 5 and sim.enemies.list.size() == n_map
		and sim.world.biome == b0 and not Progress.in_arena)
	t.check("back on the map: the bond picker opens (state choice, pair mode)", sim.state == "choice" and sim.bond_opt.get("mode", "") == "pair")
	sim.choose_bond([sim.bond_opt["loose"][0], sim.bond_opt["loose"][1]])
	# loss: fall inside -> out after 1.4 s + 1.2 s, revived at 30 %, run not over
	sim = new_sim(11)
	pl = sim.player
	sim.time = 200.0
	sim.rift.debug_arena("ghost")
	t.check("forced arena type ghost -> a ghost legendary", Data.dex_by[int(sim.rift.arena["dex"])]["types"].has("ghost") and sim.rift.arena["type"] == "ghost")
	pl.invuln = 0.0
	pl.hurt(pl.hp + 9999.0)
	steps = 0
	while sim.rift.in_arena and steps < 600:
		frame(sim)
		steps += 1
	t.check("loss (you fall): expelled after %.2f s (1.4 + 1.2), revived at 30 %% HP, the run goes on" % (steps / 60.0),
		absf(steps / 60.0 - 2.6) < 0.05 and not pl.dead and rel(pl.hp, pl.max_hp * 0.3) and sim.state == "playing" and pl.bonds == 0)
	# loss by time: 120 s
	sim = new_sim(11)
	pl = sim.player
	pl.god = true
	sim.rift.debug_arena("water")
	sim.enemies.list[0].hp = 1e12
	sim.enemies.list[0].max_hp = 1e12
	steps = 0
	while sim.rift.in_arena and sim.rift.arena["phase"] == "fight" and steps < 130 * 60:
		frame(sim)
		steps += 1
	t.check("loss by time: after %.2f s (120 s)" % (steps / 60.0), absf(steps / 60.0 - 120.0) < 0.05 and sim.rift.arena.get("phase", "") == "lost")
	# the rift expires after 45 s
	sim = new_sim(11)
	sim.rift.debug_open()
	steps = 0
	while not sim.rift.portal.is_empty() and steps < 50 * 60:
		sim.rift.update(1.0 / 60.0, sim.player, 100.0)
		steps += 1
	t.check("an unvisited rift closes after 45 s (%.2f)" % (steps / 60.0), absf(steps / 60.0 - 45.0) < 0.05)

# ---------------- runtime: bonds ----------------

static func _rt_bond(t: Object) -> void:
	print("-- Phase 3b runtime: fused slot casts every move --")
	var sim := new_sim(13)
	var pl := sim.player
	pl.add_move("water-gun")
	pl.add_move("thunder-shock")
	pl.bonds = 1
	sim.offer_bond(true)
	var opened: bool = sim.state == "choice" and sim.bond_opt.get("mode", "") == "pair"
	var a: Dictionary = sim.bond_opt["loose"][0]
	var b: Dictionary = sim.bond_opt["loose"][1]
	sim.choose_bond([a, b])
	var g := pl.active_group()
	t.check("bond picker -> %s + %s in one slot, active, %d slots, bonds 0, banner" % [a["name"], b["name"], pl.slots.size()],
		opened and sim.state == "playing" and g.size() == 2 and pl.slots.size() == 2 and pl.bonds == 0 and sim.spawner.announce == "¡Vínculo! 2 movimientos a la vez")
	var e := Phase2Tests.enemy_of(19, pl.x + 60.0, pl.y)
	e.max_hp = 1e9
	e.hp = 1e9
	sim.enemies.add(e)
	for m in g:
		m["cast_at"] = 0
	for i in 180:
		sim.enemies.rebuild_grid()
		pl.update(1.0 / 60.0)
		sim.combat.tick(1.0 / 60.0, pl, float(i) / 60.0)
	t.check("both fused moves cast on their own cooldowns", g.all(func(m): return int(m.get("cast_at", 0)) > 0))
	# no option -> the bond waits ("Guardas el vínculo...")
	sim = new_sim(13)
	pl = sim.player
	pl.bonds = 1
	sim.offer_bond(false)
	t.check("one move only: bond kept, message", sim.state == "playing" and pl.bonds == 1 and sim.spawner.announce == "Guardas el vínculo: aprende otro movimiento para usarlo")
	pl.add_move("water-gun")
	sim.update(1.0 / 60.0)
	t.check("learning a 2nd move opens the picker on the next frame", sim.state == "choice")
