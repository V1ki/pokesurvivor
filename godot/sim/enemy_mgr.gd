class_name EnemyMgr
extends RefCounted
## Enemy manager (G.EnemyMgr, js/entities/enemy.js): alive list, corpses, spatial grid
## (cell 52 wu, rebuilt every frame), soft separation and laggard relocation.

const CELL := 52.0
const LAG_T := 2.5
const MAX_CORPSES := 120
## Spatial grid: a dense window of WIN x WIN cells around the camera with per-cell linked
## lists (head / next indices), rebuilt every frame like the JS Map grid. Same results and
## order as JS (cells row-major, each cell in list order); enemies outside the window (far
## bosses / shinies) go to an overflow list scanned only by queries that reach outside it.
const WIN := 64

var list: Array[Enemy] = []
var corpses: Array[Enemy] = []
var by_id: Dictionary = {}
var _ents: Array[Enemy] = []           # grid entries (alive at the last rebuild), list order
var _ecx := PackedInt32Array()         # cell of each entry
var _ecy := PackedInt32Array()
var _next := PackedInt32Array()        # next entry in the same cell (-1 = end)
var _head := PackedInt32Array()        # first entry per window cell (-1 = empty)
var _over := PackedInt32Array()        # entries outside the window
var _wx0 := 0                          # window origin (cell)
var _wy0 := 0

func _init() -> void:
	_head.resize(WIN * WIN)
	_head.fill(-1)

func clear() -> void:
	list.clear()
	corpses.clear()
	_stashed.clear()
	by_id.clear()
	_ents.clear()
	_head.fill(-1)
	_over.clear()

func count() -> int:
	return list.size()

# --- rift arena (Phase 3b) ---
var _stashed: Array[Enemy] = []

## Keeps the map's enemies aside while the arena lasts.
func stash() -> void:
	_stashed.assign(list.filter(func(e: Enemy): return not e.dead))
	for e in _stashed:
		by_id.erase(e.id)
	list.clear()
	corpses.clear()

## Back from the arena: drops the arena's enemies and brings the map's back.
func restore() -> void:
	for e in list:
		by_id.erase(e.id)
	list.clear()
	corpses.clear()
	for e in _stashed:
		add(e)
	_stashed.clear()

func add(e: Enemy) -> Enemy:
	list.append(e)
	by_id[e.id] = e
	return e

func get_enemy(id: int) -> Enemy:
	return by_id.get(id)

static func cell_of(v: float) -> int:
	return int(floorf(v / CELL))

func rebuild_grid() -> void:
	_ents.clear()
	_head.fill(-1)
	_over.clear()
	var cam: SimCamera = Sim.cur.cam if Sim.cur != null else null
	var wx0 := (cell_of(cam.x) if cam != null else 0) - WIN / 2
	var wy0 := (cell_of(cam.y) if cam != null else 0) - WIN / 2
	_wx0 = wx0
	_wy0 = wy0
	var k := 0
	for e in list:
		if e.dead:
			continue
		_ents.append(e)
		e.gi = k                   # grid entry index (separate() finds itself without a search)
		k += 1
	var n := k
	_ecx.resize(n)
	_ecy.resize(n)
	_next.resize(n)
	for q in n:
		var e := _ents[q]
		var cx := int(floorf(e.x / CELL))
		var cy := int(floorf(e.y / CELL))
		_ecx[q] = cx
		_ecy[q] = cy
		if cx < wx0 or cy < wy0 or cx >= wx0 + WIN or cy >= wy0 + WIN:
			_over.append(q)
	# insert backwards so every cell lists its enemies in list order
	for q in range(n - 1, -1, -1):
		var i := _ecx[q] - wx0
		var j := _ecy[q] - wy0
		if i < 0 or j < 0 or i >= WIN or j >= WIN:
			_next[q] = -1
			continue
		var c := j * WIN + i
		_next[q] = _head[c]
		_head[c] = q

