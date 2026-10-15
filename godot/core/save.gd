class_name Save
extends RefCounted
## The local save (port of js/core/db.js: newSave / migrate / sanitize / helpers).
## One local profile in user://save.json holding exactly the JS save object, so a save from the
## web game (localStorage "ps.guest", a JSON string) can be imported verbatim and exported back.
## Object keys stay strings like in JS ("4" for dex 4); integral numbers are kept as ints.
## A static class so it also works in `--script` tests. Nothing is read or written until
## load_or_create() is called (headless tests never touch the player's save).

const VERSION := 4              # 4 (2026-10-14): trainer + families (core/families.gd)
const START_COINS := 500
const PATH := "user://save.json"

static var data: Dictionary = {}
static var loaded := false
static var path := PATH            # tests redirect this
static var read_only := false      # debug runs (autoshot / autoplay / metashot): never written
static var storage_ok := true
static var now_override := -1      # tests: a fixed "now" (ms), like the JS vectors' Date.now

## The previous save before an import (next to the save file).
static func backup_path() -> String:
	return path.get_basename() + ".backup.json"

## Where Export writes its copy (next to the save file).
static func export_path() -> String:
	return path.get_base_dir().path_join("save_export.json")

static func now_ms() -> int:
	if now_override >= 0:
		return now_override
	return int(Time.get_unix_time_from_system() * 1000.0)

# ---------------- save object ----------------

static func new_save(name: String) -> Dictionary:
	var t := now_ms()
	return {
		"v": VERSION,
		"name": name,
		"created": t,
		"updated": t,
		"coins": START_COINS,
		"owned": {},                 # dex -> {at, from: starter|gacha|wild|rescue}
		"shiny": {},                 # dex -> {at, from}
		"partner": null,
		"partnerShiny": false,
		"starter": null,
		"personality": null,         # {trait, scores}
		"upgrades": {},              # (old) account-wide upgrades, then per Pokémon (migration only)
		"pupg": {},                  # (old) dex -> {upgradeId: level}
		"trainer": {},               # id -> level: trainer upgrades, for every Pokémon (core/families.gd)
		"fams": {},                  # family -> {lv, xp, shards, stars}
		"uni": 0,                    # universal shards
		"tickets": {"t1": 0, "t10": 0},
		"pity": {},                  # banner gen -> pulls since the last 5*
		"legends": {},
		"arenas": {},
		"itemsFound": {},
		"evoMoves": {},
		"ach": {},
		"missions": {},
		"profile": {"favs": [], "title": ""},
		"stats": {"runs": 0, "bestTime": 0, "bestLevel": 0, "totalKills": 0, "pulls": 0, "coinsEarned": 0, "shinies": 0,
			"bossesTotal": 0, "riftWins": 0, "evolutions": 0, "missionsDone": 0, "groupRuns": 0, "bestGroupTime": 0,
			# when it moved to families: what was owned before can always be used
			"famAt": 1},
	}

## Fills fields missing in older saves, runs the v1->v2->v3->v4 migrations and sanitize (db.js migrate).
static func migrate(s: Dictionary, name := "") -> Dictionary:
	Data.ensure()
	var base := new_save(name if name != "" else str(s.get("name", "")))
	# v3 -> v4 (2026-10-14): from per-Pokémon upgrades to trainer + families
	var fam_first := not (s.get("stats") is Dictionary and Save._truthy(s["stats"].get("famAt")))
	for k in base:
		if s.get(k) == null:
			s[k] = base[k]
	# a hand-edited save can have the wrong container types: JS would misbehave, here they reset
	for k in ["owned", "shiny", "upgrades", "pupg", "trainer", "fams", "legends", "arenas", "itemsFound", "evoMoves", "ach", "missions", "profile", "stats"]:
		if not (s[k] is Dictionary):
			s[k] = base[k]
	for k in base["stats"]:
		if s["stats"].get(k) == null:
			s["stats"][k] = base["stats"][k]
	if fam_first:
		s["stats"]["famAt"] = now_ms()
	Families.migrate(s, fam_first)
	# v1 -> v2: a single banner (Kanto) with the pity as a number
	if s["pity"] is float or s["pity"] is int:
		s["pity"] = {"1": s["pity"]}
	elif not (s["pity"] is Dictionary):
		s["pity"] = {}
	# v2 -> v3: upgrades were account-wide; they move to the partner of that time
	if not _truthy(s.get("pupgDone")):
		var any := false
		for v in (s["upgrades"] as Dictionary).values():
			if (v is int or v is float) and v > 0:
				any = true
		if _truthy(s["partner"]) and any:
			s["pupg"][_key(s["partner"])] = (s["upgrades"] as Dictionary).duplicate()
		s["pupgDone"] = true
	var t: Dictionary = {"t1": 0, "t10": 0}
	if s["tickets"] is Dictionary:
		t.merge(s["tickets"], true)
	s["tickets"] = t
	sanitize(s)
	s["v"] = VERSION
	return s

