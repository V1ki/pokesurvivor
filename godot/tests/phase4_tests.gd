class_name Phase4Tests
extends RefCounted
## Meta-progression tests (Phase 4), called from tests/run_tests.gd. Reference values come from
## data/test_vectors_p4.json, computed by the unchanged JS (db.js, gacha.js, progress.js, ranking.js,
## upgrades.js, achievements.js, starters.js) in tools/export_godot.js; the real web save used as a
## fixture is tests/fixtures/web_guest_save.json. The player's own save is never touched
## (Save.path is redirected to user://tests/).

var t: Object          # the SceneTree test runner (check())
var V: Dictionary = {}

func run(runner: Object) -> void:
	t = runner
	var txt := FileAccess.get_file_as_string("res://data/test_vectors_p4.json")
	V = JSON.parse_string(txt) if txt != "" else {}
	if V.is_empty():
		t.check("phase 4 vectors present (node tools/export_godot.js)", false)
		return
	DirAccess.make_dir_recursive_absolute("user://tests")
	var old_path := Save.path
	Save.path = "user://tests/save_test.json"
	test_save()
	test_coins()
	test_upgrades()
	test_gacha()
	test_missions()
	test_achievements()
	test_personality()
	test_import_path()
	Save.path = old_path
	Save.loaded = false
	Save.data = {}
	Progress.now_override = -1

func check(name: String, ok: bool, detail := "") -> void:
	t.check(name, ok, detail)

## Deep equality of JSON-like values; numbers compare by value (int vs float), keys as strings.
static func deq(a: Variant, b: Variant, path := "") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if float(a) == float(b) else "%s: %s != %s" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		for k in b:
			if not (a as Dictionary).has(str(k)) and not (a as Dictionary).has(k):
				return "%s.%s missing" % [path, k]
		for k in a:
			if not (b as Dictionary).has(str(k)):
				return "%s.%s extra" % [path, k]
			var e := deq(a[k], b[str(k)], path + "." + str(k))
			if e != "":
				return e
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: size %d != %d" % [path, a.size(), b.size()]
		for i in a.size():
			var e := deq(a[i], b[i], "%s[%d]" % [path, i])
			if e != "":
				return e
		return ""
	if a == null and b == null:
		return ""
	if typeof(a) != typeof(b):
		return "%s: type %s vs %s (%s / %s)" % [path, type_string(typeof(a)), type_string(typeof(b)), a, b]
	return "" if a == b else "%s: %s != %s" % [path, a, b]

# ---------------- save ----------------

func test_save() -> void:
	print("-- save: newSave / migrate / sanitize (db.js) --")
	var ns := Save.new_save("x")
	check("newSave keys and order identical to JS", deq(ns.keys(), V["save"]["new_save_keys"]) == "" and \
		deq((ns["stats"] as Dictionary).keys(), V["save"]["new_save_stats"]) == "")
	var fx: Dictionary = V["save"]["fixture"]
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/web_guest_save.json")
	var parsed: Variant = Save.parse(raw)
	check("fixture (real web guest save) parses", parsed is Dictionary)
	# the first v3 -> v4 migration stamps stats.famAt with "now": the JS vectors' fixed one
	Save.now_override = int(V["save"].get("now", -1))
	var out := Save.migrate(parsed, "Invitado")
	var e := deq(out, fx["output"])
	check("migrate(real web save) == JS migrate (deep, every field)", e == "", e)
	# 716 coins + 1950 back for its Veto levels (refunded the first time it moves to families)
	check("fixture: 48 Pokémon, 716 + 1950 (Veto refund) coins, partner 936, created kept",
		(out["owned"] as Dictionary).size() == 48 and int(out["coins"]) == 2666 \
		and int(out["partner"]) == 936 and int(out["created"]) == 1791894369798)
	# round trip: stringify -> parse -> migrate is stable and ints stay ints
	var again := Save.migrate(Save.parse(JSON.stringify(out)), "Invitado")
	e = deq(again, fx["output"])
	check("save JSON round trip (stringify/parse/migrate) is lossless", e == "" and again["created"] is int and again["coins"] is int, e)
	check("serialized ints have no '.0' (web game reads them back as-is)", not JSON.stringify(again).contains(".0,"))
	var lg := Save.migrate(Save.parse(JSON.stringify(V["save"]["legacy"]["input"])), "")
	e = deq(lg, V["save"]["legacy"]["output"])
	check("migrate(legacy v1 save: pity number, account upgrades, bad dex/keys/moves/levels) == JS", e == "", e)
	var lg2 := Save.migrate(Save.parse(JSON.stringify(lg)), "")
	e = deq(lg2, V["save"]["legacy"]["again"])
	check("migrating a v4 save again changes nothing (== JS, trainer / families kept)", e == "" and deq(lg2, lg) == "", e)
	Save.now_override = -1

