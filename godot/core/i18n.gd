class_name I18n
extends RefCounted
## Languages (port of js/core/i18n.js): the game is written in Spanish and the Spanish text is
## the key. Every visible string is translated CENTRALLY at the output chokepoints, never at the
## call sites:
##   - Controls (Label / Button / tooltips / OptionButton items / placeholders ...) through
##     TranslationServer: install() registers I18nTranslation, whose _get_message() is t();
##   - custom-drawn text through DrawUtil.text() / text_width().
## Lookup, exactly like JS (verified against it in tests/i18n_tests.gd):
##   1. exact phrase                 'Volver' -> 'Back'   (ALL-CAPS text: case-insensitive)
##   2. {x} patterns                 'Nivel {x}' -> 'Level {x}' (captured groups translated too)
##   3. whole-word fragments inside a longer text (keys of >= 4 chars or with a space)
## ALL-CAPS sources give ALL-CAPS results. Chinese also loads the English dictionary first as a
## fallback (the Chinese one is added after it and wins), like the web.
## Dictionaries: data/lang_en.json, data/lang_zh.json (tools/export_godot.js, the add() calls of
## js/data/lang-*.js in order) + core/i18n_extra.gd (strings that only exist in the Godot port).
## Godot-only extension: a text with line breaks is translated line by line.

const LANGS := ["es", "en", "zh"]
const NAMES := {"es": "Español", "en": "English", "zh": "简体中文"}

static var lang := "es"
static var use_extra := true          # tests switch the Godot supplement off for JS parity
static var _ready_lang := ""
static var _exact: Dictionary = {}       # es -> tr
static var _exact_low: Dictionary = {}   # lower(es) -> tr
static var _patterns: Dictionary = {}    # es -> {re, re_i, tr, pre, suf, pre_l, suf_l, min}; ordered like a JS Map
static var _frag: Dictionary = {}        # lower(es) -> tr
static var _frag_lens: PackedInt32Array = PackedInt32Array()
static var _cache: Dictionary = {}
static var _re_letter: RegEx = null
static var _re_word: RegEx = null
static var _re_ws: RegEx = null
static var _tr_obj: Translation = null
static var missing: Dictionary = {}      # debug: untranslated texts seen (record_missing)
static var record_missing := false

# ---------------- language ----------------

## Default language from the OS locale (zh* -> zh, es* -> es, anything else -> en).
static func os_lang() -> String:
	var loc := OS.get_locale().to_lower()
	if loc.begins_with("zh"):
		return "zh"
	if loc.begins_with("es"):
		return "es"
	return "en"

## Loads the dictionaries of language l (no-op if already loaded) and refreshes the UI.
static func set_lang(l: String) -> void:
	if not l in LANGS:
		l = "es"
	lang = l
	_build()
	if _tr_obj != null:
		_tr_obj.locale = _locale()
		TranslationServer.set_locale(_locale())
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)

static func _locale() -> String:
	return "zh_CN" if lang == "zh" else lang

## Hooks the translator into TranslationServer (all Controls). Call uninstall() before quitting.
static func install() -> void:
	if _tr_obj != null:
		return
	_tr_obj = I18nTranslation.new()
	_tr_obj.locale = _locale()
	TranslationServer.add_translation(_tr_obj)
	TranslationServer.set_locale(_locale())

static func uninstall() -> void:
	if _tr_obj == null:
		return
	TranslationServer.remove_translation(_tr_obj)
	_tr_obj = null

