extends Control
## Screen-space layer under the HUD: damage numbers (drawn in screen space at
## 13/20 px * camera scale so they stay crisp, as the JS world-space text does).

var sim: Sim

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if sim == null or sim.player == null:
		return
	if SimProf.on: SimProf.begin()
	var cam := sim.cam
	var texts := sim.fx.texts
	var f := DrawUtil.font(700)
	var big := int(round(20.0 * cam.scale))
	var small := int(round(13.0 * cam.scale))
	var outline := maxi(2, int(round(3.0 * cam.scale)))
	# DrawUtil.text centred (stroke, then fill), batched: outline and fill glyphs live in different
	# font cache textures, so drawing them alternately costs 2 draw calls per number. Fills are
	# held back and drawn together, except that a held fill is flushed before any later outline
	# that overlaps it: the result is pixel-identical to stroke/fill per text, in a few batches.
	# The translated string and its width are cached on the text (they don't change).
	var pend: Array[FX.Text] = []
	var boxes := PackedFloat32Array()       # x0, y0, x1, y1 of each held fill (glyph box + margin)
	var asc := f.get_ascent(small)
	var desc := f.get_descent(small)
	var asc_big := f.get_ascent(big)
	var desc_big := f.get_descent(big)
	for t in texts:
		var size := big if t.big else small
		if t.tsize != size:
			t.ts = I18n.t(t.s)
			t.tw = f.get_string_size(t.ts, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			t.tsize = size
		var p := cam.world_to_screen(t.x, t.y)
		var pos := Vector2(round(p.x - t.tw / 2.0), round(p.y))
		t.tpos = pos
		# glyph box with a margin (fallback CJK glyphs, overhangs); its outline reaches `outline` further
		var m := 2.0 + size * 0.2
		var x0 := pos.x - m
		var x1 := pos.x + t.tw + m
		var y0 := pos.y - (asc_big if t.big else asc) - m
		var y1 := pos.y + (desc_big if t.big else desc) + m
		for q in range(0, boxes.size(), 4):
			if x0 - outline < boxes[q + 2] and x1 + outline > boxes[q] and y0 - outline < boxes[q + 3] and y1 + outline > boxes[q + 1]:
				_fills(f, pend)
				boxes.clear()
				break
		var a := minf(1.0, (1.0 - t.t / t.life) * 2.2)
		draw_string_outline(f, pos, t.ts, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.75 * a))
		pend.append(t)
		boxes.append(x0)
		boxes.append(y0)
		boxes.append(x1)
		boxes.append(y1)
	_fills(f, pend)
	if SimProf.on: SimProf.lap(SimProf.D_TEXT)

## Draws the held fills in order and empties the list.
func _fills(f: Font, pend: Array[FX.Text]) -> void:
	for t in pend:
		var a := minf(1.0, (1.0 - t.t / t.life) * 2.2)
		draw_string(f, t.tpos, t.ts, HORIZONTAL_ALIGNMENT_LEFT, -1, t.tsize, Color(t.color, a))
	pend.clear()
