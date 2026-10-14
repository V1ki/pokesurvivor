class_name Sprites
extends RefCounted
## PMD sprite-sheet helpers (port of js/core/sprites.js): metadata lookups, derived
## gameplay geometry, a lazily (threaded) loaded texture cache with LRU eviction and
## white silhouettes for the hit flash.
## Two on-disk layouts (tools/sync_sprites.js):
##   atlas (default, full set): res://assets/pokemon/{dex}[s][_page].png + atlas.json with each
##     sheet's [page, x, y]; one threaded load per species/variant page, sheets are AtlasTextures.
##   per-file (legacy subset): res://assets/pokemon/{dex}/[s/]{Anim}.png, one load per sheet.
## Sheet layout: columns = frames, rows = 8 directions (0 Down, 1 DownRight ... 7 DownLeft).

const PX := 2.0                        # world units per art pixel
const ANIMS := ["Idle", "Walk", "Attack", "Shoot", "Charge", "Hurt", "Faint"]
const ROOT := "res://assets/pokemon/"
const ATLAS_INDEX := "res://assets/pokemon/atlas.json"
const MAX_SHEETS := 200                # per-file layout
const MAX_PAGES := 48                  # atlas layout (a page holds all 7 sheets of a species)
const IDLE_MS := 20000

enum { LOADING, READY, FAILED }

static var _sheets: Dictionary = {}    # "dex/Anim[/s]" -> Sheet
static var _avail: Dictionary = {}     # dex -> bool (normal sheets present in this build)
static var _mode := -1                 # -1 unknown, 0 per-file, 1 atlas
static var _index: Dictionary = {}     # "4" / "4s" -> [[page, x, y] | 0] in ANIMS order
static var _pages: Dictionary = {}     # page path -> Page
static var _pindex: Dictionary = {}    # "4" / "4s" -> ["idle1", x, y] (preview strips)

class Sheet:
	var path := ""
	var state := -1               # -1 new (no request yet), then LOADING / READY / FAILED
	var tex: Texture2D = null     # whole sheet (Texture2D) or its region of an atlas page (AtlasTexture)
	var white: Texture2D = null
	var white_done := false
	var at := 0
	var page: Page = null         # atlas layout only
	var region := Rect2i()
	var evicted := false          # dropped from the cache (PmdAnimator.draw_sheet must refetch)

class Page:
	var path := ""
	var state := -1
	var tex: Texture2D = null
	var img: Image = null         # CPU copy, fetched once for white silhouettes
	var at := 0
	var keys: Array = []          # sheet keys using this page

# ---------------- metadata ----------------

static func meta(dex: int) -> Dictionary:
	return Data.meta_by.get(dex, {})

static func has_sprite_meta(dex: int) -> bool:
	return Data.meta_by.has(dex)

## Does the species visually hover? (tools/hover_flags.py) Flies over terrain.
static func hovers(dex: int) -> bool:
	return int(meta(dex).get("hv", 0)) == 1

static func has_shiny(dex: int) -> bool:
	return int(meta(dex).get("sh", 0)) == 1

static func _has(m: Dictionary, anim: String, shiny: bool) -> bool:
	if not m["a"].has(anim):
		return false
	return not (shiny and m.has("sm") and (m["sm"] as Array).has(anim))

static func anim_name(dex: int, anim: String, shiny := false) -> String:
	var m := meta(dex)
	if m.is_empty():
		return ""
	shiny = shiny and int(m.get("sh", 0)) == 1
	if _has(m, anim, shiny):
		return anim
	return "Idle" if _has(m, "Idle", shiny) else "Walk"

## Geometry of one animation: {w, h, n, r, d[], ax, ay} (shiny overrides in `sa`).
static func anim_meta(dex: int, anim: String, shiny := false) -> Dictionary:
	var m := meta(dex)
	if m.is_empty():
		return {}
	var nm := anim_name(dex, anim, shiny)
	if shiny and int(m.get("sh", 0)) == 1 and m.has("sa") and m["sa"].has(nm):
		return m["sa"][nm]
	return m["a"].get(nm, {})

