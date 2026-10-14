class_name DrawUtil
extends RefCounted
## Canvas helpers that Godot's CanvasItem lacks (ellipses, rounded pills, centred text)
## plus the PMD sprite blit used by every Pokémon (feet-anchored, §2.2).

static var font_bold: Font = null
static var font_regular: Font = null
static var font_cjk: Font = null

## Pixelify PS (Latin) with the Fusion Pixel 12 px font as the fallback for Chinese (css/style.css
## @font-face unicode-range): both pixel-crisp (no antialiasing / hinting / subpixel). The CJK
## font is drawn at whole multiples of its 12 px grid (12 up to 17 px text, 24 from 18 px...).
static func fonts() -> void:
	if font_bold != null:
		return
	font_cjk = _load_font("res://assets/fonts/FusionPixel-12px-zh_hans.woff2")
	if font_cjk is FontFile:
		(font_cjk as FontFile).fixed_size = 12
		(font_cjk as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font_bold = _load_font("res://assets/fonts/PixelifyPS-700.ttf")
	font_regular = _load_font("res://assets/fonts/PixelifyPS-400.ttf")
	for f in [font_bold, font_regular]:
		if f is FontFile and font_cjk is FontFile:
			(f as FontFile).fallbacks = [font_cjk]

static func _load_font(path: String) -> Font:
	var f: Variant = load(path)
	if f is FontFile:
		var ff: FontFile = f
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		return ff
	return ThemeDB.fallback_font

## CSS weights >= 551 use the 700 file (§9.6).
static func font(weight := 700) -> Font:
	fonts()
	return font_bold if weight >= 551 else font_regular

# ---------------- shapes ----------------

## One shared white "shapes" texture for every untextured ellipse / diamond / box: drawn as
## textured rects they batch with each other (one draw call for a run of shadows, gems, HP bars)
## instead of one polygon draw call each. Nearest filtering: the 512 px disc rasterizes like the
## old 64-segment circle polygon at every size used in game.
const SHAPE_DISC := Rect2(0, 0, 512, 512)
const SHAPE_DIAMOND := Rect2(516, 0, 256, 256)
const SHAPE_BOX := Rect2(248, 248, 16, 16)        # solid centre of the disc
static var _shapes: Texture2D = null

static func shapes() -> Texture2D:
	if _shapes == null:
		var img := Image.create_empty(772, 512, false, Image.FORMAT_RGBA8)
		for y in 512:
			var dy := (y + 0.5 - 256.0) / 256.0
			var hw := sqrt(maxf(0.0, 1.0 - dy * dy)) * 256.0
			var x0 := int(ceilf(256.0 - hw - 0.5))
			var x1 := int(floorf(256.0 + hw - 0.5))
			if x1 >= x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), Color.WHITE)
		for y in 256:
			var dy := absf((y + 0.5 - 128.0) / 128.0)
			var hw := (1.0 - dy) * 128.0
			var x0 := int(ceilf(128.0 - hw - 0.5))
			var x1 := int(floorf(128.0 + hw - 0.5))
			if x1 >= x0:
				img.fill_rect(Rect2i(516 + x0, y, x1 - x0 + 1, 1), Color.WHITE)
		_shapes = ImageTexture.create_from_image(img)
	return _shapes

