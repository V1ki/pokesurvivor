class_name WorldMap
extends RefCounted
## Infinite deterministic world (port of js/world/world.js): terrain (bit-exact noise, §7.2),
## chunk data cache with props (§7.3), legendary arena terrain (setArena, §7.11), collision and
## queries (§7.5), liquids (§7.6), prop damage + loot, biome palette + crossfade state (§7.4).
## Chunk data can be generated on worker threads (request_chunk); everything a worker computes
## is a pure function of (tile, seed, arena snapshot). Rendering lives in render/ground_layer.gd
## (painter: sim/world_paint.gd, prop sprites: render/prop_art.gd).

const N := 16                    # tiles per chunk
const TS := 32.0                 # tile size in wu (16 art px * 2)
const CW := 512.0                # chunk size in wu
const FLOOR := 0
const WALL := 1
const LIQUID := 2
const MAX_DATA := 400
const FADE := 2.6                # biome crossfade (s)

## Liquid effects per kind (world.js LIQ). dmg = fraction of max HP.
const LIQ := {
	"water": {"slow": 0.6, "immune": ["water"]},
	"swamp": {"slow": 0.45, "immune": ["water"]},
	"lava": {"dmg": 0.06, "flat": 5.0, "every": 0.5, "color": "#ff8a3d", "immune": ["fire"]},
	"poison": {"dmg": 0.035, "flat": 3.0, "every": 0.5, "color": "#c86bdc", "immune": ["poison", "steel"]},
	"spark": {"dmg": 0.045, "flat": 4.0, "every": 0.7, "color": "#ffe14d", "immune": ["electric", "ground"]},
	"ice": {"slide": true, "immune": ["ice"]},
}

## PROP table (world.js): hp INF = indestructible.
const PROP := {
	"tree": {"solid": true, "hp": INF, "r": 13.0},
	"rock": {"solid": true, "hp": 34.0, "r": 12.0},
	"chest": {"solid": true, "hp": 22.0, "r": 12.0},
	"grass": {"solid": false, "hp": 1.0, "r": 14.0},
	"altar": {"solid": true, "hp": INF, "r": 9.0},
	"spring": {"solid": false, "hp": INF, "r": 22.0, "flat": true},
	"bigchest": {"solid": true, "hp": INF, "r": 14.0},
	"trap": {"solid": false, "hp": INF, "r": 9.0, "flat": true},
}
const PROP_TYPES := ["tree", "rock", "chest", "grass", "altar", "spring", "bigchest", "trap"]
const P_TREE := 0
const P_ROCK := 1
const P_CHEST := 2
const P_GRASS := 3
const P_ALTAR := 4
const P_SPRING := 5
const P_BIGCHEST := 6
const P_TRAP := 7
const SPECIAL := {"altar": true, "spring": true, "bigchest": true, "trap": true}

## One chunk of data (world.js chunkData): terrain, props, solid-prop index, liquid tiles.
class ChunkData:
	var cx := 0
	var cy := 0
	var terr := PackedByteArray()        # 256 terrain kinds
	var solid := PackedByteArray()       # 256: 1 where a solid prop stands (pathing, fast checks)
	var props: Array[WorldProp] = []
	var prop_at: Dictionary = {}         # local tile index -> solid WorldProp
	var liquids := PackedInt32Array()    # tx, ty pairs (liquid shimmer)
	# destructible props (props order) with x, y, r packed, for props_in_circle (projectiles hit
	# it every frame); rebuilt when `props` changes size or destroy_prop() marks it dirty
	var dprops: Array[WorldProp] = []
	var dxyr := PackedFloat64Array()
	var dsize := -1

	func destructibles() -> void:
		if dsize == props.size():
			return
		dsize = props.size()
		dprops.clear()
		dxyr.clear()
		for p in props:
			if p.destructible:
				dprops.append(p)
				dxyr.append(p.x)
				dxyr.append(p.y)
				dxyr.append(p.r)

## Chunk generation job (worker thread or synchronous). Inputs are copies: no shared state.
class ChunkJob:
	var task := -1
	var seed := 1
	var version := 0
	var cx := 0
	var cy := 0
	var arena: Dictionary = {}
	var terr := PackedByteArray()
	var liquids := PackedInt32Array()
	var props := PackedInt32Array()      # [type index, tx, ty, kind] per prop

var seed := 1
var biome := 0
var biome_version := 0           # bumps when the palette changes
var terrain_version := 0         # bumps on reset(): every cached chunk/texture is stale
var arena: Dictionary = {}       # {tx, ty, r, type, th} in tiles, {} = none (rift.js)
var purge_serial := 0            # bumps when set_arena() forgets the chunks around the arena
var broken: Dictionary = {}      # Vector2i(tx, ty) -> true: destroyed props
var fade_from := -1              # biome crossfade: old biome index, -1 = no fade
var fade_t := 0.0
var _next_prop_id := 1
var _data: Dictionary = {}       # Vector2i(cx, cy) -> ChunkData
var _fifo: Array[Vector2i] = []
var _last_cx := 1 << 40          # one-entry cache: most lookups hit the same chunk
var _last_cy := 1 << 40
var _last_d: ChunkData = null
## Generate chunks requested with request_chunk() on worker threads (the game; headless
## runs stay synchronous and deterministic).
var async_chunks := false
var _pending: Dictionary = {}    # Vector2i -> ChunkJob

