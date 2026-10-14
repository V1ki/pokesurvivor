class_name AudioTests
extends RefCounted
## Audio checks (run by tests/run_tests.gd): the pre-rendered set of assets/audio/manifest.json
## against what AudioLogic can ask for, the files themselves, and the sfx() rules of
## js/core/audio.js (MIN_GAP per key, the voice cap, xp combo, shot kind/type and rarity variants,
## fades and volume smoothing).

static func run(t) -> void:
	print("-- audio (manifest, files, limiter) --")
	var f := FileAccess.open(AudioMgr.MANIFEST, FileAccess.READ)
	t.check("audio manifest exists", f != null, AudioMgr.MANIFEST)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	_manifest(t, m)
	_files(t, m)
	_limiter(t)
	_variants(t)
	_mixing(t)

static func _manifest(t, m: Dictionary) -> void:
	var music: Dictionary = m["music"]
	var names := ["village", "forest", "cave", "volcano", "boss", "rift"]
	t.check("manifest: the 6 tracks of music.js", music.keys().size() == 6 and names.all(func(n): return music.has(n)), str(music.keys()))
	t.check("manifest: biome music forest/cave/volcano", m["biome_music"] == ["forest", "cave", "volcano"])
	var bad := []
	for n in names:
		var e: Dictionary = music[n]
		var loop: float = int(e["bars"]) * 16 * 60.0 / float(e["bpm"]) / 4.0      # audio.js compile(): steps * sd
		var sr := float(m["sample_rate"])
		if absf(float(e["samples"]) - loop * sr) > 0.5 or int(e["ogg_samples"]) != int(e["samples"]):
			bad.append(n)
	t.check("music loops = bars*16 steps of 60/bpm/4 s, whole samples, OGG length exact", bad.is_empty(), str(bad))
	t.check("village loop 38.4 s (100 bpm, 16 bars)", is_equal_approx(float(music["village"]["loop_len"]), 38.4))
	var ids := AudioLogic.all_ids()
	var sfx: Dictionary = m["sfx"]
	var missing := []
	for id in ids:
		if not sfx.has(id):
			missing.append(id)
	var orphan := []
	for id in sfx.keys():
		if not id in ids:
			orphan.append(id)
	t.check("manifest SFX = every id AudioLogic can resolve (%d)" % ids.size(), missing.is_empty() and orphan.is_empty() and ids.size() == 155,
		"missing %s orphan %s" % [missing, orphan])

static func _files(t, m: Dictionary) -> void:
	var bad := []
	var short := []
	for id in (m["sfx"] as Dictionary).keys():
		var e: Dictionary = m["sfx"][id]
		var st := load("res://assets/audio/" + str(e["file"])) as AudioStream
		if st == null:
			bad.append(id)
		elif absf(st.get_length() - float(e["dur"])) > 0.002:
			short.append("%s %.4f/%.4f" % [id, st.get_length(), float(e["dur"])])
	t.check("all 155 SFX files load as AudioStream", bad.is_empty(), str(bad))
	t.check("SFX lengths match the manifest (+-2 ms)", short.is_empty(), str(short.slice(0, 5)))
	var mb := []
	for n in (m["music"] as Dictionary).keys():
		var e: Dictionary = m["music"][n]
		var st := load("res://assets/audio/" + str(e["file"])) as AudioStreamOggVorbis
		if st == null or absf(st.get_length() - float(e["loop_len"])) > 0.001:
			mb.append(n)
	t.check("music OGGs load, length = one loop (+-1 ms)", mb.is_empty(), str(mb))
	var gains := []
	for sec in ["music", "sfx"]:
		for id in (m[sec] as Dictionary).keys():
			var e: Dictionary = m[sec][id]
			# files are kept below 0.97 peak; gain_db restores the level
			if float(e["peak"]) > 0.97 and absf(float(e["gain_db"]) - (-20.0 * log(0.97 / float(e["peak"])) / log(10.0))) > 0.01:
				gains.append(id)
			if float(e["peak"]) <= 0.97 and float(e["gain_db"]) != 0.0:
				gains.append(id)
	t.check("headroom gains consistent with peaks", gains.is_empty(), str(gains))

