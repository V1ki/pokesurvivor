extends Node2D
## Everything in world space, drawn in the JS order (§1.6): ground, hazard telegraphs,
## ground fields, pickups, y-sorted Pokémon, projectiles, air fields, FX. One custom-drawn
## node; the Camera2D child mirrors SimCamera.
## Ground and liquid shimmer are the GroundLayer / LiquidLayer children (drawn behind this node);
## props join the y-sorted pass (PropArt.draw).

const SUPPORT_ICON := {"healer": "heart", "shielder": "shield", "summoner": "friends"}

var sim: Sim
var camera: Camera2D
var ground: GroundLayer
var liquid: LiquidLayer

func _ready() -> void:
	material = DrawUtil.flash_material()      # hit flashes without white silhouette textures
	camera = Camera2D.new()
	camera.name = "Camera2D"
	add_child(camera)
	camera.make_current()
	ground = GroundLayer.new()
	ground.name = "Ground"
	ground.sim = sim
	add_child(ground)
	liquid = LiquidLayer.new()
	liquid.name = "Liquid"
	liquid.sim = sim
	add_child(liquid)

## Called by Game every frame after the simulation step.
func sync_camera() -> void:
	var c := sim.cam
	camera.zoom = Vector2(c.scale, c.scale)
	# JS translates the world by -left + shake: the camera moves the other way
	camera.position = Vector2(c.x - c.sx, c.y - c.sy)

## CPU time spent recording this node's draw commands (read and reset by main.gd's [perf] line).
var draw_us_acc := 0
var draw_us_max := 0

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_world()
	var us := Time.get_ticks_usec() - t0
	draw_us_acc += us
	draw_us_max = maxi(draw_us_max, us)

func _draw_world() -> void:
	if sim == null:
		return
	if sim.player == null:
		return              # menu: GroundLayer/LiquidLayer draw the world, ui/backdrop.gd props + wanderers
	var P := SimProf.on
	if P: SimProf.begin()
	_draw_hazards()
	if P: SimProf.lap(SimProf.D_HAZARDS)
	_draw_ground_fields()
	if P: SimProf.lap(SimProf.D_GFIELDS)
	_draw_pickups()
	if P: SimProf.lap(SimProf.D_PICKUPS)
	_draw_entities()                        # laps D_ENT_LIST inside
	if P: SimProf.lap(SimProf.D_ENT_DRAW)
	_draw_projectiles()
	if P: SimProf.lap(SimProf.D_PROJ)
	_draw_air_fields()
	if P: SimProf.lap(SimProf.D_AFIELDS)
	_draw_fx()
	if P: SimProf.lap(SimProf.D_FX)

static func _c(hex: String) -> Color:
	return Color.html(hex)

# colours drawn every frame (Color.html would parse the string on every call)
const C_FURY := Color("#ff4a4a")
const C_SHINY := Color("#9ae6ff")
const C_GOLD := Color("#ffd23f")
const C_BOSS := Color("#ffd95e")
const C_SHIELD := Color("#9fd8ff")
const C_BURN := Color("#ff8a3d")
const C_POISON := Color("#c86bdc")
const C_HP_BOSS := Color("#ffcb3d")
const C_HP := Color("#ff5f6d")
const C_COIN_IN := Color("#b8860b")
const C_ESHOT := Color(1.0, 60 / 255.0, 80 / 255.0, 0.35)
const BUFF_COLS := {"atk": Color("#ff6b4d"), "spd": Color("#7fe0ff"), "def": Color("#b0b8c8"), "regen": Color("#5fe08a")}
const PICKUP_ICON := {"heal": "berry", "magnet": "magnet", "bomb": "bomb", "ticket": "ticket", "ticket10": "ticket10"}
## y-sorted pass item kinds
enum { K_ENEMY, K_PLAYER, K_EVENT, K_PROP }

static var _pk: Dictionary = {}        # pickup kind -> [glow colour (a 0.3), colour, r] (Pickups.KIND parsed once)
var _items: Array = []                 # y-sorted pass, reused every frame

# ---------------- pickups ----------------