# ---------------- coins ----------------

func test_coins() -> void:
	print("-- end-of-run coins (game.js endRun) --")
	var ok := true
	var det := ""
	for c in V["coins"]:
		var r := Meta.run_coins(float(c["time"]), int(c["kills"]), int(c["bosses"]), int(c["picked"]), float(c["mul"]))
		if int(r["coins"]) != int(c["coins"]) or r["breakdown"] != c["breakdown"]:
			ok = false
			det = "%s -> %d '%s' (JS %d '%s')" % [c, r["coins"], r["breakdown"], c["coins"], c["breakdown"]]
	check("coins formula + breakdown text identical to JS (%d cases)" % V["coins"].size(), ok, det)

# ---------------- upgrades ----------------

func test_upgrades() -> void:
	print("-- per-Pokémon upgrades (upgrades.js) --")
	var ok := true
	var n := 0
	var det := ""
	for id in V["upgrades"]["cost"]:
		var js: Array = V["upgrades"]["cost"][id]
		for l in js.size():
			n += 1
			if Upgrades.cost(id, l) != int(js[l]):
				ok = false
				det = "%s lvl %d: %d vs %d" % [id, l, Upgrades.cost(id, l), int(js[l])]
	check("cost(id, lvl) identical to JS for all 13 upgrades (%d prices)" % n, ok and n == 90, det)
	var total := 0
	for l in 10:
		total += Upgrades.cost("hp", l)
	check("spec table: Vitality 60..890, total 3270", Upgrades.cost("hp", 0) == 60 and Upgrades.cost("hp", 9) == 890 and total == 3270)
	ok = true
	for p in V["upgrades"]["perks"]:
		var g := Upgrades.perks(p["levels"])
		var e := ""
		for k in p["perks"]:
			if absf(float(g[k]) - float(p["perks"][k])) > 1e-12:
				e = "%s %s vs %s" % [k, g[k], p["perks"][k]]
		if e != "":
			ok = false
			det = e
	check("perks(levels) identical to JS (clamped to max, negatives 0)", ok, det)

# ---------------- gacha ----------------