static func _build() -> void:
	var key := lang + ("+x" if use_extra else "")
	if key == _ready_lang:
		return
	_ready_lang = key
	_exact.clear()
	_exact_low.clear()
	_patterns.clear()
	_frag.clear()
	_frag_lens = PackedInt32Array()
	_cache.clear()
	if lang == "es":
		return
	# English (+ its Godot supplement) first: it is also the fallback of Chinese, whose entries
	# (web, then Godot supplement) are added after it and win
	for a in _adds("en"):
		add(a, "en")
	var extra: Array = []
	if use_extra:
		extra = _pairs(I18nExtra.EN)
		add(extra, "en")
	if lang == "zh":
		for a in _adds("zh"):
			add(a, "zh")
		if use_extra:
			var z := _pairs(I18nExtra.ZH)
			add(z, "zh")
			extra += z
	if use_extra:
		# the supplement's patterns are tried first (more specific than the web ones)
		var front := {}
		for p in extra:
			if _patterns.has(p[0]):
				front[p[0]] = _patterns[p[0]]
		for k in _patterns:
			if not front.has(k):
				front[k] = _patterns[k]
		_patterns = front

static func _adds(l: String) -> Array:
	var f := FileAccess.open("res://data/lang_%s.json" % l, FileAccess.READ)
	if f == null:
		push_warning("I18n: missing data/lang_%s.json" % l)
		return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return []
	return (j.data as Dictionary).get("adds", [])

## Supplement entries: keys compare with collapsed whitespace, like the texts they match.
static func _pairs(d: Dictionary) -> Array:
	_regs()
	var out: Array = []
	for k in d:
		out.append([_re_ws.sub(str(k).strip_edges(), " ", true), d[k]])
	return out

static func _regs() -> void:
	if _re_letter != null:
		return
	_re_letter = RegEx.create_from_string("(*UTF)\\p{L}")
	_re_word = RegEx.create_from_string("(*UTF)[\\p{L}\\p{N}]")
	_re_ws = RegEx.create_from_string("(*UTF)\\s+")

static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		if ".*+?^${}()|[]\\/".contains(ch):
			out += "\\"
		out += ch
	return out

## add() of i18n.js: pairs [[es, tr], ...] of language l (only the current language, plus English
## as the fallback of Chinese). A translation equal to the Spanish text removes the fallback.
static func add(pairs: Array, l := "en") -> void:
	if l != lang and not (l == "en" and lang == "zh"):
		return
	_regs()
	for p in pairs:
		var es := str(p[0])
		var tr := str(p[1]) if p[1] != null else ""
		if tr == "":
			continue
		if es == tr:
			_patterns.erase(es)
			_exact.erase(es)
			_exact_low.erase(es.to_lower())
			_frag.erase(es.to_lower())
			continue
		if es.contains("{x}"):
			var parts := es.split("{x}")
			var esc: Array = []
			for s in parts:
				esc.append(_esc(s))
			var body := "^" + "(.+?)".join(PackedStringArray(esc)) + "\\z"
			var pre := parts[0]
			var suf := parts[parts.size() - 1]
			_patterns[es] = {"re": RegEx.create_from_string("(*UTF)" + body), "re_i": RegEx.create_from_string("(*UTF)(*UCP)(?i)" + body),
				"tr": tr, "pre": pre, "suf": suf, "pre_l": pre.to_lower(), "suf_l": suf.to_lower(),
				"min": pre.length() + suf.length() + parts.size() - 1}
		else:
			_exact[es] = tr
			_exact_low[es.to_lower()] = tr
			if es.length() >= 4 or _re_ws.search(es) != null:
				_frag[es.to_lower()] = tr
	var lens := {}
	for k in _frag:
		lens[(k as String).length()] = true
	var arr: Array = lens.keys()
	arr.sort()
	arr.reverse()
	_frag_lens = PackedInt32Array(arr)
	_cache.clear()

# ---------------- lookup ----------------

static func _has_letter(s: String) -> bool:
	_regs()
	return _re_letter.search(s) != null

static func _keep_case(src: String, tr: String) -> String:
	if src == src.to_upper() and _has_letter(src):
		return tr.to_upper()
	return tr

