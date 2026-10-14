extends SceneTree
## Packs the PMD sprite sheets into one atlas per Pokémon and variant (normal / shiny).
## Called by tools/sync_sprites.js (--atlas); can also be run directly:
##   godot --headless --path godot --script res://tools/pack_sprites.gd -- \
##       --src=<repo>/assets/pokemon --dst=<godot>/assets/pokemon [--from=1 --to=1025] [--dex=4,7] [--no-shiny]
## Output: <dst>/<dex>.png (normal), <dst>/<dex>s.png (shiny), extra pages <dex>[s]_<k>.png when a
## species does not fit in MAX x MAX, per-generation preview pages idle<gen>[s][_k].png holding the
## first Idle row (direction Down) of every species (collection grid, gacha cards: a whole species
## atlas is ~4 MB of VRAM, a preview strip ~10 KB), and <dst>/atlas.json:
##   {"v": 1, "anims": [...7 names], "d": {"<dex>": [[page, x, y] | 0 per anim], "<dex>s": [...]},
##    "p": {"<dex>[s]": ["idle1[_k]", x, y]}}
## Sheet sizes always equal meta w*n x h*r (checked), so w/h are not stored.
## Each page is shelf-packed (sheets sorted by height); several widths are tried and the one with the
## smallest area wins, so small species don't waste texture memory.

const ANIMS := ["Idle", "Walk", "Attack", "Shoot", "Charge", "Hurt", "Faint"]
const MAX := 2048          # GLES3 guarantees 2048; bigger species get extra pages

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var src: String = args.get("src", "")
	var dst: String = args.get("dst", "")
	if src == "" or dst == "":
		printerr("pack_sprites: --src and --dst are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(dst)
	var dexes: Array = []
	if args.has("dex"):
		for s in str(args["dex"]).split(","):
			dexes.append(int(s))
	else:
		var from := int(args.get("from", "1"))
		var to := int(args.get("to", "100000"))
		var d := DirAccess.open(src)
		for nm in d.get_directories():
			if nm.is_valid_int() and int(nm) >= from and int(nm) <= to:
				dexes.append(int(nm))
	dexes.sort()
	var shiny := not args.has("no-shiny")
	var index := {}
	var idx_path := dst.path_join("atlas.json")
	if args.has("merge") and FileAccess.file_exists(idx_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
		if old is Dictionary:
			index = old.get("d", {})
	var t0 := Time.get_ticks_msec()
	var pages := 0
	var px := 0
	for dex in dexes:
		for variant in (["", "s"] if shiny else [""]):
			var dir := src.path_join(str(dex)) + ("/s" if variant == "s" else "")
			var r := _pack(dir, dst, str(dex) + variant)
			if r.is_empty():
				continue
			index[str(dex) + variant] = r["entries"]
			pages += int(r["pages"])
			px += int(r["px"])
	var prev := _previews(src, dst, shiny)
	var f := FileAccess.open(idx_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "max": MAX, "anims": ANIMS, "d": index, "p": prev}))
	f.close()
	print("pack_sprites: %d species, %d atlas pages, %.1f Mpx, %d ms -> %s" % [
		dexes.size(), pages, px / 1e6, Time.get_ticks_msec() - t0, dst])
	quit(0)

