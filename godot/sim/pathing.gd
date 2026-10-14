class_name Pathing
extends RefCounted
## Enemies walk around rocks and lakes (js/systems/pathing.js): a BFS distance field
## ("flow field") around the player, rebuilt every 0.35 s. An enemy just steps to the
## neighbouring tile with fewer steps. 8 neighbours, no corner cutting; walls, solid props
## and damaging liquids block (water is walkable). Hovering species don't use it.
## R = 28 tiles -> 57x57 cells, stored with a 1-cell closed border (59x59) so the BFS needs
## no bounds checks; indices below are in that padded grid.
## GDScript cost: the BFS is ~1.4 ms on a desktop, so update() spreads each rebuild over a
## few frames (BUDGET cells per frame, double buffered) after the terrain chunks it covers
## exist (generated on worker threads in game); build() is the one-shot version (tests).
## One array holds both walkability and distance: BLOCK = closed (walls, solid props, damaging
## liquid, the border), UNSEEN = open but not reached (yet), else BFS steps; so "open and not
## visited" is a single read in the BFS.

const R := 28
const N := R * 2 + 1             # 57
const W := N + 2                 # padded row length
const EVERY := 0.35
const UNSEEN := 0x7fff
const BLOCK := 0x8000            # closed cell (> UNSEEN: never the lowest neighbour)
const TS := WorldMap.TS
const BUDGET := 1100             # BFS cells per frame (~3 frames per rebuild)
# active field (used by dir_for)
var ox := 0                      # tile of field cell (0, 0)
var oy := 0
var ready := false
var dist := PackedInt32Array()   # BLOCK / UNSEEN / steps (see above)
# field being built
var _box := 0
var _boy := 0
var _bdist := PackedInt32Array()
var _queue := PackedInt32Array()
var _head := 0
var _tail := 0
var _state := 0                  # 0 idle, 1 waiting for terrain chunks, 2 BFS running
var _px := 0.0
var _py := 0.0
var timer := 0.0
## Optional walkability override (tx, ty) -> bool, used by the unit tests.
var walk_fn := Callable()

func _init() -> void:
	dist.resize(W * W)
	dist.fill(BLOCK)
	_bdist.resize(W * W)
	_queue.resize(W * W)

func clear() -> void:
	ready = false
	timer = 0.0
	_state = 0

func update(dt: float, pl: Player) -> void:
	timer -= dt
	if timer <= 0.0:
		timer = EVERY
		if pl != null and not pl.dead:
			_px = pl.x
			_py = pl.y
			_state = 1
	if _state == 1:
		# terrain first (chunk generation is the expensive part): in game the missing chunks
		# are generated on worker threads; headless (sync) one per frame, deterministically
		var tx0 := int(floorf(_px / TS)) - R
		var ty0 := int(floorf(_py / TS)) - R
		var world := Sim.cur.world
		var waiting := false
		for cy in range(ty0 >> 4, ((ty0 + N - 1) >> 4) + 1):
			for cx in range(tx0 >> 4, ((tx0 + N - 1) >> 4) + 1):
				if world.has_chunk(cx, cy):
					continue
				if not world.async_chunks:
					world.chunk(cx, cy)
					return
				if not world.request_chunk(cx, cy):
					waiting = true
		if waiting:
			return
		_begin(_px, _py)
	if _state == 2 and _steps(BUDGET):
		_swap()

## One-shot rebuild around (x, y) (same result as the JS build()).
func build(x: float, y: float) -> void:
	_begin(x, y)
	_steps(1 << 30)
	_swap()

func _begin(x: float, y: float) -> void:
	_box = int(floorf(x / TS)) - R
	_boy = int(floorf(y / TS)) - R
	_bdist.fill(BLOCK)               # the border stays closed
	if walk_fn.is_valid():
		for j in N:
			var row := (j + 1) * W + 1
			for i in N:
				_bdist[row + i] = UNSEEN if walk_fn.call(_box + i, _boy + j) else BLOCK
	else:
		Sim.cur.world.fill_walk_codes(_bdist, _box, _boy, N, W, W + 1, UNSEEN, BLOCK)
	var start := (R + 1) * W + R + 1
	_bdist[start] = 0                # the player's cell always counts (open)
	_queue[0] = start
	_head = 0
	_tail = 1
	_state = 2

## BFS over at most `budget` cells, 8 neighbours in the JS order (E, W, S, N, SE, NE, SW, NW);
## a diagonal needs both side cells free. The closed border replaces the bounds checks.
## A cell is open iff its code is not BLOCK and unvisited iff it is UNSEEN (which implies open),
## so each neighbour costs one read. Returns true when the field is complete.
func _steps(budget: int) -> bool:
	var head := _head
	var tail := _tail
	var stop := mini(tail + budget, 1 << 30)
	while head < tail and head < stop:
		var c := _queue[head]
		head += 1
		var d := _bdist[c] + 1
		var ve := _bdist[c + 1]
		var vw := _bdist[c - 1]
		var vs := _bdist[c + W]
		var vn := _bdist[c - W]
		if ve == UNSEEN:
			_bdist[c + 1] = d
			_queue[tail] = c + 1
			tail += 1
		if vw == UNSEEN:
			_bdist[c - 1] = d
			_queue[tail] = c - 1
			tail += 1
		if vs == UNSEEN:
			_bdist[c + W] = d
			_queue[tail] = c + W
			tail += 1
		if vn == UNSEEN:
			_bdist[c - W] = d
			_queue[tail] = c - W
			tail += 1
		var oe := ve != BLOCK
		var ow := vw != BLOCK
		var os := vs != BLOCK
		var on := vn != BLOCK
		var n := c + W + 1
		if oe and os and _bdist[n] == UNSEEN:
			_bdist[n] = d
			_queue[tail] = n
			tail += 1
		n = c - W + 1
		if oe and on and _bdist[n] == UNSEEN:
			_bdist[n] = d
			_queue[tail] = n
			tail += 1
		n = c + W - 1
		if ow and os and _bdist[n] == UNSEEN:
			_bdist[n] = d
			_queue[tail] = n
			tail += 1
		n = c - W - 1
		if ow and on and _bdist[n] == UNSEEN:
			_bdist[n] = d
			_queue[tail] = n
			tail += 1
	_head = head
	_tail = tail
	return head >= tail

