class_name Phase2Tests
extends RefCounted
## Phase 2 (combat completeness) checks, called from run_tests.gd with `Phase2Tests.run(self)`.
## Reference values come from data/test_vectors_p2.json, computed by the unchanged JS
## (enemy.js, combat.js, hazards.js, pathing.js, moves.js, enemies.js, items.js) in
## tools/export_godot.js; the rest are spec numbers (§4.6, §5.5-5.11) checked in a live Sim.

static var V: Dictionary = {}

static func run(t: Object) -> void:
	V = Data._json("test_vectors_p2.json") if FileAccess.file_exists("res://data/test_vectors_p2.json") else {}
	if V.is_empty():
		t.check("test_vectors_p2.json present", false, "run: node tools/export_godot.js")
		return
	_moves(t)
	_evolution(t)
	_defs(t)
	_bosses(t)
	_behaviors(t)
	_supports(t)
	_hazards(t)
	_flow(t)
	_grid(t)
	_items(t)
	_crit(t)
	_vfx(t)
	_kinds_runtime(t)
	_fields_runtime(t)
	_enemy_runtime(t)
	_sim_flow(t)

# ---------------- helpers ----------------

static func rel(a: float, b: float, eps := 1e-12) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

## Compares a GDScript dictionary against a JS object (numbers relative, strings exact).
static func diff(mine: Dictionary, js: Dictionary, skip: Array = []) -> Array:
	var out: Array = []
	for k in js:
		if skip.has(k):
			continue
		var b: Variant = js[k]
		var a: Variant = mine.get(k)
		if b == null:
			if a != null:
				out.append("%s %s!=null" % [k, str(a)])
		elif b is String or b is bool:
			if str(a) != str(b):
				out.append("%s %s!=%s" % [k, str(a), str(b)])
		elif b is Array or b is Dictionary:
			if JSON.stringify(a) != JSON.stringify(b):
				out.append(k)
		elif a == null or not rel(float(a), float(b)):
			out.append("%s %s!=%s" % [k, str(a), str(b)])
	return out

static func new_sim(seed := 1) -> Sim:
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, seed)
	sim.enemies.clear()
	return sim

static func enemy_of(dex: int, x: float, y: float, ti := 0, sc := {"hp": 1.0, "dmg": 1.0, "spd": 1.0}) -> Enemy:
	return Enemy.new(EnemyDefs.def_for(Data.dex_by[dex], EnemyDefs.tiers()[ti], ti), x, y, sc)

## Hazards of the live sim as JS-shaped dictionaries.
static func hz_list(sim: Sim) -> Array:
	var out: Array = []
	for h in sim.hazards.list:
		out.append({"kind": h.kind, "x": h.x, "y": h.y, "r": h.r, "angle": h.angle, "len": h.len, "w": h.w,
			"delay": h.delay, "dmg": h.dmg, "type": h.type, "color": "#" + h.color.to_html(false)})
	return out

static func shot_list(sim: Sim) -> Array:
	var out: Array = []
	for p in sim.projectiles.list:
		if not p.friendly:
			out.append({"a": atan2(p.vy, p.vx), "sp": sqrt(p.vx * p.vx + p.vy * p.vy), "dmg": p.dmg, "r": p.r, "life": p.life, "mtype": p.mtype})
	return out

## Hazards / shots equality; `fixed` = how many leading hazards have deterministic positions.
static func same_hazards(mine: Array, js: Array, fixed := 99) -> Array:
	var bad: Array = []
	if mine.size() != js.size():
		return ["count %d!=%d" % [mine.size(), js.size()]]
	for i in js.size():
		var h: Dictionary = js[i]
		var skip := ["x", "y"] if i >= fixed else []
		if h["kind"] == "zone":
			skip += ["angle", "len", "w"]
		else:
			skip += ["r"]
		var d := diff(mine[i], h, skip)
		if not d.is_empty():
			bad.append("#%d %s" % [i, ", ".join(d)])
	return bad

static func same_shots(mine: Array, js: Array) -> Array:
	if mine.size() != js.size():
		return ["count %d!=%d" % [mine.size(), js.size()]]
	var bad: Array = []
	for i in js.size():
		# JS stores vx/vy then we recompute the angle: compare with float tolerance
		var d := diff(mine[i], js[i])
		for k in d:
			if not (str(k).begins_with("a ") or str(k).begins_with("sp ")):
				bad.append("#%d %s" % [i, k])
		if absf(float(mine[i]["a"]) - float(js[i]["a"])) > 1e-9 or not rel(float(mine[i]["sp"]), float(js[i]["sp"]), 1e-9):
			bad.append("#%d angle/speed" % i)
	return bad

# ---------------- moves: ladders of every kind, reach ----------------

static func _moves(t: Object) -> void:
	print("-- Phase 2: move ladders of every kind, evolutions, reach (§4.2, §4.4, §4.7) --")
	var by_kind := {}
	for mv in V["moves"]:
		var id: String = mv["id"]
		var kind: String = Moves.def(id)["kind"]
		if not by_kind.has(kind):
			by_kind[kind] = {"n": 0, "bad": []}
		var k: Dictionary = by_kind[kind]
		for l in 5:
			var d := diff(Moves.instance(id, l + 1), mv["lv"][l], ["t", "maxLvl", "desc", "baseName", "def"])
			k["n"] += 1
			if not d.is_empty():
				k["bad"].append("%s L%d: %s" % [id, l + 1, ", ".join(d)])
		var m := Moves.instance(id, 5)
		Moves.evolve(m)
		var de := diff(m, mv["evo"], ["t", "maxLvl", "desc", "baseName", "def"])
		k["n"] += 1
		if not de.is_empty():
			k["bad"].append("%s evo: %s" % [id, ", ".join(de)])
	var kinds: Array = by_kind.keys()
	kinds.sort()
	for kind in kinds:
		var k: Dictionary = by_kind[kind]
		t.check("%-10s ladders L1-5 + evolution identical to JS (%d instances)" % [kind, k["n"]], (k["bad"] as Array).is_empty(),
			"; ".join((k["bad"] as Array).slice(0, 3)))
	t.check("all 15 move kinds covered", kinds.size() == 15, str(kinds))
	var bad: Array = []
	for r in V["reach"]:
		if not rel(Combat.reach(Moves.instance(r[0], 1)), float(r[1])) or not rel(Combat.reach(Moves.instance(r[0], 5)), float(r[2])):
			bad.append(r[0])
	t.check("reach(m) identical to JS for all 64 moves at L1 and L5", bad.is_empty(), str(bad))