## Live enemies whose circle touches this circle.
func query_circle(x: float, y: float, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var c0x := int(floorf((x - r) / CELL)) - 1
	var c1x := int(floorf((x + r) / CELL)) + 1
	var c0y := int(floorf((y - r) / CELL)) - 1
	var c1y := int(floorf((y + r) / CELL)) + 1
	var inside := c0x >= _wx0 and c0y >= _wy0 and c1x < _wx0 + WIN and c1y < _wy0 + WIN
	for cy in range(c0y, c1y + 1):
		for cx in range(c0x, c1x + 1):
			var k := -1
			if inside or (cx >= _wx0 and cy >= _wy0 and cx < _wx0 + WIN and cy < _wy0 + WIN):
				k = _head[(cy - _wy0) * WIN + cx - _wx0]
				while k >= 0:
					var e := _ents[k]
					k = _next[k]
					if e.dead:
						continue
					var rr := r + e.r
					var dx := e.x - x
					var dy := e.y - y
					if dx * dx + dy * dy <= rr * rr:
						out.append(e)
			else:
				for o in _over:
					if _ecx[o] != cx or _ecy[o] != cy:
						continue
					var e := _ents[o]
					if e.dead:
						continue
					var rr := r + e.r
					var dx := e.x - x
					var dy := e.y - y
					if dx * dx + dy * dy <= rr * rr:
						out.append(e)
	return out

## Grid entries of one cell, in order (slow path for cells outside the window).
func _cell_entries(cx: int, cy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if cx >= _wx0 and cy >= _wy0 and cx < _wx0 + WIN and cy < _wy0 + WIN:
		var k := _head[(cy - _wy0) * WIN + cx - _wx0]
		while k >= 0:
			out.append(k)
			k = _next[k]
	else:
		for o in _over:
			if _ecx[o] == cx and _ecy[o] == cy:
				out.append(o)
	return out

## Soft separation: push overlapping enemies apart (bosses too). At most 7 pushes are counted
## per cell scan (the JS `break` only leaves the current cell's bucket).
## The grid entries' positions / radii / alive flags are copied to packed arrays first (much
## cheaper than object property reads in the pair loop); every moved enemy writes its new
## position back, so later enemies see it exactly like the JS loop reading live positions.
func separate(dt: float) -> void:
	var world := Sim.cur.world
	var ents := _ents
	var ne := ents.size()
	var sx := PackedFloat64Array()
	var sy := PackedFloat64Array()
	var sr := PackedFloat64Array()
	var live := PackedByteArray()
	sx.resize(ne)
	sy.resize(ne)
	sr.resize(ne)
	live.resize(ne)
	for q in ne:
		var o := ents[q]
		sx[q] = o.x
		sy[q] = o.y
		sr[q] = o.r
		live[q] = 0 if o.dead else 1
	var nxt := _next
	var head := _head
	var wx0 := _wx0
	var wy0 := _wy0
	for e in list:
		if e.dead:
			continue
		var gi := e.gi
		if gi < 0 or gi >= ne or ents[gi] != e:
			gi = -1                # not in the grid (summoned after the rebuild)
		var ex := e.x
		var ey := e.y
		var er := e.r
		var cx := int(floorf(ex / CELL))
		var cy := int(floorf(ey / CELL))
		var px := 0.0
		var py := 0.0
		var n := 0
		var fast := cx - 1 >= wx0 and cy - 1 >= wy0 and cx + 1 < wx0 + WIN and cy + 1 < wy0 + WIN
		if fast:
			# 3x3 cells, rows then columns (same order as the JS bucket scan)
			for j in 3:
				var c0 := (cy - 1 + j - wy0) * WIN + cx - 1 - wx0
				for ci in range(c0, c0 + 3):
					var k := head[ci]
					while k >= 0:
						var o := k
						k = nxt[k]
						if o == gi or live[o] == 0:
							continue
						var mn := (er + sr[o]) * 0.82
						var dx := ex - sx[o]
						var dy := ey - sy[o]
						var d2 := dx * dx + dy * dy
						if d2 > mn * mn or d2 < 1e-4:
							continue
						var d := sqrt(d2)
						var f := (mn - d) / mn
						px += (dx / d) * f
						py += (dy / d) * f
						n += 1
						if n > 6:
							break
		else:
			# a cell outside the dense window (far bosses / shinies): same body, overflow list
			for j in range(-1, 2):
				for i in range(-1, 2):
					for o in _cell_entries(cx + i, cy + j):
						if o == gi or live[o] == 0:
							continue
						var mn := (er + sr[o]) * 0.82
						var dx := ex - sx[o]
						var dy := ey - sy[o]
						var d2 := dx * dx + dy * dy
						if d2 > mn * mn or d2 < 1e-4:
							continue
						var d := sqrt(d2)
						var f := (mn - d) / mn
						px += (dx / d) * f
						py += (dy / d) * f
						n += 1
						if n > 6:
							break
		if n > 0:
			e.x += px * 42.0 * dt
			e.y += py * 42.0 * dt
			if not e.flying:
				world.collide(e)
			if gi >= 0:
				sx[gi] = e.x
				sy[gi] = e.y

func update(dt: float, pl: Player) -> void:
	var S := Sim.cur
	# smoothed player velocity (runner lead, laggard detection)
	if pl._has_prev and dt > 0.0:
		var k := minf(1.0, dt * 5.0)
		pl.vsx += ((pl.x - pl._px) / dt - pl.vsx) * k
		pl.vsy += ((pl.y - pl._py) / dt - pl.vsy) * k
		if absf(pl.x - pl._px) > 200.0 or absf(pl.y - pl._py) > 200.0:
			pl.vsx = 0.0
			pl.vsy = 0.0
	else:
		pl.vsx = 0.0
		pl.vsy = 0.0
	pl._px = pl.x
	pl._py = pl.y
	pl._has_prev = true

	rebuild_grid()
	var P := SimProf.on
	if P: SimProf.lap(SimProf.E_GRID)
	# index loop: minions appended mid-loop are updated this same frame (JS for...of)
	var i := 0
	while i < list.size():
		list[i].update(dt, pl)
		i += 1
	if P: SimProf.lap(SimProf.E_AI)
	separate(dt)
	if P: SimProf.lap(SimProf.E_SEP)

	var cam := S.cam
	var R := cam.outer_radius() + 40.0
	# loop invariants (nothing below changes them): player speed, arena flag, cull radii
	var R2 := R * R
	var sp := sqrt(pl.vsx * pl.vsx + pl.vsy * pl.vsy)
	var in_arena := S.rift.in_arena
	var px := pl.x
	var py := pl.y
	for j in range(list.size() - 1, -1, -1):
		var e := list[j]
		if e.dead:
			pl.kills += 1
			if e.boss:
				pl.bosses += 1
			Progress.kill(e)          # missions / achievements / stats (JS enemy.js:909)
			corpses.append(e)
			list.remove_at(j)
			by_id.erase(e.id)
			continue
		# the treasure thief escapes if you don't catch it in time (Phase 3b)
		if e._bk == Enemy.BK_THIEF:
			e.life -= dt
			if e.life <= 0.0:
				S.fx.burst(e.x, e.y - 10.0, Color.html("#ffd23f"), 16, 140.0)
				S.spawner.say("¡" + e.name + " se ha escapado!", 2.4)
				list.remove_at(j)
				by_id.erase(e.id)
				continue
		if e.boss or e.shiny or in_arena:
			continue
		# laggards: left behind, off-screen, while you run -> respawn ahead of you
		var ex := e.x
		var ey := e.y
		var d2 := (px - ex) * (px - ex) + (py - ey) * (py - ey)        # U.dist2(e, pl)
		var unseen := d2 > R2 and not cam.sees(ex, ey, 60.0)
		var behind := sp > 40.0 and ((ex - px) * pl.vsx + (ey - py) * pl.vsy) < -0.2 * sqrt(d2) * sp
		if unseen and behind:
			e.lag_t += dt
		elif not unseen:
			e.lag_t = 0.0
		if (unseen and e.lag_t > LAG_T) or d2 > 1400.0 * 1400.0:
			e.lag_t = 0.0
			if not S.spawner.ahead(e, pl):
				list.remove_at(j)
				by_id.erase(e.id)
	for j in range(corpses.size() - 1, -1, -1):
		corpses[j].update(dt, pl)
		if corpses[j].fade <= 0.0:
			corpses.remove_at(j)
	if corpses.size() > MAX_CORPSES:
		corpses = corpses.slice(corpses.size() - MAX_CORPSES)
	if P: SimProf.lap(SimProf.E_CULL)

## Live shinies (HUD off-screen arrows).
func shinies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in list:
		if e.shiny and not e.dead:
			out.append(e)
	return out

func boss_alive() -> bool:
	for e in list:
		if e.boss and not e.dead:
			return true
	return false

## Corpses + alive enemies near the view, for the y-sorted draw pass.
func drawables(cam: SimCamera) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in corpses:
		if cam.sees(e.x, e.y, 80.0):
			out.append(e)
	for e in list:
		if cam.sees(e.x, e.y, 80.0):
			out.append(e)
	return out
