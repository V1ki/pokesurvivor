extends SceneTree
## Headless unit tests. Run from the repo root:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exit code 0 = all passed. Reference values come from PORTING.md (§3.8, §5.2, §5.3,
## §10.4, §11.7) and from data/test_vectors.json (computed by the JS code itself in
## tools/export_godot.js).

var passes := 0
var fails := 0

func _initialize() -> void:
	seed(20261013)                 # reproducible randomness (Math.random equivalent)
	Data.ensure()
	print("== PokeSurvivor Godot port - unit tests ==")
	test_hash()
	test_mulberry()
	test_terrain()
	test_xp()
	test_spawn_rate()
	test_enemy_multipliers()
	test_enemy_defs()
	test_moves()
	test_types()
	test_swept_collision()
	test_levelup_offer()
	test_short_sim()
	Phase2Tests.run(self)                # combat completeness (tests/phase2_tests.gd)
	Phase4Tests.new().run(self)          # meta-progression (tests/phase4_tests.gd)
	Phase3Tests.run(self)                # world visuals & terrain (tests/phase3_tests.gd)
	Phase3bTests.run(self)               # interactables, events, rifts, bonds (tests/phase3b_tests.gd)
	I18nTests.new().run(self)            # languages vs js/core/i18n.js (tests/i18n_tests.gd)
	AudioTests.run(self)                 # pre-rendered audio + sfx() limiter (tests/audio_tests.gd)
	ParityTests.run(self)                # rules fixed by the parity audit (tests/parity_tests.gd, docs/PARITY.md)
	print("== %d passed, %d failed ==" % [passes, fails])
	quit(1 if fails > 0 else 0)

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("  PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		fails += 1
		print("  FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")

static func near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

## IEEE-754 bits as little-endian hex (JSON doubles are not parsed exactly by Godot).
static func bits(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.hex_encode()

## Relative comparison for values derived from JSON data (1-2 ulp parse error).
static func rel(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-12 * maxf(1.0, absf(b))

# ---------------- §10.4 hash / RNG ----------------

func test_hash() -> void:
	print("-- hash01 (G.U.hash) --")
	var spec := [[0, 0, 0, 0.0], [1, 0, 0, 0.5081244609], [5, -3, 4242, 0.0931424084], [25, 7, 11, 0.3687830963],
		[-17, 123, 909, 0.5947388003], [1000, 7, 11, 0.0754888116], [123456, -654321, 2246822519, 0.7198840545]]
	for v in spec:
		var h := U.hash01(v[0], v[1], v[2])
		check("hash(%d,%d,%d) = %.10f (spec)" % [v[0], v[1], v[2], v[3]], near(h, v[3], 5e-11), "%.10f" % h)
	for v in Data.test_vectors.get("hash", []):
		var h := U.hash01(int(v["x"]), int(v["y"]), int(v["seed"]))
		check("hash(%d,%d,%d) bit-exact vs JS" % [int(v["x"]), int(v["y"]), int(v["seed"])], bits(h) == v["bits"],
			"uint32 %d" % int(h * 4294967296.0))
	# the uint32 behind the float must match exactly too
	check("imul32 wraps like Math.imul", U.imul32(0x7fffffff, 3) == 0x7ffffffd and U.imul32(-1, -1) == 1)

class Mulberry:
	var h: int
	func _init(seed_str: String) -> void:
		h = 2166136261
		for c in seed_str.to_utf8_buffer():
			h = U.imul32(h ^ c, 16777619)
	func next() -> float:
		h = (h + 0x6D2B79F5) & U.M32
		var t := h
		t = U.imul32(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + U.imul32(t ^ (t >> 7), t | 61)) & U.M32)) & U.M32
		return float((t ^ (t >> 14)) & U.M32) / 4294967296.0

func test_mulberry() -> void:
	print("-- mission RNG (FNV-1a + mulberry32) --")
	var r := Mulberry.new("d20261013" + "1700000000000")
	var spec := [0.4235570813, 0.6687115475, 0.4403369226]
	var got: Array = []
	for i in 5:
		got.append(r.next())
	for i in 3:
		check("mulberry[%d] = %.10f (spec)" % [i, spec[i]], near(got[i], spec[i], 5e-11), "%.10f" % got[i])
	var js: Array = Data.test_vectors.get("mulberry", {}).get("bits", [])
	var exact := js.size() == 5
	for i in js.size():
		exact = exact and bits(got[i]) == js[i]
	check("mulberry 5 values bit-exact vs JS", exact)

# ---------------- §7.2 terrain ----------------

func test_terrain() -> void:
	print("-- terrainRaw vs JS world.js dump --")
	var dumps: Array = Data.test_vectors.get("terrain", [])
	if dumps.is_empty():
		check("terrain dump present", false, "re-run tools/export_godot.js")
		return
	for d in dumps:
		var w := WorldMap.new()
		w.reset(int(d["seed"]))
		var x0 := int(d["x0"])
		var y0 := int(d["y0"])
		var rows: Array = d["rows"]
		var bad := 0
		var counts := {"f": 0, "w": 0, "l": 0}
		for j in rows.size():
			var row: String = rows[j]
			for i in row.length():
				var k := "fwl"[w.terrain_at(x0 + i, y0 + j)]
				counts[row[i]] += 1
				if k != row[i]:
					bad += 1
		check("seed %d tiles (%d,%d) %dx%d identical" % [int(d["seed"]), x0, y0, rows.size(), rows.size()], bad == 0,
			"%d mismatches; floor %d wall %d liquid %d" % [bad, counts["f"], counts["w"], counts["l"]])

# ---------------- §3.8 XP curve ----------------

func test_xp() -> void:
	print("-- XP curve (§3.8) --")
	var cum := 0
	var to_lvl := {}
	for l in range(1, 61):
		cum += Player.xp_for(l)
		to_lvl[l + 1] = cum
	check("cumulative XP to reach level 5 = 510", to_lvl[5] == 510, str(to_lvl[5]))
	check("cumulative XP to reach level 6 = 768", to_lvl[6] == 768, str(to_lvl[6]))
	check("xpFor(1/2/3/5/10/60) = 62/101/147/258/631/9750",
		Player.xp_for(1) == 62 and Player.xp_for(2) == 101 and Player.xp_for(3) == 147 and Player.xp_for(5) == 258 \
		and Player.xp_for(10) == 631 and Player.xp_for(60) == 9750)
	check("cumulative to 11/21/61 = 3128/15087/230586", to_lvl[11] == 3128 and to_lvl[21] == 15087 and to_lvl[61] == 230586)
	var js: Array = Data.test_vectors.get("xp_for", [])
	var same := js.size() == 60
	for i in js.size():
		same = same and Player.xp_for(i + 1) == int(js[i])
	check("xpFor(1..60) identical to JS Player.xpFor", same)
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, 1)
	var pl := sim.player
	var lv := pl.gain_xp(509)
	check("gainXp(509) from level 1 -> level 4 (3 level-ups)", pl.level == 4 and lv == 3, "level %d" % pl.level)
	lv = pl.gain_xp(1)
	check("+1 XP -> level 5, xp 0", pl.level == 5 and pl.xp == 0.0 and lv == 1)
	lv = pl.gain_xp(258)
	check("+258 XP -> level 6 (total 768)", pl.level == 6 and lv == 1)