## Screen angle (atan2(dy,dx)) -> direction row 0..7.
static func dir_from_angle(a: float) -> int:
	return posmod(U.jroundi((PI / 2.0 - a) / (PI / 4.0)), 8)

## Collision radius from the Idle frame width (gameplay!).
static func body_radius(dex: int, scale := 1.0) -> float:
	var m := anim_meta(dex, "Idle")
	var w: float = m["w"] if not m.is_empty() else 32.0
	return U.clampf_(w * 0.22, 5.0, 26.0) * PX * scale

## Visual height (HP bar / damage numbers).
static func body_height(dex: int, scale := 1.0) -> float:
	var m := anim_meta(dex, "Idle")
	var ay: float = m["ay"] if not m.is_empty() else 24.0
	return ay * PX * scale

## Shadow ellipse x-radius from the PMD ShadowSize.
static func shadow_rx(dex: int, scale := 1.0) -> float:
	var m := meta(dex)
	var s: int = clampi(int(m.get("s", 1)), 0, 2) if not m.is_empty() else 1
	return [5.0, 8.0, 12.0][s] * PX * scale


# ---------------- layout / availability ----------------

## Atlas layout present? (reads atlas.json once)
static func atlas_mode() -> bool:
	if _mode < 0:
		_mode = 0
		if FileAccess.file_exists(ATLAS_INDEX):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_INDEX))
			if v is Dictionary and v.get("d") is Dictionary:
				_index = v["d"]
				_pindex = v.get("p", {})
				_mode = 1
	return _mode == 1

## Are the normal sheets of this species present in this build? (see tools/sync_sprites.js)
static func available(dex: int) -> bool:
	if _avail.has(dex):
		return _avail[dex]
	var ok := false
	if has_sprite_meta(dex):
		if atlas_mode():
			var e: Variant = _index.get(str(dex))
			ok = e is Array and e[0] is Array
		else:
			ok = ResourceLoader.exists(ROOT + str(dex) + "/Idle.png")
	_avail[dex] = ok
	return ok

static func shiny_available(dex: int) -> bool:
	if not has_shiny(dex):
		return false
	if atlas_mode():
		var e: Variant = _index.get(str(dex) + "s")
		return e is Array and e[0] is Array
	return ResourceLoader.exists(ROOT + str(dex) + "/s/Idle.png")

# ---------------- textures ----------------

static func _path(dex: int, nm: String, shiny: bool) -> String:
	return ROOT + str(dex) + ("/s/" if shiny else "/") + nm + ".png"

## Sheet record for an animation; requests a threaded load the first time. May be not READY yet.
static func sheet(dex: int, anim: String, shiny := false) -> Sheet:
	shiny = shiny and has_shiny(dex)
	var nm := anim_name(dex, anim, shiny)
	if nm == "":
		return null
	var key := str(dex) + "/" + nm + ("/s" if shiny else "")
	var now := Time.get_ticks_msec()
	var s: Sheet = _sheets.get(key)
	if s != null:
		s.at = now
		if s.page != null:
			s.page.at = now
		if s.state == LOADING:
			_poll(s)
		return s
	if atlas_mode():
		s = _atlas_sheet(dex, nm, shiny, key, now)
		_sheets[key] = s
		return s
	if _sheets.size() >= MAX_SHEETS:
		_evict(now)
	s = Sheet.new()
	s.path = _path(dex, nm, shiny)
	s.at = now
	if not ResourceLoader.exists(s.path):
		s.state = FAILED
	elif ResourceLoader.load_threaded_request(s.path, "Texture2D") != OK:
		s.state = FAILED
	else:
		s.state = LOADING
		_poll(s)
	_sheets[key] = s
	return s