static func _limiter(t) -> void:
	var L := AudioLogic.new()
	# MIN_GAP: hit 45 ms (JS `now - last < gap` -> exactly 45 ms passes)
	var r := [L.resolve("hit", {}, 1000.0), L.resolve("hit", {}, 1044.0), L.resolve("hit", {}, 1045.0)]
	t.check("MIN_GAP hit 45 ms: 0 ok, +44 dropped, +45 ok", r == ["hit", "", "hit"], str(r))
	# a dropped call doesn't move `last`
	r = [L.resolve("coin", {}, 2000.0), L.resolve("coin", {}, 2049.0), L.resolve("coin", {}, 2050.0)]
	t.check("MIN_GAP coin 50 ms (drop keeps the old time)", r == ["coin", "", "coin"], str(r))
	# no gap for names outside MIN_GAP
	r = [L.resolve("levelup", {}, 3000.0), L.resolve("levelup", {}, 3000.0)]
	t.check("no MIN_GAP for levelup", r == ["levelup", "levelup"], str(r))
	# shots: one key per (mapped) kind
	L = AudioLogic.new()
	r = [L.resolve("shot", {"kind": "melee", "type": "fire"}, 0.0), L.resolve("shot", {"kind": "beam", "type": "fire"}, 10.0),
		L.resolve("shot", {"kind": "chain", "type": "water"}, 20.0), L.resolve("shot", {"kind": "dash", "type": "fire"}, 30.0),
		L.resolve("shot", {"kind": "beam", "type": "fire"}, 80.0)]
	t.check("shot MIN_GAP 70 ms per kind (chain=beam, dash=melee keys)", r == ["shot_melee", "shot_beam_fire", "", "", "shot_beam_fire"], str(r))
	# voice cap: `if (voices > 24) return` -> 25 per 150 ms window
	L = AudioLogic.new()
	var ok := 0
	for i in 40:
		if L.resolve("levelup", {}, 5000.0 + i * 0.1) != "":
			ok += 1
	t.check("voice cap: 25 of 40 simultaneous SFX play", ok == 25 and L.cap_drops == 15 and L.max_voices == 25,
		"ok %d drops %d max %d" % [ok, L.cap_drops, L.max_voices])
	t.check("voice cap: still full 149 ms later", L.resolve("levelup", {}, 5149.0) == "")
	t.check("voice cap: voices expire after 150 ms", L.resolve("levelup", {}, 5150.0 + 3.9) == "levelup" and L.voices(5154.0) == 1)
	# muted-style drops (MIN_GAP) don't take voices
	L = AudioLogic.new()
	for i in 30:
		L.resolve("hit", {}, 7000.0 + i)
	t.check("MIN_GAP drops don't count as voices", L.voices(7030.0) == 1 and L.gap_drops == 29)
	t.check("unknown SFX ignored", L.resolve("nope", {}, 8000.0) == "" and L.unknown == 1 and L.resolve("", {}, 8000.0) == "")

static func _variants(t) -> void:
	var L := AudioLogic.new()
	var r := []
	for i in 30:
		r.append(L.resolve("xp", {}, 10000.0 + i * 40.0))
	t.check("xp combo: +1 per pickup < 0.45 s apart, max 24", r[0] == "xp_0" and r[1] == "xp_1" and r[24] == "xp_24" and r[29] == "xp_24", "%s %s %s" % [r[0], r[1], r[29]])
	t.check("xp combo: a pickup dropped by MIN_GAP doesn't count", L.resolve("xp", {}, 10000.0 + 29 * 40.0 + 20.0) == "" and L.xp_combo == 24)
	t.check("xp combo resets after 0.45 s", L.resolve("xp", {}, 10000.0 + 29 * 40.0 + 450.0) == "xp_0")
	L = AudioLogic.new()
	var cases := [
		[{"kind": "projectile", "type": "fire"}, "shot_projectile_fire"], [{"kind": "boomerang", "type": "ice"}, "shot_projectile_ice"],
		[{"kind": "cone", "type": "bug"}, "shot_projectile_bug"], [{"kind": "mine", "type": "ice"}, "shot_nova"],
		[{"kind": "meteor", "type": "rock"}, "shot_nova"], [{"kind": "turret", "type": "steel"}, "shot_buff_steel"],
		[{"kind": "orbit", "type": "ghost"}, "shot_orbit_ghost"], [{"kind": "aura", "type": "???"}, "shot_aura_normal"],
		[{"kind": "trail", "type": "poison"}, "shot_aura_poison"], [{"kind": "weird", "type": "dark"}, "shot_projectile_dark"],
		[{"kind": "beam"}, "shot_beam_normal"]]
	var bad := []
	var now := 20000.0
	for c in cases:
		now += 100.0
		var id := L.resolve("shot", c[0], now)
		if id != c[1]:
			bad.append("%s -> %s" % [c[0], id])
	t.check("shot variants (player.js SND map, unknown type = normal pitch)", bad.is_empty(), str(bad))
	t.check("shot without opts is silent (JS throws)", L.resolve("shot", {}, now + 500.0) == "")
	r = [L.resolve("burst", {"rarity": 4}, now + 600.0), L.resolve("burst", {}, now + 601.0), L.resolve("reveal", {"rarity": 0}, now + 602.0),
		L.resolve("reveal", {"rarity": 5.0}, now + 603.0), L.resolve("burst", {"rarity": 6}, now + 604.0)]
	t.check("burst/reveal per rarity (missing/0 -> 1, >5 silent)", r == ["burst_4", "burst_1", "reveal_1", "reveal_5", ""], str(r))

static func _mixing(t) -> void:
	# stopCurrent: linear 0.7 s fade; startSong: 0 -> 1 over 0.8 s
	t.check("music fade-in ramp (0.4 s of 0.8 = 0.5)", is_equal_approx(AudioLogic.ramp(10.4, 10.0, 0.8, 0.0, 1.0), 0.5)
		and AudioLogic.ramp(9.0, 10.0, 0.8, 0.0, 1.0) == 0.0 and AudioLogic.ramp(11.0, 10.0, 0.8, 0.0, 1.0) == 1.0)
	t.check("music fade-out from a partial level", is_equal_approx(AudioLogic.ramp(0.35, 0.0, 0.7, 0.6, 0.0), 0.3))
	var v := 0.0
	for i in 3:
		v = AudioLogic.smooth(v, 1.0, 0.05)
	t.check("volume smoothing tau 0.05 s (3 tau -> 95 %)", absf(v - (1.0 - exp(-3.0))) < 1e-9, "%.4f" % v)
	# the facade is silent-safe without an audio node and in headless mode
	Sfx.play("hit")
	Sfx.music("boss")
	t.check("Sfx facade callable headless", true)