## Packs one folder of sheets. Returns {entries: [[page,x,y]|0 x7], pages, px} or {} if empty.
func _pack(dir: String, dst: String, base: String) -> Dictionary:
	var imgs: Array = []          # [anim index, Image]
	for i in ANIMS.size():
		var p := dir.path_join(ANIMS[i] + ".png")
		if not FileAccess.file_exists(p):
			continue
		var img := Image.load_from_file(p)
		if img == null or img.is_empty():
			printerr("pack_sprites: cannot read ", p)
			continue
		img.convert(Image.FORMAT_RGBA8)
		imgs.append([i, img])
	if imgs.is_empty():
		return {}
	# tallest first; ties keep the anim order (stable)
	imgs.sort_custom(func(a, b): return a[1].get_height() > b[1].get_height() or \
		(a[1].get_height() == b[1].get_height() and a[0] < b[0]))
	var entries: Array = []
	entries.resize(ANIMS.size())
	entries.fill(0)
	var page := 0
	var rest := imgs
	var total_px := 0
	while not rest.is_empty():
		var best: Dictionary = {}
		var min_w := 0
		for it in rest:
			min_w = maxi(min_w, it[1].get_width())
		var w := min_w
		while w <= MAX:
			var lay := _shelf(rest, w)
			if best.is_empty() or (lay["placed"].size() > best["placed"].size()) or \
					(lay["placed"].size() == best["placed"].size() and lay["w"] * lay["h"] < best["w"] * best["h"]):
				best = lay
			w += 32
		var out := Image.create_empty(int(best["w"]), int(best["h"]), false, Image.FORMAT_RGBA8)
		var left: Array = []
		var placed: Dictionary = best["placed"]
		for it in rest:
			var k: int = it[0]
			if not placed.has(k):
				left.append(it)
				continue
			var pos: Vector2i = placed[k]
			var img: Image = it[1]
			out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
			entries[k] = [page, pos.x, pos.y]
		var name := base + (".png" if page == 0 else "_%d.png" % page)
		out.save_png(dst.path_join(name))
		total_px += out.get_width() * out.get_height()
		page += 1
		if left.size() == rest.size():
			printerr("pack_sprites: sheet larger than %d px in %s" % [MAX, dir])
			break
		rest = left
	return {"entries": entries, "pages": page, "px": total_px}

## Shelf packing at a fixed width; stops (leaving the rest for the next page) at MAX height.
func _shelf(items: Array, width: int) -> Dictionary:
	var placed := {}
	var x := 0
	var y := 0
	var row_h := 0
	var used_w := 0
	for it in items:
		var img: Image = it[1]
		var iw := img.get_width()
		var ih := img.get_height()
		if x + iw > width:
			y += row_h
			x = 0
			row_h = 0
		if y + ih > MAX:
			continue
		placed[it[0]] = Vector2i(x, y)
		x += iw
		row_h = maxi(row_h, ih)
		used_w = maxi(used_w, x)
	return {"placed": placed, "w": used_w, "h": y + row_h}

## Per-generation preview pages: row 0 of each species' Idle sheet (normal and shiny).
func _previews(src: String, dst: String, shiny: bool) -> Dictionary:
	Data.ensure()
	var out := {}
	var gens := {}
	for p in Data.dex:
		if Data.meta_by.has(int(p["dex"])):
			var g := int(p["gen"])
			if not gens.has(g):
				gens[g] = []
			gens[g].append(int(p["dex"]))
	for g in gens:
		for variant in (["", "s"] if shiny else [""]):
			var items: Array = []
			for dex in gens[g]:
				var path := src.path_join(str(dex)) + ("/s" if variant == "s" else "") + "/Idle.png"
				if not FileAccess.file_exists(path):
					continue
				var m: Dictionary = Data.meta_by[dex]["a"]["Idle"]
				if variant == "s" and Data.meta_by[dex].has("sa") and Data.meta_by[dex]["sa"].has("Idle"):
					m = Data.meta_by[dex]["sa"]["Idle"]
				var img := Image.load_from_file(path)
				img.convert(Image.FORMAT_RGBA8)
				var strip := img.get_region(Rect2i(0, 0, int(m["w"]) * int(m["n"]), int(m["h"])))
				items.append([dex, strip])
			items.sort_custom(func(a, b): return a[1].get_height() > b[1].get_height() or \
				(a[1].get_height() == b[1].get_height() and a[0] < b[0]))
			var page := 0
			var rest := items
			while not rest.is_empty():
				var best: Dictionary = {}
				var w := 256
				while w <= MAX:
					var lay := _shelf(rest, w)
					if best.is_empty() or lay["placed"].size() > best["placed"].size() or \
							(lay["placed"].size() == best["placed"].size() and lay["w"] * lay["h"] < best["w"] * best["h"]):
						best = lay
					w += 64
				var img := Image.create_empty(int(best["w"]), int(best["h"]), false, Image.FORMAT_RGBA8)
				var name := "idle%d%s%s" % [g, variant, "" if page == 0 else "_%d" % page]
				var left: Array = []
				for it in rest:
					if not best["placed"].has(it[0]):
						left.append(it)
						continue
					var pos: Vector2i = best["placed"][it[0]]
					img.blit_rect(it[1], Rect2i(Vector2i.ZERO, it[1].get_size()), pos)
					out[str(it[0]) + variant] = [name, pos.x, pos.y]
				img.save_png(dst.path_join(name + ".png"))
				page += 1
				if left.size() == rest.size():
					break
				rest = left
	return out