func _swap() -> void:
	var td := dist
	dist = _bdist
	_bdist = td
	ox = _box
	oy = _boy
	ready = true
	_state = 0

## Field distance at tile (tx, ty) (UNSEEN outside / unreachable).
func dist_at(tx: int, ty: int) -> int:
	var i := tx - ox
	var j := ty - oy
	if i < 0 or j < 0 or i >= N or j >= N:
		return UNSEEN
	var v := dist[(j + 1) * W + i + 1]
	return UNSEEN if v == BLOCK else v

func _open_at(i: int, j: int) -> bool:
	return dist[(j + 1) * W + i + 1] != BLOCK

## Normalized direction for `e` to reach the player around obstacles, or null when not
## needed (close, outside the field, no path, or clear line of sight).
## now_ms: time used to throttle the line-of-sight check (every 200 ms per enemy).
func dir_for(e: Enemy, pl: Body, now_ms: float) -> Variant:
	if not ready:
		return null
	var tx := int(floorf(e.x / TS)) - ox
	var ty := int(floorf(e.y / TS)) - oy
	if tx < 0 or ty < 0 or tx >= N or ty >= N:
		return null
	var c := (ty + 1) * W + tx + 1
	var here := dist[c]
	if here <= 1 or here >= UNSEEN:
		return null
	# clear view to the player: straight line (more natural); re-checked every 0.2 s
	if e.los_at < 0.0 or now_ms - e.los_at > 200.0:
		e.los_at = now_ms
		e.los = clear_line(e.x, e.y, pl.x, pl.y, e.r)
	if e.los:
		return null
	# next tile of the path: lowest neighbour in the D8 order (E, W, S, N, SE, NE, SW, NW), a
	# diagonal only with both side cells open. Unrolled; neighbours outside the field are the
	# padded closed border (dist UNSEEN), so they never win and need no bounds check.
	var bx := tx
	var by := ty
	var best := here
	var v := dist[c + 1]
	if v < best:
		best = v
		bx = tx + 1
		by = ty
	v = dist[c - 1]
	if v < best:
		best = v
		bx = tx - 1
		by = ty
	v = dist[c + W]
	if v < best:
		best = v
		bx = tx
		by = ty + 1
	v = dist[c - W]
	if v < best:
		best = v
		bx = tx
		by = ty - 1
	var oe := dist[c + 1] != BLOCK
	var ow := dist[c - 1] != BLOCK
	var os := dist[c + W] != BLOCK
	var on := dist[c - W] != BLOCK
	v = dist[c + W + 1]
	if v < best and oe and os:
		best = v
		bx = tx + 1
		by = ty + 1
	v = dist[c - W + 1]
	if v < best and oe and on:
		best = v
		bx = tx + 1
		by = ty - 1
	v = dist[c + W - 1]
	if v < best and ow and os:
		best = v
		bx = tx - 1
		by = ty + 1
	v = dist[c - W - 1]
	if v < best and ow and on:
		best = v
		bx = tx - 1
		by = ty - 1
	if bx == tx and by == ty:
		return null
	var gx := (ox + bx + 0.5) * TS
	var gy := (oy + by + 0.5) * TS
	# off-centre and the shortcut grazes an obstacle: go to the centre of its own tile first
	if not clear_line(e.x, e.y, gx, gy, e.r):
		gx = (ox + tx + 0.5) * TS
		gy = (oy + ty + 0.5) * TS
	return U.norm(gx - e.x, gy - e.y)

## Does a body of radius r fit along the straight line (ax, ay) -> (bx, by)?
func clear_line(ax: float, ay: float, bx: float, by: float, r: float) -> bool:
	var len := sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
	if len < 1.0:
		return true
	var ux := (bx - ax) / len
	var uy := (by - ay) / len
	var w := minf(r * 0.9, TS * 0.45)
	var step := TS * 0.4
	# lateral offsets s = -w, 0, +w: cx - uy * s and cy + ux * s, unrolled (same values:
	# cx - uy * (-w) == cx + uy * w exactly, and the centre sample is (cx, cy))
	var uyw := uy * w
	var uxw := ux * w
	var d := 0.0
	while d <= len:
		var cx := ax + ux * d
		var cy := ay + uy * d
		var x := int(floorf((cx + uyw) / TS)) - ox
		var y := int(floorf((cy - uxw) / TS)) - oy
		if x < 0 or y < 0 or x >= N or y >= N or dist[(y + 1) * W + x + 1] == BLOCK:
			return false
		x = int(floorf(cx / TS)) - ox
		y = int(floorf(cy / TS)) - oy
		if x < 0 or y < 0 or x >= N or y >= N or dist[(y + 1) * W + x + 1] == BLOCK:
			return false
		x = int(floorf((cx - uyw) / TS)) - ox
		y = int(floorf((cy + uxw) / TS)) - oy
		if x < 0 or y < 0 or x >= N or y >= N or dist[(y + 1) * W + x + 1] == BLOCK:
			return false
		d += step
	return true