static func _atlas_sheet(dex: int, nm: String, shiny: bool, key: String, now: int) -> Sheet:
	var s := Sheet.new()
	s.at = now
	var e: Variant = _index.get(str(dex) + ("s" if shiny else ""))
	var i := ANIMS.find(nm)
	if not (e is Array) or i < 0 or not (e[i] is Array):
		s.state = FAILED
		return s
	var ent: Array = e[i]
	var m := anim_meta(dex, nm, shiny)
	s.region = Rect2i(int(ent[1]), int(ent[2]), int(m["w"]) * int(m["n"]), int(m["h"]) * int(m["r"]))
	var pg := int(ent[0])
	var path := ROOT + str(dex) + ("s" if shiny else "") + (".png" if pg == 0 else "_%d.png" % pg)
	s.path = path
	var p := _page(path, now, false)
	p.keys.append(key)
	s.page = p
	s.state = LOADING
	_poll(s)
	return s

## Preview strip: the first Idle row (direction Down) of a species, for grids and cards. Frame i is
## at Rect2(i * w, 0, w, h) of `tex` with the Idle meta (same coordinates as a full Idle sheet, which
## is returned in the per-file layout or when the index has no preview). May be not READY yet.
static func preview(dex: int, shiny := false) -> Sheet:
	shiny = shiny and has_shiny(dex)
	if not atlas_mode():
		return sheet(dex, "Idle", shiny)
	var id := str(dex) + ("s" if shiny else "")
	var key := "p/" + id
	var now := Time.get_ticks_msec()
	var s: Sheet = _sheets.get(key)
	if s != null:
		s.at = now
		if s.page != null:
			s.page.at = now
		if s.state == LOADING:
			_poll(s)
		return s
	var e: Variant = _pindex.get(id)
	if not (e is Array):
		return sheet(dex, "Idle", shiny)
	var m := anim_meta(dex, "Idle", shiny)
	s = Sheet.new()
	s.at = now
	s.region = Rect2i(int(e[1]), int(e[2]), int(m["w"]) * int(m["n"]), int(m["h"]))
	s.path = ROOT + str(e[0]) + ".png"
	s.page = _page(s.path, now, false)
	s.page.keys.append(key)
	s.state = LOADING
	_poll(s)
	_sheets[key] = s
	return s

static func _poll(s: Sheet) -> void:
	if s.page != null:
		var p := s.page
		if p.state == LOADING:
			var st := ResourceLoader.load_threaded_get_status(p.path)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				p.tex = ResourceLoader.load_threaded_get(p.path) as Texture2D
				p.state = READY if p.tex != null else FAILED
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				p.state = FAILED
		if p.state == READY:
			_bind(s)
		elif p.state == FAILED:
			s.state = FAILED
		return
	var st2 := ResourceLoader.load_threaded_get_status(s.path)
	if st2 == ResourceLoader.THREAD_LOAD_LOADED:
		s.tex = ResourceLoader.load_threaded_get(s.path) as Texture2D
		s.state = READY if s.tex != null else FAILED
	elif st2 == ResourceLoader.THREAD_LOAD_FAILED or st2 == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		s.state = FAILED

## Page record; created with a threaded request (or a blocking load when sync).
static func _page(path: String, now: int, sync: bool) -> Page:
	var p: Page = _pages.get(path)
	if p == null:
		if _pages.size() >= MAX_PAGES:
			_evict_pages(now)
		p = Page.new()
		p.path = path
		if not ResourceLoader.exists(path):
			p.state = FAILED
		elif sync:
			p.tex = load(path) as Texture2D
			p.state = READY if p.tex != null else FAILED
		elif ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
			p.state = FAILED
		else:
			p.state = LOADING
		_pages[path] = p
	p.at = now
	return p

## Page ready: the sheet becomes an AtlasTexture over its region (draw code is unchanged).
static func _bind(s: Sheet) -> void:
	var at := AtlasTexture.new()
	at.atlas = s.page.tex
	at.region = Rect2(s.region)
	s.tex = at
	s.state = READY

## Drop sheets unused for > 20 s (oldest first) down to 75% of the cap (per-file layout).
static func _evict(now: int) -> void:
	var old: Array = []
	for k in _sheets:
		var s: Sheet = _sheets[k]
		if now - s.at > IDLE_MS and s.state != LOADING:
			old.append([s.at, k])
	old.sort_custom(func(a, b): return a[0] < b[0])
	var drop := maxi(_sheets.size() - int(MAX_SHEETS * 0.75), 0)
	for i in mini(drop, old.size()):
		(_sheets[old[i][1]] as Sheet).evicted = true
		_sheets.erase(old[i][1])

