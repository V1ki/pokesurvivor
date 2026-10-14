class_name Phase3Tests
extends RefCounted
## Phase 3a (world visuals & terrain) checks, called from run_tests.gd with `Phase3Tests.run(self)`
## (or alone: res://tests/run_p3_tests.gd). Reference values come from data/test_vectors_p3.json,
## computed by the unchanged tiles.js / world.js / weather.js in tools/export_godot.js
## (exportPhase3): SHA-256 of painted chunks and prop sprites, prop placement, collision,
## liquid effects and a weather schedule replayed with the same random draws.

static var V: Dictionary = {}
## Paint timings (ms) measured by the painter test: [avg, max, n].
static var paint_ms: Array = []

static func run(t: Object) -> void:
	V = Data._json("test_vectors_p3.json") if FileAccess.file_exists("res://data/test_vectors_p3.json") else {}
	if V.is_empty():
		t.check("test_vectors_p3.json present", false, "run: node tools/export_godot.js")
		return
	_painter(t)
	_props(t)
	_collide(t)
	_sprites(t)
	_liquids(t)
	_weather(t)
	_runtime(t)

static func sha(b: PackedByteArray) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(b)
	return hc.finish().hex_encode()

static func bits(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.hex_encode()

# ---------------- ground painter ----------------

static func _painter(t: Object) -> void:
	print("-- ground painter vs tiles.js paintChunk (SHA-256 of RGBA) --")
	var cache: Dictionary = {}
	var total := 0.0
	var mx := 0.0
	var n := 0
	var ok_all := 0
	for c in V["chunks"]:
		var seed := int(c["seed"])
		var cx := int(c["cx"])
		var cy := int(c["cy"])
		var key := "%d/%d/%d" % [seed, cx, cy]
		if not cache.has(key):
			var w := WorldMap.new()
			w.reset(seed)
			var k18 := w.terrain_block(cx, cy)
			var t0 := Time.get_ticks_usec()
			cache[key] = WorldPaint.paint(cx, cy, k18, seed)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			mx = maxf(mx, ms)
			n += 1
		var rgba := WorldPaint.to_rgba(cache[key], WorldPaint.palette(int(c["biome"])))
		var ok: bool = sha(rgba) == c["sha"]
		var detail := "kinds f/w/l %s" % str(c["kinds"])
		if not ok:
			var bad: Array = []
			for r in 16:
				if sha(rgba.slice(r * 16 * 256 * 4, (r + 1) * 16 * 256 * 4)) != c["rows"][r]:
					bad.append(r)
			detail += ", tile rows differing: %s" % str(bad)
			var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, rgba)
			img.save_png("user://p3_chunk_%d_%d_%d_%d.png" % [seed, cx, cy, int(c["biome"])])
		else:
			ok_all += 1
		t.check("chunk seed %d (%d,%d) biome %d pixel-exact" % [seed, cx, cy, int(c["biome"])], ok, detail)
	paint_ms = [total / maxi(1, n), mx, n]
	print("  paint (main thread, headless): avg %.1f ms, max %.1f ms over %d chunks" % paint_ms)

static func _props(t: Object) -> void:
	print("-- prop placement vs world.js placeProps --")
	for c in V["props"]:
		var seed := int(c["seed"])
		var w := WorldMap.new()
		w.reset(seed)
		var mine: Array = []
		for cy in range(int(c["y0"]), int(c["y0"]) + int(c["n"])):
			for cx in range(int(c["x0"]), int(c["x0"]) + int(c["n"])):
				for p in w.chunk_data(cx, cy).props:
					mine.append("%s,%d,%d,%d" % [p.type, p.tx, p.ty, p.kind])
		var js: Array = []
		for q in c["list"]:
			js.append("%s,%d,%d,%d" % [q[0], int(q[1]), int(q[2]), int(q[3])])
		var first := ""
		for i in mini(mine.size(), js.size()):
			if mine[i] != js[i]:
				first = "#%d mine %s js %s" % [i, mine[i], js[i]]
				break
		var specials := js.filter(func(s: String): return s.begins_with("altar") or s.begins_with("spring") or s.begins_with("bigchest") or s.begins_with("trap")).size()
		t.check("props seed %d, %dx%d chunks: %d props identical (incl. %d interactables)" % [seed, int(c["n"]), int(c["n"]), js.size(), specials],
			mine == js, first if first != "" else "%d vs %d" % [mine.size(), js.size()])
	# worker-thread generation (request_chunk) == synchronous generation
	var a := WorldMap.new()
	a.reset(777)
	var b := WorldMap.new()
	b.reset(777)
	b.async_chunks = true
	var keys: Array[Vector2i] = []
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			keys.append(Vector2i(cx, cy))
	var t0 := Time.get_ticks_msec()
	var pending := true
	while pending and Time.get_ticks_msec() - t0 < 10000:
		pending = false
		for k in keys:
			if not b.request_chunk(k.x, k.y):
				pending = true
		if pending:
			OS.delay_msec(2)
	var same := not pending
	for k in keys:
		var ca := a.chunk_data(k.x, k.y)
		var cb := b.chunk_data(k.x, k.y)
		if ca.terr != cb.terr or ca.liquids != cb.liquids or ca.solid != cb.solid or ca.props.size() != cb.props.size():
			same = false
	t.check("chunks generated on worker threads == synchronous (terrain, liquids, props, solid index)", same)

