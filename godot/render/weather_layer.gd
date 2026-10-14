class_name WeatherLayer
extends Control
## Weather visuals in screen space (weather.js draw, §7.10): a light tint and a few pixel
## particles (rain streaks, snow, sand, sun motes), advanced only while playing. Lives in the
## vignette CanvasLayer before the vignette rect; also feeds the fog amount to the vignette
## shader (game.js: the vignette closes in fog).

const WANT := {"rain": 70.0, "snow": 45.0, "sand": 40.0, "sun": 14.0, "fog": 0.0}

class Part:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var a := 0.0
	var c := Color.WHITE
	var t := 0.0
	var life := 0.0

var sim: Sim
var vignette_mat: ShaderMaterial      # main.gd's vignette (uniform "fog")
var parts: Array[Part] = []
var _dt := 0.0
var _fog := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_dt = minf(delta, 1.0 / 30.0) if (sim != null and sim.state == "playing") else 0.0
	var fog := sim.weather.vignette() if (sim != null and sim.player != null) else 0.0
	if vignette_mat != null and fog != _fog:
		_fog = fog
		vignette_mat.set_shader_parameter("fog", fog)
	queue_redraw()

func _spawn(kind: String, w: float, h: float, anywhere: bool) -> Part:
	var p := Part.new()
	p.y = randf() * h if anywhere else -10.0
	match kind:
		"rain":
			p.x = randf() * (w + 200.0)
			p.vx = -120.0
			p.vy = 720.0
			p.a = 0.5
			p.c = Color.html("#cfe2ff")
			p.life = 9.0
		"snow":
			p.x = randf() * w
			p.vx = U.rand(-20.0, 20.0)
			p.vy = U.rand(40.0, 80.0)
			p.a = 0.7
			p.c = Color.WHITE
			p.life = 20.0
		"sand":
			p.x = randf() * w if anywhere else w + 20.0
			p.y = randf() * h
			p.vx = U.rand(-520.0, -380.0)
			p.vy = U.rand(20.0, 60.0)
			p.a = 0.4
			p.c = Color.html("#e8cf8f")
			p.life = 9.0
		_:
			# sun: motes of light rising slowly
			p.x = randf() * w
			p.y = randf() * h if anywhere else h + 5.0
			p.vx = U.rand(-8.0, 8.0)
			p.vy = -U.rand(15.0, 30.0)
			p.a = 0.45
			p.c = Color.html("#fff1b0")
			p.life = 12.0
	return p

func _draw() -> void:
	if sim == null or sim.player == null:
		parts.clear()
		return
	var wx := sim.weather
	var k := wx.level()
	if wx.cur.is_empty() or k <= 0.0:
		parts.clear()
		return
	var d := wx.def()
	var tint: Array = d["tint"]
	var vs := get_viewport_rect().size
	var w := vs.x
	var h := vs.y
	draw_rect(Rect2(0, 0, w, h), Color8(int(tint[0]), int(tint[1]), int(tint[2]), 255) * Color(1, 1, 1, float(tint[3]) * k))
	var kind: String = wx.cur["kind"]
	var want: float = WANT.get(kind, 0.0) * k * (w / 1280.0)
	while parts.size() < want:
		parts.append(_spawn(kind, w, h, true))
	if parts.size() > want + 4.0:
		parts.resize(int(ceilf(want)))
	var s := maxf(2.0, roundf(w / 640.0))           # one game "pixel"
	var dt := _dt
	for i in range(parts.size() - 1, -1, -1):
		var p := parts[i]
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.t += dt
		if p.y > h + 20.0 or p.x < -40.0 or p.x > w + 40.0 or p.t > p.life:
			parts[i] = _spawn(kind, w, h, false)
			continue
		var col := Color(p.c, p.a * k)
		if kind == "rain":
			for j in 4:
				draw_rect(Rect2(roundf(p.x - j * s * 0.5), roundf(p.y - j * s * 1.5), s * 0.5, s * 1.5), col)
		elif kind == "sand":
			draw_rect(Rect2(roundf(p.x), roundf(p.y), s * 3.0, s * 0.5), col)
		else:
			draw_rect(Rect2(roundf(p.x), roundf(p.y), s, s), col)