func test_gacha() -> void:
	print("-- gacha (gacha.js): pools, seeded pulls, pity, guarantee, odds --")
	var ok := true
	for g in V["gacha_pools"]:
		for r in 5:
			ok = ok and Gacha.pool(r + 1, int(g)).size() == int(V["gacha_pools"][g][r])
	check("pool sizes per banner and rarity identical to JS (9 x 5)", ok)
	ok = true
	for g in V["gacha_featured"]:
		ok = ok and deq(Gacha.featured(int(g)), V["gacha_featured"][g]) == ""
	check("featured(gen) (top-3 5* by BST) identical to JS", ok)
	for c in V["gacha"]:
		var s := _gsave()
		var rng := Progress.Rng.new(str(c["seed"]))
		var rnd := func() -> float: return rng.next()
		var steps: Array = []
		for k in 6:
			steps.append(Gacha.pull(s, int(c["n"]), int(c["gen"]), str(c["use"]), rnd))
		# JS returns null when unaffordable; we return []
		var js_steps: Array = c["results"].map(func(x): return [] if x == null else x)
		var e := deq(steps, js_steps)
		if e == "":
			e = deq(s["pity"], c["pity"])
		if e == "" and int(s["coins"]) != int(c["coins"]):
			e = "coins %d vs %d" % [s["coins"], c["coins"]]
		if e == "":
			e = deq(s["tickets"], c["tickets"])
		var owned: Array = (s["owned"] as Dictionary).keys().map(func(k): return int(k))
		owned.sort()
		if e == "":
			e = deq(owned, c["owned"])
		check("seeded pulls bit-identical to JS: seed %s, banner %d, x%d (%s) x6" % [c["seed"], c["gen"], c["n"], c["use"]], e == "", e)
	# shiny swap / turn-normal paths
	var gs: Dictionary = V["gacha_shiny"]
	var s2 := _gsave()
	s2["tickets"]["t1"] = 3000
	for p in Data.dex:
		if int(p["gen"]) == 1 and int(p["dex"]) % 2 == 1 and Sprites.has_shiny(int(p["dex"])):
			s2["shiny"][str(p["dex"])] = {"at": 1, "from": "gacha"}
	var rng2 := Progress.Rng.new("g-shiny")
	var rnd2 := func() -> float: return rng2.next()
	var res: Array = []
	for k in int(gs["pulls"]):
		res.append_array(Gacha.pull(s2, 1, 1, "t1", rnd2))
	var sh := res.filter(func(r): return r["shiny"])
	var e2 := deq(sh, gs["shinies"])
	check("1000 seeded pulls with owned shinies (swap / no repeats) identical to JS", e2 == "" and int(s2["coins"]) == int(gs["coins"]) \
		and (s2["shiny"] as Dictionary).size() == int(gs["shiny_n"]), e2)
	# pity: an RNG that never rolls a 5* still gets one at pull 70; pity is per banner
	var s3 := _gsave()
	s3["pity"] = {}
	s3["tickets"]["t1"] = 100
	var low := func() -> float: return 0.0
	var first5 := -1
	for i in 75:
		var r: Array = Gacha.pull(s3, 1, 3, "t1", low)
		if int(r[0]["rarity"]) == 5 and first5 < 0:
			first5 = i + 1
	check("pity: with no luck the 70th pull on a banner is 5* and resets the counter", first5 == 70 and int(s3["pity"]["3"]) == 5)
	# x10 guarantee: with no luck the 10th card is >= 4*
	var s4 := _gsave()
	var r10 := Gacha.pull(s4, 10, 2, "t1", low)
	var best := 0
	for i in 9:
		best = maxi(best, int(r10[i]["rarity"]))
	check("x10 guarantee: 9 commons then a 4*+ card", best == 1 and int(r10[9]["rarity"]) >= 4)
	check("costs: x1 = 1 ticket, x10 = 10 tickets or 1 x10 ticket, unaffordable -> []",
		Gacha.cost_of({"tickets": {"t1": 9, "t10": 0}}, 10, "t1").is_empty() and Gacha.cost_of({"tickets": {"t1": 0, "t10": 1}}, 10, "t10")["t10"] == 1 \
		and Gacha.pull({"tickets": {"t1": 0, "t10": 0}}, 1, 1).is_empty())
	# statistical: rarity odds over 200k single rolls, shiny rate over 100k pulls
	var cnt := [0, 0, 0, 0, 0, 0]
	var rr := RandomNumberGenerator.new()
	rr.seed = 4242
	var rf := func() -> float: return rr.randf()
	var N := 200000
	for i in N:
		cnt[Gacha.roll_rarity(rf)] += 1
	var exp := [0.0, 45.0, 30.0, 17.0, 6.5, 1.5]
	var stat_ok := true
	var det := ""
	for r in range(1, 6):
		var pct: float = 100.0 * cnt[r] / N
		det += "%d*: %.2f%% " % [r, pct]
		stat_ok = stat_ok and absf(pct - exp[r]) < 0.35
	check("rarity odds over 200k rolls ~ 45/30/17/6.5/1.5 %", stat_ok, det)
	var g4 := [0, 0, 0, 0, 0, 0]
	for i in 100000:
		g4[Gacha.roll_rarity(rf, 4)] += 1
	check("x10 guarantee roll: 4* 81.25% / 5* 18.75%", absf(g4[4] / 1000.0 - 81.25) < 0.5 and absf(g4[5] / 1000.0 - 18.75) < 0.5,
		"%.2f / %.2f" % [g4[4] / 1000.0, g4[5] / 1000.0])
	var shinies := 0
	var fives := 0
	var pulls := 0
	var s5 := _gsave()
	for i in 5000:
		if i % 7 == 0:          # fresh shiny collection now and then: duplicates would turn normal
			var keep: Dictionary = s5["pity"]
			s5 = _gsave()
			s5["pity"] = keep
			s5["tickets"]["t1"] = 100000
		for r in Gacha.pull(s5, 10, 1 + i % 9, "t1", rf):
			pulls += 1
			if r["shiny"]:
				shinies += 1
			if int(r["rarity"]) == 5:
				fives += 1
	# x10 pulls: base 1.5% + pity (E[pulls to 5*] ~ 43.5) + the 18.75% 5* share of the guarantee card -> ~2.9%
	check("50k x10 pulls: shiny 1/100, effective 5* rate (pity + guarantee) 2.5-3.3%", absf(shinies * 100.0 / pulls - 1.0) < 0.15 and \
		fives * 100.0 / pulls > 2.5 and fives * 100.0 / pulls < 3.3, "shiny %.2f%%, 5* %.2f%%" % [shinies * 100.0 / pulls, fives * 100.0 / pulls])