static func _collide(t: Object) -> void:
	print("-- collision / queries with props vs world.js --")
	var w := WorldMap.new()
	w.reset(12345)
	for cy in range(-2, 3):
		for cx in range(-2, 3):
			w.chunk_data(cx, cy)
	var bad: Array = []
	var hits := 0
	var n := 0
	for c in V["collide"]:
		var x := _dbl(c["xb"])
		var y := _dbl(c["yb"])
		var e := Body.new()
		e.x = x
		e.y = y
		e.r = float(c["r"])
		var hit := w.collide(e)
		var b: Variant = w.projectile_block_any(x, y, 6.0)
		var pb := "wall" if b is String else ("prop:" + (b as WorldProp).type if b != null else "")
		var ok: bool = hit == c["hit"] and bits(e.x) == c["bx"] and bits(e.y) == c["by"] \
			and w.is_free(x, y, float(c["r"])) == c["free"] and w.is_free(x, y, 14.0, true) == c["freeL"] \
			and pb == c["pb"] and w.walkable(int(floorf(x / 32.0)), int(floorf(y / 32.0))) == c["walk"]
		n += 1
		if hit:
			hits += 1
		if not ok and bad.size() < 3:
			bad.append("(%.2f,%.2f) hit %s/%s pb %s/%s" % [x, y, hit, c["hit"], pb, c["pb"]])
	t.check("collide / isFree / projectileBlock / walkable: %d cases (%d pushes) bit-exact" % [n, hits], bad.is_empty(), str(bad))
	# fill_walkable (pathing bulk path) == walkable() tile by tile, props included
	var out := PackedByteArray()
	out.resize(60 * 60)
	w.fill_walkable(out, -30, -30, 60, 60, 0)
	var diff := 0
	var blocked := 0
	for j in 60:
		for i in 60:
			var wk := w.walkable(-30 + i, -30 + j)
			if (out[j * 60 + i] == 1) != wk:
				diff += 1
			if w.prop_at_tile(-30 + i, -30 + j) != null:
				blocked += 1
	t.check("fill_walkable == walkable over 60x60 tiles (%d solid props)" % blocked, diff == 0 and blocked > 0, "%d differ" % diff)
	for c in V["near"]:
		var x := float(c["x"])
		var y := float(c["y"])
		var r := float(c["r"])
		var nb := w.nearest_breakable(x, y, r)
		var nbs := "%s,%d,%d" % [nb.type, nb.tx, nb.ty] if nb != null else "null"
		var jb: Variant = c["breakable"]
		var jbs := "%s,%d,%d" % [jb[0], int(jb[1]), int(jb[2])] if jb != null else "null"
		var sp: Array = []
		for p in w.specials_near(x, y, r):
			sp.append("%s,%d,%d,%d" % [p.type, p.tx, p.ty, p.kind])
		sp.sort()
		var jsp: Array = []
		for q in c["specials"]:
			jsp.append("%s,%d,%d,%d" % [q[0], int(q[1]), int(q[2]), int(q[3])])
		var ic: Array = []
		for p in w.props_in_circle(x, y, r):
			ic.append("%s,%d,%d" % [p.type, p.tx, p.ty])
		ic.sort()
		var jic: Array = []
		for q in c["inCircle"]:
			jic.append("%s,%d,%d" % [q[0], int(q[1]), int(q[2])])
		t.check("nearestBreakable / specialsNear / propsInCircle at (%d,%d) r %d" % [x, y, r],
			nbs == jbs and sp == jsp and ic == jic, "%s vs %s, %d/%d specials, %d/%d in circle" % [nbs, jbs, sp.size(), jsp.size(), ic.size(), jic.size()])