# ---------------- §5.2 spawn rate ----------------

func test_spawn_rate() -> void:
	print("-- spawn rate (§5.2) --")
	var r60 := Spawner.rate(60.0)
	check("rate(60) ~= 0.907 /s", near(r60, 0.907, 0.0005), "%.4f" % r60)
	for v in Data.test_vectors.get("spawn_rate", []):
		check("rate(%d) bit-exact vs JS" % int(v["t"]), bits(Spawner.rate(float(v["t"]))) == v["bits"], "%.6f /s" % Spawner.rate(float(v["t"])))
	check("hpK(0)=3.3, hpK(210)=4.3, hpK(357)=hpK(600)=5.0", near(Spawner.hp_k(0), 3.3, 1e-12) and near(Spawner.hp_k(210), 4.3, 1e-12) \
		and near(Spawner.hp_k(357), 5.0, 1e-12) and near(Spawner.hp_k(600), 5.0, 1e-12))

# ---------------- §5.3 multipliers ----------------

static func r2(x: float) -> float:
	return floor(x * 100.0 + 0.5) / 100.0

static func r1(x: float) -> float:
	return floor(x * 10.0 + 0.5) / 10.0

func test_enemy_multipliers() -> void:
	print("-- enemy HP / damage / speed multipliers (§5.3) --")
	# t, hp, dmg, spd as printed in the spec (HP with 1 decimal from 3 min on)
	var spec := [[0.0, 3.30, 2.40, 1.00], [60.0, 5.85, 2.74, 1.04], [180.0, 12.0, 3.43, 1.13], [300.0, 19.7, 4.11, 1.21]]
	for s in spec:
		var m := Spawner.spawn_mults(s[0])
		var hp: float = r2(m["hp"]) if s[0] < 120.0 else r1(m["hp"])
		check("t=%3ds  HP x%.2f  dmg x%.2f  spd x%.2f" % [int(s[0]), s[1], s[2], s[3]],
			near(hp, s[1], 1e-9) and near(r2(m["dmg"]), s[2], 1e-9) and near(r2(m["spd"]), s[3], 1e-9),
			"got HP x%.4f dmg x%.4f spd x%.4f" % [m["hp"], m["dmg"], m["spd"]])
	for v in Data.test_vectors.get("enemy_scale", []):
		var sc := EnemyDefs.scale(float(v["t"]))
		var bs := EnemyDefs.boss_scale(float(v["t"]))
		var jb: Dictionary = v["bits"]
		check("scale(%d)/bossScale bit-exact vs JS" % int(v["t"]),
			bits(sc["hp"]) == jb["hp"] and bits(sc["dmg"]) == jb["dmg"] and bits(sc["spd"]) == jb["spd"] \
			and bits(bs["hp"]) == jb["bhp"] and bits(bs["dmg"]) == jb["bdmg"], "hp x%.6f" % sc["hp"])
	# full spawn pipeline on a real def (Charmander, tier 0): HP rounding, DMG_K, XP_K, elite
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, 1)
	var def := EnemyDefs.def_for(Data.dex_by[4], EnemyDefs.tiers()[0], 0)
	for t in [0.0, 60.0, 180.0, 300.0]:
		var m := Spawner.spawn_mults(t)
		var e := Spawner.make_enemy(def, 0, 0, t, 0)
		var ok: bool = e.max_hp == U.jround(def["hp"] * m["hp"]) and near(e.dmg, def["dmg"] * m["dmg"], 1e-9) \
			and near(e.spd, def["spd"] * m["spd"], 1e-9) and e.xp == U.jround(def["xp"] * 5.6)
		check("spawned Charmander t=%ds: HP %d dmg %.2f spd %.1f xp %d" % [int(t), int(e.max_hp), e.dmg, e.spd, int(e.xp)], ok)
	var el := Spawner.make_enemy(def, 0, 0, 60.0, 55)
	var base := Spawner.make_enemy(def, 0, 0, 60.0, 54)
	check("elite at >= 55 alive: HP x1.6, dmg x1.25, XP x1.6", el.max_hp == U.jround(base.max_hp * 1.6) \
		and near(el.dmg, base.dmg * 1.25, 1e-9) and el.xp == U.jround(base.xp * 1.6), "HP %d vs %d" % [int(el.max_hp), int(base.max_hp)])