func _gsave() -> Dictionary:
	var s := Save.new_save("Gacha")
	s["created"] = 1
	s["tickets"] = {"t1": 200, "t10": 3}
	s["owned"] = {"1": {"at": 1, "from": "starter"}, "4": {"at": 1, "from": "gacha"}}
	s["pity"] = {"1": 60, "9": 68}
	return s

# ---------------- missions ----------------

func test_missions() -> void:
	print("-- missions: Madrid period ids, seeded sets (progress.js / ranking.js) --")
	var ok := true
	var det := ""
	for p in V["periods"]:
		var ids := Progress.period_ids(int(p["ms"]))
		if ids["d"] != p["ids"]["d"] or ids["w"] != p["ids"]["w"]:
			ok = false
			det += "%s: %s/%s vs %s/%s; " % [p["iso"], ids["d"], ids["w"], p["ids"]["d"], p["ids"]["w"]]
	check("periodIds (Europe/Madrid, DST switches, ISO weeks/years) for %d instants == JS" % V["periods"].size(), ok, det)
	ok = true
	det = ""
	for m in V["missions"]:
		var s := {"created": int(m["created"])}
		Progress.ensure(s, int(m["ms"]))
		var e := deq(s["missions"]["daily"], m["daily"])
		if e == "":
			e = deq(s["missions"]["weekly"], m["weekly"])
		if e != "":
			ok = false
			det = "%d/%d %s" % [m["ms"], m["created"], e]
	check("generated daily (3) + weekly (2) sets == JS for %d date/account pairs" % V["missions"].size(), ok, det)
	ok = true
	for m in V["mission_text"]:
		var tx := Progress.text({"id": m["id"], "goal": int(m["goal"]), "param": m["param"]})
		if tx != m["text"]:
			ok = false
			det = "%s vs %s" % [tx, m["text"]]
	check("mission texts identical to missions.js (all goals)", ok, det)
	# progress semantics on a live save
	Save.data = Save.new_save("M")
	Save.loaded = true
	Progress.now_override = 1791885600000
	var M: Dictionary = Save.data["missions"]
	Progress.ensure(Save.data)
	M["daily"] = [{"id": "killType", "goal": 2, "param": "fire", "prog": 0, "claimed": false, "told": false},
		{"id": "survive", "goal": 5, "param": null, "prog": 0, "claimed": false, "told": false},
		{"id": "coins", "goal": 100, "param": null, "prog": 0, "claimed": false, "told": false}]
	M["weekly"] = [{"id": "wboss", "goal": 4, "param": null, "prog": 0, "claimed": false, "told": false},
		{"id": "wdaily", "goal": 8, "param": null, "prog": 0, "claimed": false, "told": false}]
	Progress.popups.clear()
	Progress.event("kill", {"types": ["water"], "boss": false, "legend": 0})
	Progress.event("kill", {"types": ["fire", "flying"], "boss": true, "legend": 0})
	Progress.event("kill", {"types": ["fire"], "boss": false, "legend": 0})
	Progress.event("runEnd", {"time": 359.0, "level": 9, "coins": 60, "types": ["fire"], "group": false})
	Progress.event("runEnd", {"time": 200.0, "level": 4, "coins": 50, "types": ["fire"], "group": false})
	var d: Array = M["daily"]
	check("advance: killType counts matching types, survive keeps the max minutes, coins add up, boss counts",
		int(d[0]["prog"]) == 2 and int(d[1]["prog"]) == 5 and int(d[2]["prog"]) == 110 and int(M["weekly"][0]["prog"]) == 1 \
		and Save.stat("bossesTotal") == 1)
	var c0 := int(Save.data["coins"])
	var t0 := int(Save.data["tickets"]["t1"])
	var claimed := Progress.claim(d[0])
	check("claim: reward granted once, missionsDone++, weekly 'wdaily' advances, 'Misión completada' popups queued",
		claimed and not Progress.claim(d[0]) and int(Save.data["coins"]) == c0 + 200 and int(Save.data["tickets"]["t1"]) == t0 + 2 \
		and Save.stat("missionsDone") == 1 and int(M["weekly"][1]["prog"]) == 1 and Progress.popups.size() >= 3)
	check("pending() counts finished unclaimed rewards", Progress.pending() == 2)
	var before: Array = d.map(func(x): return x["id"])
	var rr := Progress.reroll(1)
	check("reroll: once a day, not the claimed one, never one of today's ids",
		rr and not Progress.reroll(2) and not before.slice(1).has(M["daily"][1]["id"]) and M["rerolled"] == true)
	Save.loaded = false