static func _dbl(hex: String) -> float:
	return hex.hex_decode().decode_double(0)

static func _sprites(t: Object) -> void:
	print("-- prop sprites vs tiles.js propSprite (SHA-256 of RGBA) --")
	var bad: Array = []
	var n := 0
	for c in V["sprites"]:
		var bi := int(c["bi"])
		var P := PropArt.paint(Data.biomes[bi], str(c["type"]), int(c["v"]))
		n += 1
		if P.w != int(c["w"]) or P.h != int(c["h"]) or sha(P.buf.to_byte_array()) != c["sha"]:
			if bad.size() < 6:
				bad.append("%d/%s/%d" % [bi, c["type"], int(c["v"])])
	t.check("%d prop sprites (21 biomes x tree/rock/grass/chest/altar/spring/bigchest/trap variants + rift) pixel-exact" % n,
		bad.is_empty(), "differ: %s" % str(bad))

static func _liquids(t: Object) -> void:
	print("-- liquid effects per biome vs world.js liquidEffect --")
	var w := WorldMap.new()
	w.reset(1)
	var bad: Array = []
	var kinds := {}
	for c in V["liquids"]:
		w.set_biome(int(c["biome"]), true)
		if w.liquid_kind() != c["kind"]:
			bad.append("biome %d kind %s/%s" % [int(c["biome"]), w.liquid_kind(), c["kind"]])
		kinds[c["kind"]] = true
		for f in c["fx"]:
			var mine := w.liquid_effect(f["types"])
			var js: Dictionary = f["e"]
			var ok := mine.size() == js.size()
			for k in js:
				if not mine.has(k):
					ok = false
				elif js[k] is float or js[k] is int:
					ok = ok and absf(float(mine[k]) - float(js[k])) < 1e-12
				else:
					ok = ok and str(mine[k]) == str(js[k])
			if not ok and bad.size() < 4:
				bad.append("biome %d %s: %s vs %s" % [int(c["biome"]), str(f["types"]), str(mine), str(js)])
	t.check("liquid kind + effect for 21 biomes x 10 type sets (%s)" % ", ".join(kinds.keys()), bad.is_empty(), str(bad))

class FakeMon:
	extends RefCounted
	var dead := false
	var boss := false
	var hp := 0.0
	var max_hp := 0.0
	var flash := 0.0
	var types: Array = []
	var mon: Dictionary = {}
	var x := 0.0
	var y := 0.0
	var body_h := 30.0
	func die() -> void:
		dead = true