func _draw_pickups() -> void:
	var c := sim.cam
	if _pk.is_empty():
		for kind in Pickups.KIND:
			var d: Dictionary = Pickups.KIND[kind]
			_pk[kind] = [Color(Color.html(d["glow"]), 0.3), Color.html(d["color"]), float(d["r"])]
	for p in sim.pickups.list:
		if not c.sees(p.x, p.y, 30.0):
			continue
		var k: Array = _pk[p.kind]
		var bounce := absf(sin(p.t * 0.8)) * 3.0
		var r: float = k[2]
		var y := p.y - 6.0 - bounce
		# shadow, glow, gem / coin and highlight all on DrawUtil's shapes texture: one batch
		DrawUtil.ellipse(self, p.x, p.y, r * 0.9, r * 0.35, Color(0, 0, 0, 0.28))
		DrawUtil.ellipse(self, p.x, y, r * 2.0, r * 2.0, k[0])
		var col: Color = k[1]
		if p.kind == "xp" or p.kind == "xpBig":
			DrawUtil.diamond(self, p.x, y, r * 0.78, r, col)
			DrawUtil.ellipse(self, p.x - r * 0.25, y - r * 0.3, r * 0.28, r * 0.28, Color(1, 1, 1, 0.8))
		elif p.kind == "coin":
			var sx := maxf(0.25, absf(cos(p.t * 0.9)))
			DrawUtil.ellipse(self, p.x, y, r * sx, r, col)
			DrawUtil.ellipse(self, p.x, y, r * sx * 0.5, r * 0.5, C_COIN_IN)
			DrawUtil.ellipse(self, p.x - r * 0.25, y - r * 0.3, r * 0.28, r * 0.28, Color(1, 1, 1, 0.8))
		else:
			var icon: String = PICKUP_ICON.get(p.kind, "star")
			var sz := 24.0 if p.kind == "ticket10" or p.kind == "item" else 18.0
			if p.kind == "item":
				# pickup.js: a held item shows its own icon over a pulsing gold glow (seen from afar)
				DrawUtil.ellipse(self, p.x, y, 18.0, 18.0, Color(1.0, 0.882, 0.302, 0.35 + sin(p.t * 1.5) * 0.15))
				icon = str(p.value)
			Icons.draw(self, icon, p.x - sz / 2.0, y - sz / 2.0 - 1.0, sz)

# ---------------- y-sorted Pokémon ----------------

## y-sort order: int64 keys (feet y in 1/4096 wu, then the insertion index), one PackedInt64Array
## sort instead of sort_custom with a lambda; equal y keep their insertion order (stable).
## Returns the sorted indices of `objs` (each needs a `y`).
static func _y_order(objs: Array) -> PackedInt64Array:
	var n := objs.size()
	var keys := PackedInt64Array()
	keys.resize(n)
	if n >= 4096:
		var tmp := objs.duplicate()
		tmp.sort_custom(func(a, b): return a.y < b.y)
		for i in n:
			keys[i] = objs.find(tmp[i])
		return keys
	for i in n:
		keys[i] = (int(roundf(float(objs[i].y) * 4096.0)) << 12) | i
	keys.sort()
	for i in n:
		keys[i] = keys[i] & 4095
	return keys

func _draw_entities() -> void:
	var cam := sim.cam
	var items := _items
	items.clear()
	var kinds := PackedByteArray()
	# EnemyMgr.drawables() inlined: corpses + alive enemies within 80 wu of the view
	for e in sim.enemies.corpses:
		if cam.sees(e.x, e.y, 80.0):
			items.append(e)
			kinds.append(K_ENEMY)
	for e in sim.enemies.list:
		if cam.sees(e.x, e.y, 80.0):
			items.append(e)
			kinds.append(K_ENEMY)
	items.append(sim.player)
	kinds.append(K_PLAYER)
	EventDraw.collect(sim, items)          # rift portal, lost Pokémon + goal mark (Phase 3b)
	while kinds.size() < items.size():
		kinds.append(K_EVENT)
	# props (Phase 3a): flat ones (spring, trap) under everything, the rest y-sorted
	var t := Time.get_ticks_msec() / 1000.0
	var flats: Array = []
	for p in sim.world.visible_props(cam):
		if p.flat:
			flats.append(p)
		else:
			items.append(p)
			kinds.append(K_PROP)
	if not flats.is_empty():
		for i in _y_order(flats):
			PropArt.draw(self, flats[i], sim.world, t)
	var order := _y_order(items)
	if SimProf.on: SimProf.lap(SimProf.D_ENT_LIST)
	for i in order:
		match kinds[i]:
			K_ENEMY:
				_draw_enemy(items[i])
			K_PROP:
				PropArt.draw(self, items[i], sim.world, t)
			K_EVENT:
				EventDraw.draw_item(self, sim, items[i])
			_:
				_draw_player(items[i])
	items.clear()