static var _wj: Dictionary = {}

## data/world.json (arena themes, weather tables).
static func world_json() -> Dictionary:
	if _wj.is_empty():
		_wj = Data._json("world.json")
	return _wj

## Biome index of a type's rift arena (G.Tiles.arenaBiome).
static func arena_biome(type: String) -> int:
	var w := world_json()
	return int(w["arena_first"]) + maxi(0, (w["arena_types"] as Array).find(type))

func reset(s: int) -> void:
	_finish_pending()
	seed = s if s != 0 else 1
	_data.clear()
	_fifo.clear()
	broken.clear()
	arena = {}
	fade_from = -1
	_last_cx = 1 << 40
	_last_d = null
	biome_version += 1
	terrain_version += 1

## Biome index wraps over all palettes (21: 3 overworld + 18 arena themes). Not instant:
## the old palette fades out over FADE s (ground and props).
func set_biome(i: int, instant := false) -> void:
	var n := Data.biomes.size()
	var b := posmod(i, n) if n > 0 else 0
	if b == biome:
		return
	fade_from = -1 if instant else biome
	fade_t = 0.0
	biome = b
	biome_version += 1

## Smoothstepped crossfade 0..1, or -1 when no fade is running (world.js fadeK).
func fade_k() -> float:
	if fade_from < 0:
		return -1.0
	var x := minf(1.0, fade_t / FADE)
	return x * x * (3.0 - 2.0 * x)

func biome_name() -> String:
	return Data.biomes[biome]["name"] if biome < Data.biomes.size() else ""

func liquid_kind() -> String:
	return Data.biomes[biome]["liquid"] if biome < Data.biomes.size() else "water"

# ---------------- noise (bit-exact with JS) ----------------

func vnoise(x: float, y: float, s: int) -> float:
	var fx := floorf(x)
	var fy := floorf(y)
	var xi := int(fx)
	var yi := int(fy)
	var xf := x - fx
	var yf := y - fy
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := U.hash01(xi, yi, s)
	var b := U.hash01(xi + 1, yi, s)
	var c := U.hash01(xi, yi + 1, s)
	var d := U.hash01(xi + 1, yi + 1, s)
	return (a + (b - a) * u) * (1.0 - v) + (c + (d - c) * u) * v

func fbm(x: float, y: float, s: int) -> float:
	return vnoise(x, y, s) * 0.65 + vnoise(x * 2.13 + 17.0, y * 2.13 - 9.0, s + 1) * 0.35

## Pure terrain of a tile (no cache).
func terrain_raw(tx: int, ty: int) -> int:
	return _terrain_seed(tx, ty, seed, arena)

## terrain_raw for an explicit seed and arena snapshot (also called from worker threads).
func _terrain_seed(tx: int, ty: int, s: int, ar: Dictionary = {}) -> int:
	if not ar.is_empty():
		var lx: int = tx - int(ar["tx"])
		var ly: int = ty - int(ar["ty"])
		var ad := sqrt(float(lx * lx + ly * ly))
		var r: float = ar["r"]
		if ad < r + 7.0:
			if ad >= r:
				return WALL
			if _arena_safe_l(lx, ly):
				return FLOOR
			var th: Dictionary = ar["th"]
			var pillars: float = th.get("pillars", 0.0)
			# 2x2 pillars (cover) and pools, by the arena's type
			if pillars > 0.0 and ad < r - 2.0 and U.hash01(tx >> 1, ty >> 1, s + 31 + int(ar["tx"])) < pillars:
				return WALL
			var pools: float = th.get("pools", 0.0)
			if pools > 0.0 and ad < r - 1.5 and fbm(tx / 3.2, ty / 3.2, s + 37 + int(ar["tx"])) < pools:
				return LIQUID
			return FLOOR
	var d := sqrt(float(tx * tx + ty * ty))
	if d < 9.0:
		return FLOOR                                   # start clearing
	var ramp := U.clampf_((d - 9.0) / 8.0, 0.0, 1.0)  # soft ramp
	if fbm(tx / 13.0, ty / 13.0, s + 101) < 0.04 + 0.23 * ramp:
		return LIQUID
	if fbm(tx / 8.0, ty / 8.0, s + 202) > 1.0 - 0.27 * ramp:
		return WALL
	return FLOOR

# ---------------- arena (rift.js / world.js setArena) ----------------

## Free corridor of the arena: where you appear (south) and the legendary (north).
static func _arena_safe_l(lx: int, ly: int) -> bool:
	return (absi(lx) <= 2 and ly >= -6 and ly <= 5) or sqrt(float(lx * lx + ly * ly)) < 2.5