# ---------------- §5.1 behaviors / defs ----------------

func test_enemy_defs() -> void:
	print("-- enemy behaviors, defs, candidates (§5.1) --")
	var table: Dictionary = Data.enemies["behavior_by_dex"]
	var bad: Array = []
	for p in Data.dex:
		if EnemyDefs.behavior_of(p) != table[str(p["dex"])]:
			bad.append(p["dex"])
	check("behaviorOf matches JS for all %d species" % Data.dex.size(), bad.is_empty(), "mismatch: %s" % str(bad.slice(0, 10)))
	var cbt: Array = Data.enemies["candidates_by_tier"]
	var same := true
	for ti in cbt.size():
		var mine: Array = EnemyDefs.candidates_all(EnemyDefs.tiers()[ti]).map(func(p): return p["dex"])
		var js: Array = cbt[ti].map(func(d): return int(d))
		same = same and mine == js
	check("tier candidates identical to JS (6 tiers)", same)
	var ok := true
	var js_defs: Array = Data.test_vectors.get("def_for_dex4", [])
	for ti in js_defs.size():
		var d := EnemyDefs.def_for(Data.dex_by[4], EnemyDefs.tiers()[ti], ti)
		var j: Dictionary = js_defs[ti]
		for k in j:
			if k == "name" or k == "behavior":
				ok = ok and str(d[k]) == str(j[k])
			else:
				ok = ok and float(d[k]) == float(j[k])
	check("defFor(Charmander, tier 0..5) identical to JS", ok and js_defs.size() == 6)
	check("startMoveOf(4) = ember", Moves.start_move_of(4) == Data.test_vectors.get("start_move_dex4", "") and Moves.start_move_of(4) == "ember")
	# rollRun is random: check its invariants over many rolls
	var sizes_ok := true
	var runner_ok := true
	var all_avail := true
	var support_ok := true
	var runners := 0
	for r in 50:
		var defs := EnemyDefs.new()
		defs.roll_run()
		for ti in defs.cast.size():
			var lst: Array = defs.cast[ti]["list"]
			sizes_ok = sizes_ok and lst.size() == 7
			var n_run := 0
			var n_plain := 0
			var n_sup := 0
			for d in lst:
				all_avail = all_avail and Sprites.available(int(d["dex"]))
				if d["behavior"] == "runner":
					n_run += 1
				elif d["behavior"] in ["chase", "charger", "tank"]:
					n_plain += 1
				elif d["behavior"] in ["healer", "shielder", "summoner"]:
					n_sup += 1
			runners += n_run
			# exactly one runner whenever the tier has a chase/charger/tank (JS: `if (r)`)
			runner_ok = runner_ok and n_run <= 1 and (n_run == 1 or n_plain == 0)
			support_ok = support_ok and n_sup >= 1
	check("rollRun x50: 6 tiers x 7 species, one runner per tier when possible, a support in every tier",
		sizes_ok and runner_ok and support_ok, "%d runners in 300 tiers" % runners)
	check("Phase 1 cast only uses species with sprites present", all_avail)