func _draw_enemy(e: Enemy) -> void:
	var alpha := clampf(e.fade / 0.5, 0.0, 1.0) if e.dead else 1.0
	if alpha <= 0.0:
		return
	# shapes use the sprite's own atlas page when cached: glow, shadow, sprite, flash, status
	# and HP bar are then a single batch (see DrawUtil.flash_material)
	var bt := DrawUtil.batch_tex(e.anim)
	var gold := e.golden or e._bk == Enemy.BK_THIEF
	if (e.boss or e.shiny or gold) and not e.dead:
		var ac := C_FURY if (e.ai != null and e.ai.fury) else (C_SHINY if e.shiny else (C_GOLD if gold else C_BOSS))
		_ell(bt, e.x, e.y, e.r * 1.6, e.r * 0.6, Color(ac, (0.32 if gold and not e.boss else 0.22) + sin(e.bob * 0.5) * 0.06))
	# ground shadow (DrawUtil.shadow with the radius cached on the enemy)
	var srx := e.shadow_rx
	if srx < 0.0:
		srx = Sprites.shadow_rx(e.dex, e.scale)
		e.shadow_rx = srx
	_ell(bt, e.x, e.y, srx, srx * 0.42, Color(0, 0, 0, 0.34 * alpha))
	# hovering species bob a little; jumpers arc
	var lift := (1.0 + sin(e.bob) * 1.5 if e.flying and not e.boss else 0.0) + e.jump_lift
	DrawUtil.pmd(self, e.anim, e.x, e.y - lift, e.flash > 0.0, false, alpha * alpha)    # enemy.js: globalAlpha × Animator alpha
	if e.dead:
		return
	if e.shield > 0.0:
		var a := 0.35 + sin(e.bob) * 0.08
		_ell(bt, e.x, e.y - e.body_h * 0.45, e.r * 1.5, e.body_h * 0.65, Color(127 / 255.0, 200 / 255.0, 1.0, 0.14 * a))
		DrawUtil.ellipse_line(self, e.x, e.y - e.body_h * 0.45, e.r * 1.5, e.body_h * 0.65, Color(C_SHIELD, a), 2.0)
	if e.burn > 0.0 or e.poison > 0.0:
		_ell(bt, e.x, e.y, e.r * 1.2, e.r * 0.5, Color(C_BURN if e.burn > 0.0 else C_POISON, 0.45))
	# supports: icon on top so you know whom to hit first
	var sup: String = SUPPORT_ICON.get(e.behavior, "") if (e._keep or e._bk == Enemy.BK_SHIELDER) else ""
	if sup != "":
		Icons.draw(self, sup, U.jround(e.x - 6.0), U.jround(e.y - e.body_h - (26.0 if e.hp < e.max_hp else 18.0)), 12)
	if e.boss or e.hp < e.max_hp:
		var w := 90.0 if e.boss else maxf(22.0, e.r * 2.0)
		var y := e.y - e.body_h - 10.0
		if bt != null:
			DrawUtil.box_t(self, bt, Rect2(e.x - w / 2.0, y, w, 3.4), Color(0, 0, 0, 0.6))
			DrawUtil.box_t(self, bt, Rect2(e.x - w / 2.0, y, w * maxf(0.0, e.hp / e.max_hp), 3.4), C_HP_BOSS if e.boss else C_HP)
		else:
			DrawUtil.box(self, Rect2(e.x - w / 2.0, y, w, 3.4), Color(0, 0, 0, 0.6))
			DrawUtil.box(self, Rect2(e.x - w / 2.0, y, w * maxf(0.0, e.hp / e.max_hp), 3.4), C_HP_BOSS if e.boss else C_HP)