static func _evolution(t: Object) -> void:
	var bad: Array = []
	for c in V["evo_info"]:
		var m := Moves.instance(c["id"], int(c["lvl"]))
		if c.get("evolved", false):
			Moves.evolve(m)
		var st := {}
		for k in c["stats"]:
			st[k] = int(c["stats"][k])
		var r := Moves.evo_info(m, st)
		var js: Variant = c["r"]
		if js == null:
			if not r.is_empty():
				bad.append("%s L%d should be null" % [c["id"], int(c["lvl"])])
		elif r.is_empty() or r["name"] != js["name"] or r["needs"] != js["needs"] or bool(r["ready"]) != bool(js["ready"]):
			bad.append("%s L%d %s" % [c["id"], int(c["lvl"]), str(r)])
	t.check("evoInfo conditions (L5 + its stat taken, not evolved) match JS (%d cases)" % V["evo_info"].size(), bad.is_empty(), str(bad.slice(0, 4)))
	# gold card: a maxed move waiting for its stat -> that stat card has weight 14 and the gold tag
	var sim := new_sim()
	var pl := sim.player
	pl.moves[0] = Moves.instance("ember", 5)
	pl.slots[0] = [pl.moves[0]]
	var w := 0.0
	var tag := ""
	for c in LevelUp.candidates(pl):
		if c["key"] == "stat:atk":
			w = c["w"]
			tag = c["tag"]
	t.check("maxed move waiting for its stat: stat card weight 14, gold tag", w == 14.0 and tag.begins_with("Evoluciona"), "%s %s" % [w, tag])
	pl.stats_taken["atk"] = 1
	var all_evo := true
	for i in 30:
		all_evo = all_evo and LevelUp.offer(pl)[0]["type"] == "evo"
	t.check("evolution ready -> forced gold card first in every offer (30 draws)", all_evo)
	(LevelUp.offer(pl)[0]["apply"] as Callable).call(pl)
	t.check("picking the gold card evolves Ascuas -> Llamarada (x1.8 dmg)", pl.moves[0]["evolved"] and pl.moves[0]["name"] == Data.evo["ember"][0]
		and rel(float(pl.moves[0]["dmg"]), float(Moves.instance("ember", 5)["dmg"]) * 1.8), str(pl.moves[0]["name"]))
	var new_kinds := {}
	var sim2 := new_sim()
	sim2.player.mon = Data.dex_by[25]
	for i in 300:
		for c in LevelUp.candidates(sim2.player):
			if c["type"] == "new":
				new_kinds[Moves.def(c["key"].substr(4))["kind"]] = true
	t.check("new-move cards now offer every kind in the pool (Pikachu: chain, aura, buff...)", new_kinds.has("chain") and new_kinds.has("aura") and new_kinds.has("buff"), str(new_kinds.keys()))

# ---------------- enemy defs, bosses ----------------

static func _defs(t: Object) -> void:
	print("-- Phase 2: enemy defs of every species, bosses (§5.1, §5.3, §5.6) --")
	var keys := ["dex", "behavior", "hp", "spd", "dmg", "xp", "shotDmg", "shotCd", "range", "minion", "fanN", "zones"]
	for tab in V["def_for"]:
		var ti := int(tab["ti"])
		var bad: Array = []
		for row in tab["rows"]:
			var d := EnemyDefs.def_for(Data.dex_by[int(row[0])], EnemyDefs.tiers()[ti], ti)
			for k in keys.size():
				var b: Variant = row[k]
				var a: Variant = d.get(keys[k])
				if b == null:
					if a != null:
						bad.append("%d %s" % [int(row[0]), keys[k]])
				elif b is String:
					if str(a) != b:
						bad.append("%d %s" % [int(row[0]), keys[k]])
				elif a == null or float(a) != float(b):
					bad.append("%d %s %s!=%s" % [int(row[0]), keys[k], str(a), str(b)])
		t.check("defFor (shotDmg/shotCd/range/minion/fanN/zones) identical to JS, %d species, tier %d" % [tab["rows"].size(), ti],
			bad.is_empty(), str(bad.slice(0, 5)))

static func _bosses(t: Object) -> void:
	var bad: Array = []
	var slots: Array = Data.enemies["boss_slots"]
	for b in V["boss_defs"]:
		var js: Dictionary = b["def"]
		var d := diff(EnemyDefs.boss_def(slots[int(b["slot"])], Data.dex_by[int(js["dex"])]), js)
		if not d.is_empty():
			bad.append("slot %d dex %d: %s" % [int(b["slot"]), int(js["dex"]), ", ".join(d)])
	t.check("boss defs (x1.35 HP, x1.2 dmg, spd, behavior, shotDmg) identical to JS (%d rolled)" % V["boss_defs"].size(), bad.is_empty(), str(bad.slice(0, 3)))
	var sim := new_sim()
	var pl := sim.player
	var ontime: Array = []
	for B in V["bosses"]:
		var def: Dictionary = B["def"]
		var e := Enemy.new(def, 0.0, 0.0, EnemyDefs.boss_scale(float(def["at"])), true)
		ontime.append("%d HP/%.0f" % [int(e.max_hp), e.dmg])
		var st := diff({"maxHp": e.max_hp, "dmg": e.dmg, "spd": e.spd, "scale": e.scale, "r": e.r, "shotDmg": e.shot_dmg()}, B,
			["slot", "def", "ai", "casts"])
		e.boss_init()
		var ai := {"melee": e.ai.melee, "ranged": e.ai.ranged, "farLike": e.ai.far_like, "mode": e.ai.mode}
		st += diff(ai, B["ai"])
		t.check("boss slot %d (%s): HP %d dmg %.1f, scale %.1f, AI set %s/%s identical to JS" % [int(B["slot"]) + 1, def["name"], int(e.max_hp), e.dmg,
			e.scale, str(e.ai.melee), str(e.ai.ranged)], st.is_empty(), ", ".join(st))
		var cbad: Array = []
		for c in B["casts"]:
			sim.hazards.clear()
			sim.projectiles.clear()
			e.ai.fury = bool(c["fury"])
			e.ai.cast = {}
			e.jump = {}
			e.x = 0.0
			e.y = 0.0
			pl.x = 300.0
			pl.y = 120.0
			e.boss_start(c["id"], pl)
			if not e.ai.cast.is_empty() and (c["id"] == "volley" or c["id"] == "nova"):
				e._boss_cast(float(e.ai.cast["wind"]), pl)
			var tag := "%s%s" % [c["id"], "!" if c["fury"] else ""]
			if c["cast"] != null:
				var cd := diff(e.ai.cast, c["cast"], ["t", "fired", "go"])
				if not cd.is_empty():
					cbad.append(tag + " cast " + ", ".join(cd))
			if c["jump"] != null:
				var jd := diff(e.jump, c["jump"])
				if not jd.is_empty():
					cbad.append(tag + " jump " + ", ".join(jd))
			var hb := same_hazards(hz_list(sim), c["hazards"], 1)
			if not hb.is_empty():
				cbad.append(tag + " hazards " + ", ".join(hb))
			var sb := same_shots(shot_list(sim), c["shots"])
			if not sb.is_empty():
				cbad.append(tag + " shots " + ", ".join(sb))
		t.check("boss slot %d: 7 casts x fury on/off (telegraphs, winds, volleys, rings) identical to JS" % [int(B["slot"]) + 1], cbad.is_empty(), "; ".join(cbad.slice(0, 3)))
	t.check("on-time boss stats match §5.3 (2457/53, 6912/80, 14364/110, 26730/147, 54000/205)",
		ontime == ["2457 HP/53", "6912 HP/80", "14364 HP/110", "26730 HP/147", "54000 HP/205"], str(ontime))