static func _weather(t: Object) -> void:
	print("-- weather schedule / intensity / multipliers / chip vs weather.js (same random draws) --")
	var W: Dictionary = V["weather"]
	var keep := Sim.cur
	Sim.cur = null
	var draws: Array = W["draws"]
	var di := [0]
	var wx := Weather.new()
	wx.rng = func() -> float:
		var k: float = draws[di[0]]
		di[0] += 1
		return k / 4294967296.0
	wx.reset()
	var pl := FakeMon.new()
	pl.max_hp = 180.0
	pl.hp = 180.0
	pl.mon = {"types": ["fire"]}
	var ens: Array = []
	for e in W["enemies"]:
		var f := FakeMon.new()
		f.types = [e[0]]
		f.hp = float(e[1])
		f.max_hp = float(e[1])
		f.boss = e.size() > 2
		ens.append(f)
	wx.enemies_override = ens
	var dt := 1.0 / 60.0
	var time := 0.0
	var starts: Array = []
	var prev := ""
	var samples: Array = []
	var frames := int(W["frames"])
	for f in frames:
		time += dt
		wx.biome_override = int(floorf(time / 240.0)) % 21
		if f == int(W["force"]["f"]):
			wx.force(W["force"]["kind"], float(W["force"]["dur"]))
		if f == int(W["ice_at"]):
			pl.mon = {"types": ["ice"]}
		wx.update(dt, time, pl)
		var c := wx.current()
		var key := "" if c.is_empty() else "%s%d" % [c["kind"], int(c["dur"])]
		if key != "" and key != prev:
			starts.append("%d:%s:%d" % [f, c["kind"], int(c["dur"])])
		prev = key
		if f % 1200 == 0:
			var m: Array = []
			for ty in ["fire", "water", "electric", "rock", "ice", "ghost", "grass"]:
				m.append(bits(wx.mult(ty)))
			var ehp: Array = []
			var edead: Array = []
			for e in ens:
				ehp.append(bits(e.hp))
				edead.append(e.dead)
			samples.append([f, c.get("kind", null), bits(float(c["left"])) if not c.is_empty() else null, bits(wx.vignette()), m,
				[bits(wx.speed_for(["fire"])), bits(wx.speed_for(["ice"]))], [wx.hurts(["fire"]), wx.hurts(["rock"]), wx.hurts(["ice"])],
				bits(pl.hp), ehp, edead])
	Sim.cur = keep
	var js_starts: Array = []
	for s in W["starts"]:
		js_starts.append("%d:%s:%d" % [int(s["f"]), s["kind"], int(s["dur"])])
	t.check("weather schedule over 60 min (%d events incl. forced snow; %d random draws replayed)" % [js_starts.size(), draws.size()],
		starts == js_starts and di[0] == draws.size(), "%s vs %s" % [str(starts.slice(0, 4)), str(js_starts.slice(0, 4))])
	var bad: Array = []
	for i in mini(samples.size(), (W["samples"] as Array).size()):
		var a: Array = samples[i]
		var j: Dictionary = W["samples"][i]
		var ok: bool = int(j["f"]) == a[0] and j["cur"] == a[1] and j["left"] == a[2] and j["vig"] == a[3] and j["m"] == a[4] \
			and j["sp"] == a[5] and j["hurts"] == a[6] and j["hp"] == a[7] and j["ehp"] == a[8] and j["edead"] == a[9]
		if not ok and bad.size() < 2:
			bad.append("f %d: %s vs %s" % [a[0], str(a), str(j)])
	t.check("weather level / mult(7 types) / speedFor / hurts / chip on player and enemies: %d samples bit-exact" % samples.size(),
		bad.is_empty() and samples.size() == (W["samples"] as Array).size(), str(bad))

