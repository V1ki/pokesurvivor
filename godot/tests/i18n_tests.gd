class_name I18nTests
extends RefCounted
## i18n tests (Phase 5), called from tests/run_tests.gd: the port's I18n.t() against the strings
## translated by the unchanged js/core/i18n.js + js/data/lang-*.js in Node
## (tests/fixtures/i18n_vectors.json, written by exportI18n() in tools/export_godot.js): exact
## phrases, upper case, {x} patterns with nested names, fragments in longer texts, whitespace,
## game data texts and the Godot UI literals, in es / en / zh. The Godot supplement
## (core/i18n_extra.gd) is off for the parity checks and checked on its own.

var t: Object

func run(runner: Object) -> void:
	t = runner
	print("-- i18n (I18n.t vs js/core/i18n.js) --")
	var txt := FileAccess.get_file_as_string("res://tests/fixtures/i18n_vectors.json")
	var V: Dictionary = JSON.parse_string(txt) if txt != "" else {}
	if V.is_empty():
		t.check("i18n vectors present (node tools/export_godot.js)", false)
		return
	var keep_lang := I18n.lang
	var keep_extra := I18n.use_extra
	I18n.use_extra = false
	var cases: Array = V["cases"]
	for l in ["es", "en", "zh"]:
		I18n.set_lang(l)
		var exp: Array = V[l]
		var bad := 0
		var first := ""
		var t0 := Time.get_ticks_usec()
		for i in cases.size():
			var got := I18n.t(str(cases[i]))
			if got != str(exp[i]):
				bad += 1
				if bad <= 5:
					first += "\n      %s -> got %s, JS %s" % [JSON.stringify(cases[i]), JSON.stringify(got), JSON.stringify(exp[i])]
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		t.check("i18n %s: %d strings identical to JS" % [l, cases.size()], bad == 0,
			("%d differ%s" % [bad, first]) if bad else "%.0f ms uncached" % ms)
	# cached lookups are cheap (the HUD translates every frame)
	I18n.set_lang("zh")
	var s := "PRADERA · 123 DERROTADOS · 45 MONEDAS"
	I18n.t(s)
	var t1 := Time.get_ticks_usec()
	for i in 1000:
		I18n.t(s)
	var per := (Time.get_ticks_usec() - t1) / 1000.0
	t.check("i18n cached lookup < 5 us", per < 5.0, "%.2f us" % per)
	# Godot-side supplement + multi-line texts
	I18n.use_extra = true
	I18n.set_lang("en")
	t.check("i18n supplement en: Nv. 5 -> Lv. 5", I18n.t("Nv. 5") == "Lv. 5", I18n.t("Nv. 5"))
	t.check("i18n multi-line: per line", I18n.t("Volver\nAjustes") == "Back\nSettings", JSON.stringify(I18n.t("Volver\nAjustes")))
	I18n.set_lang("zh")
	t.check("i18n zh: Pokémon name by dex", I18n.t("Charmander") == "小火龙", I18n.t("Charmander"))
	# the English supplement is only a fallback for Chinese: web zh entries keep winning
	var hint := "WASD moverse  ·  1-4 / Q / E o clic en un ataque para cambiarlo  ·  Esc pausa"
	t.check("i18n zh: web zh beats the English supplement", I18n.t(hint) == "WASD 移动 · 1-4 / Q / E 或点击招式切换 · Esc 暂停", I18n.t(hint))
	t.check("i18n zh: supplement pattern first (shiny name order)", I18n.t("¡Mewtwo shiny te esperaba en la grieta!") == "闪光超梦正在裂隙中等着你！",
		I18n.t("¡Mewtwo shiny te esperaba en la grieta!"))
	t.check("i18n f(): gaps filled after translating", I18n.f("Nv. {x}", [7]) == "Lv. 7", I18n.f("Nv. {x}", [7]))
	t.check("i18n os_lang in LANGS", I18n.os_lang() in I18n.LANGS, I18n.os_lang())
	I18n.use_extra = keep_extra
	I18n.set_lang(keep_lang)