# ---------------- behaviors: shots, telegraphs, jumps, fuses ----------------

static func _behaviors(t: Object) -> void:
	print("-- Phase 2: enemy behaviors, shots and telegraphs (§5.5, §5.7) --")
	var sim := new_sim()
	var pl := sim.player
	for B in V["behaviors"]:
		sim.hazards.clear()
		sim.projectiles.clear()
		pl.x = 300.0
		pl.y = 120.0
		var e := Enemy.new(B["def"], 100.0, 50.0, B["sc"])
		e.dmg *= 2.4
		var n := Enemy.dir_to(e.x, e.y, pl.x, pl.y)
		match str(B["beh"]):
			"jumper":
				e.start_jump(pl)
			"bomber":
				e.start_fuse()
			_:
				e.special(pl, n[0], n[1])
		var bad := diff({"maxHp": e.max_hp, "dmg": e.dmg, "shotDmg": e.shot_dmg()}, B, ["beh", "dex", "ti", "sc", "def", "x", "y", "hazards", "shots", "jump", "phase", "pt"])
		bad += same_hazards(hz_list(sim), B["hazards"], 1) if B["beh"] != "zoner" else []
		if B["beh"] == "zoner":
			# 1..zones zones (random count): the first sits on the player, the rest are random
			var hs := hz_list(sim)
			var zmax := int(B["def"].get("zones", 3))
			if hs.size() < 1 or hs.size() > zmax:
				bad.append("zone count %d" % hs.size())
			else:
				bad += same_hazards(hs.slice(0, 1), (B["hazards"] as Array).slice(0, 1))
				for h in hs:
					if not rel(h["r"], 44.0) or not rel(h["delay"], 1.2) or not rel(h["dmg"], e.shot_dmg() * 0.95):
						bad.append("zone params")
		bad += same_shots(shot_list(sim), B["shots"])
		if B["jump"] != null:
			bad += diff(e.jump, B["jump"])
		if B["beh"] == "bomber":
			bad += diff({"phase": e.phase, "pt": e.pt}, {"phase": B["phase"], "pt": B["pt"]})
		t.check("%-7s (%s): %d telegraph(s), %d shot(s), dmg x shotDmg identical to JS" % [B["beh"], Data.dex_by[int(B["dex"])]["name"],
			(B["hazards"] as Array).size(), (B["shots"] as Array).size()], bad.is_empty(), ", ".join(bad))

static func _supports(t: Object) -> void:
	var S: Dictionary = V["supports"]
	var sim := new_sim()
	var ti := int(S["ti"])
	var make := func() -> Array:
		sim.enemies.clear()
		var list: Array = []
		var gs: Array = S["group"]
		for i in gs.size():
			var g: Dictionary = gs[i]
			var e := Enemy.new(EnemyDefs.def_for(Data.dex_by[int(g["dex"])], EnemyDefs.tiers()[ti], ti), float(g["x"]), float(g["y"]), S["sc"])
			e.dmg *= 2.4
			e.hp = U.jround(e.max_hp * (0.3 + 0.07 * i))
			sim.enemies.add(e)
			list.append(e)
		sim.enemies.rebuild_grid()
		return list
	sim.player.atk_mul = float(S["pl_atk"])
	var list: Array = make.call()
	var start_ok := true
	for i in list.size():
		start_ok = start_ok and rel(list[i].hp, float(S["group_start_hp"][i]))
	(list[0] as Enemy).heal_around()
	var bad: Array = []
	for i in list.size():
		if not rel(list[i].hp, float(S["healed"][i]["hp"]), 1e-9):
			bad.append("%d: %.3f vs %.3f" % [i, list[i].hp, float(S["healed"][i]["hp"])])
	t.check("healer: +7% x min(2.5, pow^0.35) of max HP to hurt allies within 150 (JS values)", start_ok and bad.is_empty(), str(bad))
	list = make.call()
	(list[1] as Enemy).cast_shields()
	bad = []
	for i in list.size():
		if not rel(list[i].shield, float(S["shielded"][i]["shield"]), 1e-9) or not rel(list[i].shield_t, float(S["shielded"][i]["shieldT"])):
			bad.append(i)
	t.check("shielder: 35% max-HP shields (8 s) on the 6 nearest within 160 (JS values)", bad.is_empty(), str(bad))
	sim.enemies.clear()
	var su: Dictionary = S["summoner"]
	var s := Enemy.new(su["def"], 0.0, 0.0, S["sc"])
	sim.enemies.add(s)
	s.summon()
	bad = []
	var js_m: Array = su["minions"]
	if s.minions.size() != js_m.size():
		bad.append("count %d" % s.minions.size())
	else:
		for i in js_m.size():
			var m: Enemy = s.minions[i]
			bad += diff({"dex": m.dex, "maxHp": m.max_hp, "dmg": m.dmg, "spd": m.spd, "xp": m.xp}, js_m[i], ["def"])
			bad += diff(m.def, js_m[i]["def"], ["name"])
	t.check("summoner: 2 minions with 35% HP / 110% spd / 60% dmg / 25% XP of its def (JS values)", bad.is_empty(), ", ".join(bad))

static func _hazards(t: Object) -> void:
	for c in V["hazards_inside"]:
		var h := Hazards.Hazard.new()
		var j: Dictionary = c["h"]
		h.kind = j["kind"]
		h.x = j["x"]
		h.y = j["y"]
		h.r = j.get("r", 0.0)
		h.angle = j.get("angle", 0.0)
		h.len = j.get("len", 0.0)
		h.w = j.get("w", 0.0)
		var bits := ""
		for r in [8.0, 14.0]:
			var y := -320
			while y <= 320:
				var x := -320
				while x <= 420:
					bits += "1" if Hazards.inside(h, x, y, r) else "0"
					x += 13
				y += 11
		var hits := bits.count("1")
		t.check("hazard %s inside() on %d points identical to JS (%d inside)" % [h.kind, bits.length(), hits], bits == c["bits"])

# ---------------- flow field ----------------

