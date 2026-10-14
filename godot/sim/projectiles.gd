class_name Projectiles
extends RefCounted
## One list for everything that flies (js/entities/projectile.js): player shots, enemy
## shots and orbit orbs (orbs are projectiles anchored to their owner that re-hit every
## `rehit` s). They live on the GROUND plane and are drawn LIFT wu higher with a shadow.

class Proj:
	var id := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var px := 0.0                 # previous position (swept collision)
	var py := 0.0
	var has_prev := false
	var dmg := 10.0
	var r := 6.0
	var life := 1.4
	var t := 0.0
	var pierce := 0
	var hits: Dictionary = {}     # enemy id -> true
	var phits: Dictionary = {}    # prop id -> true (each shot hits a prop once)
	var friendly := true
	var color := Color.WHITE
	var homing := 0.0
	var slow := 0.0
	var burn := 0.0
	var poison := 0.0
	var knock := 0.0
	var mtype := ""
	var vis: Dictionary = {}      # VFX look {pal, proj, trail?}
	var pal := "normal"           # = vis.pal (kept for the impact sprites / bursts)
	var trail_t := 0.0
	var owner: Player = null
	var orb := false
	var mid := ""
	var oa := 0.0
	var orad := 0.0
	var ospeed := 0.0
	var rehit := 0.34
	var hit_log: Dictionary = {}  # enemy id -> run time of last hit (orbs)
	var boom := 0.0               # boomerang: out time (s); 0 = not a boomerang
	var back := false
	var bsp := 0.0

var list: Array[Proj] = []
var _next_id := 1

func clear() -> void:
	list.clear()

func count() -> int:
	return list.size()

func add(p: Proj) -> Proj:
	p.id = _next_id
	_next_id += 1
	if p.vis.is_empty():
		p.vis = VFX.for_type("normal")
	p.pal = p.vis.get("pal", "normal")
	list.append(p)
	return p

## Remove the orbs of one player (or all when owner is null), e.g. on slot change.
func clear_orbs(owner: Player) -> void:
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		if p.orb and (owner == null or p.owner == owner):
			list.remove_at(i)

func remove(p: Proj) -> void:
	var i := list.find(p)
	if i >= 0:
		list.remove_at(i)

func update(dt: float, player: Player, enemies: Array[Enemy]) -> void:
	var S := Sim.cur
	var cam := S.cam
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.t += dt
		if p.orb:
			var o: Player = p.owner if p.owner != null else player
			p.oa += p.ospeed * dt
			p.x = o.x + cos(p.oa) * p.orad
			p.y = o.y + sin(p.oa) * p.orad * 0.7
			continue
		if p.t >= p.life:
			list.remove_at(i)
			continue
		# boomerang: turns around at `boom` s (can hit the same enemies again) and returns
		if p.boom > 0.0:
			var ob: Player = p.owner if p.owner != null else player
			if not p.back and p.t >= p.boom:
				p.back = true
				p.hits = {}
			if p.back:
				var nb := U.norm(ob.x - p.x, ob.y - p.y)
				p.vx = U.damp(p.vx, nb.x * p.bsp, 7.0, dt)
				p.vy = U.damp(p.vy, nb.y * p.bsp, 7.0, dt)
				if U.dist2(p.x, p.y, ob.x, ob.y) < (ob.r + 8.0) * (ob.r + 8.0):
					list.remove_at(i)
					continue
		# homing: bend the velocity toward the nearest enemy (constant speed)
		if p.homing > 0.0 and p.friendly:
			var tg := nearest(enemies, p.x, p.y, 340.0)
			if tg != null:
				var nh := U.norm(tg.x - p.x, tg.y - p.y)
				var sp := sqrt(p.vx * p.vx + p.vy * p.vy)
				p.vx = U.damp(p.vx, nh.x * sp, p.homing, dt)
				p.vy = U.damp(p.vy, nh.y * sp, p.homing, dt)
		p.px = p.x
		p.py = p.y
		p.has_prev = true
		var tr: String = p.vis.get("trail", "")
		if tr != "" and cam.sees(p.x, p.y, 20.0):
			p.trail_t -= dt
			if p.trail_t <= 0.0:
				p.trail_t = 0.04
				S.fx.trail(tr, p.pal, p.x, p.y - U.LIFT, p.vx, p.vy)
		p.x += p.vx * dt
		p.y += p.vy * dt
		# far outside the view -> discarded
		if not cam.sees(p.x, p.y, 260.0):
			list.remove_at(i)

## Nearest live enemy within max_dist (squared distance to the feet).
func nearest(enemies: Array, x: float, y: float, max_dist: float) -> Enemy:
	var best: Enemy = null
	var bd := max_dist * max_dist
	for e: Enemy in enemies:
		if e.dead:
			continue
		var d := U.dist2(x, y, e.x, e.y)
		if d < bd:
			bd = d
			best = e
	return best