## Filled ellipse on `bt` (shader shape, same batch as that texture) or on DrawUtil's shapes texture.
func _ell(bt: Texture2D, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if bt != null:
		DrawUtil.ellipse_t(self, bt, cx, cy, rx, ry, col)
	else:
		DrawUtil.ellipse(self, cx, cy, rx, ry, col)

func _draw_player(p: Player) -> void:
	var m := p.active_move()
	if not m.is_empty() and not p.dead:
		DrawUtil.ellipse_line(self, p.x, p.y, p.r * 1.5, p.r * 0.6, Color(Data.tcolor(m["type"]), 0.22), 2.0)
	DrawUtil.shadow(self, p.dex, p.x, p.y)
	# altar power: a ring of its colour pulsing under the feet (Phase 3b)
	if not p.power.is_empty() and not p.dead:
		DrawUtil.ellipse_line(self, p.x, p.y, p.r * 2.1, p.r * 0.85, Color(_c(p.power["def"]["color"]),
			0.35 + sin(Time.get_ticks_msec() / 120.0) * 0.15), 3.0)
	var alpha := 1.0
	if p.invuln > 0.0 and not p.dead and int(floor(p.invuln * 18.0)) % 2 == 1:
		alpha = 0.45
	DrawUtil.pmd(self, p.anim, p.x, p.y, p.flash > 0.0, true, alpha, C_HP_BOSS)
	# buff arcs around the feet
	var i := 0
	for k in p.buffs:
		var b: Dictionary = p.buffs[k]
		if int(b["n"]) <= 0:
			continue
		var rx := p.r * 1.8 + i * 5.0
		DrawUtil.ellipse_line(self, p.x, p.y, rx, rx * 0.42, Color(BUFF_COLS[k], 0.6), 2.0, 0.0, TAU * (float(b["n"]) / 5.0))
		i += 1

# ---------------- hazards (telegraphs, under everything) ----------------

func _draw_hazards() -> void:
	var blink := sin(Time.get_ticks_msec() / 60.0) > 0.0
	for h in sim.hazards.list:
		if h.hit:
			continue
		var k := minf(1.0, h.t / h.delay)
		var hot := k > 0.75 and blink
		if h.kind == "zone":
			DrawUtil.ellipse(self, h.x, h.y, h.r, h.r * 0.75, Color(h.color, 0.16))
			DrawUtil.ellipse(self, h.x, h.y, h.r * k, h.r * 0.75 * k, Color(h.color, 0.32))
			DrawUtil.dashed_ellipse(self, h.x, h.y, h.r, h.r * 0.75, Color(h.color, 0.95 if hot else 0.6), 2.0, 4.0, 4.0)
		else:
			draw_set_transform(Vector2(h.x, h.y), h.angle, Vector2.ONE)
			DrawUtil.box(self, Rect2(0, -h.w / 2.0, h.len, h.w), Color(h.color, 0.14))
			DrawUtil.box(self, Rect2(0, -h.w / 2.0 * k, h.len, h.w * k), Color(h.color, 0.34))
			var hw := h.w / 2.0
			DrawUtil.dashed(self, PackedVector2Array([Vector2(0, -hw), Vector2(h.len, -hw), Vector2(h.len, hw), Vector2(0, hw), Vector2(0, -hw)]),
				Color(h.color, 0.95 if hot else 0.55), 2.0, 6.0, 4.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------- fields (mines, meteors, turrets, trail patches) ----------------

func _draw_ground_fields() -> void:
	var c := sim.cam
	var now := Time.get_ticks_msec() / 1000.0
	for f in sim.combat.fields:
		if not c.sees(f.x, f.y, 60.0):
			continue
		match f.kind:
			"patch":
				var a := minf(1.0, minf((f.life - f.t) * 2.0, f.t * 6.0))
				DrawUtil.ellipse(self, f.x, f.y, f.r, f.r * 0.62, Color(f.col, 0.32 * a))
				DrawUtil.ellipse_line(self, f.x, f.y, f.r * 0.8, f.r * 0.5, Color(f.col, 0.5 * a), 1.5)
			"mine":
				var blink := f.t >= f.arm and sin(now * 8.0 + f.x) > 0.3
				DrawUtil.ellipse(self, f.x, f.y, f.r * 0.45, f.r * 0.28, Color(f.col, 0.18))
				VFX.draw(self, f.vis.get("proj", "star"), f.vis["pal"], f.x, f.y - 4.0, 0.0, 1.0, 0, 1.0 if blink else 0.75)
			"meteor":
				var k := clampf(f.t / f.fall, 0.0, 1.0)
				var g := 0.3 + k * 0.7
				DrawUtil.ellipse(self, f.x, f.y, f.r * g, f.r * 0.6 * g, Color(0, 0, 0, 0.2 + k * 0.3))
				DrawUtil.dashed_ellipse(self, f.x, f.y, f.r, f.r * 0.6, Color(f.col, 0.6), 1.5, 4.0, 4.0)
			"turret":
				DrawUtil.ellipse(self, f.x, f.y, 11.0, 4.5, Color(0, 0, 0, 0.3))

func _draw_air_fields() -> void:
	var c := sim.cam
	var now := Time.get_ticks_msec() / 1000.0
	for f in sim.combat.fields:
		if not c.sees(f.x, f.y, 200.0):
			continue
		if f.kind == "meteor" and f.t > 0.0:
			var k := clampf(f.t / f.fall, 0.0, 1.0)
			VFX.draw(self, f.vis.get("proj", "rock"), f.vis["pal"], f.x + (1.0 - k) * 40.0, f.y - (1.0 - k) * 170.0 - 6.0,
				atan2(170.0, -40.0), 1.5, int(floorf(now * 12.0)))
		elif f.kind == "turret":
			var fade := minf(1.0, minf((f.life - f.t) * 2.0, f.t * 5.0))
			var bob := sin(now * 4.0 + f.x) * 2.0 - (2.0 if f.kick > 0.0 else 0.0)
			VFX.draw(self, f.vis.get("proj", "star"), f.vis["pal"], f.x, f.y - 16.0 + bob, 0.0, 1.5, int(floorf(now * 8.0)), fade)

# ---------------- projectiles ----------------

func _draw_projectiles() -> void:
	var list := sim.projectiles.list
	for p in list:
		DrawUtil.ellipse(self, p.x, p.y, p.r * 0.9, p.r * 0.38, Color(0, 0, 0, 0.25))
	# enemy shots carry a red ring on the ground: "this hurts you"
	for p in list:
		if not p.friendly:
			DrawUtil.ellipse(self, p.x, p.y, p.r * 1.5, p.r * 0.6, C_ESHOT)
	for p in list:
		var shape: String = p.vis.get("proj", "ball")
		var a := 1.0 if p.orb else minf(1.0, (p.life - p.t) * 4.0)
		var angle := 0.0
		if VFX.is_dir(shape):
			angle = p.oa + PI / 2.0 if p.orb else atan2(p.vy, p.vx)
		elif VFX.spins(shape):
			angle = p.t * 9.0
		VFX.draw(self, shape, p.pal, p.x, p.y - U.LIFT, angle, 1.5 if p.r >= 8.0 else 1.0, int(floorf(p.t * 12.0)), a)

# ---------------- FX ----------------

static func _snap(v: float) -> float:
	return round(v / FX.PX) * FX.PX

func _draw_beam(b: FX.Beam) -> void:
	var PX := FX.PX
	var k := 1.0 - b.t / b.life
	var P := Data.pal(b.pal)
	var a := roundf(b.angle / (PI / 16.0)) * (PI / 16.0)
	var o := Vector2(_snap(b.x), _snap(b.y))
	var al := FX.step(k)
	var seg := PX * 2.0
	var now := Time.get_ticks_msec() / 1000.0
	draw_set_transform(o, a, Vector2.ONE)
	if b.shape == "lightning":
		# zigzag redrawn every frame
		var py := 0.0
		var d := 0.0
		while d < b.len:
			var ny := 0.0 if d + seg >= b.len else _snap((U.hash01(int(d), int(now * 30.0), int(b.seed)) - 0.5) * b.width)
			var lo := minf(py, ny)
			var hi := maxf(py, ny)
			draw_rect(Rect2(d - PX, lo - PX * 2.0, seg + PX * 2.0, hi - lo + PX * 4.0), Color(P[3], al))
			draw_rect(Rect2(d, lo - PX, seg, hi - lo + PX * 2.0), Color(P[4], al))
			py = ny
			d += seg
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# body made of blocks, with a vibrating edge
	var d := 0.0
	while d < b.len:
		var wob := 0.7 + 0.3 * sin(d * 0.18 + now * 30.0 + b.seed)
		var hw := maxf(PX, _snap(b.width / 2.0 * wob * (0.6 + 0.4 * k)))
		var hi := _snap(hw * 0.55)
		draw_rect(Rect2(d, -hw - PX, seg, hw * 2.0 + PX * 2.0), Color(P[1], al))
		draw_rect(Rect2(d, -hw, seg, hw * 2.0), Color(P[2], al))
		draw_rect(Rect2(d, -hi, seg, hi * 2.0), Color(P[3], al))
		draw_rect(Rect2(d, -PX, seg, PX * 2.0), Color(P[4], al))
		d += seg
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# sprites travelling along the beam (flames, drops, shards, rings)
	if b.shape != "":
		var gap := 26.0
		var ca := cos(a)
		var sa := sin(a)
		d = fmod(now * 420.0, gap)
		while d < b.len - 6.0:
			var yo := sin(d * 0.3 + b.seed) * b.width * 0.18
			VFX.draw(self, b.shape, b.pal, o.x + ca * d - sa * yo, o.y + sa * d + ca * yo, a, 1.5,
				int(d / gap + now * 12.0), al, false)
			d += gap

func _draw_fx() -> void:
	var fx := sim.fx
	var PX := FX.PX
	for b in fx.beams:
		_draw_beam(b)
	for s in fx.slashes:
		var k := 1.0 - s.t / s.life
		var P := Data.pal(s.pal)
		var half := minf(s.arc, 6.2832) / 2.0
		var r := s.radius * (0.72 + 0.28 * (1.0 - k))
		var n := maxi(8, int(ceil(r * half * 2.0 / PX)))
		var al := FX.step(k)
		for i in n + 1:
			var u := float(i) / n
			var a := s.angle - half + u * half * 2.0
			var thick := U.jroundi(sin(PI * u) * 3.0 * k)
			for j in range(-1, thick + 1):
				var rr := r - j * PX
				var c: Color = P[1] if j < 0 else (P[4] if j == thick else (P[3] if j > thick / 2.0 else P[2]))
				draw_rect(Rect2(roundf((s.x + cos(a) * rr) / PX) * PX, roundf((s.y + sin(a) * rr) / PX) * PX, PX, PX), Color(c, al))
	for rg in fx.rings:
		var k := rg.t / rg.life
		var rad := lerpf(rg.r0, rg.r1, k)
		var n := maxi(10, int(ceil(rad * 6.2832 / (PX * 2.0))))
		var size := PX * 2.0 if rg.width >= 4.0 else PX
		var col := Color(rg.color, FX.step(1.0 - k))
		for i in n:
			var a := float(i) / n * 6.2832
			draw_rect(Rect2(roundf((rg.x + cos(a) * rad) / PX) * PX, roundf((rg.y + sin(a) * rad * 0.9) / PX) * PX, size, size), col)
	# particles (packed arrays): _snap / FX.step inlined
	var px := fx.p_x
	var py := fx.p_y
	var pt := fx.p_t
	var pl := fx.p_life
	var ps := fx.p_s
	var pc := fx.p_col
	for i in fx.n_parts:
		var k := 1.0 - pt[i] / pl[i]
		var s := ps[i]
		draw_rect(Rect2(roundf(px[i] / PX) * PX, roundf(py[i] / PX) * PX, s, s),
			Color(pc[i], 1.0 if k > 0.66 else (0.66 if k > 0.33 else 0.33)))
	for s in fx.sprites:
		if s.twinkle:
			DrawUtil.twinkle(self, s.x, s.y, s.t / s.life, PX)
			continue
		var k := 1.0 - s.t / s.life
		VFX.draw(self, s.shape, s.pal, s.x, s.y, s.angle, s.scale, int(floorf(s.t * s.fr)), FX.step(k) if s.fade else 1.0)
