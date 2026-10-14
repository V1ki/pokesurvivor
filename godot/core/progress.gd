class_name Progress
extends RefCounted
## Missions, achievements and account stats (port of js/systems/progress.js, js/data/missions.js,
## js/data/achievements.js). The single entry point for run events:
##   Progress.kill(e)                                  enemy died (EnemyMgr, like enemy.js:909)
##   Progress.event("chest")                           locked chest opened
##   Progress.event("item", {"id": id})                held item equipped
##   Progress.event("evolve", {"move": id})            move evolved
##   Progress.event("rift", {"type": t})               rift fight won
##   Progress.event("runEnd", {time, level, coins, types, group})
##   Progress.event("missionDone", {"daily": bool})    (claim() fires it)
##   Progress.shiny_caught(dex) -> bool                wild shiny caught (G.onShinyCaught)
## Everything is a no-op until Save.load_or_create() ran (headless tests never touch the save).
## Missions: 3 daily + 2 weekly, drawn with a seed from the Madrid-time period id + save.created.

const DAILY_N := 3
const WEEKLY_N := 2

static var in_arena := false        # set by the rift system: arena bosses count as legends
static var enabled := true          # false for bot runs (--autoshot / --autoplay): no missions/achievements
static var popups: Array = []       # [{title, sub, ach}] queued for the popup UI (ui/popups.gd)
static var _ach_t := -100000
static var _defs: Dictionary = {}   # missions.json {daily, weekly}
static var _mby: Dictionary = {}
static var _ach: Dictionary = {}    # achievements.json {cats, list}
static var _aby: Dictionary = {}
static var now_override := -1       # unix ms; tests pin the clock

# ---------------- deterministic RNG (progress.js rng: FNV-1a + mulberry32) ----------------

class Rng:
	var h: int
	func _init(seed_str: String) -> void:
		h = 2166136261
		for c in seed_str.to_utf8_buffer():      # JS charCodeAt: seeds are ASCII
			h = U.imul32(h ^ c, 16777619)
	func next() -> float:
		h = (h + 0x6D2B79F5) & U.M32
		var t := h
		t = U.imul32(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + U.imul32(t ^ (t >> 7), t | 61)) & U.M32)) & U.M32
		return float((t ^ (t >> 14)) & U.M32) / 4294967296.0

# ---------------- data ----------------

static func _ensure_defs() -> void:
	if not _defs.is_empty():
		return
	Data.ensure()
	_defs = Data._json("missions.json")
	for m in _defs["daily"] + _defs["weekly"]:
		var g: Array = []
		for v in m["goals"]:
			g.append(int(v))
		m["goals"] = g
		_mby[m["id"]] = m
	_ach = Data._json("achievements.json")
	for a in _ach["list"]:
		a["goal"] = int(a["goal"])
		a["tier"] = int(a["tier"])
		if a.has("dex"):
			a["dex"] = int(a["dex"])
		_aby[a["id"]] = a

static func mission_defs() -> Dictionary:
	_ensure_defs()
	return _defs

static func mission_def(id: String) -> Dictionary:
	_ensure_defs()
	return _mby.get(id, {})

static func ach_list() -> Array:
	_ensure_defs()
	return _ach["list"]

static func ach_cats() -> Array:
	_ensure_defs()
	return _ach["cats"]

static func ach_by(id: String) -> Dictionary:
	_ensure_defs()
	return _aby.get(id, {})

# ---------------- Madrid-time period ids (ranking.js periodIds) ----------------

static func now_ms() -> int:
	return now_override if now_override >= 0 else Save.now_ms()

