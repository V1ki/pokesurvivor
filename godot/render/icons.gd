class_name Icons
extends RefCounted
## Procedural pixel-art icons (subset of js/ui/icons.js) built once into ImageTextures:
##   "move:<id>"  16x16 type emblem + 5x5 kind badge
##   "type:<t>"   16x16 type emblem
##   <name>       12x12 char-map UI icon from icons.json (heart, fist, boot, ...)
## Always draw at integer multiples (snap()) with Nearest filtering.

const K := "#1b1528"          # outline
static var _cache: Dictionary = {}

static func shade(c: Color, k: float) -> Color:
	return Color8(clampi(U.jroundi(c.r8 * k), 0, 255), clampi(U.jroundi(c.g8 * k), 0, 255), clampi(U.jroundi(c.b8 * k), 0, 255))

static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var img: Image
	if name.begins_with("move:"):
		var m := Moves.def(name.substr(5))
		img = _emblem(m.get("type", "normal"), m.get("kind", ""))
	elif name.begins_with("type:"):
		img = _emblem(name.substr(5), "")
	else:
		var ui: Dictionary = Data.icons.get("ui", {})
		img = _from_rows(ui.get(name, ui.get("star", {})))
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t

static func _emblem(type: String, kind: String) -> Image:
	var S := 16
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var c := Data.tcolor(type)
	var dark := shade(c, 0.55)
	var lite := shade(c, 1.3)
	var k := Color.html(K)
	for y in S:
		for x in S:
			var d := sqrt((x - 7.5) * (x - 7.5) + (y - 7.5) * (y - 7.5))
			if d > 7.6:
				continue
			var f := c
			if d > 6.6:
				f = k
			elif (x - 7.5) + (y - 7.5) > 6.0:
				f = dark
			elif (x - 7.5) + (y - 7.5) < -6.5:
				f = lite
			img.set_pixel(x, y, f)
	var glyphs: Dictionary = Data.icons.get("type_glyph", {})
	var g: Array = glyphs.get(type, glyphs.get("normal", []))
	for y in g.size():
		var row: String = g[y]
		for x in row.length():
			if row[x] == "#":
				img.set_pixel(x + 5, y + 5, dark)
	for y in g.size():
		var row: String = g[y]
		for x in row.length():
			if row[x] == "#":
				img.set_pixel(x + 4, y + 4, Color.WHITE)
	var kg: Dictionary = Data.icons.get("kind_glyph", {})
	if kind != "" and kg.has(kind):
		img.fill_rect(Rect2i(9, 9, 7, 7), k)
		img.fill_rect(Rect2i(10, 10, 5, 5), Color.html("#2b3454"))
		var rows: Array = kg[kind]
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					img.set_pixel(x + 10, y + 10, Color.html("#ffd23f"))
	return img

static func _from_rows(def: Dictionary) -> Image:
	var rows: Array = def.get("rows", [])
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var outline: bool = def.get("outline", false)
	var pad := 1 if outline else 0
	var img := Image.create_empty(maxi(1, w + pad * 2), maxi(1, h + pad * 2), false, Image.FORMAT_RGBA8)
	var pal := {"k": Color.html(K)}
	var dp: Dictionary = def.get("pal", {})
	for ch in dp:
		pal[ch] = Color.html(dp[ch])
	if outline:
		for y in h:
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "." or row[x] == " ":
					continue
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					img.set_pixel(x + pad + o.x, y + pad + o.y, pal["k"])
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or ch == " " or not pal.has(ch):
				continue
			img.set_pixel(x + pad, y + pad, pal[ch])
	return img

## Drawn size snapped to an integer multiple of the native width (20 -> 24, 32 -> 32 for 16 px).
static func snap(name: String, size: float) -> float:
	var w := float(tex(name).get_width())
	return w * maxf(1.0, round(size / w))

## Draw centred in the (x, y, size) box like G.Icons.draw.
static func draw(ci: CanvasItem, name: String, x: float, y: float, size: float, modulate := Color.WHITE) -> void:
	var t := tex(name)
	var s2 := snap(name, size)
	x += (size - s2) / 2.0
	y += (size - s2) / 2.0
	ci.draw_texture_rect(t, Rect2(round(x), round(y), s2, s2 * t.get_height() / t.get_width()), false, modulate)