func arena_dist(tx: int, ty: int) -> float:
	if arena.is_empty():
		return INF
	var lx: int = tx - int(arena["tx"])
	var ly: int = ty - int(arena["ty"])
	return sqrt(float(lx * lx + ly * ly))

func arena_safe(tx: int, ty: int) -> bool:
	return not arena.is_empty() and _arena_safe_l(tx - int(arena["tx"]), ty - int(arena["ty"]))

func arena_outer() -> float:
	return float(arena["r"]) + 7.0 if not arena.is_empty() else 0.0

## Turns a far zone into the round legendary arena: a = {tx, ty, r, type} (tiles); {} clears it.
## Like JS, clearing doesn't forget chunks; setting one forgets the chunks around it.
func set_arena(a: Dictionary) -> void:
	_finish_pending()
	if a.is_empty():
		arena = {}
		return
	var themes: Dictionary = world_json()["arena_themes"]
	arena = {"tx": int(a["tx"]), "ty": int(a["ty"]), "r": float(a["r"]), "type": str(a.get("type", "normal"))}
	arena["th"] = themes.get(arena["type"], themes["normal"])
	for k: Vector2i in _data.keys():
		if purges(k.x, k.y):
			_data.erase(k)
			_fifo.erase(k)
	_last_cx = 1 << 40
	_last_d = null
	purge_serial += 1

## Was chunk (cx, cy) forgotten by the last set_arena()? (the renderer drops its texture too)
func purges(cx: int, cy: int) -> bool:
	if arena.is_empty():
		return false
	var R: float = float(arena["r"]) + 9.0
	return absf(cx * N + N / 2.0 - int(arena["tx"])) < R + N and absf(cy * N + N / 2.0 - int(arena["ty"])) < R + N

# ---------------- chunk data ----------------

## Is the data of this chunk already generated (cached)?
func has_chunk(cx: int, cy: int) -> bool:
	return _data.has(Vector2i(cx, cy))

## Terrain kinds of a chunk (generated synchronously if needed).
func chunk(cx: int, cy: int) -> PackedByteArray:
	return chunk_data(cx, cy).terr

func chunk_data(cx: int, cy: int) -> ChunkData:
	var k := Vector2i(cx, cy)
	var c: ChunkData = _data.get(k)
	if c != null:
		return c
	var job: ChunkJob = _pending.get(k)
	if job != null:
		# needed right now: wait for the worker instead of computing it twice
		WorkerThreadPool.wait_for_task_completion(job.task)
		_pending.erase(k)
		if job.version == terrain_version and job.seed == seed:
			return _store_job(job)
	job = _new_job(cx, cy)
	_gen_job(job)
	return _store_job(job)

func _new_job(cx: int, cy: int) -> ChunkJob:
	var job := ChunkJob.new()
	job.seed = seed
	job.version = terrain_version
	job.cx = cx
	job.cy = cy
	job.arena = arena.duplicate()
	return job

func _store_job(job: ChunkJob) -> ChunkData:
	var c := ChunkData.new()
	c.cx = job.cx
	c.cy = job.cy
	c.terr = job.terr
	c.liquids = job.liquids
	c.solid.resize(N * N)
	var sp := job.props
	for i in range(0, sp.size(), 4):
		var tx := sp[i + 1]
		var ty := sp[i + 2]
		if broken.has(Vector2i(tx, ty)):
			continue
		var p := _make_prop(PROP_TYPES[sp[i]], tx, ty, sp[i + 3])
		c.props.append(p)
		if p.solid:
			var li := (ty & 15) * N + (tx & 15)
			c.prop_at[li] = p
			c.solid[li] = 1
	var k := Vector2i(job.cx, job.cy)
	if _data.size() > MAX_DATA:
		var old: Vector2i = _fifo.pop_front()
		_data.erase(old)
		if old.x == _last_cx and old.y == _last_cy:
			_last_cx = 1 << 40
			_last_d = null
	_data[k] = c
	_fifo.append(k)
	return c

func _make_prop(type: String, tx: int, ty: int, kind := 0) -> WorldProp:
	var d: Dictionary = PROP[type]
	var p := WorldProp.new()
	p.id = _next_prop_id
	_next_prop_id += 1
	p.type = type
	p.tx = tx
	p.ty = ty
	p.kind = kind
	p.x = tx * TS + TS / 2.0
	p.y = ty * TS + TS - 4.0
	p.r = d["r"]
	p.hp = d["hp"]
	p.max_hp = d["hp"]
	p.solid = d["solid"]
	p.flat = d.get("flat", false)
	p.destructible = p.hp != INF
	p.wiggle = U.hash01(tx, ty, 9) * 6.28
	return p