## Translates a text to the current language (Spanish in, Spanish out when lang == "es").
static func t(s: String) -> String:
	if lang == "es" or s == "":
		return s
	if _ready_lang == "":
		_build()
	var c: Variant = _cache.get(s)
	if c != null:
		return c
	var r: String
	if s.contains("\n"):
		var lines := s.split("\n")
		for i in lines.size():
			lines[i] = t(lines[i])
		r = "\n".join(lines)
	elif not _has_letter(s):
		r = s
	else:
		r = _core(s)
		if record_missing and r == s:
			missing[s] = true
	if _cache.size() > 4000:
		_cache.clear()
	_cache[s] = r
	return r

## Text with {x} gaps for code (G.I18n.f): I18n.f("Nivel {x}", [5]).
static func f(es: String, vals: Array) -> String:
	var out := t(es)
	for v in vals:
		var i := out.find("{x}")
		if i < 0:
			break
		out = out.substr(0, i) + str(v) + out.substr(i + 3)
	return out

static func _core(s: String) -> String:
	_regs()
	# keep the surrounding whitespace; inner runs of whitespace compare as one space
	var a := 0
	var b := s.length()
	while a < b and _is_space(s.unicode_at(a)):
		a += 1
	while b > a and _is_space(s.unicode_at(b - 1)):
		b -= 1
	var lead := s.substr(0, a)
	var tail := s.substr(b)
	var body := _re_ws.sub(s.substr(a, b - a), " ", true)
	if body == "":
		return s
	var upper := body == body.to_upper() and _has_letter(body)
	var r: Variant = _exact.get(body)
	if r == null and upper:
		var e: Variant = _exact_low.get(body.to_lower())
		if e != null:
			r = _keep_case(body, e)
	if r == null:
		var low := body.to_lower() if upper else ""
		var n := body.length()
		for p in _patterns.values():
			if n < int(p["min"]):
				continue
			if upper:
				if not (low.begins_with(p["pre_l"]) and low.ends_with(p["suf_l"])):
					continue
			elif not (body.begins_with(p["pre"]) and body.ends_with(p["suf"])):
				continue
			var m: RegExMatch = (p["re_i"] if upper else p["re"]).search(body)
			if m == null:
				continue
			var tr: String = p["tr"]
			var out := ""
			var gi := 1
			var pos := 0
			while true:
				var k := tr.find("{x}", pos)
				if k < 0:
					break
				out += tr.substr(pos, k - pos)
				if gi <= m.get_group_count():
					out += _core(m.get_string(gi))
				gi += 1
				pos = k + 3
			out += tr.substr(pos)
			r = _keep_case(body, out)
			break
	if r == null and not _frag.is_empty():
		r = _frag_replace(body)
	return lead + (body if r == null else str(r)) + tail

static func _is_space(c: int) -> bool:
	# JS \s: ASCII whitespace, NBSP, the Unicode space separators, line/paragraph separators, BOM
	return c == 32 or (c >= 9 and c <= 13) or c == 0xA0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200A) \
		or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000 or c == 0xFEFF

## Level 3: replaces every whole-word dictionary fragment (longest first) case-insensitively,
## like the JS regex (?<![\p{L}\p{N}])(k1|k2|...)(?![\p{L}\p{N}]) with flags giu.
static func _frag_replace(body: String) -> String:
	var n := body.length()
	var word := PackedByteArray()
	word.resize(n + 1)
	for m in _re_word.search_all(body):
		word[m.get_start()] = 1
	var low := body.to_lower()
	if low.length() != n:
		return body
	var out := ""
	var i := 0
	var last := 0
	while i < n:
		if i > 0 and word[i - 1] == 1:
			i += 1
			continue
		var hit := 0
		for L in _frag_lens:
			if L > n - i:
				continue
			if word[i + L] == 1:
				continue
			if _frag.has(low.substr(i, L)):
				hit = L
				break
		if hit == 0:
			i += 1
			continue
		var w := body.substr(i, hit)
		out += body.substr(last, i - last) + _keep_case(w, str(_frag.get(w.to_lower(), w)))
		i += hit
		last = i
	return out + body.substr(last)