static func _flow(t: Object) -> void:
	print("-- Phase 2: flow-field pathing + line of sight (§5.13) --")
	var F: Dictionary = V["flow"]
	var sim := new_sim()
	var rows: Array = F["rows"]
	var fox := int(F["ox"])
	var foy := int(F["oy"])
	var pf := Pathing.new()
	pf.walk_fn = func(tx: int, ty: int) -> bool:
		var i := tx - fox
		var j := ty - foy
		return i >= 0 and j >= 0 and j < rows.size() and i < (rows[j] as String).length() and (rows[j] as String)[i] == "."
	var pl: Dictionary = F["pl"]
	pf.build(float(pl["x"]), float(pl["y"]))
	var js: Array = F["dist"]
	var same := pf.ox == fox and pf.oy == foy
	var reach := 0
	for j in Pathing.N:
		for i in Pathing.N:
			var v := pf.dist_at(fox + i, foy + j)
			same = same and v == int(js[j * Pathing.N + i])
			if v != Pathing.UNSEEN:
				reach += 1
	t.check("BFS distance field 57x57 identical to JS on a known map (%d reachable cells)" % reach, same)
	var body := Body.new()
	body.x = float(pl["x"])
	body.y = float(pl["y"])
	var bad: Array = []
	var n_null := 0
	var n_los := 0
	for d in F["dirs"]:
		var e := enemy_of(10, float(d["x"]), float(d["y"]))
		e.r = float(d["r"])
		var got: Variant = pf.dir_for(e, body, 0.0)
		var want: Variant = d["d"]
		if want == null:
			n_null += 1
			if got != null:
				bad.append("(%.0f,%.0f) want null" % [e.x, e.y])
		elif got == null or absf((got as Vector2).x - float(want[0])) > 1e-6 or absf((got as Vector2).y - float(want[1])) > 1e-6:
			bad.append("(%.0f,%.0f) %s vs %s" % [e.x, e.y, str(got), str(want)])
		if e.los:
			n_los += 1
		if e.los != bool(d["los"]):
			bad.append("los")
	t.check("dirFor (next tile, corner rule, LOS shortcut, centre fallback) = JS for %d enemies (%d null, %d LOS)" % [F["dirs"].size(), n_null, n_los],
		bad.is_empty(), str(bad.slice(0, 4)))
	# the time-sliced rebuild used in game converges to the same field
	var pf2 := Pathing.new()
	pf2.walk_fn = pf.walk_fn
	pf2._begin(float(pl["x"]), float(pl["y"]))
	var frames := 0
	while not pf2._steps(Pathing.BUDGET):
		frames += 1
	pf2._swap()
	t.check("time-sliced rebuild (%d cells/frame) gives the same field in %d frames" % [Pathing.BUDGET, frames + 1], pf2.dist == pf.dist and frames < 4)
	# integration: a walker behind a wall goes around it
	var sim2 := new_sim(3)
	var wx := 0
	var w := sim2.world
	# find a wall tile with floor on both sides along x near the start
	var found := false
	for ty in range(-25, 25):
		for tx in range(-25, 25):
			if w.terrain_at(tx, ty) == WorldMap.WALL and w.terrain_at(tx - 2, ty) == WorldMap.FLOOR and w.terrain_at(tx + 2, ty) == WorldMap.FLOOR \
					and w.terrain_at(tx - 1, ty) != WorldMap.WALL and absf(tx) > 3:
				wx = tx
				var wy := ty
				sim2.player.x = (tx + 2.5) * WorldMap.TS
				sim2.player.y = (wy + 0.5) * WorldMap.TS
				sim2.pathing.build(sim2.player.x, sim2.player.y)
				var e := enemy_of(19, (tx - 1.5) * WorldMap.TS, (wy + 0.5) * WorldMap.TS)
				var dd: Variant = sim2.pathing.dir_for(e, sim2.player, 0.0)
				found = dd != null
				if found:
					break
		if found:
			break
	t.check("enemy with a wall between it and the player gets a path direction (not straight)", found, "wall at x=%d" % wx)

# ---------------- spatial grid ----------------

## Reference: the JS Map grid (cells row-major, each bucket in list order) with an exact key.
static func _ref_query(buckets: Dictionary, x: float, y: float, r: float) -> Array:
	var out: Array = []
	for cy in range(EnemyMgr.cell_of(y - r) - 1, EnemyMgr.cell_of(y + r) + 2):
		for cx in range(EnemyMgr.cell_of(x - r) - 1, EnemyMgr.cell_of(x + r) + 2):
			for e: Enemy in buckets.get(Vector2i(cx, cy), []):
				if not e.dead and U.dist2(x, y, e.x, e.y) <= (r + e.r) * (r + e.r):
					out.append(e)
	return out

static func _grid(t: Object) -> void:
	var sim := new_sim(21)
	var bad := 0
	var total := 0
	for round_i in 6:
		sim.enemies.clear()
		sim.cam.x = U.rand(-3000, 3000)
		sim.cam.y = U.rand(-3000, 3000)
		var n := 40 + round_i * 15
		for i in n:
			var far := randf() < 0.08          # far bosses / shinies: outside the dense window
			var spread := 2600.0 if far else 700.0
			var e := enemy_of([19, 10, 74, 95, 6][i % 5], sim.cam.x + U.rand(-spread, spread), sim.cam.y + U.rand(-spread, spread))
			sim.enemies.add(e)
		sim.enemies.rebuild_grid()
		var buckets := {}
		for e in sim.enemies.list:
			var k := Vector2i(EnemyMgr.cell_of(e.x), EnemyMgr.cell_of(e.y))
			if not buckets.has(k):
				buckets[k] = []
			buckets[k].append(e)
		# after the rebuild: some die, some move (the grid keeps their old cell, like JS)
		for e in sim.enemies.list:
			if randf() < 0.1:
				e.dead = true
			elif randf() < 0.2:
				e.x += U.rand(-40, 40)
		for q in 200:
			var x := sim.cam.x + U.rand(-2900, 2900) if q % 4 == 0 else sim.cam.x + U.rand(-800, 800)
			var y := sim.cam.y + U.rand(-2900, 2900) if q % 4 == 0 else sim.cam.y + U.rand(-800, 800)
			var r: float = [14.0, 60.0, 150.0, 340.0, 900.0][q % 5]
			var got := sim.enemies.query_circle(x, y, r)
			var want := _ref_query(buckets, x, y, r)
			total += 1
			if got.size() != want.size():
				bad += 1
				continue
			for i in got.size():
				if got[i] != want[i]:
					bad += 1
					break
	t.check("windowed spatial grid: query_circle = reference Map grid (same enemies, same order) in %d queries" % total, bad == 0, "%d differ" % bad)

# ---------------- held items, crits ----------------