## Asks for a chunk without blocking: true once it is cached. Synchronous unless async_chunks.
func request_chunk(cx: int, cy: int) -> bool:
	var k := Vector2i(cx, cy)
	if _data.has(k):
		return true
	if not async_chunks:
		chunk_data(cx, cy)
		return true
	var job: ChunkJob = _pending.get(k)
	if job == null:
		job = _new_job(cx, cy)
		job.task = WorkerThreadPool.add_task(_gen_job.bind(job), false, "terrain chunk")
		_pending[k] = job
		return false
	if not WorkerThreadPool.is_task_completed(job.task):
		return false
	WorkerThreadPool.wait_for_task_completion(job.task)
	_pending.erase(k)
	if job.version == terrain_version and job.seed == seed:
		_store_job(job)
		return true
	return false

## Pure: terrain, liquid tiles and prop placement of one chunk (worker thread or main thread).
func _gen_job(job: ChunkJob) -> void:
	var s := job.seed
	var terr := PackedByteArray()
	terr.resize(N * N)
	var liq := PackedInt32Array()
	for j in N:
		for i in N:
			var tx := job.cx * N + i
			var ty := job.cy * N + j
			var t := _terrain_seed(tx, ty, s, job.arena)
			terr[j * N + i] = t
			if t == LIQUID:
				liq.append(tx)
				liq.append(ty)
	job.terr = terr
	job.liquids = liq
	job.props = _place_props(job.cx, job.cy, terr, s, job.arena)