## Removes the impossible from a hand-edited save (db.js sanitize).
static func sanitize(s: Dictionary) -> void:
	s["coins"] = _n(s.get("coins"))
	s["tickets"]["t1"] = _n(s["tickets"].get("t1"))
	s["tickets"]["t10"] = _n(s["tickets"].get("t10"))
	for coll in ["owned", "shiny"]:
		var c: Dictionary = s.get(coll, {}) if s.get(coll) is Dictionary else {}
		for d in c.keys():
			if not valid_dex_key(str(d)):
				c.erase(d)
	# hotkeys: 4 slots holding an existing move (or null), no repeats
	if s.get("pbind") is Dictionary:
		var pb: Dictionary = s["pbind"]
		for d in pb.keys():
			var l: Array = (pb[d] as Array).slice(0, 4) if pb[d] is Array else []
			var seen := {}
			var out: Array = []
			for i in 4:
				var id: Variant = l[i] if i < l.size() else null
				if not (id is String) or not Data.move_by.has(id) or seen.has(id):
					out.append(null)
				else:
					seen[id] = true
					out.append(id)
			pb[d] = out
	else:
		s["pbind"] = {}
	# bans: existing moves, no repeats, at most 3
	if s.get("pban") is Dictionary:
		var pn: Dictionary = s["pban"]
		for d in pn.keys():
			var l: Array = pn[d] if pn[d] is Array else []
			var out: Array = []
			for id in l:
				if id is String and Data.move_by.has(id) and not out.has(id):
					out.append(id)
			pn[d] = out.slice(0, 3)
	else:
		s["pban"] = {}
	var pu: Dictionary = s["pupg"]
	for d in pu.keys():
		var u: Variant = pu[d]
		if u == null or not (u is Dictionary or u is Array):
			pu.erase(d)
			continue
		if u is Array:
			pu[d] = {}
			continue
		for id in (u as Dictionary).keys():
			var def := Upgrades.by_id(str(id))
			if def.is_empty():
				u.erase(id)
			else:
				u[id] = mini(int(def["max"]), _n(u[id]))
	# trainer and families: levels within their caps and positive numbers
	if not (s.get("trainer") is Dictionary):
		s["trainer"] = {}
	var tr: Dictionary = s["trainer"]
	for id in tr.keys():
		var tdef := Upgrades.by_id(str(id))
		if tdef.is_empty():
			tr.erase(id)
		else:
			tr[id] = mini(int(tdef["max"]), _n(tr[id]))
	if not (s.get("fams") is Dictionary):
		s["fams"] = {}
	var fs: Dictionary = s["fams"]
	for f in fs.keys():
		var v: Variant = fs[f]
		if not (v is Dictionary):
			fs.erase(f)
			continue
		v["lv"] = maxi(1, mini(int(Families.R["cap"]), _n(v.get("lv")) if _n(v.get("lv")) > 0 else 1))
		var xf := Families._num(v.get("xp"))
		v["xp"] = ints(maxf(0.0, xf if is_finite(xf) else 0.0))
		v["shards"] = _n(v.get("shards"))
		v["stars"] = mini(int(Families.R["stars"]), _n(v.get("stars")))
	s["uni"] = _n(s.get("uni"))

## JS n(): finite positive numbers floored, everything else 0 (+true is 1, "12" is 12).
static func _n(v: Variant) -> int:
	var f := 0.0
	if v is int or v is float:
		f = float(v)
	elif v is bool:
		f = 1.0 if v else 0.0
	elif v is String and (v as String).strip_edges().is_valid_float():
		f = float(v)
	else:
		return 0
	if is_nan(f) or is_inf(f) or f <= 0.0:
		return 0
	return int(floor(f))

static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return true

## Object key of a dex number ("4"), as JS stores it.
static func _key(d: Variant) -> String:
	if d is float:
		return str(int(d))
	return str(d)

## Is "4" a dex in G.DEX_BY? ("04" / "4.0" are not, like in JS.)
static func valid_dex_key(k: String) -> bool:
	return k.is_valid_int() and str(int(k)) == k and Data.dex_by.has(int(k))

## Integral floats -> ints, recursively (Godot's JSON parser returns floats for every number).
static func ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and f == floor(f) and absf(f) < 9007199254740992.0:
			return int(f)
		return f
	if v is Dictionary:
		var d: Dictionary = v
		for k in d.keys():
			d[k] = ints(d[k])
		return d
	if v is Array:
		var a: Array = v
		for i in a.size():
			a[i] = ints(a[i])
		return a
	return v

