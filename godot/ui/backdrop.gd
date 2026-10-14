class_name MenuBackdrop
extends Node2D
## Live menu backdrop (game.js Backdrop, §1.7): the real world (seed 4242) with 20 wild Pokémon
## wandering, stopping and "attacking" the air, and a slowly drifting camera; the biome palette
## cycles every 30 s. The painted ground and liquid shimmer are WorldView's GroundLayer /
## LiquidLayer (sim.state == "ui"); this node draws the props and the wanderers y-sorted in world
## space on top, under the same Camera2D.

const CAST := [1, 4, 7, 25, 133, 52, 39, 35, 16, 43, 60, 69, 74, 92, 129, 147, 113, 143, 54, 79]

class Wanderer:
	extends Body
	var dex := 0
	var anim: PmdAnimator
	var vx := 0.0
	var vy := 0.0
	var t := 0.0

var sim: Sim
var wanderers: Array = []
var _t := 0.0
var _biome_t := 0.0
var _bi := 0
var active := false
var _inited := false

## (Re)builds the menu world: called when the menu opens and after each run (Backdrop.restore).
func begin(s: Sim) -> void:
	sim = s
	sim.world.async_chunks = true      # terrain for the painted ground on worker threads (Phase 3a)
	sim.world.reset(4242)
	sim.world.set_biome(_bi, true)
	if not _inited:                    # Backdrop.init: camera at (0, 0); restore() after a run keeps it
		_inited = true
		sim.cam.x = 0.0
		sim.cam.y = 0.0
	sim.cam.shake = 0.0
	sim.fx.clear()
	sim.enemies.clear()
	sim.pickups.clear()
	sim.projectiles.clear()
	wanderers.clear()
	for d in CAST:
		wanderers.append(_spawn(d, true))
	Sprites.preload_dex(CAST)
	active = true
	visible = true

func end() -> void:
	active = false
	visible = false
	wanderers.clear()

func _spawn(dex: int, anywhere: bool) -> Wanderer:
	var w := Wanderer.new()
	w.dex = dex
	w.anim = PmdAnimator.new(dex, 1.0)
	w.r = Sprites.body_radius(dex)
	var c := sim.cam
	var k := 0.6 if anywhere else 0.7
	for i in 20:
		w.x = c.x + randf_range(-1.0, 1.0) * c.w * k
		w.y = c.y + randf_range(-1.0, 1.0) * c.h * k
		if sim.world.is_free(w.x, w.y, w.r):
			break
	return w

func step(dt: float) -> void:
	if not active:
		return
	_t += dt
	sim.world.update(dt)
	var c := sim.cam
	c.x += cos(_t * 0.05) * 14.0 * dt
	c.y += sin(_t * 0.037) * 10.0 * dt
	c.follow(c.x, c.y, dt)
	_biome_t += dt
	if _biome_t > 30.0:
		_biome_t = 0.0
		_bi = (_bi + 1) % 3
		sim.world.set_biome(_bi)
	for i in wanderers.size():
		var w: Wanderer = wanderers[i]
		w.t -= dt
		if w.t <= 0.0:
			# wander, stop, or attack the air now and then
			w.t = randf_range(1.0, 3.5)
			var r := randf()
			if r < 0.55:
				var a := randf() * TAU
				var s := randf_range(25.0, 55.0)
				w.vx = cos(a) * s
				w.vy = sin(a) * s
			else:
				w.vx = 0.0
				w.vy = 0.0
				if r > 0.85:
					w.anim.play(["Attack", "Shoot", "Charge"].pick_random())
		w.x += w.vx * dt
		w.y += w.vy * dt
		sim.world.collide(w)
		var moving := absf(w.vx) + absf(w.vy) > 1.0
		if moving:
			w.anim.dir = Sprites.dir_from_angle(atan2(w.vy, w.vx))
		w.anim.loop("Walk" if moving else "Idle")
		w.anim.update(dt)
		# off camera: reappear inside the view
		if not c.sees(w.x, w.y, 120.0):
			wanderers[i] = _spawn(w.dex, false)
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	var list := wanderers.duplicate()
	# scenery (Phase 3a): flat props under everything, the rest y-sorted with the wanderers
	var t := Time.get_ticks_msec() / 1000.0
	var flats: Array = []
	for p in sim.world.visible_props(sim.cam):
		if p.flat:
			flats.append(p)
		else:
			list.append(p)
	flats.sort_custom(func(a, b): return a.y < b.y)
	for p in flats:
		PropArt.draw(self, p, sim.world, t)
	list.sort_custom(func(a, b): return a.y < b.y)
	for w in list:
		if w is WorldProp:
			PropArt.draw(self, w, sim.world, t)
			continue
		# while its sheet loads: shadow + the grey ball (sprites.js fallback), like JS
		DrawUtil.shadow(self, w.dex, w.x, w.y)
		DrawUtil.pmd(self, w.anim, w.x, w.y)