## placeProps (world.js:118-163) as a pure function: [type index, tx, ty, kind] per prop, in
## JS order. Broken props are skipped when the chunk is stored. Neighbour terrain outside the
## chunk is computed lazily (only floor tiles need their 3x3 "open" test).
func _place_props(cx: int, cy: int, terr: PackedByteArray, s: int, ar: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var k18 := PackedByteArray()
	k18.resize(18 * 18)
	k18.fill(255)
	for j in N:
		for i in N:
			k18[(j + 1) * 18 + i + 1] = terr[j * N + i]
	var has_ar := not ar.is_empty()
	var atx: int = int(ar["tx"]) if has_ar else 0
	var aty: int = int(ar["ty"]) if has_ar else 0
	var ar_r: float = float(ar["r"]) if has_ar else 0.0
	var outer := ar_r + 7.0 if has_ar else 0.0
	for j in N:
		for i in N:
			if terr[j * N + i] != FLOOR:
				continue
			var tx := cx * N + i
			var ty := cy * N + j
			var d0 := sqrt(float(tx * tx + ty * ty))
			if d0 < 7.0:
				continue
			# needs floor all around so it never sticks to walls / water
			var open := true
			for b in range(-1, 2):
				for a in range(-1, 2):
					var ki := (j + 1 + b) * 18 + i + 1 + a
					var v := k18[ki]
					if v == 255:
						v = _terrain_seed(tx + a, ty + b, s, ar)
						k18[ki] = v
					if v != FLOOR:
						open = false
						break
				if not open:
					break
			# inside the arena: its type's decoration (and nothing in the corridor)
			var ad := INF
			if has_ar:
				ad = sqrt(float((tx - atx) * (tx - atx) + (ty - aty) * (ty - aty)))
			if ad < outer + 2.0:
				if not has_ar or ad >= ar_r - 1.2 or _arena_safe_l(tx - atx, ty - aty):
					continue
				var pr: Dictionary = (ar["th"] as Dictionary).get("props", {})
				var hh := U.hash01(tx, ty, s + 777)
				var ptree: float = pr.get("tree", 0.0)
				var prock: float = pr.get("rock", 0.0)
				var pgrass: float = pr.get("grass", 0.0)
				var at := -1
				if open and hh < ptree:
					at = P_TREE
				elif open and hh < ptree + prock:
					at = P_ROCK
				elif hh > 1.0 - pgrass:
					at = P_GRASS
				if at >= 0:
					out.append_array([at, tx, ty, 0])
				continue
			var type := -1
			var kind := 0
			# interactables (rare), away from the start clearing
			if open and d0 > 12.0:
				var hs := U.hash01(tx, ty, s + 909)
				if hs < 0.0032:
					type = P_ALTAR if hs < 0.0004 else (P_SPRING if hs < 0.0008 else (P_BIGCHEST if hs < 0.0011 else P_TRAP))
					kind = int(floorf(U.hash01(tx, ty, s + 910) * (4.0 if type == P_ALTAR else 3.0)))
			if type < 0 and open:
				var h := U.hash01(tx, ty, s + 404)
				if h < 0.07 and h < (0.07 if fbm(tx / 10.0, ty / 10.0, s + 505) > 0.6 else 0.006):
					type = P_TREE
				elif h > 0.992:
					type = P_ROCK
				elif h > 0.985 and h <= 0.992 and U.hash01(tx, ty, s + 606) < 0.07:
					type = P_CHEST
			if type < 0 and U.hash01(tx, ty, s + 808) < 0.75 and fbm(tx / 5.0, ty / 5.0, s + 707) > 0.66:
				type = P_GRASS
			if type >= 0:
				out.append_array([type, tx, ty, kind])
	return out

func _finish_pending() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion((_pending[k] as ChunkJob).task)
	_pending.clear()

## 18x18 terrain kinds around chunk (cx, cy) (1-tile border) for the ground painter, or an
## empty array while a neighbour chunk is still being generated (async mode, unless wait).
func terrain_block(cx: int, cy: int, wait := false) -> PackedByteArray:
	for b in range(-1, 2):
		for a in range(-1, 2):
			if wait:
				chunk_data(cx + a, cy + b)
			elif not request_chunk(cx + a, cy + b):
				return PackedByteArray()
	var out := PackedByteArray()
	out.resize(18 * 18)
	for b in range(-1, 2):
		for a in range(-1, 2):
			var t: PackedByteArray = (_data[Vector2i(cx + a, cy + b)] as ChunkData).terr
			for j in N:
				var oy := b * N + j + 1
				if oy < 0 or oy >= 18:
					continue
				for i in N:
					var ox := a * N + i + 1
					if ox >= 0 and ox < 18:
						out[oy * 18 + ox] = t[j * N + i]
	return out

func terrain_at(tx: int, ty: int) -> int:
	var cx := tx >> 4
	var cy := ty >> 4
	if cx != _last_cx or cy != _last_cy:
		_last_d = chunk_data(cx, cy)
		_last_cx = cx
		_last_cy = cy
	return _last_d.terr[(ty & 15) * N + (tx & 15)]

## Solid prop standing on a tile, or null (world.js propAtTile).
func prop_at_tile(tx: int, ty: int) -> WorldProp:
	var cx := tx >> 4
	var cy := ty >> 4
	if cx != _last_cx or cy != _last_cy:
		_last_d = chunk_data(cx, cy)
		_last_cx = cx
		_last_cy = cy
	if _last_d.solid[(ty & 15) * N + (tx & 15)] == 0:
		return null
	return _last_d.prop_at.get((ty & 15) * N + (tx & 15))

static func tile_of(v: float) -> int:
	return int(floorf(v / TS))

func kind_at(x: float, y: float) -> int:
	return terrain_at(tile_of(x), tile_of(y))

func is_wall(x: float, y: float) -> bool:
	return terrain_at(tile_of(x), tile_of(y)) == WALL

func is_liquid(x: float, y: float) -> bool:
	return terrain_at(tile_of(x), tile_of(y)) == LIQUID

## Effect of the current liquid on a Pokémon of these types ({} if immune).
func liquid_effect(types: Array) -> Dictionary:
	var e: Dictionary = LIQ.get(liquid_kind(), LIQ["water"])
	for t in types:
		if (e["immune"] as Array).has(t):
			return {}
	return e

## Can an enemy walk through this tile? (pathing.js)
func walkable(tx: int, ty: int) -> bool:
	var t := terrain_at(tx, ty)
	if t == WALL:
		return false
	if t == LIQUID and LIQ.get(liquid_kind(), {}).has("dmg"):
		return false
	return prop_at_tile(tx, ty) == null

## Fast bulk walkable(): fills out[off + j*stride + i] (1/0) for tiles (ox+i, oy+j), 0 <= i, j < n,
## reading whole chunks at once (the flow field needs 57x57 tiles every 0.35 s).
## Keep in sync with walkable().
func fill_walkable(out: PackedByteArray, ox: int, oy: int, n: int, stride: int, off: int) -> void:
	var codes := PackedInt32Array()
	codes.resize(out.size())
	fill_walk_codes(codes, ox, oy, n, stride, off, 1, 0)
	for j in n:
		var row := off + j * stride
		for i in n:
			out[row + i] = codes[row + i]

## fill_walkable() into int codes: open_v where walkable, closed_v where not (the flow field
## writes its UNSEEN / BLOCK distance codes directly). Keep in sync with walkable().
func fill_walk_codes(out: PackedInt32Array, ox: int, oy: int, n: int, stride: int, off: int,
		open_v: int, closed_v: int) -> void:
	var bad_liquid: bool = LIQ.get(liquid_kind(), {}).has("dmg")
	var cx0 := ox >> 4
	var cx1 := (ox + n - 1) >> 4
	var cy0 := oy >> 4
	var cy1 := (oy + n - 1) >> 4
	for cy in range(cy0, cy1 + 1):
		var j0 := maxi(oy, cy * N)
		var j1 := mini(oy + n - 1, cy * N + N - 1)
		for cx in range(cx0, cx1 + 1):
			var cd := chunk_data(cx, cy)
			var c := cd.terr
			var so := cd.solid
			var i0 := maxi(ox, cx * N)
			var i1 := mini(ox + n - 1, cx * N + N - 1)
			for ty in range(j0, j1 + 1):
				var src := (ty - cy * N) * N - cx * N
				var dst := off + (ty - oy) * stride - ox
				for tx in range(i0, i1 + 1):
					var t := c[src + tx]
					out[dst + tx] = closed_v if (t == WALL or (t == LIQUID and bad_liquid) or so[src + tx] != 0) else open_v

## Is there room for something of radius r here? (no wall, no liquid unless allowed, no solid prop)
func is_free(x: float, y: float, r := 12.0, allow_liquid := false) -> bool:
	var t0x := tile_of(x - r)
	var t1x := tile_of(x + r)
	var t0y := tile_of(y - r)
	var t1y := tile_of(y + r)
	for ty in range(t0y, t1y + 1):
		for tx in range(t0x, t1x + 1):
			var t := terrain_at(tx, ty)
			if t == WALL or (not allow_liquid and t == LIQUID):
				return false
			var p := prop_at_tile(tx, ty)
			if p != null and U.dist2(x, y, p.x, p.y) < (r + p.r) * (r + p.r):
				return false
	return true

## Push a circle out of walls and solid props (2 passes, sliding). True if it hit something.
func collide(e: Body) -> bool:
	var r := e.r
	# fast path (open ground, the common case): no wall / solid prop under the AABB
	var any := false
	var t0x := int(floorf((e.x - r) / TS))           # tile_of() inlined
	var t1x := int(floorf((e.x + r) / TS))
	var t0y := int(floorf((e.y - r) / TS))
	var t1y := int(floorf((e.y + r) / TS))
	if (t0x >> 4) == (t1x >> 4) and (t0y >> 4) == (t1y >> 4):
		# AABB inside one chunk: read its arrays directly (same chunk fetch as terrain_at)
		if (t0x >> 4) != _last_cx or (t0y >> 4) != _last_cy:
			_last_d = chunk_data(t0x >> 4, t0y >> 4)
			_last_cx = t0x >> 4
			_last_cy = t0y >> 4
		var terr := _last_d.terr
		var so := _last_d.solid
		for ty in range(t0y, t1y + 1):
			var row := (ty & 15) * N
			for tx in range(t0x, t1x + 1):
				if terr[row + (tx & 15)] == WALL or so[row + (tx & 15)] != 0:
					any = true
	else:
		for ty in range(t0y, t1y + 1):
			for tx in range(t0x, t1x + 1):
				if terrain_at(tx, ty) == WALL or _last_d.solid[(ty & 15) * N + (tx & 15)] != 0:
					any = true
	if not any:
		return false
	var hit := false
	for pass_i in 2:
		t0x = tile_of(e.x - r)
		t1x = tile_of(e.x + r)
		t0y = tile_of(e.y - r)
		t1y = tile_of(e.y + r)
		for ty in range(t0y, t1y + 1):
			for tx in range(t0x, t1x + 1):
				var li := (ty & 15) * N + (tx & 15)
				if terrain_at(tx, ty) == WALL:         # (also points _last_d at this tile's chunk)
					# closest point of the tile box to the circle centre
					var bx0 := tx * TS
					var by0 := ty * TS
					var bx1 := bx0 + TS
					var by1 := by0 + TS
					var qx := U.clampf_(e.x, bx0, bx1)
					var qy := U.clampf_(e.y, by0, by1)
					var dx := e.x - qx
					var dy := e.y - qy
					var d2 := dx * dx + dy * dy
					if d2 >= r * r:
						continue
					hit = true
					if d2 > 1e-6:
						var d := sqrt(d2)
						e.x += dx / d * (r - d)
						e.y += dy / d * (r - d)
					else:
						# centre inside the box: leave through the nearest side
						var l := e.x - bx0
						var rr := bx1 - e.x
						var u := e.y - by0
						var b := by1 - e.y
						var m := minf(minf(l, rr), minf(u, b))
						if m == l:
							e.x = bx0 - r
						elif m == rr:
							e.x = bx1 + r
						elif m == u:
							e.y = by0 - r
						else:
							e.y = by1 + r
				if _last_d.solid[li] != 0:
					var p: WorldProp = _last_d.prop_at[li]
					var pdx := e.x - p.x
					var pdy := e.y - p.y
					var mn := r + p.r
					var pd2 := pdx * pdx + pdy * pdy
					if pd2 < mn * mn:
						hit = true
						var d := sqrt(pd2)
						if d == 0.0:
							d = 0.01
						e.x = p.x + pdx / d * mn
						e.y = p.y + pdy / d * mn
	return hit

## world.js projectileBlock: "wall", the solid WorldProp that stops a shot here, or null.
func projectile_block_any(x: float, y: float, r: float) -> Variant:
	var tx := tile_of(x)
	var ty := tile_of(y)
	if terrain_at(tx, ty) == WALL:
		return "wall"
	if ((tx - 1) >> 4) == ((tx + 1) >> 4) and ((ty - 1) >> 4) == ((ty + 1) >> 4):
		# fast path: the 3x3 tiles are in the chunk terrain_at just cached; same scan order,
		# only tiles flagged solid look their prop up
		var so := _last_d.solid
		for b in range(-1, 2):
			var row := ((ty + b) & 15) * N
			for a in range(-1, 2):
				var li := row + ((tx + a) & 15)
				if so[li] == 0:
					continue
				var p: WorldProp = _last_d.prop_at.get(li)
				if p != null and U.dist2(x, y, p.x, p.y) < (r + p.r) * (r + p.r):
					return p
		return null
	for b in range(-1, 2):
		for a in range(-1, 2):
			var p := prop_at_tile(tx + a, ty + b)
			if p != null and U.dist2(x, y, p.x, p.y) < (r + p.r) * (r + p.r):
				return p
	return null

## Does a projectile hit something here? "wall", "prop" (any solid prop) or "".
func projectile_block(x: float, y: float, r: float) -> String:
	var b: Variant = projectile_block_any(x, y, r)
	if b == null:
		return ""
	return "wall" if b is String else "prop"

# ---------------- props: queries ----------------

## Destructible props (grass included) with hp left that touch a circle.
## Scans each chunk's packed destructible list (same props, same order as `props`).
func props_in_circle(x: float, y: float, r: float) -> Array[WorldProp]:
	var out: Array[WorldProp] = []
	var c0x := int(floorf((x - r) / CW))
	var c1x := int(floorf((x + r) / CW))
	var c0y := int(floorf((y - r) / CW))
	var c1y := int(floorf((y + r) / CW))
	for cy in range(c0y, c1y + 1):
		for cx in range(c0x, c1x + 1):
			var cd := chunk_data(cx, cy)
			cd.destructibles()
			var xyr := cd.dxyr
			for i in cd.dprops.size():
				var rr := r + xyr[i * 3 + 2]
				var dx := xyr[i * 3] - x
				var dy := xyr[i * 3 + 1] - y
				if dx * dx + dy * dy <= rr * rr:
					var p := cd.dprops[i]
					if p.hp > 0.0:
						out.append(p)
	return out

## Interactables (altars, springs, locked chests, traps) near a point (interact.js).
func specials_near(x: float, y: float, r: float) -> Array[WorldProp]:
	var out: Array[WorldProp] = []
	var c0x := int(floorf((x - r) / CW))
	var c1x := int(floorf((x + r) / CW))
	var c0y := int(floorf((y - r) / CW))
	var c1y := int(floorf((y + r) / CW))
	for cy in range(c0y, c1y + 1):
		for cx in range(c0x, c1x + 1):
			for p in chunk_data(cx, cy).props:
				if SPECIAL.has(p.type) and U.dist2(x, y, p.x, p.y) <= (r + p.r) * (r + p.r):
					out.append(p)
	return out

## Nearest rock or chest (auto-aim when no enemies are around), or null.
func nearest_breakable(x: float, y: float, r: float) -> WorldProp:
	var best: WorldProp = null
	var bd := r * r
	for p in props_in_circle(x, y, r):
		if not p.solid:
			continue
		var d := U.dist2(x, y, p.x, p.y)
		if d < bd:
			bd = d
			best = p
	return best

## Props near the view (pad 60 chunks, 70 wu), for the y-sorted draw pass.
func visible_props(cam: SimCamera) -> Array[WorldProp]:
	var out: Array[WorldProp] = []
	var x0 := int(floorf((cam.left() - 60.0) / CW))
	var x1 := int(floorf((cam.left() + cam.w + 60.0) / CW))
	var y0 := int(floorf((cam.top() - 60.0) / CW))
	var y1 := int(floorf((cam.top() + cam.h + 60.0) / CW))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c: ChunkData = _data.get(Vector2i(cx, cy))
			if c == null:
				continue           # not generated yet (async): nothing to draw this frame
			for p in c.props:
				if cam.sees(p.x, p.y, 70.0):
					out.append(p)
	return out

## Liquid tiles (tx, ty pairs) of a cached chunk, empty if not generated.
func liquids_of(cx: int, cy: int) -> PackedInt32Array:
	var c: ChunkData = _data.get(Vector2i(cx, cy))
	return c.liquids if c != null else PackedInt32Array()

# ---------------- props: damage and loot ----------------

## Hit a destructible prop. True if it broke.
func damage_prop(p: WorldProp, amount: float, color := Color.WHITE) -> bool:
	if not p.destructible or p.hp <= 0.0:
		return false
	p.hp -= amount
	p.flash = 0.08
	if p.type != "grass" and Sim.cur != null:
		Sim.cur.fx.spark(p.x, p.y - 10.0, color, 0.0, -1.0, 3)
	if p.hp <= 0.0:
		destroy_prop(p)
		return true
	return false

## Breaks a prop now (interactables: chest opened, trap triggered), once.
func break_prop(p: WorldProp) -> void:
	if not broken.has(Vector2i(p.tx, p.ty)):
		destroy_prop(p)

## XP that gives exactly one level (game.js levelXp), for the locked chest.
static func level_xp() -> float:
	var pl: Player = Sim.cur.player if Sim.cur != null else null
	if pl == null:
		return 20.0
	var k := pl.xp_mul if pl.xp_mul != 0.0 else 1.0
	return ceilf((pl.xp_next - pl.xp + 1.0) / k)

func destroy_prop(p: WorldProp) -> void:
	broken[Vector2i(p.tx, p.ty)] = true
	var c: ChunkData = _data.get(Vector2i(p.tx >> 4, p.ty >> 4))
	if c != null:
		var i := c.props.find(p)
		if i < 0:
			# stale object (chunk evicted and regenerated): drop whatever stands on that tile
			for j in c.props.size():
				if c.props[j].tx == p.tx and c.props[j].ty == p.ty:
					i = j
					break
		if i >= 0:
			c.props.remove_at(i)
		c.dsize = -1
		var li := (p.ty & 15) * N + (p.tx & 15)
		c.prop_at.erase(li)
		c.solid[li] = 0
	var S := Sim.cur
	if S == null:
		return
	var B: Dictionary = Data.biomes[biome]
	Sfx.play("grass" if p.type == "grass" else ("chest" if p.type == "chest" else "break"))
	match p.type:
		"grass":
			S.fx.burst(p.x, p.y - 6.0, Color.html(B["grass"][1]), 6, 70.0)
			var r := randf()
			if r < 0.05:
				S.pickups.drop("heal", p.x, p.y)
			elif r < 0.11:
				S.pickups.drop("coin", p.x, p.y, 1)
		"rock":
			S.fx.burst(p.x, p.y - 10.0, Color.html(B["rock"][1]), 14, 140.0)
			S.fx.ring(p.x, p.y - 8.0, 4.0, 26.0, Color.html(B["rock"][2]), 0.3, 3.0)
			var r := randf()
			if r < 0.40:
				S.pickups.drop_xp(p.x, p.y, 6.0)
			if r > 0.75:
				S.pickups.drop("coin", p.x, p.y, 2)
			if r > 0.94:
				S.pickups.drop("heal", p.x + 8.0, p.y)
		"chest":
			var gold := Color.html("#f2c443")
			S.fx.burst(p.x, p.y - 10.0, gold, 22, 180.0)
			S.fx.ring(p.x, p.y - 8.0, 6.0, 46.0, gold, 0.45, 4.0)
			S.cam.kick(0.25)
			var n := U.rand_int(4, 7)
			for i in n:
				S.pickups.drop("coin", p.x + U.rand(-14.0, 14.0), p.y + U.rand(-10.0, 10.0), 3)
			S.pickups.drop("heal" if randf() < 0.5 else "magnet", p.x, p.y)
			S.pickups.drop_xp(p.x, p.y, 20.0)
			if randf() < 0.08:
				S.pickups.drop("item", p.x, p.y - 12.0, Items.roll())
		"bigchest":
			# big loot: coins, tickets and the XP for exactly one level
			var gold := Color.html("#f2c443")
			S.fx.burst(p.x, p.y - 12.0, gold, 34, 220.0)
			S.fx.ring(p.x, p.y - 8.0, 6.0, 80.0, gold, 0.6, 5.0)
			S.cam.kick(0.4)
			for i in 9:
				S.pickups.drop("coin", p.x + U.rand(-22.0, 22.0), p.y + U.rand(-14.0, 14.0), 4)
			var tk := U.rand_int(1, 3)
			for i in tk:
				S.pickups.drop("ticket", p.x + U.rand(-16.0, 16.0), p.y + U.rand(-10.0, 10.0), 1)
			if randf() < 0.15:
				S.pickups.drop("ticket10", p.x, p.y - 10.0, 1)
			if randf() < 0.5:
				S.pickups.drop("item", p.x + 14.0, p.y - 14.0, Items.roll())
			S.pickups.drop_xp(p.x, p.y, level_xp())
			Progress.event("chest")
		"trap":
			var it: Variant = S.get("interact")      # Phase 3b (sim/interact.gd)
			if it != null and (it as Object).has_method("trap_effect"):
				it.trap_effect(p)

# ---------------- frame ----------------

## Crossfade timer + prop hit flashes near the view (world.js update).
func update(dt: float, cam: SimCamera = null) -> void:
	if fade_from >= 0:
		fade_t += dt
		if fade_t >= FADE:
			fade_from = -1
	if cam == null:
		cam = Sim.cur.cam if Sim.cur != null else null
	if cam == null:
		return
	var x0 := int(floorf((cam.left() - 60.0) / CW))
	var x1 := int(floorf((cam.left() + cam.w + 60.0) / CW))
	var y0 := int(floorf((cam.top() - 60.0) / CW))
	var y1 := int(floorf((cam.top() + cam.h + 60.0) / CW))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c: ChunkData = _data.get(Vector2i(cx, cy))
			if c == null:
				continue
			for p in c.props:
				if p.flash > 0.0:
					p.flash -= dt