# ---------------- §4.2 moves ----------------

func test_moves() -> void:
	print("-- move instances / ladders / evolution (§4.2, §4.7) --")
	check("melee load-time buff in data: tackle dmg 16 radius 60 arc 2.13",
		float(Moves.def("tackle")["dmg"]) == 16.0 and float(Moves.def("tackle")["radius"]) == 60.0 and float(Moves.def("tackle")["arc"]) == 2.13)
	for v in Data.test_vectors.get("move_instances", []):
		var m := Moves.instance(v["id"], int(v["lvl"]))
		if v.get("evolved", false):
			Moves.evolve(m)
		var js: Dictionary = v["m"]
		var diff: Array = []
		for k in js:
			if k == "t" or k == "maxLvl" or k == "desc" or k == "baseName":
				continue
			var a: Variant = m.get(k)
			var b: Variant = js[k]
			if b is String or b is bool:
				if str(a) != str(b):
					diff.append(k)
			elif a == null or not rel(float(a), float(b)):
				diff.append("%s %s!=%s" % [k, str(a), str(b)])
		check("instance(%s, %d)%s matches JS" % [v["id"], int(v["lvl"]), " +evolve" if v.get("evolved", false) else ""],
			diff.is_empty(), ", ".join(diff))

func test_types() -> void:
	print("-- type chart (§4.5) --")
	check("fire vs grass = 1.6", near(Types.mult("fire", ["grass"]), 1.6, 1e-12))
	check("fire vs bug/grass = 2.4 (clamped 2.56)", near(Types.mult("fire", ["bug", "grass"]), 2.4, 1e-12))
	check("normal vs ghost = 0.3", near(Types.mult("normal", ["ghost"]), 0.3, 1e-12))
	check("water vs water/dragon = 0.36", near(Types.mult("water", ["water", "dragon"]), 0.36, 1e-12))
	check("labels super/weak", Types.label(1.6) == "super" and Types.label(0.6) == "weak" and Types.label(1.0) == "")

# ---------------- §4.6 swept collision ----------------