## Filled axis-aligned ellipse (was a scaled draw_circle polygon).
static func ellipse(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	ci.draw_texture_rect_region(shapes(), Rect2(cx - rx, cy - ry, rx * 2.0, ry * 2.0), SHAPE_DISC, col)

## Filled diamond (rhombus) centred on (cx, cy), half extents hw x hh.
static func diamond(ci: CanvasItem, cx: float, cy: float, hw: float, hh: float, col: Color) -> void:
	ci.draw_texture_rect_region(shapes(), Rect2(cx - hw, cy - hh, hw * 2.0, hh * 2.0), SHAPE_DIAMOND, col)

## Filled rectangle on the shapes texture (batches with ellipses, unlike draw_rect).
static func box(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_texture_rect_region(shapes(), r, SHAPE_BOX, col)

## Outline points / dash segments around the origin, cached by shape (fields, telegraphs and
## rings redraw the same few sizes every frame); drawn with a translation.
static var _outline: Dictionary = {}

static func _cached(key: Variant) -> Variant:
	if _outline.size() > 512:
		_outline.clear()
	return _outline.get(key)

static func ellipse_line(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, col: Color, width := 2.0,
		a0 := 0.0, a1 := TAU, segs := 40) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var key := Vector4(rx, ry, a1 - a0, segs + a0 * 1000.0)
	var pts: Variant = _cached(key)
	if pts == null:
		var pp := PackedVector2Array()
		var n := maxi(4, int(segs * absf(a1 - a0) / TAU))
		for i in n + 1:
			var a := a0 + (a1 - a0) * float(i) / n
			pp.append(Vector2(cos(a) * rx, sin(a) * ry))
		_outline[key] = pp
		pts = pp
	ci.draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
	ci.draw_polyline(pts, col, width)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Dashed polyline through pts (canvas setLineDash([dash, gap]); lengths in local units).
## All dashes go out as one draw_multiline (same segments as one draw_line each, one command).
static func dashed(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	var segs := dash_segments(pts, dash, gap)
	if not segs.is_empty():
		ci.draw_multiline(segs, col, width)

## The dash segments (pairs of points) of a polyline.
static func dash_segments(pts: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var on := true
	var left := dash
	var segs := PackedVector2Array()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var pos := 0.0
		while pos < seg:
			var step := minf(left, seg - pos)
			if on:
				segs.append(a.lerp(b, pos / seg))
				segs.append(a.lerp(b, (pos + step) / seg))
			pos += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap
	return segs

static func dashed_ellipse(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, col: Color, width: float,
		dash: float, gap: float) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var key := Vector4(rx, ry, dash, -1.0 - gap)
	var segs: Variant = _cached(key)
	if segs == null:
		var n := clampi(int(rx * 0.6), 16, 72)
		var pts := PackedVector2Array()
		for i in n + 1:
			var a := TAU * float(i) / n
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		segs = dash_segments(pts, dash, gap)
		_outline[key] = segs
	if (segs as PackedVector2Array).is_empty():
		return
	ci.draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
	ci.draw_multiline(segs, col, width)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Shiny twinkle (Icons.twinkle in JS): a pixel cross that grows, gets diagonal tips, fades.
## phase 0..1, px = pixel size.
static func twinkle(ci: CanvasItem, x: float, y: float, phase: float, px := 2.0) -> void:
	var st := 0 if phase < 0.15 else (1 if phase < 0.32 else (2 if phase < 0.62 else (1 if phase < 0.82 else 0)))
	var X := U.jround(x / px) * px
	var Y := U.jround(y / px) * px
	var arm := Color(1.0, 0.953, 0.659)      # #fff3a8
	var tip := Color(0.604, 0.902, 1.0)      # #9ae6ff
	ci.draw_rect(Rect2(X, Y, px, px), Color.WHITE)
	if st >= 1:
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			ci.draw_rect(Rect2(X + d[0] * px, Y + d[1] * px, px, px), arm)
	if st >= 2:
		for d in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
			ci.draw_rect(Rect2(X + d[0] * px, Y + d[1] * px, px, px), arm)
		for d in [[3, 0], [-3, 0], [0, 3], [0, -3], [1, 1], [-1, 1], [1, -1], [-1, -1]]:
			ci.draw_rect(Rect2(X + d[0] * px, Y + d[1] * px, px, px), tip)

## Rounded rectangle (fill and/or stroke), like the HUD roundRect().
static func round_rect(ci: CanvasItem, r: Rect2, radius: float, fill: Color, stroke := Color(0, 0, 0, 0), width := 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(round(radius)))
	sb.corner_detail = 6
	if stroke.a > 0.0:
		sb.border_color = stroke
		sb.set_border_width_all(int(maxf(1.0, round(width))))
		sb.draw_center = fill.a > 0.0
	ci.draw_style_box(sb, r)

## HUD bar: pill background + fill rect `w·frac` clipped to the pill (hud.js bar(): a true sliver
## at low values, square right end).
static func bar(ci: CanvasItem, x: float, y: float, w: float, h: float, frac: float, col: Color, bg := Color(0, 0, 0, 0.55)) -> void:
	round_rect(ci, Rect2(x, y, w, h), h / 2.0, bg)
	frac = clampf(frac, 0.0, 1.0)
	if frac > 0.0:
		clipped_round_rect(ci, Rect2(x, y, w, h), h / 2.0, Rect2(x, y, w * frac, h), col)

## Canvas roundRect(r, radius) + clip() + fillRect(clip): the rounded rectangle cut to `clip`.
static func clipped_round_rect(ci: CanvasItem, r: Rect2, radius: float, clip: Rect2, col: Color) -> void:
	var pts := clipped_round_rect_points(r, radius, clip)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, col)

static func clipped_round_rect_points(r: Rect2, radius: float, clip: Rect2) -> PackedVector2Array:
	var rad := minf(radius, minf(r.size.x, r.size.y) / 2.0)
	var pts := PackedVector2Array()
	var corners := [[r.position.x + rad, r.position.y + rad, PI], [r.end.x - rad, r.position.y + rad, PI * 1.5],
		[r.end.x - rad, r.end.y - rad, 0.0], [r.position.x + rad, r.end.y - rad, PI * 0.5]]
	for c in corners:
		for k in 7:
			var a: float = c[2] + PI * 0.5 * k / 6.0
			pts.append(Vector2(c[0] + cos(a) * rad, c[1] + sin(a) * rad))
	# Sutherland-Hodgman against the 4 sides of `clip` (the rounded rectangle is convex)
	for e in 4:
		var out := PackedVector2Array()
		var n := pts.size()
		for i in n:
			var a2 := pts[i]
			var b2 := pts[(i + 1) % n]
			var ia := _inside(a2, clip, e)
			if ia:
				out.append(a2)
			if ia != _inside(b2, clip, e):
				var t := (_edge(clip, e) - _axis(a2, e)) / (_axis(b2, e) - _axis(a2, e))
				out.append(a2.lerp(b2, t))
		pts = out
		if pts.size() < 3:
			return PackedVector2Array()
	return pts

static func _axis(p: Vector2, e: int) -> float:
	return p.x if e < 2 else p.y

static func _edge(c: Rect2, e: int) -> float:
	return [c.position.x, c.end.x, c.position.y, c.end.y][e]

static func _inside(p: Vector2, c: Rect2, e: int) -> bool:
	return _axis(p, e) >= _edge(c, e) if e % 2 == 0 else _axis(p, e) <= _edge(c, e)

## Text with baseline at y; align: -1 left, 0 centre, 1 right. outline = stroke width in px.
## The Spanish source text is translated here (I18n, like the patched fillText of the web).
static func text(ci: CanvasItem, s: String, x: float, y: float, size: int, col: Color, align := 0, weight := 700,
		outline := 0, outline_col := Color(0, 0, 0, 0.75)) -> void:
	s = I18n.t(s)
	var f := font(weight)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px := x
	if align == 0:
		px = x - w / 2.0
	elif align == 1:
		px = x - w
	var pos := Vector2(round(px), round(y))
	if outline > 0:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func text_width(s: String, size: int, weight := 700) -> float:
	return font(weight).get_string_size(I18n.t(s), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

# ---------------- Pokémon ----------------

## Hit-flash material for canvas items that draw sprites every frame (the world view): the white
## silhouette is the sprite's own texture drawn with a marker modulate instead of a separate
## white texture (Sprites.white / PropArt.white read the atlas page back from the GPU and build
## an image on the first hit of every sheet: 1-4 ms hitches on desktop, far more on a phone;
## the extra texture also broke the sprite batches). Red channel of the modulate:
##   >= MARK_BOX     flat box of colour (red - MARK_BOX, g, b, a), texture ignored
##   >= MARK_ELLIPSE  ellipse filling the rect, same colour coding (UV over the UNIT_SRC texels)
##   >= FLASH_SOLID  white where the texel is not fully transparent (blit_rect_mask silhouette)
##   >= FLASH_ALPHA  white with the texel's alpha (PropArt.white)
##   else            texture * modulate (the default canvas shader; Color(4, 4, 4) still brightens)
## The shapes take the texture of the sprite they go with (ellipse_t / box_t), so a Pokémon's
## shadow, sprite, flash and HP bar are one batch instead of alternating textures.
const FLASH_SOLID := 16.0
const FLASH_ALPHA := 8.0
const MARK_ELLIPSE := 32.0
const MARK_BOX := 48.0
const UNIT_SRC := Rect2(0, 0, 4096, 4096)  # big: region UVs are inset by half a texel
const FLASH_SHADER := """
shader_type canvas_item;
varying vec4 mod_color;    // the draw's modulate (fragment COLOR already includes the texture)
void vertex() {
	mod_color = COLOR;
}
void fragment() {
	float m = mod_color.r;
	if (m >= 47.0) {
		COLOR = vec4(m - 48.0, mod_color.g, mod_color.b, mod_color.a);
	} else if (m >= 31.0) {
		vec2 q = UV / TEXTURE_PIXEL_SIZE / 2048.0 - 1.0;
		COLOR = vec4(m - 32.0, mod_color.g, mod_color.b, dot(q, q) <= 1.0 ? mod_color.a : 0.0);
	} else if (m >= 15.0) {
		COLOR = vec4(1.0, 1.0, 1.0, (texture(TEXTURE, UV).a > 0.0 ? 1.0 : 0.0) * mod_color.a);
	} else if (mod_color.r >= 7.0) {
		COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * mod_color.a);
	}
}
"""
static var _flash_mat: ShaderMaterial = null

static func flash_material() -> ShaderMaterial:
	if _flash_mat == null:
		var sh := Shader.new()
		sh.code = FLASH_SHADER
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = sh
	return _flash_mat

## Filled ellipse / box drawn with `tex` by flash_material()'s shader (see above).
static func ellipse_t(ci: CanvasItem, tex: Texture2D, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	ci.draw_texture_rect_region(tex, Rect2(cx - rx, cy - ry, rx * 2.0, ry * 2.0), UNIT_SRC,
		Color(MARK_ELLIPSE + col.r, col.g, col.b, col.a))

static func box_t(ci: CanvasItem, tex: Texture2D, r: Rect2, col: Color) -> void:
	ci.draw_texture_rect_region(tex, r, UNIT_SRC, Color(MARK_BOX + col.r, col.g, col.b, col.a))

## The texture DrawUtil.pmd will draw this animator with (its cached READY sheet's atlas page),
## or null when not cached (then shapes go on the shapes texture as usual).
static func batch_tex(an: PmdAnimator) -> Texture2D:
	var s := an.draw_sheet
	if s == null or an.draw_ver != an._ver or s.evicted:
		return null
	return s.page.tex if s.page != null else s.tex

## True if `ci` draws with flash_material() (white flashes via the modulate marker).
static func flash_marked(ci: CanvasItem) -> bool:
	return _flash_mat != null and is_same(ci.material, _flash_mat)

## Draws the animator's current frame with the anchor pixel on the feet (x, y).
## flash: enemies draw the white silhouette only; soft (player) draws it over at 55%.
static func pmd(ci: CanvasItem, an: PmdAnimator, x: float, y: float, flash := false, soft := false,
		alpha := 1.0, fallback := Color(0.4196, 0.4784, 0.5804)) -> void:
	if alpha <= 0.0:
		return
	var cs := an.draw_sheet
	if cs != null and an.draw_ver == an._ver and not cs.evicted:
		# fast path: the READY sheet of the current animation cached on the animator and its
		# geometry in fields (no key string / dictionary lookups); same LRU touch as Sprites.sheet
		var now := Time.get_ticks_msec()
		cs.at = now
		if cs.page != null:
			cs.page.at = now
		var ck := Sprites.PX * an.scale
		var cw := an._w
		var ch := an._h
		var csrc := Rect2(mini(an.frame, an._n - 1) * cw, mini(an.dir, an._rows - 1) * ch, cw, ch)
		var cdst := Rect2(floorf(x - an._ax * ck + 0.5), floorf(y - an._ay * ck + 0.5), cw * ck, ch * ck)
		if not flash or soft:
			ci.draw_texture_rect_region(cs.tex, cdst, csrc, Color(1, 1, 1, alpha))
		if flash:
			if is_same(ci.material, _flash_mat) and _flash_mat != null:
				ci.draw_texture_rect_region(cs.tex, cdst, csrc, Color(FLASH_SOLID, 1, 1, alpha * (0.55 if soft else 1.0)))
				return
			var cwt := Sprites.white(cs)
			if cwt != null:
				ci.draw_texture_rect_region(cwt, cdst, csrc, Color(1, 1, 1, alpha * (0.55 if soft else 1.0)))
			elif not soft:
				ci.draw_texture_rect_region(cs.tex, cdst, csrc, Color(4, 4, 4, alpha))
		return
	var m := an.meta()
	var s := Sprites.sheet(an.dex, an.cur, an.shiny)
	if an.shiny and s != null and s.state == Sprites.FAILED:
		# shiny sheet not in this build's sprite subset: show the normal sheet
		s = Sprites.sheet(an.dex, an.cur, false)
		m = Sprites.anim_meta(an.dex, an.cur, false)
	var k := Sprites.PX * an.scale
	var frame := an.frame
	if s != null and s.state != Sprites.READY:
		# while this animation loads, show Idle if it is ready
		var idle := Sprites.sheet(an.dex, "Idle", an.shiny)
		if idle != null and idle.state == Sprites.READY:
			s = idle
			m = Sprites.anim_meta(an.dex, "Idle", an.shiny)
			frame = 0
	if m.is_empty() or s == null or s.state != Sprites.READY:
		ci.draw_circle(Vector2(x, y - 12.0 * k), 8.0 * k, Color(fallback, alpha))
		return
	if is_same(m, an.meta()) and frame == an.frame and s == Sprites.sheet(an.dex, an.cur, an.shiny):
		an.draw_sheet = s           # the plain case (no shiny / loading fallback): cache it
		an.draw_ver = an._ver
	var w := float(m["w"])
	var h := float(m["h"])
	var row := mini(an.dir, int(m["r"]) - 1)
	var src := Rect2(mini(frame, int(m["n"]) - 1) * w, row * h, w, h)
	var dst := Rect2(U.jround(x - float(m["ax"]) * k), U.jround(y - float(m["ay"]) * k), w * k, h * k)
	if not flash or soft:
		ci.draw_texture_rect_region(s.tex, dst, src, Color(1, 1, 1, alpha))
	if flash:
		if is_same(ci.material, _flash_mat) and _flash_mat != null:
			ci.draw_texture_rect_region(s.tex, dst, src, Color(FLASH_SOLID, 1, 1, alpha * (0.55 if soft else 1.0)))
			return
		var wt := Sprites.white(s)
		if wt != null:
			ci.draw_texture_rect_region(wt, dst, src, Color(1, 1, 1, alpha * (0.55 if soft else 1.0)))
		elif not soft:
			ci.draw_texture_rect_region(s.tex, dst, src, Color(4, 4, 4, alpha))

## Ground shadow ellipse (PMD ShadowSize).
static func shadow(ci: CanvasItem, dex: int, x: float, y: float, scale := 1.0, alpha := 1.0) -> void:
	var rx := Sprites.shadow_rx(dex, scale)
	ellipse(ci, x, y, rx, rx * 0.42, Color(0, 0, 0, 0.34 * alpha))