# ---------------- storage ----------------

static func load_or_create() -> void:
	Data.ensure()
	loaded = true
	var s: Variant = null
	if FileAccess.file_exists(path) and not read_only:
		s = parse(FileAccess.get_file_as_string(path))
		if s == null:
			push_warning("Save: %s is not a valid save, starting a new one (old file kept as .bad)" % path)
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bad"))
	data = migrate(s, "Invitado") if s is Dictionary else new_save("Invitado")      # db.js playAsGuest (the app's save)
	commit()

## Parses a save from text: a JSON object, or a JSON string holding one (localStorage values
## copied with quotes). Returns the Dictionary (ints normalized) or null.
static func parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text.strip_edges()) != OK:
		return null
	var v: Variant = j.data
	if v is String:
		if j.parse(v) != OK:
			return null
		v = j.data
	if not (v is Dictionary):
		return null
	return ints(v)

## Writes the save immediately (db.js commit): bumps `updated`.
static func commit() -> bool:
	if not loaded:
		return false
	data["updated"] = now_ms()
	if read_only:
		return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		storage_ok = false
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	storage_ok = true
	return true

static func to_json() -> String:
	return JSON.stringify(data)

## Imports a save exported from the web game (or by export). Returns "" on success or an error.
## The current save is kept in backup_path() (user://save.backup.json).
## Why `text` can't be imported ("" = it can).
static func import_error(text: String) -> String:
	var s: Variant = parse(text)
	if s == null:
		return "No es un JSON de partida válido."
	var d: Dictionary = s
	if not (d.has("owned") or d.has("coins") or d.has("v")):
		return "El JSON no parece una partida de PokéSurvivor."
	if d.has("v") and (d["v"] is int) and int(d["v"]) > VERSION:
		return "La partida es de una versión más nueva (v%d)." % int(d["v"])
	return ""

static func import_json(text: String) -> String:
	var err := import_error(text)
	if err != "":
		return err
	var d: Dictionary = parse(text)
	migrate(d, str(d.get("name", "Invitado")))
	# a partner that does not exist would crash the menu: back to the personality test
	if d["partner"] != null and not valid_dex_key(_key(d["partner"])):
		d["partner"] = null
	if loaded and not data.is_empty() and not read_only:
		var f := FileAccess.open(backup_path(), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(data))
			f.close()
	data = d
	loaded = true
	commit()
	return ""

## Writes the save to export_path() (user://save_export.json) and returns the JSON text.
static func export_json() -> String:
	var txt := to_json()
	var f := FileAccess.open(export_path(), FileAccess.WRITE) if not read_only else null
	if f != null:
		f.store_string(txt)
		f.close()
	return txt

## Deletes the save and starts a fresh one (Settings > Delete save).
static func delete_save() -> void:
	if FileAccess.file_exists(path) and not read_only:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	data = new_save("Invitado")
	loaded = true
	commit()

# ---------------- helpers (db.js) ----------------

static func partner() -> int:
	return int(data["partner"]) if data.get("partner") != null else 0

static func owns(dex: int) -> bool:
	return loaded and (data["owned"] as Dictionary).has(str(dex))

static func grant(dex: int, from: String) -> void:
	if not (data["owned"] as Dictionary).has(str(dex)):
		data["owned"][str(dex)] = {"at": now_ms(), "from": from}

static func owns_shiny(dex: int) -> bool:
	return loaded and (data["shiny"] as Dictionary).has(str(dex))

## Grants the shiny (and the normal form if missing). True if the shiny is new.
static func grant_shiny(dex: int, from: String) -> bool:
	grant(dex, from)
	if (data["shiny"] as Dictionary).has(str(dex)):
		return false
	data["shiny"][str(dex)] = {"at": now_ms(), "from": from}
	return true

## Upgrade levels bought for a Pokémon: {id: level} (created on demand like upgradesOf).
static func upgrades_of(dex: int) -> Dictionary:
	var pu: Dictionary = data["pupg"]
	if not pu.has(str(dex)) or not (pu[str(dex)] is Dictionary):
		pu[str(dex)] = {}
	return pu[str(dex)]

## Owned dex numbers (valid ones), ascending.
static func owned_list() -> Array:
	var out: Array = []
	for k in (data["owned"] as Dictionary):
		if valid_dex_key(str(k)):
			out.append(int(k))
	out.sort()
	return out

static func owned_count() -> int:
	var n := 0
	for k in (data["owned"] as Dictionary):
		if valid_dex_key(str(k)):
			n += 1
	return n

static func stat(k: String) -> int:
	return int(data["stats"].get(k, 0)) if data["stats"].get(k) != null else 0

static func tickets() -> Dictionary:
	return data["tickets"]