func test_swept_collision() -> void:
	print("-- swept projectile collision (§4.6; enemies hugging the player) --")
	for swept in [true, false]:
		var sim := Sim.new()
		sim.render = false
		sim.start_run(4, 1)
		var pl := sim.player
		var def := EnemyDefs.def_for(Data.dex_by[10], EnemyDefs.tiers()[0], 0)   # Caterpie
		var e := Enemy.new(def, pl.x + 6.0, pl.y, {"hp": 1.0, "dmg": 1.0, "spd": 1.0})
		sim.enemies.add(e)
		sim.enemies.rebuild_grid()
		var p := Projectiles.Proj.new()
		p.px = pl.x + 3.0
		p.py = pl.y
		p.x = pl.x + 70.0          # a fast shot already moved past the enemy this frame
		p.y = pl.y
		p.has_prev = swept
		p.vx = 2000.0
		p.r = 5.0
		p.dmg = 1.0
		p.mtype = "electric"
		p.owner = pl
		sim.projectiles.add(p)
		var hp0 := e.hp
		sim.combat.resolve(1.0 / 30.0, pl, 0.0)
		if swept:
			check("fast shot (3 -> 70 wu in one frame) hits enemy at 6 wu (swept)", e.hp < hp0 and sim.projectiles.count() == 0,
				"enemy HP %d -> %d" % [int(hp0), int(e.hp)])
		else:
			check("control: end-point test alone would miss it", e.hp == hp0)
	# end-to-end: real ember casts kill an enemy standing on the player
	var sim2 := Sim.new()
	sim2.render = false
	sim2.start_run(4, 2)
	var pl2 := sim2.player
	var e2 := Enemy.new(EnemyDefs.def_for(Data.dex_by[10], EnemyDefs.tiers()[0], 0), pl2.x + 4.0, pl2.y + 2.0, {"hp": 1.0, "dmg": 0.0, "spd": 0.0})
	sim2.enemies.add(e2)
	var t := 0.0
	while t < 3.0 and not e2.dead:
		sim2.enemies.rebuild_grid()
		pl2.update(1.0 / 60.0)
		sim2.combat.tick(1.0 / 60.0, pl2, t)
		sim2.projectiles.update(1.0 / 60.0, pl2, sim2.enemies.list)
		sim2.combat.resolve(1.0 / 60.0, pl2, t)
		t += 1.0 / 60.0
	check("Ember kills a Caterpie hugging Charmander (end-to-end)", e2.dead, "after %.2f s" % t)

# ---------------- §6 level-up ----------------

func test_levelup_offer() -> void:
	print("-- level-up cards (§6) --")
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, 1)
	var pl := sim.player
	var ok := true
	var kinds_ok := true
	for i in 200:
		var cards := LevelUp.offer(pl)
		var keys := {}
		for c in cards:
			keys[c["key"]] = true
			if c["type"] == "new":
				kinds_ok = kinds_ok and Moves.IMPLEMENTED_KINDS.has(Moves.def(c["key"].substr(4))["kind"])
		ok = ok and cards.size() == 3 and keys.size() == 3
	check("offer(): 3 distinct cards (200 draws)", ok)
	check("new-move cards only offer implemented kinds", kinds_ok)
	for i in 12:
		LevelUp.apply_stat("spd", pl)
		pl.stats_taken["spd"] = int(pl.stats_taken.get("spd", 0)) + 1
	var has_spd := false
	for i in 100:
		for c in LevelUp.offer(pl):
			has_spd = has_spd or c["key"] == "stat:spd"
	check("stat caps: Carrera (max 8) no longer offered after 12", not has_spd)
	pl.moves[0] = Moves.instance("ember", 5)
	pl.slots[0] = [pl.moves[0]]
	pl.stats_taken["atk"] = 1
	var first: Dictionary = LevelUp.offer(pl)[0]
	check("ready evolution -> gold card always first", first["type"] == "evo", str(first["key"]))

# ---------------- short headless run ----------------

func test_short_sim() -> void:
	print("-- 60 s headless run sanity --")
	var sim := Sim.new()
	sim.render = false
	sim.start_run(4, 4242)
	var dt := 1.0 / 60.0
	var picks := 0
	for i in 3600:
		sim.input_axis = Bot.axis(sim)
		if sim.state == "levelup" or sim.state == "choice":
			Bot.pick(sim)
			picks += 1
		sim.update(dt)
		if sim.state == "over":
			break
	check("60 s simulated without errors", sim.time > 59.0 or sim.state == "over", "t=%.1f state=%s" % [sim.time, sim.state])
	check("enemies spawned and died, XP leveled", sim.player.kills > 0 and sim.player.level > 1,
		"kills %d level %d picks %d alive %d" % [sim.player.kills, sim.player.level, picks, sim.enemies.count()])
