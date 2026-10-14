class_name GroundLayer
extends Node2D
## World ground (world.js drawGround, §7.7 / §11.4). Child of WorldView drawn behind it
## (show_behind_parent). Each chunk is painted by WorldPaint on a WorkerThreadPool task into a
## 256x256 palette-slot map -> R8 ImageTexture (main thread), drawn at CW + 1 wu with a palette
## shader: the biome crossfade (2.6 s) only mixes two palettes, nothing is repainted. Until a
## chunk is ready a 16x16 per-tile placeholder (same shader) is shown. <= 48 textures (LRU).

const MAX_IMAGES := 48
const PREFETCH := 300.0          # wu around the view painted ahead of time
const MAX_JOBS := 3              # paint tasks in flight (terrain/pathing jobs share the pool)
const MAX_UPLOADS := 2           # finished chunks turned into textures per frame

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
// palette slot map (R8) -> colour; old palette (a) mixed with the new one (b) by k
uniform vec4 pal_a[24];
uniform vec4 pal_b[24];
uniform float k = 1.0;
void fragment() {
	int i = int(texture(TEXTURE, UV).r * 255.0 + 0.5);
	if (i > 23) {
		i = 0;
	}
	COLOR = vec4(mix(pal_a[i].rgb, pal_b[i].rgb, k), 1.0);
}
"""

class Job:
	var task := -1
	var key := Vector2i.ZERO
	var seed := 1
	var version := 0
	var purge := 0
	var k18 := PackedByteArray()
	var out := PackedByteArray()
	var us := 0

var sim: Sim
## Paint visible chunks synchronously (screenshot harness: no placeholders in the PNGs).
var sync_paint := false
var _tex: Dictionary = {}          # Vector2i -> ImageTexture (painted chunk)
var _ph: Dictionary = {}           # Vector2i -> ImageTexture (16x16 placeholder)
var _used: Dictionary = {}         # Vector2i -> frame last drawn
var _jobs: Dictionary = {}         # Vector2i -> Job
var _stale: Array[Job] = []        # jobs of a previous world, waited for and dropped
var _ver := -1
var _purge := -1
var _frame := 0
var _mat: ShaderMaterial
var _pal: Dictionary = {}          # biome -> PackedColorArray
var _pal_key := ""

# stats (read and reset by the [perf] line / autoshot)
var paint_n := 0
var paint_us_acc := 0
var paint_us_max := 0
var upload_us_max := 0
var main_us_acc := 0              # main-thread time: job polling + uploads + draw recording
var main_us_max := 0
var main_frames := 0
var _frame_us := 0

func _ready() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	material = _mat

func _exit_tree() -> void:
	for k in _jobs:
		WorkerThreadPool.wait_for_task_completion((_jobs[k] as Job).task)
	for j in _stale:
		WorkerThreadPool.wait_for_task_completion(j.task)
	_jobs.clear()
	_stale.clear()
	PropArt.finish()
	if sim != null:
		sim.world._finish_pending()      # terrain chunk tasks too: none may outlive the tree

func _active() -> bool:
	return sim != null and (sim.player != null or sim.state == "ui")

func _process(_dt: float) -> void:
	_frame += 1
	var t0 := Time.get_ticks_usec()
	_collect()
	_frame_us = Time.get_ticks_usec() - t0
	queue_redraw()

## Finished paint tasks -> textures (at most MAX_UPLOADS per frame).
func _collect() -> void:
	for i in range(_stale.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_stale[i].task):
			WorkerThreadPool.wait_for_task_completion(_stale[i].task)
			_stale.remove_at(i)
	var uploads := 0
	for k: Vector2i in _jobs.keys():
		if uploads >= MAX_UPLOADS:
			break
		var job: Job = _jobs[k]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(k)
		if job.version != _ver or job.purge != _purge:
			continue
		_upload(job)
		uploads += 1

func _upload(job: Job) -> void:
	var t0 := Time.get_ticks_usec()
	var img := Image.create_from_data(WorldPaint.W, WorldPaint.W, false, Image.FORMAT_R8, job.out)
	_store(job.key, ImageTexture.create_from_image(img))
	upload_us_max = maxi(upload_us_max, Time.get_ticks_usec() - t0)
	paint_n += 1
	paint_us_acc += job.us
	paint_us_max = maxi(paint_us_max, job.us)

func _store(k: Vector2i, t: Texture2D) -> void:
	_tex[k] = t
	_ph.erase(k)
	_used[k] = _frame
	if _tex.size() > MAX_IMAGES:
		# drop the least recently drawn chunk (never one drawn this frame)
		var old := Vector2i.ZERO
		var best := 1 << 62
		for q: Vector2i in _tex:
			var f: int = _used.get(q, 0)
			if f < best and q != k:
				best = f
				old = q
		_tex.erase(old)
		_used.erase(old)

static func _paint_job(job: Job) -> void:
	var t0 := Time.get_ticks_usec()
	job.out = WorldPaint.paint(job.key.x, job.key.y, job.k18, job.seed)
	job.us = Time.get_ticks_usec() - t0

## Starts a paint task (false if the terrain around the chunk isn't generated yet).
func _start(k: Vector2i) -> bool:
	var w := sim.world
	var k18 := w.terrain_block(k.x, k.y, sync_paint)
	if k18.is_empty():
		return false
	var job := Job.new()
	job.key = k
	job.seed = w.seed
	job.version = _ver
	job.purge = _purge
	job.k18 = k18
	if sync_paint:
		_paint_job(job)
		_upload(job)
		return true
	job.task = WorkerThreadPool.add_task(_paint_job.bind(job), false, "ground chunk")
	_jobs[k] = job
	if not _ph.has(k):
		var ph := Image.create_from_data(16, 16, false, Image.FORMAT_R8, WorldPaint.placeholder(k18))
		_ph[k] = ImageTexture.create_from_image(ph)
	return true

func _palette(bi: int) -> PackedColorArray:
	if not _pal.has(bi):
		_pal[bi] = WorldPaint.palette(bi)
	return _pal[bi]

func _sync_world() -> void:
	var w := sim.world
	if w.terrain_version != _ver:
		_ver = w.terrain_version
		_tex.clear()
		_ph.clear()
		_used.clear()
		for k in _jobs:
			_stale.append(_jobs[k])
		_jobs.clear()
		PropArt.prewarm(w.biome)
	if w.purge_serial != _purge:
		_purge = w.purge_serial
		for k: Vector2i in _tex.keys():
			if w.purges(k.x, k.y):
				_tex.erase(k)
				_ph.erase(k)
		for k in _jobs:
			_stale.append(_jobs[k])
		_jobs.clear()
	# palettes: current biome, or old -> new while the crossfade runs
	var fk := w.fade_k()
	var key := "%d/%d/%.4f" % [w.biome, w.fade_from, fk]
	if key != _pal_key:
		if _pal_key == "" or not _pal_key.begins_with("%d/" % w.biome):
			PropArt.prewarm(w.biome)
			PropArt.prewarm((w.biome + 1) % Data.biomes.size())
		_pal_key = key
		var cur := _palette(w.biome)
		_mat.set_shader_parameter("pal_a", _palette(w.fade_from) if fk >= 0.0 else cur)
		_mat.set_shader_parameter("pal_b", cur)
		_mat.set_shader_parameter("k", fk if fk >= 0.0 else 1.0)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_ground()
	var us := _frame_us + Time.get_ticks_usec() - t0
	_frame_us = 0
	main_us_acc += us
	main_us_max = maxi(main_us_max, us)
	main_frames += 1

func _draw_ground() -> void:
	if not _active():
		return
	_sync_world()
	var c := sim.cam
	var CW := WorldMap.CW
	var view := Rect2(c.left(), c.top(), c.w, c.h)
	var cx0 := int(floorf((c.left() - PREFETCH) / CW))
	var cx1 := int(floorf((c.left() + c.w + PREFETCH) / CW))
	var cy0 := int(floorf((c.top() - PREFETCH) / CW))
	var cy1 := int(floorf((c.top() + c.h + PREFETCH) / CW))
	var want: Array = []               # [priority, key] of chunks still to paint
	var ccx := c.x
	var ccy := c.y
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := Vector2i(cx, cy)
			var r := Rect2(cx * CW, cy * CW, CW + 1.0, CW + 1.0)
			var vis := r.intersects(view)
			if not _tex.has(k) and not _jobs.has(k):
				var d := absf(cx * CW + CW / 2.0 - ccx) + absf(cy * CW + CW / 2.0 - ccy)
				want.append([d + (0.0 if vis else 1e6), k])
				if vis and sync_paint:
					_start(k)
			if not vis:
				continue
			if _tex.has(k):
				_used[k] = _frame
				draw_texture_rect(_tex[k], r, false)
			elif _ph.has(k):
				draw_texture_rect(_ph[k], r, false)
			else:
				draw_rect(r, Color.WHITE)      # slot 255 -> floor[0] (shader)
	if want.is_empty() or _jobs.size() >= MAX_JOBS or sync_paint:
		return
	want.sort_custom(func(a, b): return a[0] < b[0])
	for it in want:
		if _jobs.size() >= MAX_JOBS:
			break
		if not _tex.has(it[1]):
			_start(it[1])

## Debug / tests: number of painted textures cached and jobs in flight.
func stats() -> Dictionary:
	return {"textures": _tex.size(), "jobs": _jobs.size(), "placeholders": _ph.size()}

## [perf] helper: chunks painted on workers (avg/max per chunk), worst texture upload and the
## main-thread time of the ground + liquid layers (draw + job polling) since the last call.
func take_perf(liq: Node = null) -> String:
	var fr := maxi(1, main_frames)
	var lq_acc: int = liq.get("draw_us_acc") if liq != null else 0
	var lq_max: int = liq.get("draw_us_max") if liq != null else 0
	var s := "painted=%d paint_avg=%.1fms paint_max=%.1fms upload_max=%.2fms main_avg=%.3fms main_max=%.2fms liquid_avg=%.3fms liquid_max=%.2fms textures=%d jobs=%d" % [
		paint_n, paint_us_acc / 1000.0 / maxi(1, paint_n), paint_us_max / 1000.0, upload_us_max / 1000.0,
		main_us_acc / 1000.0 / fr, main_us_max / 1000.0, lq_acc / 1000.0 / fr, lq_max / 1000.0, _tex.size(), _jobs.size()]
	paint_n = 0
	paint_us_acc = 0
	paint_us_max = 0
	upload_us_max = 0
	main_us_acc = 0
	main_us_max = 0
	main_frames = 0
	if liq != null:
		liq.set("draw_us_acc", 0)
		liq.set("draw_us_max", 0)
	return s