static func _utc(y: int, m: int, d: int, h := 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": h, "minute": 0, "second": 0}))

## Last Sunday of a month at 01:00 UTC (EU summer-time switch).
static func _last_sunday_1utc(y: int, m: int) -> int:
	var days := 31 if m in [1, 3, 5, 7, 8, 10, 12] else 30
	var t := _utc(y, m, days)
	var wd: int = Time.get_datetime_dict_from_unix_time(t)["weekday"]      # 0 = Sunday
	return t - wd * 86400 + 3600

## Europe/Madrid UTC offset in seconds (CET +1 / CEST +2, EU rule since 1996).
static func madrid_offset(unix_s: int) -> int:
	var y: int = Time.get_datetime_dict_from_unix_time(unix_s)["year"]
	return 7200 if unix_s >= _last_sunday_1utc(y, 3) and unix_s < _last_sunday_1utc(y, 10) else 3600

## {d: "dYYYYMMDD", w: "wYYYY-WW"} (ISO week) for a unix time in ms (default: now).
static func period_ids(ms: int = -1) -> Dictionary:
	if ms < 0:
		ms = now_ms()
	var s := int(floor(ms / 1000.0))
	var loc: Dictionary = Time.get_datetime_dict_from_unix_time(s + madrid_offset(s))
	var y: int = loc["year"]
	var m: int = loc["month"]
	var d: int = loc["day"]
	# ISO week: Thursday of this week decides the year
	var t := _utc(y, m, d)
	var day: int = loc["weekday"]
	if day == 0:
		day = 7
	t += (4 - day) * 86400
	var ty: int = Time.get_datetime_dict_from_unix_time(t)["year"]
	var y0 := _utc(ty, 1, 1)
	var week := int(ceil(((t - y0) / 86400.0 + 1.0) / 7.0))
	return {"d": "d%d%02d%02d" % [y, m, d], "w": "w%d-%02d" % [ty, week]}

# ---------------- missions ----------------

static func _make(def: Dictionary, r: Rng) -> Dictionary:
	var goals: Array = def["goals"]
	var goal: int = goals[int(floor(r.next() * goals.size()))]
	var param: Variant = null
	if def.get("param") == "type":
		param = Data.type_order[int(floor(r.next() * Data.type_order.size()))]
	return {"id": def["id"], "goal": goal, "param": param, "prog": 0, "claimed": false, "told": false}

static func pick_set(defs: Array, n: int, r: Rng, avoid: Array = []) -> Array:
	var pool: Array = defs.filter(func(d): return not avoid.has(d["id"]))
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(_make(pool.pop_at(int(floor(r.next() * pool.size()))), r))
	return out

## Creates today's / this week's missions if the period changed (progress.js ensure).
static func ensure(s: Dictionary, ms: int = -1) -> void:
	if s.is_empty():
		return
	_ensure_defs()
	var ids := period_ids(ms)
	var key := str(int(s.get("created", 0))) if s.get("created") != null else "0"
	if not (s.get("missions") is Dictionary):
		s["missions"] = {}
	var M: Dictionary = s["missions"]
	if M.get("day") != ids["d"]:
		M["day"] = ids["d"]
		M["rerolled"] = false
		M["daily"] = pick_set(_defs["daily"], DAILY_N, Rng.new(ids["d"] + key))
	if M.get("week") != ids["w"]:
		M["week"] = ids["w"]
		M["weekly"] = pick_set(_defs["weekly"], WEEKLY_N, Rng.new(ids["w"] + key))

static func type_name(t: Variant) -> String:
	return Data.type_name.get(str(t), str(t))

static func _num(n: int) -> String:
	# toLocaleString('es'): 4.000 (Spanish grouping from 5 digits; 4 digits stay ungrouped in es)
	var s := str(n)
	if s.length() <= 4:
		return s
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## Mission text (missions.js text()).
static func text(m: Dictionary) -> String:
	var n: int = int(m["goal"])
	var t := type_name(m.get("param"))
	match str(m["id"]):
		"kill": return "Derrota a %d Pokémon" % n
		"killType": return "Derrota a %d Pokémon de tipo %s" % [n, t]
		"survive": return "Aguanta %d minutos en una run" % n
		"level": return "Llega al nivel %d en una run" % n
		"boss": return "Derrota a un jefe" if n == 1 else "Derrota a %d jefes" % n
		"chest": return "Abre un cofre con candado" if n == 1 else "Abre %d cofres con candado" % n
		"coins": return "Recoge %d monedas en tus runs" % n
		"playType": return "Aguanta %d minutos con un Pokémon de tipo %s" % [n, t]
		"item": return "Encuentra un objeto equipable"
		"evolve": return "Evoluciona un movimiento"
		"wkill": return "Derrota a %s Pokémon" % _num(n)
		"wrift": return "Gana una pelea en una grieta" if n == 1 else "Gana %d peleas en grietas" % n
		"wboss": return "Derrota a %d jefes" % n
		"wsurvive": return "Aguanta %d minutos en una run" % n
		"wevolve": return "Evoluciona %d movimientos" % n
		"wdaily": return "Completa %d misiones diarias" % n
	return str(m["id"])

static func done(m: Dictionary) -> bool:
	return int(m["prog"]) >= int(m["goal"])

static func _has_type(d: Dictionary, t: Variant) -> bool:
	return (d.get("types", []) as Array).has(t)

## Does this event count for the mission? (missions.js match)
static func _match(id: String, d: Dictionary, param: Variant) -> bool:
	match id:
		"killType", "playType": return _has_type(d, param)
		"boss", "wboss": return bool(d.get("boss", false))
		"wdaily": return bool(d.get("daily", false))
	return true

## How much the event is worth (missions.js value; 1 without value()).
static func _value(id: String, d: Dictionary) -> int:
	match id:
		"survive", "playType", "wsurvive": return int(floor(float(d.get("time", 0.0)) / 60.0))
		"level": return int(d.get("level", 0))
		"coins": return int(d.get("coins", 0))
	return 1

static func _advance(list: Variant, kind: String, d: Dictionary) -> void:
	if not (list is Array):
		return
	for m in list:
		if m.get("claimed", false) or done(m):
			continue
		var def := mission_def(str(m["id"]))
		if def.is_empty() or def["ev"] != kind:
			continue
		if not _match(str(m["id"]), d, m.get("param")):
			continue
		var v := _value(str(m["id"]), d)
		m["prog"] = maxi(int(m["prog"]), v) if def.get("mode") == "max" else int(m["prog"]) + v
		if done(m) and not m.get("told", false):
			m["told"] = true
			notify("Misión completada: " + text(m), "Recoge el premio en Misiones")

## Claims a finished mission's reward (manual, like JS).
static func claim(m: Dictionary, weekly := false) -> bool:
	if not Save.loaded or m.get("claimed", false) or not done(m):
		return false
	var s := Save.data
	m["claimed"] = true
	grant(mission_def(str(m["id"]))["reward"])
	s["stats"]["missionsDone"] = Save.stat("missionsDone") + 1
	event("missionDone", {"daily": not weekly})
	Save.commit()
	return true

## Swaps an unclaimed daily for another one (once a day, non-deterministic seed).
static func reroll(i: int) -> bool:
	if not Save.loaded:
		return false
	var s := Save.data
	ensure(s)
	var M: Dictionary = s["missions"]
	var daily: Array = M["daily"]
	if i < 0 or i >= daily.size() or M.get("rerolled", false) or daily[i].get("claimed", false):
		return false
	var r := Rng.new(str(M["day"]) + "cambio" + str(Save.now_ms()))
	var ids: Array = daily.map(func(x): return x["id"])
	var n := pick_set(_defs["daily"], 1, r, ids)
	if n.is_empty():
		return false
	daily[i] = n[0]
	M["rerolled"] = true
	Save.commit()
	return true

static func grant(r: Dictionary) -> void:
	var s := Save.data
	if r.is_empty():
		return
	if r.get("coins", 0):
		s["coins"] = int(s["coins"]) + int(r["coins"])
	if r.get("t1", 0):
		s["tickets"]["t1"] = int(s["tickets"]["t1"]) + int(r["t1"])
	if r.get("t10", 0):
		s["tickets"]["t10"] = int(s["tickets"]["t10"]) + int(r["t10"])

static func reward_text(r: Dictionary) -> String:
	var p: Array = []
	if r.get("t10", 0):
		p.append("%d ticket ×10" % int(r["t10"]))
	if r.get("t1", 0):
		p.append("%d ticket%s" % [int(r["t1"]), "" if int(r["t1"]) == 1 else "s"])
	if r.get("coins", 0):
		p.append("%d monedas" % int(r["coins"]))
	return " · ".join(p)

## Rewards still to claim (menu badge).
static func pending() -> int:
	if not Save.loaded:
		return 0
	ensure(Save.data)
	var n := 0
	for m in Save.data["missions"]["daily"] + Save.data["missions"]["weekly"]:
		if done(m) and not m.get("claimed", false):
			n += 1
	return n

# ---------------- events ----------------

static func event(kind: String, d: Dictionary = {}) -> void:
	if not Save.loaded or not enabled:
		return
	var s := Save.data
	ensure(s)
	var S: Dictionary = s["stats"]
	var t := Save.now_ms()
	match kind:
		"kill":
			if d.get("boss", false):
				S["bossesTotal"] = Save.stat("bossesTotal") + 1
			var lg := int(d.get("legend", 0))
			if lg:
				if not (s["legends"] as Dictionary).has(str(lg)):
					s["legends"][str(lg)] = t
		"rift":
			S["riftWins"] = Save.stat("riftWins") + 1
			if str(d.get("type", "")) != "" and not (s["arenas"] as Dictionary).has(str(d["type"])):
				s["arenas"][str(d["type"])] = t
		"evolve":
			S["evolutions"] = Save.stat("evolutions") + 1
			if not (s["evoMoves"] as Dictionary).has(str(d.get("move", ""))):
				s["evoMoves"][str(d.get("move", ""))] = t
		"item":
			if not (s["itemsFound"] as Dictionary).has(str(d.get("id", ""))):
				s["itemsFound"][str(d.get("id", ""))] = t
		"runEnd":
			if d.get("group", false):
				S["groupRuns"] = Save.stat("groupRuns") + 1
	_advance(s["missions"].get("daily"), kind, d)
	_advance(s["missions"].get("weekly"), kind, d)
	# achievements: at most once per second for plain kills (there are hundreds)
	if kind != "kill" or d.get("boss", false) or int(d.get("legend", 0)):
		check_ach()
	elif Time.get_ticks_msec() - _ach_t > 1000:
		check_ach()

## An enemy died (progress.js kill). `e` is an Enemy (types, boss, legend, dex).
static func kill(e: Object) -> void:
	if not Save.loaded or not enabled:
		return
	var boss: bool = e.get("boss")
	var legend: int = int(e.get("dex")) if (e.get("legend") or (in_arena and boss)) else 0
	event("kill", {"types": e.get("types"), "boss": boss, "legend": legend})

## Wild shiny caught (game.js G.onShinyCaught): shiny + normal form, stats, commit. True if new.
static func shiny_caught(dex: int) -> bool:
	if not Save.loaded or not enabled:
		return not Save.owns_shiny(dex)
	var is_new := Save.grant_shiny(dex, "wild")
	Save.data["stats"]["shinies"] = Save.stat("shinies") + 1
	Save.commit()
	return is_new

# ---------------- achievements ----------------

static func _count(s: Dictionary, k: String) -> int:
	return (s[k] as Dictionary).size() if s.get(k) is Dictionary else 0

static func _st(s: Dictionary, k: String) -> int:
	var v: Variant = s["stats"].get(k) if s.get("stats") is Dictionary else null
	return int(v) if (v is int or v is float) else 0

## Achievement progress value (achievements.js value(save)).
static func ach_value(a: Dictionary, s: Dictionary) -> int:
	var id: String = a["id"]
	if a.has("dex"):
		return 1 if (s.get("legends") is Dictionary and (s["legends"] as Dictionary).has(str(a["dex"]))) else 0
	if id.begins_with("own"):
		var n := 0
		for k in (s.get("owned", {}) as Dictionary):
			if Save.valid_dex_key(str(k)):
				n += 1
		return n
	if id.begins_with("shiny"):
		return _count(s, "shiny")
	if id.begins_with("time"):
		return int(floor(_st(s, "bestTime") / 60.0))
	match id:
		"pulls100": return _st(s, "pulls")
		"lvl20", "lvl40": return _st(s, "bestLevel")
		"runs50": return _st(s, "runs")
		"kills1k", "kills10k", "kills100k": return _st(s, "totalKills")
		"boss1", "boss25", "boss100": return _st(s, "bossesTotal")
		"evo1", "evo25": return _st(s, "evolutions")
		"evoAll": return _count(s, "evoMoves")
		"items5", "itemsAll": return _count(s, "itemsFound")
		"rift1", "rift10": return _st(s, "riftWins")
		"arenas": return _count(s, "arenas")
		"leg10", "leg30", "legAll": return _count(s, "legends")
		"mis10", "mis50", "mis200": return _st(s, "missionsDone")
		"group1", "group10": return _st(s, "groupRuns")
	push_warning("Progress: no value() for achievement " + id)
	return 0

## Grants every reached achievement (reward included). Returns the ids granted now.
static func check_ach(s: Dictionary = {}) -> Array:
	var real := s.is_empty()
	if real:
		if not Save.loaded:
			return []
		s = Save.data
	_ach_t = Time.get_ticks_msec()
	if not (s.get("ach") is Dictionary):
		s["ach"] = {}
	var got: Array = []
	for a in ach_list():
		if (s["ach"] as Dictionary).has(a["id"]):
			continue
		if ach_value(a, s) < int(a["goal"]):
			continue
		s["ach"][a["id"]] = Save.now_ms()
		got.append(a["id"])
		if real:
			grant(a["reward"])
			notify("¡Logro: %s!" % a["name"], ("Nuevo título: " + str(a["title"])) if a.get("title", "") != "" else "", a)
		else:
			_grant_to(s, a["reward"])
	return got

static func _grant_to(s: Dictionary, r: Dictionary) -> void:
	s["coins"] = int(s["coins"]) + int(r.get("coins", 0))
	s["tickets"]["t1"] = int(s["tickets"]["t1"]) + int(r.get("t1", 0))
	s["tickets"]["t10"] = int(s["tickets"]["t10"]) + int(r.get("t10", 0))

## Titles of unlocked achievements (profile).
static func titles() -> Array:
	var out: Array = []
	if not Save.loaded:
		return out
	for a in ach_list():
		if a.get("title", "") != "" and (Save.data["ach"] as Dictionary).has(a["id"]):
			out.append(a["title"])
	return out

# ---------------- popups ----------------

static func notify(title: String, sub: String, ach: Dictionary = {}) -> void:
	popups.append({"title": title, "sub": sub, "ach": ach})