static func _runtime(t: Object) -> void:
	print("-- runtime: liquids on the player, destructibles, biome cycle + crossfade, weather wiring --")
	var keep := Sim.cur
	var sim := Sim.new()
	sim.render = false
	# lava (biome 2) on a water-type partner: max(5, 6% maxHp / 2) every 0.5 s, i-frames ignored
	sim.start_run(7, 12345)
	var w := sim.world
	var spot := _liquid_tile(w)
	t.check("found a liquid tile near the start (seed 12345)", spot != Vector2i(1 << 30, 0))
	w.set_biome(2, true)
	var pl := sim.player
	pl.x = spot.x * 32.0 + 16.0
	pl.y = spot.y * 32.0 + 16.0
	var hp0 := pl.hp
	for i in 66:                     # 1.1 s: ticks at 0, 0.5, 1.0
		sim.enemies.clear()
		sim.projectiles.clear()
		sim.update(1.0 / 60.0)
	var tick := maxf(5.0, pl.max_hp * 0.06 * 0.5)
	t.check("lava: Squirtle loses 3 x max(5, maxHp*0.03) in 1.1 s (i-frames ignored)", absf((hp0 - pl.hp) - 3.0 * tick) < 1e-6,
		"lost %.2f, tick %.2f" % [hp0 - pl.hp, tick])
	# water slow 0.6 (biome 0) for a grass Pokémon, none for a water type
	w.set_biome(0, true)
	pl.in_liquid = true
	var s_sq := pl.spd()
	sim.start_run(1, 12345)
	sim.world.set_biome(0, true)
	pl = sim.player
	var s_dry := pl.spd()
	pl.in_liquid = true
	var s_wet := pl.spd()
	t.check("water slows a grass Pokémon to 0.6x (water types swim freely)", absf(s_wet / s_dry - 0.6) < 1e-12 and s_sq > 0.0 \
		and sim.world.liquid_effect(["water"]).is_empty(), "%.3f" % (s_wet / s_dry))
	# poison pool: Bulbasaur (grass/poison) is immune; electric spark hurts it
	sim.world.set_biome(10, true)
	t.check("poison pools: poison types immune", sim.world.liquid_effect(pl.mon["types"]).is_empty())
	sim.world.set_biome(7, true)
	t.check("spark pools hurt (dmg 0.045, flat 4, every 0.7)", float(sim.world.liquid_effect(pl.mon["types"]).get("every", 0.0)) == 0.7)
	# ice: sliding (velocity damps toward axis*spd*1.15 at rate 1.6)
	sim.world.set_biome(8, true)
	var ws := sim.world
	var ice := _liquid_tile(ws)
	pl.x = ice.x * 32.0 + 16.0
	pl.y = ice.y * 32.0 + 16.0
	pl.in_liquid = true
	pl.svx = 0.0
	sim.input_axis = Vector2(1, 0)
	sim.enemies.clear()
	sim.update(1.0 / 60.0)
	var exp := U.damp(0.0, pl.spd() * 1.15, 1.6, 1.0 / 60.0)
	t.check("ice: first frame velocity = damp(0, spd*1.15, 1.6, dt) (slides)", absf(pl.svx - exp) < 1e-6 and pl.svx < pl.spd() * 0.1,
		"svx %.3f exp %.3f" % [pl.svx, exp])
	sim.input_axis = Vector2.ZERO
	# destructibles: a rock breaks after 34 damage, stays broken across chunk regeneration
	var rock: WorldProp = null
	var grass: WorldProp = null
	for cy in range(-2, 3):
		for cx in range(-2, 3):
			for p in ws.chunk_data(cx, cy).props:
				if p.type == "rock" and rock == null:
					rock = p
				if p.type == "grass" and grass == null:
					grass = p
	t.check("rock and grass props exist near the start", rock != null and grass != null)
	if rock != null:
		var n0 := sim.pickups.count()
		var broke1 := ws.damage_prop(rock, 20.0)
		var mid_variant := PropArt.variant_of(rock, 0.0)
		var broke2 := ws.damage_prop(rock, 20.0)
		var k := Vector2i(rock.tx >> 4, rock.ty >> 4)
		ws._data.erase(k)                         # evict + regenerate the chunk
		ws._fifo.erase(k)
		ws._last_cx = 1 << 40
		var again := ws.prop_at_tile(rock.tx, rock.ty)
		t.check("rock: 20 dmg cracks it (variant 1), 40 breaks it, loot rolled, stays broken after regeneration",
			not broke1 and mid_variant == 1 and broke2 and again == null and ws.broken.has(Vector2i(rock.tx, rock.ty))
			and ws.walkable(rock.tx, rock.ty) and sim.pickups.count() >= n0, "pickups %d -> %d" % [n0, sim.pickups.count()])
	if grass != null:
		t.check("grass is cut by any hit (hp 1) and never blocks", ws.damage_prop(grass, 1.0) and not grass.solid)
	# projectiles: trees stop player shots (indestructible), rocks don't block a ray once broken
	var tree: WorldProp = null
	for p in ws.chunk_data(1, 1).props + ws.chunk_data(-1, 1).props + ws.chunk_data(1, -1).props + ws.chunk_data(-1, -1).props:
		if p.type == "tree":
			tree = p
			break
	if tree != null:
		var b: Variant = ws.projectile_block_any(tree.x + 3.0, tree.y - 2.0, 4.0)
		t.check("a shot at a tree is blocked by it (solid, indestructible)", b is WorldProp and (b as WorldProp).type == "tree"
			and ws.projectile_block(tree.x + 3.0, tree.y - 2.0, 4.0) == "prop")
	# player auto-aims at the nearest breakable when no enemy is around
	var tgt: WorldProp = null
	for cy in range(-2, 3):
		for cx in range(-2, 3):
			for p in ws.chunk_data(cx, cy).props:
				if p.solid and p.destructible and tgt == null:
					tgt = p
	if tgt != null:
		pl.x = tgt.x + 60.0
		pl.y = tgt.y + 40.0
		ws.collide(pl)
		sim.enemies.clear()
		sim.update(1.0 / 60.0)
		t.check("no enemies: the player targets the nearest rock/chest (%s)" % tgt.type, pl.target is WorldProp)
	# biome cycle: every 240 s, through all 21 palettes, crossfading 2.6 s
	sim.time = 239.99
	sim.enemies.clear()
	sim.update(1.0 / 60.0)
	var fade0 := sim.world.fade_k()
	for i in 80:
		sim.enemies.clear()
		sim.update(1.0 / 60.0)
	var fade1 := sim.world.fade_k()
	for i in 90:
		sim.enemies.clear()
		sim.update(1.0 / 60.0)
	t.check("biome 1 at 4:00 with a 2.6 s crossfade (k 0 -> %.2f -> done)" % fade1, sim.world.biome == 1 and fade0 >= 0.0 and fade0 < 0.01
		and fade1 > 0.4 and fade1 < 0.9 and sim.world.fade_k() < 0.0, "biome %d fade %.3f/%.3f/%.3f" % [sim.world.biome, fade0, fade1, sim.world.fade_k()])
	sim.world.set_biome(22, true)
	t.check("set_biome wraps over the 21 palettes (22 -> 1, -1 -> 20)", sim.world.biome == 1 and (func(): sim.world.set_biome(-1, true); return sim.world.biome).call() == 20)
	var names: Array = []
	for i in 21:
		names.append(Data.biomes[i]["name"])
	t.check("21 biome names (3 overworld + 18 rift arenas): %s ... %s" % [names[0], names[20]], names.size() == 21 and str(names[4]).begins_with("Grieta · "))
	# weather wiring: Combat/Player multipliers and snow slow through Sim.weather
	sim.weather.force("rain", 60.0)
	sim.weather.cur["t"] = 3.0
	var rain_ok := absf(Weather.mult_of("water") - 1.5) < 1e-12 and absf(Weather.mult_of("fire") - 0.5) < 1e-12 and Weather.mult_of("grass") == 1.0
	sim.weather.force("snow", 60.0)
	sim.weather.cur["t"] = 3.0
	pl.in_liquid = false
	var sp_snow := pl.spd()
	sim.weather.clear()
	var sp_clear := pl.spd()
	t.check("weather wiring: rain water x1.5 / fire x0.5, snow slows a non-Ice partner to 0.9x", rain_ok and absf(sp_snow / sp_clear - 0.9) < 1e-12,
		"%.3f" % (sp_snow / sp_clear))
	# painter on worker threads (the game path): wall time for 8 chunks in parallel
	var jobs: Array = []
	var tw := Time.get_ticks_usec()
	for i in 8:
		var job := GroundLayer.Job.new()
		job.key = Vector2i(10 + i, -7)
		job.seed = 12345
		job.k18 = ws.terrain_block(10 + i, -7)
		job.task = WorkerThreadPool.add_task(GroundLayer._paint_job.bind(job), false, "test paint")
		jobs.append(job)
	var mx := 0
	var acc := 0
	for job in jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
		mx = maxi(mx, job.us)
		acc += job.us
	var wall := Time.get_ticks_usec() - tw
	print("  paint on WorkerThreadPool: 8 chunks in %.1f ms wall (per chunk avg %.1f ms, max %.1f ms; %d threads)" % [
		wall / 1000.0, acc / 8000.0, mx / 1000.0, OS.get_processor_count()])
	t.check("8 chunks painted on worker threads, identical to the main-thread painter",
		(jobs[0] as GroundLayer.Job).out == WorldPaint.paint(10, -7, ws.terrain_block(10, -7), 12345))
	Sim.cur = keep

## A liquid tile near the start (spiral over chunks), or (1<<30, 0).
static func _liquid_tile(w: WorldMap) -> Vector2i:
	for r in range(0, 6):
		for cy in range(-r, r + 1):
			for cx in range(-r, r + 1):
				var l := w.chunk_data(cx, cy).liquids
				for i in range(0, l.size(), 2):
					var tx := l[i]
					var ty := l[i + 1]
					# deep inside: the 3x3 around it is liquid too
					var deep := true
					for b in range(-1, 2):
						for a in range(-1, 2):
							if w.terrain_at(tx + a, ty + b) != WorldMap.LIQUID:
								deep = false
					if deep:
						return Vector2i(tx, ty)
	return Vector2i(1 << 30, 0)