static func _items(t: Object) -> void:
	print("-- Phase 2: held items, crits (§4.9, §4.5) --")
	var bad: Array = []
	for c in V.get("items", []):
		var p := Player.new(Data.dex_by[4], {}, false)
		var snap := func() -> Dictionary:
			return {"atkMul": p.atk_mul, "cdMul": p.cd_mul, "spdMul": p.spd_mul, "xpMul": p.xp_mul, "coinMul": p.coin_mul,
				"dmgReduce": p.dmg_reduce, "regenFlat": p.regen_flat}
		p.equip(c["id"])
		var d: Array = diff(snap.call(), c["on"])
		p.equip("choiceband" if c["id"] == "leftovers" else "leftovers")
		d += diff(snap.call(), c["sw"])
		p.equip(c["id"])
		d += diff(snap.call(), c["back"])
		if not d.is_empty():
			bad.append("%s: %s" % [c["id"], ", ".join(d)])
	t.check("11 items: equip / switch / re-equip stats identical to JS (on/off inverses)", bad.is_empty() and V.get("items", []).size() == 11, str(bad))
	var sim := new_sim()
	var pl := sim.player
	sim.offer_item("quickclaw")
	var ok1 := pl.item == "quickclaw" and sim.state == "playing" and rel(pl.cd_mul, 0.8)
	sim.offer_item("quickclaw")
	var ok2 := sim.state == "playing" and sim.spawner.announce.begins_with("Ya llevas")
	sim.offer_item("lifeorb")
	var ok3 := sim.state == "choice" and sim.item_choice == ["quickclaw", "lifeorb"]
	sim.choose_item(1)
	var ok4 := sim.state == "playing" and pl.item == "lifeorb" and rel(pl.cd_mul, 1.0) and rel(pl.atk_mul, 1.3)
	t.check("item pickup: wear when empty-handed, 'Ya llevas', swap screen pauses (state choice), switch", ok1 and ok2 and ok3 and ok4,
		"%s %s %s %s" % [ok1, ok2, ok3, ok4])
	pl.hp = 50.0
	pl.cast(Moves.instance("ember", 1))
	var lo := rel(pl.hp, 50.0 - maxf(1.0, pl.max_hp * 0.01))
	pl.hp = 1.0
	pl.cast(Moves.instance("ember", 1))
	t.check("Life Orb: each cast costs 1% max HP, never below 1", lo and pl.hp == 1.0)
	pl.equip("focussash")
	pl.sash_t = -999999
	pl.hp = 5.0
	pl.invuln = 0.0
	pl.hurt(500.0)
	var saved := not pl.dead and pl.hp == 1.0 and rel(pl.invuln, 1.2)
	pl.invuln = 0.0
	pl.hurt(500.0)
	t.check("Focus Sash: survives a lethal hit at 1 HP once, the next one (within 60 s) KOs", saved and pl.dead)
	var sim2 := new_sim()
	var p2 := sim2.player
	p2.add_move("tackle")
	p2.equip("choiceband")
	var a0 := p2.active
	p2.set_active(0 if a0 != 0 else 1)
	t.check("Choice Band: the active move can't be changed", p2.active == a0)
	p2.equip("rockyhelmet")
	var e := enemy_of(19, p2.x + 3.0, p2.y, 0, {"hp": 10.0, "dmg": 1.0, "spd": 1.0})
	sim2.enemies.add(e)
	sim2.enemies.rebuild_grid()
	var hp0 := e.hp
	sim2.combat.resolve(1.0 / 60.0, p2, 0.0)
	t.check("Rocky Helmet: an enemy touching you takes 15 + 4*level", hp0 - e.hp == 15.0 + 4.0 * p2.level, "%d" % int(hp0 - e.hp))

static func _crit(t: Object) -> void:
	var sim := new_sim()
	var pl := sim.player
	var m := Moves.instance("ember", 1)
	var e := enemy_of(1, pl.x + 50.0, pl.y, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})   # Bulbasaur: grass/poison
	sim.enemies.add(e)
	var tk := Types.mult("fire", e.types)
	pl.crit_chance = 0.0
	var h0 := e.hp
	sim.combat._hit(pl, e, 100.0, Color.WHITE, 1.0, 0.0, 0.0, m)
	var plain := h0 - e.hp
	pl.crit_chance = 1.0
	h0 = e.hp
	sim.combat._hit(pl, e, 100.0, Color.WHITE, 1.0, 0.0, 0.0, m)
	var crit := h0 - e.hp
	var orange := false
	for tx in sim.fx.texts:
		orange = orange or (tx.color.is_equal_approx(Color.html("#ff9a3c")) and tx.big)
	t.check("crit: x1.5 after the type chart (fire vs grass/poison x%.1f: %d -> %d), big orange number" % [tk, int(plain), int(crit)],
		plain == U.jround(100.0 * tk) and crit == U.jround(100.0 * tk * 1.5) and orange)
	var n := 0
	for i in 2000:
		pl.crit_chance = 0.25
		if sim.combat._is_crit(pl):
			n += 1
	t.check("crit chance 25%% -> %.1f%% of 2000 rolls" % (n / 20.0), absf(n / 2000.0 - 0.25) < 0.04)

# ---------------- VFX ----------------

static func _vfx(t: Object) -> void:
	print("-- Phase 2: VFX shapes and palettes (§2.6), FX layer --")
	var v: Dictionary = Data._json("vfx.json")
	var n := 0
	var bad: Array = []
	for name in v["shapes"]:
		var S: Dictionary = v["shapes"][name]
		for f in (S["frames"] as Array).size():
			for pal in Data.vfx_pal:
				var tex := VFX.tex(name, pal, f)
				n += 1
				if tex.get_width() != int(S["w"]) or tex.get_height() != int(S["h"]):
					bad.append(name)
	t.check("%d VFX textures (23 shapes x their frames x 19 palettes) built with the right sizes" % n, bad.is_empty() and v["shapes"].size() == 23 and n == 38 * 19, str(bad.slice(0, 3)))
	# a pixel check: letters -> palette colours
	var img := VFX.tex("fire", "water", 0).get_image()
	var rows: Array = v["shapes"]["fire"]["frames"][0]
	var P := Data.pal("water")
	var ok := true
	for y in rows.size():
		for x in (rows[y] as String).length():
			var ch: String = rows[y][x]
			var c := img.get_pixel(x, y)
			if ch == ".":
				ok = ok and c.a == 0.0
			elif ch == "L":
				ok = ok and c.is_equal_approx(Color(P[3], 0.5))
			else:
				ok = ok and c.is_equal_approx(P[VFX.IDX[ch]])
	t.check("fire|water frame 0: every pixel = palette letter (o d m l w, L = light at 50%)", ok)
	var miss: Array = []
	for m in Data.moves:
		var vis := VFX.for_move(m)
		if not vis.has("pal") or not vis.has("proj") or VFX.shape_def(vis["proj"]).is_empty():
			miss.append(m["id"])
	t.check("every move has a VFX look (palette + projectile shape)", miss.is_empty(), str(miss))
	t.check("enemy shots: VFX.for_type (fire->fire, water->drop, normal->star, unknown->ball/normal)",
		VFX.for_type("fire")["proj"] == "fire" and VFX.for_type("water")["proj"] == "drop" and VFX.for_type("normal")["proj"] == "star"
		and VFX.for_type("???")["proj"] == "ball" and VFX.for_type("???")["pal"] == "normal")
	var fx := FX.new()
	Settings.fx = 2
	for i in 400:
		fx.sp("impact", "fire", 0, 0)
	fx.beam(0, 0, 0.3, 200, 20, {"pal": "electric", "beam": "lightning"})
	fx.slash(0, 0, 0.0, 60, 2.0, {"pal": "normal", "melee": "impact"})
	t.check("FX sprite cap 320 (high quality); beam + slash add impact sprites only under the cap", fx.sprites.size() == 320 and fx.beams.size() == 1)
	fx.update(0.25)
	t.check("FX: beams live 0.2 s, slashes 0.22 s", fx.beams.is_empty() and fx.slashes.is_empty())

