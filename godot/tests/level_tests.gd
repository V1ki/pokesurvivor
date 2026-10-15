class_name LevelTests
extends RefCounted
## Wild Pokémon levels (sim/enemy_defs.gd "wild levels", the game's enemy model since 2026-10-15),
## called from run_tests.gd with `LevelTests.run(self)`. Reference values come from
## data/test_vectors_levels.json, computed by js/data/enemies.js (MODE 'level') in
## tools/export_godot.js; then a live run in level mode. Leaves EnemyDefs in the mode it found.

static func run(t: Object) -> void:
	print("-- wild Pokémon levels (js/data/enemies.js MODE 'level') --")
	var V: Dictionary = Data._json("test_vectors_levels.json") if FileAccess.file_exists("res://data/test_vectors_levels.json") else {}
	if V.is_empty():
		t.check("test_vectors_levels.json present", false, "run: node tools/export_godot.js")
		return
	var was := EnemyDefs.mode
	EnemyDefs.set_mode("level")
	_numbers(t, V)
	_appear(t, V)
	_tiers(t, V)
	_curve(t, V)
	_defs(t, V)
	_bosses(t, V)
	_live(t)
	EnemyDefs.set_mode(was)

static func _near(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 1e-6 * maxf(1.0, absf(float(b)))
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _near(a[i], b[i]):
				return false
		return true
	return str(a) == str(b)

static func _numbers(t: Object, V: Dictionary) -> void:
	var js: Dictionary = V["lv_defaults"]
	var bad: Array = []
	for k in js:
		if not EnemyDefs.LV_DEFAULTS.has(k) or not _near(EnemyDefs.LV_DEFAULTS[k], js[k]):
			bad.append(k)
	for k in EnemyDefs.LV_DEFAULTS:
		if not js.has(k):
			bad.append(k)
	t.check("LV_DEFAULTS == G.Enemies.LV_DEFAULTS (%d numbers)" % js.size(), bad.is_empty(), str(bad))
	var exp: Dictionary = Data.enemies.get("levels", {})
	var same := exp.size() == js.size()
	for k in js:
		same = same and exp.has(k) and _near(exp[k], js[k])
	t.check("data/enemies.json: the game's mode is 'level', with the same numbers",
		str(Data.enemies.get("mode", "")) == "level" and same)

static func _appear(t: Object, V: Dictionary) -> void:
	var bad: Array = []
	for r in V["appear"]:
		var a := EnemyDefs.appear_level(int(r[0]))
		var l := EnemyDefs.leave_level(int(r[0]))
		if not _near(a, r[1]) or not _near(l, r[2]):
			bad.append("%d: %s/%s vs %s/%s" % [int(r[0]), a, l, r[1], r[2]])
	t.check("appear / leave level of all %d species" % V["appear"].size(), bad.is_empty(), str(bad.slice(0, 4)))

static func _tiers(t: Object, V: Dictionary) -> void:
	var ts := EnemyDefs.tiers()
	var ok: bool = ts.size() == V["tiers"].size()
	var detail := ""
	for i in mini(ts.size(), V["tiers"].size()):
		var js: Dictionary = V["tiers"][i]
		var mine: Array = EnemyDefs.candidates_all(ts[i]).map(func(p): return int(p["dex"]))
		var theirs: Array = (js["dex"] as Array).map(func(d): return int(d))
		if not _near(ts[i]["from"], js["from"]) or not _near(ts[i]["lv"], js["lv"]) or mine != theirs:
			ok = false
			detail += "group %d: from %s/%s, %d/%d species; " % [i, ts[i]["from"], js["from"], mine.size(), theirs.size()]
	t.check("cast groups: start time, level band and candidates (%d groups)" % ts.size(), ok, detail)

static func _curve(t: Object, V: Dictionary) -> void:
	var bad: Array = []
	for r in V["curve"]:
		if not _near(EnemyDefs.wild_level(float(r[0])), r[1]):
			bad.append("wild_level(%s)=%s vs %s" % [r[0], EnemyDefs.wild_level(float(r[0])), r[1]])
	for r in V["time_of"]:
		if not _near(EnemyDefs.time_of_level(float(r[0])), r[1]):
			bad.append("time_of_level(%s)=%s vs %s" % [r[0], EnemyDefs.time_of_level(float(r[0])), r[1]])
	t.check("level curve and its inverse (%d points)" % (V["curve"].size() + V["time_of"].size()), bad.is_empty(), str(bad.slice(0, 4)))
	var hb: Array = []
	for r in V["horde_types"]:
		if JSON.stringify(EnemyDefs.horde_types(float(r[0]))) != JSON.stringify(r[1]):
			hb.append("t=%s: %s vs %s" % [r[0], EnemyDefs.horde_types(float(r[0])), r[1]])
	t.check("horde types at %d times (only forms already out at that level)" % V["horde_types"].size(), hb.is_empty(), str(hb.slice(0, 2)))

static func _row(d: Dictionary) -> Array:
	return [int(d["dex"]), d["behavior"], int(d["level"]), d["hp"], d["dmg"], d["spd"], d["xp"], d.get("shotDmg", null), d["appear"], d["leave"]]

static func _defs(t: Object, V: Dictionary) -> void:
	var ts := EnemyDefs.tiers()
	for g in V["defs"]:
		var ti := int(g["ti"])
		var bad: Array = []
		for rows in g["rows"]:
			var dex := int(rows[0][0])
			var d := EnemyDefs.def_for(Data.dex_by[dex], ts[ti], ti)
			var mine := [_row(d)]
			for l in [1.0, 17.0, 60.0]:
				mine.append(_row(EnemyDefs.at_level(d, l)))
			if not _near(mine, rows):
				bad.append("%d: %s vs %s" % [dex, str(mine[1]), str(rows[1])])
		t.check("def_for + at_level (Lv 1 / 17 / 60) of all %d species, group %d" % [g["rows"].size(), ti], bad.is_empty(), str(bad.slice(0, 3)))

static func _bosses(t: Object, V: Dictionary) -> void:
	var slots: Array = Data.enemies["boss_slots"]
	var bad: Array = []
	for b in V["bosses"]:
		var js: Dictionary = b["def"]
		var mine := EnemyDefs.boss_def(slots[int(b["slot"])], Data.dex_by[int(js["dex"])])
		for k in js:
			if not mine.has(k) or not _near(mine[k], js[k]):
				bad.append("slot %d %s.%s: %s vs %s" % [int(b["slot"]), js["name"], k, mine.get(k), js[k]])
	t.check("boss_def of %d rolled bosses (level, HP, damage...)" % V["bosses"].size(), bad.is_empty(), str(bad.slice(0, 3)))

## A live run: every wild one carries a level near the wild level, bosses wild + boss_lv.
static func _live(t: Object) -> void:
	var sim := Sim.new()
	sim.render = false
	sim.debug = {"boss_at": 50.0}
	sim.start_run(4, 777)
	var dt := 1.0 / 60.0
	var off: Array = []
	var seen := 0
	var boss_lv := -1
	for i in 3600 * 2:
		sim.input_axis = Bot.axis(sim)
		if sim.state == "levelup" or sim.state == "choice":
			Bot.pick(sim)
		sim.update(dt)
		if sim.state == "over":
			break
		if i % 60 == 0:
			var wl := EnemyDefs.wild_level(sim.time)
			for e in sim.enemies.list:
				if e.boss:
					boss_lv = int(e.def.get("level", -1))
				elif e.def.has("bhp") and e.def.get("behavior", "") != "thief":
					seen += 1
					var l := int(e.def.get("level", -100))
					# spawned up to a minute ago at ± spread
					if l < int(EnemyDefs.wild_level(maxf(0.0, sim.time - 60.0))) - int(EnemyDefs.LV["spread"]) - 1 or l > int(wl) + int(EnemyDefs.LV["spread"]):
						off.append("%s Lv%d at %.0fs (wild %.1f)" % [e.name, l, sim.time, wl])
	t.check("live level-mode run: wild ones carry their level", seen > 50 and off.is_empty(),
		"%d seen, t=%.0f, off: %s" % [seen, sim.time, str(off.slice(0, 3))])
	var want := int(EnemyDefs.wild_level(50.0) + float(EnemyDefs.LV["boss_lv"]))
	t.check("live level-mode run: the boss comes at wild level + boss_lv", boss_lv >= want and boss_lv <= want + 1,
		"boss Lv%d, expected %d" % [boss_lv, want])