## Same policy for atlas pages: a dropped page takes its sheets (and white silhouettes) with it.
static func _evict_pages(now: int) -> void:
	var old: Array = []
	for k in _pages:
		var p: Page = _pages[k]
		if now - p.at > IDLE_MS and p.state != LOADING:
			old.append([p.at, k])
	old.sort_custom(func(a, b): return a[0] < b[0])
	var drop := maxi(_pages.size() - int(MAX_PAGES * 0.75), 0)
	for i in mini(drop, old.size()):
		var p: Page = _pages[old[i][1]]
		for key in p.keys:
			if _sheets.has(key):
				(_sheets[key] as Sheet).evicted = true
			_sheets.erase(key)
		_pages.erase(old[i][1])

## Request every animation of these species (run start / upcoming cast).
static func preload_dex(dexes: Array, shiny := false) -> void:
	for d in dexes:
		for a in ANIMS:
			sheet(int(d), a, shiny)

## Load every sheet of one species synchronously (run start: the partner never blinks).
## Call it before issuing threaded requests: blocking on an in-flight threaded load right
## after queueing many others triggered "Bug in ResourceLoader logic" in Godot 4.7.1.
static func load_now(dex: int, shiny := false) -> void:
	shiny = shiny and has_shiny(dex)
	if atlas_mode():
		# pages not requested yet are loaded synchronously first (no threaded request involved)
		var e: Variant = _index.get(str(dex) + ("s" if shiny else ""))
		if e is Array:
			for ent in e:
				if ent is Array:
					var pg := int(ent[0])
					_page(ROOT + str(dex) + ("s" if shiny else "") + (".png" if pg == 0 else "_%d.png" % pg),
						Time.get_ticks_msec(), true)
		for a in ANIMS:
			var s := sheet(dex, a, shiny)
			if s == null or s.page == null or s.state != LOADING:
				continue
			var p := s.page
			if p.state == LOADING:
				p.tex = ResourceLoader.load_threaded_get(p.path) as Texture2D
				p.state = READY if p.tex != null else FAILED
			_poll(s)
		return
	for a in ANIMS:
		var nm := anim_name(dex, a, shiny)
		if nm == "":
			continue
		var key := str(dex) + "/" + nm + ("/s" if shiny else "")
		var s: Sheet = _sheets.get(key)
		if s != null and s.state != LOADING:
			s.at = Time.get_ticks_msec()
			continue
		if s == null:
			s = Sheet.new()
			s.path = _path(dex, nm, shiny)
			_sheets[key] = s
		s.at = Time.get_ticks_msec()
		if s.state == LOADING:
			s.tex = ResourceLoader.load_threaded_get(s.path) as Texture2D
		elif ResourceLoader.exists(s.path):
			s.tex = load(s.path) as Texture2D
		s.state = READY if s.tex != null else FAILED

## White silhouette of a sheet (hit flash), generated once per sheet.
static func white(s: Sheet) -> Texture2D:
	if s.white_done:
		return s.white
	s.white_done = true
	if s.tex == null:
		return null
	var img: Image
	if s.page != null:
		# one GPU read-back per page, then cut the sheet out of the cached copy
		if s.page.img == null:
			s.page.img = s.page.tex.get_image()
			if s.page.img == null or s.page.img.is_empty():
				return null
			if s.page.img.is_compressed():
				s.page.img.decompress()
			s.page.img.convert(Image.FORMAT_RGBA8)
		img = s.page.img.get_region(s.region)
	else:
		img = s.tex.get_image()
		if img == null or img.is_empty():
			return null
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	var w := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	w.fill(Color.WHITE)
	var out := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(w, img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	s.white = ImageTexture.create_from_image(out)
	return s.white

static func sheet_count() -> int:
	return _sheets.size()

static func page_count() -> int:
	return _pages.size()
