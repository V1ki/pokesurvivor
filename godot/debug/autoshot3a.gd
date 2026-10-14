class_name Autoshot3a
extends RefCounted
## Phase 3a visual check (main.gd --autoshot=<dir> --p3a): after the title (menu backdrop) shot,
## starts a run in god mode and visits several biomes x weathers next to liquids and props,
## a biome crossfade and a prop close-up, saving one PNG per scene, then quits.
##   godot --path godot -- --autoshot=/tmp/shots --p3a [--seed=n]

const SCENES := [
	{"name": "b00_forest", "biome": 0, "weather": "", "seek": "liquid"},
	{"name": "b00_props", "biome": 0, "weather": "", "seek": "special"},
	{"name": "b00_rain", "biome": 0, "weather": "rain", "seek": "grove"},
	{"name": "b01_cave_fog", "biome": 1, "weather": "fog", "seek": "liquid"},
	{"name": "b02_volcano_sun", "biome": 2, "weather": "sun", "seek": "liquid"},
	{"name": "b04_fire_sand", "biome": 4, "weather": "sand", "seek": "liquid"},
	{"name": "b05_water", "biome": 5, "weather": "", "seek": "liquid"},
	{"name": "b06_grass_swamp", "biome": 6, "weather": "rain", "seek": "liquid"},
	{"name": "b07_electric_spark", "biome": 7, "weather": "", "seek": "liquid"},
	{"name": "b08_ice_snow", "biome": 8, "weather": "snow", "seek": "liquid"},
	{"name": "b10_poison", "biome": 10, "weather": "", "seek": "liquid"},
	{"name": "b16_ghost_fog", "biome": 16, "weather": "fog", "seek": "special"},
	{"name": "b17_dragon", "biome": 17, "weather": "", "seek": "liquid"},
	{"name": "fade_0_to_1", "biome": 0, "weather": "", "seek": "liquid", "fade_to": 1},
]

static var _i := -1
static var _t := 0.0
static var _phase := ""

static func axis(_game: Node) -> Vector2:
	return Vector2.ZERO

static func tick(game: Node) -> void:
	var sim: Sim = game.get("sim")
	if sim.state == "levelup" or sim.state == "choice":
		Bot.pick(sim)
		game.get("screens").call("hide_all")
		return
	if sim.state != "playing" or sim.player == null:
		return
	sim.player.god = true
	sim.player.invuln = 1.0
	var dt := game.get_process_delta_time()
	_t += dt
	if _phase == "":
		_i += 1
		if _i >= SCENES.size():
			_phase = "done"
			var gl: GroundLayer = game.get("world_view").get("ground")
			print("autoshot3a: done; ground ", gl.stats(), " ", gl.take_perf())
			game.get_tree().create_timer(0.3).timeout.connect(func(): game.get_tree().quit())
			return
		_setup(sim, SCENES[_i])
		_phase = "wait"
		_t = 0.0
		return
	if _phase == "wait":
		var sc: Dictionary = SCENES[_i]
		if sc.has("fade_to") and _t > 0.6 and sim.world.biome != int(sc["fade_to"]):
			sim.world.set_biome(int(sc["fade_to"]))         # crossfade starts (2.6 s)
			_t = 0.0
			return
		var need := 1.3 if sc.has("fade_to") else 1.2
		if _t >= need:
			_phase = "shot"
			game.call("_shot", "p3a_" + str(sc["name"]))
			print("autoshot3a: %s biome %d (%s) weather %s fade_k %.2f at (%.0f, %.0f)" % [sc["name"], sim.world.biome,
				sim.world.biome_name(), sim.weather.cur.get("kind", "-"), sim.world.fade_k(), sim.player.x, sim.player.y])
			_t = 0.0
		return
	if _phase == "shot" and _t > 0.25:
		_phase = ""

static func _setup(sim: Sim, sc: Dictionary) -> void:
	var w := sim.world
	w.set_biome(int(sc["biome"]), true)
	sim.weather.clear()
	if str(sc["weather"]) != "":
		sim.weather.force(str(sc["weather"]), 120.0)
		sim.weather.cur["t"] = 3.0                  # full intensity right away
	var spot := _seek(w, str(sc["seek"]), sim.player.x, sim.player.y)
	sim.player.x = spot.x
	sim.player.y = spot.y
	sim.cam.x = spot.x
	sim.cam.y = spot.y
	sim.enemies.clear()
	sim.projectiles.clear()

## A spot next to liquid / an interactable / a grove, searched in rings of chunks around (x, y)
## (never the chunk the player stands in, so every scene shows a new place).
static func _seek(w: WorldMap, what: String, x: float, y: float) -> Vector2:
	var c0 := Vector2i(int(floorf(x / WorldMap.CW)), int(floorf(y / WorldMap.CW)))
	for rad in range(1, 9):
		for cy in range(c0.y - rad, c0.y + rad + 1):
			for cx in range(c0.x - rad, c0.x + rad + 1):
				if maxi(absi(cx - c0.x), absi(cy - c0.y)) != rad:
					continue
				var cd := w.chunk_data(cx, cy)
				if what == "liquid" and cd.liquids.size() >= 2 * 14:
					# a floor tile 2-3 tiles from the first liquid tile near the chunk centre
					var best := Vector2i(cd.liquids[0], cd.liquids[1])
					var bd := 1e9
					for i in range(0, cd.liquids.size(), 2):
						var d := absf(cd.liquids[i] - (cx * 16 + 8)) + absf(cd.liquids[i + 1] - (cy * 16 + 8))
						if d < bd:
							bd = d
							best = Vector2i(cd.liquids[i], cd.liquids[i + 1])
					for off: Vector2i in [Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(2, 2)]:
						var px := (best.x + off.x) * WorldMap.TS + 16.0
						var py := (best.y + off.y) * WorldMap.TS + 16.0
						if w.is_free(px, py, 12.0):
							return Vector2(px, py)
					return Vector2(best.x * WorldMap.TS + 16.0, best.y * WorldMap.TS + 16.0)
				for p in cd.props:
					var ok := (what == "special" and WorldMap.SPECIAL.has(p.type)) or (what == "grove" and p.type == "tree")
					if ok and w.is_free(p.x, p.y + 50.0, 12.0):
						return Vector2(p.x, p.y + 50.0)
	return Vector2(x + 900.0, y)