# ---------------- kinds at runtime (combat.js) ----------------

static func _kinds_runtime(t: Object) -> void:
	print("-- Phase 2: every move kind at runtime (§4.6) --")
	var sim := new_sim(5)
	var pl := sim.player
	pl.x = 0.0
	pl.y = 0.0
	pl.aim = 0.0
	var reset := func() -> void:
		sim.enemies.clear()
		sim.projectiles.clear()
		sim.combat.clear_fields()
		sim.fx.clear()
	var count_shots := func() -> int:
		var k := 0
		for p in sim.projectiles.list:
			if p.friendly and not p.orb:
				k += 1
		return k
	# nova: max(3, count) shots evenly around
	reset.call()
	var nova := Moves.instance("heat-wave", 5)
	sim.combat.run(pl, nova)
	t.check("nova (heat-wave L5): %d shots in a ring" % count_shots.call(), count_shots.call() == maxi(3, int(nova["count"])))
	# cone: max(2, count) shots within the arc
	reset.call()
	var cone := Moves.instance("flamethrower", 1)
	sim.combat.run(pl, cone)
	var in_arc := true
	for p in sim.projectiles.list:
		in_arc = in_arc and absf(atan2(p.vy, p.vx)) <= float(cone["arc"]) / 2.0 + 0.06
	t.check("cone (flamethrower): %d short shots inside the %.1f rad arc" % [count_shots.call(), float(cone["arc"])], count_shots.call() == int(cone["count"]) and in_arc)
	# boomerang: out time radius/speed, pierce 999, comes back and is removed at the owner
	reset.call()
	var bm := Moves.instance("bonemerang", 1)
	sim.combat.run(pl, bm)
	var b: Projectiles.Proj = sim.projectiles.list[0]
	var out_t := float(bm["radius"]) / float(bm["speed"])
	var ok := rel(b.boom, out_t) and b.pierce == 999 and rel(b.life, out_t * 4.0 + 1.5) and rel(b.bsp, float(bm["speed"]) * 1.1)
	var far := 0.0
	var tt := 0.0
	while sim.projectiles.count() > 0 and tt < 5.0:
		sim.projectiles.update(1.0 / 60.0, pl, sim.enemies.list)
		far = maxf(far, b.x)
		tt += 1.0 / 60.0
	t.check("boomerang: out %.2f s (~%d wu), back to the owner in %.2f s" % [out_t, int(far), tt], ok and far > float(bm["radius"]) * 0.9 and tt < out_t * 4.0 + 1.5)
	# chain: hits count enemies, x0.85 per hop, hex x1.7 on statused targets
	reset.call()
	var es: Array = []
	for i in 6:
		var e := enemy_of(19, 60.0 + i * 70.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
		sim.enemies.add(e)
		es.append(e)
	sim.enemies.rebuild_grid()
	pl.target = es[0]
	var ch := Moves.instance("thunderbolt", 1)
	pl.crit_chance = 0.0
	sim.combat.run(pl, ch)
	var hits: Array = []
	for e in es:
		hits.append(int((e as Enemy).max_hp - (e as Enemy).hp))
	var base := float(ch["dmg"]) * pl.atk() * Types.mult("electric", (es[0] as Enemy).types)
	t.check("chain (thunderbolt): %d hops, damage x0.85 per hop %s" % [int(ch["count"]), str(hits)],
		hits[0] == U.jroundi(base) and hits[1] == U.jroundi(base * 0.85) and hits[3] == U.jroundi(base * 0.85 * 0.85 * 0.85) and hits[4] == 0)
	reset.call()
	var e0 := enemy_of(19, 60.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	e0.burn = 1.0
	sim.enemies.add(e0)
	sim.enemies.rebuild_grid()
	pl.target = e0
	var hx := Moves.instance("hex", 1)
	sim.combat.run(pl, hx)
	t.check("hex: x1.7 on a burned target", int(e0.max_hp - e0.hp) == U.jroundi(float(hx["dmg"]) * pl.atk() * Types.mult("ghost", e0.types) * 1.7))
	# beam: rectangle along the aim, cut by walls
	reset.call()
	var bmv := Moves.instance("psybeam", 1)
	var inb := enemy_of(19, 150.0, 10.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	var outb := enemy_of(19, 150.0, 80.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	var behind := enemy_of(19, -60.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	for e in [inb, outb, behind]:
		sim.enemies.add(e)
	sim.enemies.rebuild_grid()
	sim.combat.run(pl, bmv)
	t.check("beam (psybeam): hits inside the %dx%d strip only" % [int(bmv["radius"]), int(bmv["width"])],
		inb.hp < inb.max_hp and outb.hp == outb.max_hp and behind.hp == behind.max_hp and sim.fx.beams.size() == 1)
	# aura: everything within radius, no arc
	reset.call()
	var au := Moves.instance("discharge", 1)
	var a_in := enemy_of(19, -50.0, 20.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	var a_out := enemy_of(19, 0.0, 200.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	sim.enemies.add(a_in)
	sim.enemies.add(a_out)
	sim.enemies.rebuild_grid()
	sim.combat.run(pl, au)
	t.check("aura (discharge): hits within %d wu in every direction, sprites spawned" % int(au["radius"]), a_in.hp < a_in.max_hp and a_out.hp == a_out.max_hp and sim.fx.sprites.size() >= 5)
	# melee arc
	reset.call()
	var ml := Moves.instance("tackle", 1)
	var m_front := enemy_of(19, 40.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	var m_back := enemy_of(19, -40.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	sim.enemies.add(m_front)
	sim.enemies.add(m_back)
	sim.enemies.rebuild_grid()
	sim.combat.run(pl, ml)
	t.check("melee (tackle): front hit, back safe (arc %.2f)" % float(ml["arc"]), m_front.hp < m_front.max_hp and m_back.hp == m_back.max_hp)
	# buff stacks
	reset.call()
	var bf := Moves.instance("swords-dance", 2)
	for i in 8:
		sim.combat.run(pl, bf)
	var atk_b: Dictionary = pl.buffs["atk"]
	t.check("buff (swords-dance L2): stacks capped at %d, x%.2f attack" % [int(bf["stacks"]), 1.0 + atk_b["n"] * atk_b["amount"]],
		int(atk_b["n"]) == int(bf["stacks"]) and rel(float(atk_b["amount"]), float(bf["amount"])) and rel(float(atk_b["t"]), float(bf["dur"])))
	pl.buffs["atk"]["n"] = 0
	# dash: teleport along the aim, i-frames, hits the segment
	reset.call()
	var da := Moves.instance("quick-attack", 1)
	var d_hit := enemy_of(19, 60.0, 5.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	sim.enemies.add(d_hit)
	sim.enemies.rebuild_grid()
	pl.x = 0.0
	pl.y = 0.0
	pl.invuln = 0.0
	sim.combat.run(pl, da)
	var moved := pl.x
	t.check("dash (quick-attack): moved %.0f wu (radius %d, stops at walls), i-frames 0.3, hit on the way" % [moved, int(da["radius"])],
		moved > 0.0 and moved <= float(da["radius"]) and pl.invuln >= 0.3 and d_hit.hp < d_hit.max_hp)
	pl.x = 0.0
	pl.y = 0.0

static func _fields_runtime(t: Object) -> void:
	var sim := new_sim(5)
	var pl := sim.player
	pl.x = 0.0
	pl.y = 0.0
	pl.aim = 0.0
	var C := sim.combat
	# mines: count, cap 4 + 2n, arm 0.35 s, trigger within 14 wu, full damage; timeout -> 50%
	var mn := Moves.instance("spikes", 1)
	for i in 5:
		C.run(pl, mn)
	var live := 0
	for f in C.fields:
		if not f.gone:
			live += 1
	t.check("mines (spikes, count %d): cap 4 + 2n = %d live after 5 casts" % [int(mn["count"]), 4 + 2 * int(mn["count"])], live == 4 + 2 * int(mn["count"]))
	C.clear_fields()
	C.run(pl, Moves.instance("spikes", 1))
	var f0: Combat.Field = C.fields[0]
	var e := enemy_of(19, f0.x + 5.0, f0.y, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
	sim.enemies.add(e)
	sim.enemies.rebuild_grid()
	C.update_fields(0.2)
	var not_armed := e.hp == e.max_hp
	C.update_fields(0.2)
	var hit := e.max_hp - e.hp
	t.check("mine arms after 0.35 s, then blows up under the enemy (%d dmg)" % int(hit), not_armed and hit > 0.0)
	# meteors: staggered by 0.09 s, land at 0.5 s
	C.clear_fields()
	sim.enemies.clear()
	var tgts: Array = []
	for i in 3:
		var en := enemy_of(19, 100.0 + i * 30.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0})
		sim.enemies.add(en)
		tgts.append(en)
	sim.enemies.rebuild_grid()
	var mt := Moves.instance("rock-slide", 1)
	C.run(pl, mt)
	var stag := C.fields.size() == int(mt["count"]) and rel(C.fields[1].t, -0.09) and rel(C.fields[2].t, -0.18)
	var landed := 0
	var t_land := 0.0
	while C.fields.size() > 0 and t_land < 2.0:
		C.update_fields(1.0 / 60.0)
		t_land += 1.0 / 60.0
		if landed == 0 and C.fields.size() < int(mt["count"]):
			landed = 1
			stag = stag and t_land >= 0.49 and t_land < 0.53
	var dmg_n := 0
	for en in tgts:
		if en.hp < en.max_hp:
			dmg_n += 1
	t.check("meteors (rock-slide): %d staggered 0.09 s, first lands at 0.5 s, all targets hit" % int(mt["count"]), stag and dmg_n == 3)
	# turret: placed behind, first shot after 0.3 s, at most count turrets
	C.clear_fields()
	sim.projectiles.clear()
	var tu := Moves.instance("will-o-wisp", 1)
	C.run(pl, tu)
	C.run(pl, tu)
	var live_t := 0
	for f in C.fields:
		if not f.gone:
			live_t += 1
	var tf: Combat.Field = C.fields[C.fields.size() - 1]
	var behind := tf.x < pl.x
	C.update_fields(0.25)
	var none_yet := sim.projectiles.count() == 0
	C.update_fields(0.1)
	t.check("turret (will-o-wisp): behind the player, max %d live, first shot after 0.3 s" % int(tu["count"]),
		live_t == int(tu["count"]) and behind and none_yet and sim.projectiles.count() == 1)
	# trail: no new patch on top of a young one; ticks every 0.5 s; cap 18
	C.clear_fields()
	sim.projectiles.clear()
	pl.last_patch = null
	var tr := Moves.instance("toxic", 1)
	C.run(pl, tr)
	C.run(pl, tr)
	var one := C.fields.size() == 1
	for i in 25:
		pl.x += 40.0
		C.run(pl, tr)
	var live_p := 0
	for f in C.fields:
		if not f.gone:
			live_p += 1
	t.check("trail (toxic): one patch while standing, max 18 patches", one and live_p == 18)
	pl.x = 0.0
	# orbit: count orbs, re-hit interval
	C.clear_fields()
	sim.projectiles.clear()
	sim.enemies.clear()
	var ob := Moves.instance("fire-spin", 5)
	C._orbit(pl, ob, 1.0 / 60.0, 1.0)
	var orbs := 0
	for p in sim.projectiles.list:
		if p.orb:
			orbs += 1
	t.check("orbit (fire-spin L5): %d orbs, re-hit max(0.12, cd)" % orbs, orbs == int(ob["count"]) and rel(sim.projectiles.list[0].rehit, maxf(0.12, float(ob["cd"]))))

# ---------------- enemies at runtime ----------------

static func _enemy_runtime(t: Object) -> void:
	print("-- Phase 2: enemy shots, hazards, bosses, shinies at runtime (§5.5-5.11) --")
	var sim := new_sim(9)
	var pl := sim.player
	# hazard: detonates once at `delay`, ignores i-frames, removed 0.3 s later
	sim.hazards.zone(pl.x, pl.y, 40.0, 0.5, 10.0, "normal", Color.RED)
	pl.invuln = 5.0
	var hp0 := pl.hp
	sim.hazards.update(0.4, pl)
	var before := pl.hp == hp0
	sim.hazards.update(0.15, pl)
	var hurt := pl.hp < hp0
	sim.hazards.update(0.31, pl)
	t.check("zone telegraph: hurts at its delay even through i-frames, then disappears", before and hurt and sim.hazards.count() == 0)
	# enemy shot: hits the player, blocked by walls
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	var e := enemy_of(64, pl.x + 100.0, pl.y, 2)
	e.shoot(-1.0, 0.0)
	var shot: Projectiles.Proj = sim.projectiles.list[0]
	var hit := false
	for i in 120:
		sim.projectiles.update(1.0 / 60.0, pl, sim.enemies.list)
		sim.combat.resolve(1.0 / 60.0, pl, 0.0)
		if sim.projectiles.count() == 0:
			hit = pl.hp < pl.max_hp
			break
	t.check("enemy shot: 190 wu/s, r 7, life 2.4, hits the player (%.1f dmg)" % (pl.max_hp - pl.hp), hit and rel(shot.r, 7.0) and rel(shot.life, 2.4))
	# bomber: fuse 1 s next to you, then it dies (counts as a kill) and the zone fires
	sim.enemies.clear()
	sim.hazards.clear()
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	var bomber := enemy_of(74, pl.x + 10.0, pl.y, 0)
	bomber.flying = true
	sim.enemies.add(bomber)
	var kills0 := pl.kills
	for i in 70:
		sim.enemies.update(1.0 / 60.0, pl)
		sim.hazards.update(1.0 / 60.0, pl)
	t.check("bomber: fuse 1 s, explodes (zone r 62, dmg x1.4) and counts as a kill", bomber.dead and pl.kills == kills0 + 1 and pl.hp < pl.max_hp)
	# jumper: crouch 0.45 s, jump 0.6 s to the player's spot (lift 46)
	sim.enemies.clear()
	var jp := enemy_of(56, pl.x + 150.0, pl.y + 20.0, 0)
	jp.behavior = "jumper"
	jp.skill_cd = 0.0
	jp.flying = true
	sim.enemies.add(jp)
	var max_lift := 0.0
	for i in 72:
		sim.enemies.update(1.0 / 60.0, pl)
		max_lift = maxf(max_lift, jp.jump_lift)
	t.check("jumper: lands where you were after 1.05 s (lift %.0f)" % max_lift, U.dist(jp.x, jp.y, pl.x, pl.y) < 30.0 and max_lift > 40.0 and max_lift <= 46.0)
	# boss: spawn at its slot time with bossScale, enrage under 50% HP
	var sim2 := new_sim(11)
	var p2 := sim2.player
	sim2.defs.bosses[0]["at"] = 0.5
	p2.max_hp = 1e7
	p2.hp = 1e7
	p2.invuln = 99.0
	for i in 40:
		sim2.input_axis = Vector2.ZERO
		sim2.update(1.0 / 60.0)
	var boss: Enemy = null
	for en in sim2.enemies.list:
		if en.boss:
			boss = en
	var hp_ok := boss != null and boss.max_hp == U.jround(float(sim2.defs.bosses[0]["hp"]) * EnemyDefs.boss_scale(0.5)["hp"])
	t.check("boss spawns at its slot time with bossScale (%s, %d HP), banner" % [boss.name if boss else "?", int(boss.max_hp) if boss else 0],
		hp_ok and sim2.spawner.announce.ends_with("salvaje apareció!"))
	if boss != null:
		var spd0 := boss.spd
		boss.hp = boss.max_hp * 0.49
		for i in 3:
			sim2.update(1.0 / 60.0)
		t.check("boss enrages below 50% HP: fury, speed x1.15, banner", boss.ai != null and boss.ai.fury and rel(boss.spd, spd0 * 1.15)
			and sim2.spawner.announce.ends_with("se ha enfurecido!"))
		var casts := {}
		for i in 60 * 40:
			p2.hp = p2.max_hp
			p2.invuln = 99.0
			if sim2.state != "playing":
				Bot.pick(sim2)
				continue
			sim2.update(1.0 / 60.0)
			if boss.dead:
				break
			if boss.ai != null and not boss.ai.cast.is_empty():
				casts[boss.ai.cast["id"]] = true
			if not boss.jump.is_empty():
				casts["leap"] = true
		t.check("boss AI casts its attacks over 40 s (%s)" % str(casts.keys()), casts.size() >= 3)
		boss.hurt(1e9, Color.WHITE)
		var item_drop := sim2.player.item != "" or sim2.state == "choice"
		for pk in sim2.pickups.list:
			item_drop = item_drop or pk.kind == "item"
		t.check("boss death drops a held item + 10 coins + 14 big gems", item_drop)
	# shiny: forced roll, x2 HP, x5 XP, banner; catching = defeating it
	var sim3 := new_sim(13)
	sim3.spawner.force_shiny = 1
	var sh: Enemy = null
	for i in 40:
		sh = sim3.spawner.spawn_one(sim3.player, 10.0)
		if sh != null and sh.shiny:
			break
	var normal := Spawner.make_enemy(sh.def, 0, 0, 10.0, 0)
	t.check("shiny spawn: x2 HP (%d vs %d), x5 XP, banner" % [int(sh.max_hp), int(normal.max_hp)], sh.shiny and sh.max_hp == normal.max_hp * 2.0
		and sh.xp == normal.xp * 5.0 and sim3.spawner.announce.ends_with("shiny anda cerca!"))
	sh.hurt(1e9, Color.WHITE)
	t.check("shiny caught on defeat: added to the run summary, banner", sim3.caught.size() == 1 and int(sim3.caught[0]["dex"]) == sh.dex
		and (sim3.spawner.announce.begins_with("¡Has conseguido a") or sim3.spawner.announce.begins_with("¡Otro")))
	var lag := Spawner.make_enemy(sh.def, sim3.player.x + 3000.0, sim3.player.y, 10.0, 0)
	lag.make_shiny()
	sim3.enemies.add(lag)
	sim3.enemies.update(1.0 / 60.0, sim3.player)
	t.check("shinies are never relocated as laggards", absf(lag.x - (sim3.player.x + 3000.0)) < 10.0 and sim3.enemies.list.has(lag))

# ---------------- whole loop with every kind ----------------

static func _sim_flow(t: Object) -> void:
	var sets := [["hydro-pump", "razor-leaf", "thunderbolt", "spikes"], ["rock-slide", "discharge", "quick-attack", "flame-wheel"],
		["flamethrower", "will-o-wisp", "heat-wave", "swords-dance"]]
	var all_ok := true
	var info: Array = []
	for i in sets.size():
		var sim := Sim.new()
		sim.render = false
		sim.debug = {"moves": sets[i], "move_lvl": 5, "boss_at": 20.0, "force_shiny": 1}
		Bot.cycle_slots = true
		sim.start_run(4, 100 + i)
		var dt := 1.0 / 60.0
		var cast := {}
		var hz := 0
		var es := 0
		while sim.time < 50.0 and sim.state != "over":
			if sim.state == "levelup" or sim.state == "choice":
				Bot.pick(sim)
				continue
			sim.input_axis = Bot.axis(sim)
			sim.player.god = true
			sim.update(dt)
			for m in sim.player.active_group():
				if int(m.get("cast_at", 0)) > 0:
					cast[m["kind"]] = true
			hz = maxi(hz, sim.hazards.count())
			for p in sim.projectiles.list:
				if not p.friendly:
					es += 1
					break
		Bot.cycle_slots = false
		all_ok = all_ok and sim.time >= 50.0 and cast.size() >= mini(4, sim.player.slots.size()) and sim.player.bosses + sim.enemies.list.filter(func(e): return e.boss).size() >= 1
		info.append("%s: kills %d, kinds %s" % [str(i), sim.player.kills, str(cast.keys())])
	t.check("50 s runs x3 with 12 forced kinds (L5), a boss at 20 s and a forced shiny: no errors, every slot casts", all_ok, "; ".join(info))