# ---------------- achievements ----------------

func test_achievements() -> void:
	print("-- achievements (achievements.js, progress.js checkAch) --")
	var A: Dictionary = V["achievements"]
	check("127 achievements (40 fixed + 87 legendaries), 21 titles", Progress.ach_list().size() == int(A["count"]) and int(A["count"]) == 127 \
		and Progress.ach_list().filter(func(a): return a.get("title", "") != "").size() == int(A["titles"]))
	var fx_out: Dictionary = V["save"]["fixture"]["output"]
	var ok := true
	var det := ""
	for a in Progress.ach_list():
		var v := Progress.ach_value(a, fx_out)
		if v != int(A["fixture_values"][a["id"]]):
			ok = false
			det = "%s %d vs %d" % [a["id"], v, int(A["fixture_values"][a["id"]])]
	check("value(save) of all 127 on the real web save == JS", ok, det)
	var rich: Dictionary = Save.parse(JSON.stringify(A["rich"]["input"]))
	ok = true
	for a in Progress.ach_list():
		if Progress.ach_value(a, rich) != int(A["rich"]["values"][a["id"]]):
			ok = false
			det = a["id"]
	check("value(save) of all 127 on a rich synthetic save == JS", ok, det)
	var got := Progress.check_ach(rich)
	var e := deq(got, A["rich"]["granted"])
	check("checkAch grants exactly the JS set (%d) and the same rewards" % got.size(),
		e == "" and int(rich["coins"]) == int(A["rich"]["coins"]) and deq(rich["tickets"], A["rich"]["tickets"]) == "", e)
	check("checkAch is idempotent", Progress.check_ach(rich).is_empty())

# ---------------- personality ----------------

func test_personality() -> void:
	print("-- personality test (starters.js) --")
	var ok := true
	var det := ""
	for p in V["personality"]:
		var scores := {}
		var q: Array = Data._json("starters.json")["test"]
		for i in q.size():
			var a: Dictionary = q[i]["a"][int(p["answers"][i])]
			for k in a["p"]:
				scores[k] = int(scores.get(k, 0)) + int(a["p"][k])
		var rng := Progress.Rng.new(str(p["seed"]))
		var r := Meta.personality_result(scores, func() -> float: return rng.next())
		var e := deq(scores, p["scores"])
		if e == "" and (r["trait"] != p["trait"] or int(r["dex"]) != int(p["dex"]) or deq(Meta.personality_candidates(scores), p["candidates"]) != ""):
			e = "%s -> %s/%d vs %s/%d" % [p["answers"], r["trait"], r["dex"], p["trait"], p["dex"]]
		if e != "":
			ok = false
			det = e
	check("scores -> trait + suggested starter (ties seeded) == JS for %d answer sets" % V["personality"].size(), ok, det)

# ---------------- import path ----------------

func test_import_path() -> void:
	print("-- import / export through the Settings path --")
	Save.data = Save.new_save("Antes")
	Save.loaded = true
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/web_guest_save.json")
	# as copied from localStorage (a JSON string of the JSON)
	var err := Save.import_json(JSON.stringify(raw))
	check("import_json(localStorage string value) ok", err == "", err)
	check("imported: 48 Pokémon, 716 + 1950 (Veto refund) coins, partner 936, 4 tickets, 7 achievements",
		Save.owned_count() == 48 and int(Save.data["coins"]) == 2666 and Save.partner() == 936 \
		and int(Save.data["tickets"]["t1"]) == 4 and (Save.data["ach"] as Dictionary).size() == 7)
	var file_txt := FileAccess.get_file_as_string(Save.path)
	check("import wrote user://tests/save_test.json; backup of the previous save kept",
		file_txt.contains("\"partner\":936") and FileAccess.file_exists(Save.backup_path()))
	var ex := Save.export_json()
	var back: Variant = Save.parse(ex)
	check("export_json -> parse == current save", back is Dictionary and deq(back, Save.data) == "")
	check("garbage is rejected and keeps the save", Save.import_json("{\"hello\": 1}") != "" and Save.import_json("nope") != "" \
		and Save.partner() == 936)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.backup_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.export_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
