class_name SettingsScreen
extends Control
## Settings overlay (js/ui/settings-ui.js): Sonido (SoundControls), Gráficos (language, quality
## auto/high/mid/low, damage numbers, calm mode, FPS, desktop fullscreen), Controles (joystick
## size, key reference), Cuenta (the app's save: import from the web game / export as JSON,
## delete), Acerca de (+ full credits, font licences, legal notice). Opens over the menu (or the
## pause screen) and closes back to it.

var ui: MetaUI
var tab := "sound"
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _import_text: TextEdit
var _msg: Label

const TABS := [["sound", "Sonido"], ["gfx", "Gráficos"], ["ctl", "Controles"], ["save", "Cuenta"], ["about", "Acerca de"]]
const VERSION := "1.2 · 2026-10-09"                   # settings-ui.js VERSION (the web version this port follows)
const REPO := "https://github.com/JPTER78/pokesurvivor"
const CONTACT := "jpieratorregrosa@gmail.com"         # ui.js CONTACT (legal notice)
const CREDITS := "res://CREDITS.md"                   # copied from the repo by tools/export_godot.js
var about_sub := ""      # About sub-page: "" | credits | legal | pixelify | fusion

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_script(load("res://ui/dim_bg.gd"))
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	cc.add_child(_panel)
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	v.add_child(UIKit.hbox(8, [UIKit.label("Ajustes", 26), UIKit.spacer(0, 0, true), UIKit.button("Cerrar", "SmallGhost", close, "click")]))
	_tabs = UIKit.hbox(6)
	v.add_child(_tabs)
	for t in TABS:
		var id: String = t[0]
		var b := UIKit.button(t[1], "GenTab", func():
			tab = id
			about_sub = ""
			render(), "click")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(b)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = UIKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

func open(t := "") -> void:
	if t != "":
		tab = t
	about_sub = ""
	visible = true
	render()

func close() -> void:
	visible = false
	Settings.save_cfg()
	if ui != null and ui.current == "menu":
		ui.open_menu()

func render() -> void:
	_panel.custom_minimum_size = Vector2(minf(680.0, size.x - 32.0), 0)
	_scroll.custom_minimum_size = Vector2(0, minf(470.0, size.y - 190.0))
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).theme_type_variation = "GenTabOn" if TABS[i][0] == tab else "GenTab"
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"sound": _sound()
		"gfx": _gfx()
		"ctl": _ctl()
		"save": _save()
		_: _about()

func _h(text: String, sub := "") -> void:
	_body.add_child(UIKit.label(text, 17, UIKit.GOLD))           # .set-h: gold 17 px
	if sub != "":
		var l := UIKit.label(sub, 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
		l.custom_minimum_size = Vector2(580, 0)
		_body.add_child(l)

func _toggle(label: String, desc: String, getter: Callable, setter: Callable) -> void:
	var on: bool = getter.call()
	var b := UIKit.button("Sí" if on else "No", "SmallGold" if on else "SmallButton", func():
		setter.call(not getter.call())
		Settings.save_cfg()
		render(), "click")
	b.custom_minimum_size = Vector2(70, 0)
	var v := UIKit.vbox(0, [UIKit.label(label, 16), UIKit.label(desc, 13, UIKit.MUTED)])
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(UIKit.hbox(10, [v, b]))

func _chips(opts: Array, cur: Variant, setter: Callable) -> void:
	var h := UIKit.hbox(6)
	for o in opts:
		var val: Variant = o[0]
		var b := UIKit.button(o[1], "ChipOn" if val == cur else "Chip", func():
			setter.call(val)
			Settings.save_cfg()
			render(), "click")
		if o.size() > 2 and o[2] == false:
			b.disabled = true
		h.add_child(b)
	_body.add_child(h)

# ---------------- tabs ----------------

func _sound() -> void:
	_h("Sonido")
	var sc := SoundControls.make(380.0)
	sc.mute_changed.connect(func(): if ui != null: ui.refresh_sound_icon())
	_body.add_child(sc)

func _gfx() -> void:
	_h("Idioma", "Se aplica al momento.")
	var langs := UIKit.hbox(6)
	for l in I18n.LANGS:
		var code: String = l
		var lb := UIKit.button(I18n.NAMES[code], "ChipOn" if code == I18n.lang else "Chip", func():
			Settings.set_lang(code)
			render(), "click")
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # language names stay as they are (translate="no")
		langs.add_child(lb)
	_body.add_child(langs)
	var auto: String = ["baja", "media", "alta"][Settings.auto_level]
	_h("Calidad", "Cuántos efectos y partículas se dibujan. Auto la baja sola si el juego va a tirones (ahora: %s)." % auto)
	_chips([["auto", "Auto"], ["high", "Alta"], ["mid", "Media"], ["low", "Baja"]], Settings.quality, func(v): Settings.quality = v)
	_h("Pantalla")
	_toggle("Números de daño", "Los números que salen al golpear y al recibir daño.", func(): return Settings.dmg_numbers, func(v): Settings.dmg_numbers = v)
	_toggle("Menos sacudidas y destellos", "La cámara tiembla menos y los fogonazos son suaves.", func(): return Settings.calm, func(v): Settings.calm = v)
	_toggle("Mostrar FPS", "Fotogramas por segundo, en la esquina de abajo.", func(): return Settings.show_fps, func(v): Settings.show_fps = v)
	# settings-ui.js "Pantalla completa" (where the platform has windows: desktop builds)
	if not OS.has_feature("mobile"):
		var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		var fb := UIKit.button("Salir" if full else "Activar", "SmallButton", func():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_tree().create_timer(0.3).timeout.connect(func(): if visible and tab == "gfx": render()), "click")
		var fv := UIKit.vbox(0, [UIKit.label("Pantalla completa", 16), UIKit.label("Ocupa toda la pantalla, sin el marco de la ventana.", 13, UIKit.MUTED)])
		fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(UIKit.hbox(10, [fv, fb]))

func _ctl() -> void:
	_h("En móvil o tablet", "Pon el dedo en cualquier parte y arrastra para moverte: el joystick aparece donde tocas. Toca un ataque de abajo para cambiarlo y el botón de arriba a la derecha para pausar. Se juega en horizontal.")
	_body.add_child(UIKit.vbox(0, [UIKit.label("Tamaño del joystick", 16), UIKit.label("Cuánto hay que arrastrar el dedo.", 13, UIKit.MUTED)]))
	_chips([[0.8, "Pequeño"], [1.0, "Normal"], [1.25, "Grande"]], Settings.stick, func(v): Settings.stick = v)
	_h("En PC")
	for k in [["WASD o flechas", "moverse"], ["1–4 o clic en el icono", "elegir ataque"], ["Q / E", "ataque anterior / siguiente"],
			["Esc o P", "pausa"], ["1–3, R", "elegir carta al subir de nivel, cambiar opciones"], ["Mando", "stick izq. moverse · LB/RB cambiar · Start pausa · cruceta + A elegir · B atrás · Y cambiar opciones"]]:
		var l := UIKit.label(k[0], 15, UIKit.GOLD)
		l.custom_minimum_size = Vector2(220, 0)
		_body.add_child(UIKit.hbox(10, [l, UIKit.label(k[1], 15, UIKit.MUTED)]))

func _save() -> void:
	if Save.read_only:
		_h("Partida", "Partida de prueba en memoria (modo depuración): no se guarda nada.")
	else:
		_h("Partida", "Tu partida se guarda en este dispositivo (%s)." % ProjectSettings.globalize_path(Save.path))
	_h("Importar del juego web", "En el juego web abre la consola del navegador (F12) y ejecuta  copy(localStorage.getItem('ps.guest'))  (con cuenta local: 'ps.save.<nombre>'). Pega aquí el texto copiado, o guárdalo como save_import.json en la carpeta de la partida. Sustituye tu partida actual (se guarda una copia de seguridad).")
	_import_text = TextEdit.new()
	_import_text.custom_minimum_size = Vector2(0, 90)
	_import_text.placeholder_text = "{\"v\":3,\"name\":\"Invitado\",...}"
	_import_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # JSON sample: not text
	_import_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.add_child(_import_text)
	_msg = UIKit.label("", 14, UIKit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	_msg.custom_minimum_size = Vector2(580, 0)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.add_child(UIKit.button("Pegar del portapapeles", "SmallButton", func():
		_import_text.text = DisplayServer.clipboard_get(), "click"))
	row.add_child(UIKit.button("Importar", "SmallGold", func(): _confirm_import(_import_text.text), "click"))
	var file := Save.path.get_base_dir().path_join("save_import.json")
	row.add_child(UIKit.button("Importar save_import.json", "SmallButton", func():
		if not FileAccess.file_exists(file):
			_msg.text = "No existe " + ProjectSettings.globalize_path(file)
			return
		_confirm_import(FileAccess.get_file_as_string(file)), "click"))
	_body.add_child(row)
	_h("Exportar", "Copia tu partida (JSON) al portapapeles y a save_export.json; se puede importar en el juego web con localStorage.setItem('ps.guest', …).")
	var ex := UIKit.button("Exportar partida (JSON)", "SmallButton", func():
		var txt := Save.export_json()
		DisplayServer.clipboard_set(txt)
		_msg.text = "Copiada al portapapeles y guardada en " + ProjectSettings.globalize_path(Save.export_path()), "confirm")
	ex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(ex)
	_body.add_child(_msg)
	_h("Borrar")
	var del := UIKit.button("Borrar partida", "DangerButton", _confirm_delete, "click")
	del.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(del)

func _confirm(question: String, yes_text: String, on_yes: Callable) -> void:
	for c in _body.get_children():
		c.queue_free()
	_h(question)
	_body.add_child(UIKit.hbox(10, [UIKit.button("Cancelar", "GhostButton", render, "back"), UIKit.button(yes_text, "DangerButton", on_yes, "confirm")]))

func _confirm_import(text: String) -> void:
	if Save.parse(text) == null:
		_msg.text = "No es un JSON de partida válido."
		Sfx.play("error")
		return
	_confirm("Se sustituirá tu partida actual por la importada (se guarda una copia de seguridad). ¿Seguro?", "Importar", func():
		if Save.import_error(text) == "":
			ui.quit_run_requested.emit()        # a run in progress ends first (banked into the old save)
		var err := Save.import_json(text)
		render()
		if err != "":
			_msg.text = err
			Sfx.play("error")
			return
		ui.toast("Partida importada: %d Pokémon, %s monedas" % [Save.owned_count(), UIKit.num_es(int(Save.data["coins"]))], 3.0)
		after_save_change())

func _confirm_delete() -> void:
	_confirm("Se borrará toda tu partida de este dispositivo. ¿Seguro?", "Borrar para siempre", func():
		ui.quit_run_requested.emit()            # settings-ui.js: G.Game.quit() before clearGuest()
		Save.delete_save()
		ui.toast("Partida borrada")
		after_save_change())

## New save content (settings-ui.js → G.Flow.toLogin): music restarts and a run that was ended
## for it leaves the screen (main.gd), then personality test (no partner) or menu — also from
## a results screen.
func after_save_change() -> void:
	visible = false
	ui.refresh_coins()
	ui.save_replaced.emit()
	if Save.data.get("partner") == null:
		ui.start_test()
	else:
		ui.open_menu()

func _about() -> void:
	if about_sub == "credits":
		_credits()
		return
	if about_sub == "legal":
		_legal()
		return
	if about_sub in ["pixelify", "fusion"]:
		_license(about_sub)
		return
	_body.add_child(UIKit.label("PokéSurvivor", 34, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(UIKit.label("Versión " + VERSION, 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(UIKit.label("Versión nativa para Android y PC (Godot)", 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_para("Juego de fans gratuito y sin ánimo de lucro: sin anuncios ni compras. Pokémon y sus personajes son propiedad de Nintendo, Creatures y GAME FREAK; este proyecto no está afiliado a ellos.")
	_h("Créditos")
	for l in ["Sprites: PMD SpriteCollab y sus artistas (CC BY-NC 4.0).", "Datos de los Pokémon: PokéAPI.",
			"Música y sonidos: originales, generados por el propio juego.", "Fuentes: Pixelify Sans y Fusion Pixel Font (OFL)."]:
		_body.add_child(UIKit.label("· " + l, 14))
	# settings-ui.js: Aviso legal y privacidad · Contacto · Código (GitHub) (+ the full credits:
	# the web links CREDITS.md of the repository, the app shows it)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.add_child(UIKit.button("Créditos completos", "SmallButton", func(): _sub("credits"), "click"))
	row.add_child(UIKit.button("Aviso legal y privacidad", "SmallButton", func(): _sub("legal"), "click"))
	row.add_child(UIKit.button("Contacto", "SmallButton", func(): OS.shell_open("mailto:" + CONTACT + "?subject=Pok%C3%A9Survivor"), "click"))
	row.add_child(UIKit.button("Código (GitHub)", "SmallButton", func(): OS.shell_open(REPO), "click"))
	_body.add_child(row)

## Opens an About sub-page ("" = the About tab itself).
func _sub(s: String) -> void:
	about_sub = s
	render()
	_scroll.scroll_vertical = 0

func _para(text: String, col := UIKit.MUTED, translate := true) -> Label:
	var l := UIKit.label(text, 14, col, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.custom_minimum_size = Vector2(580, 0)
	if not translate:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.add_child(l)
	return l

func _sub_head(title: String, back_to := "") -> void:
	var b := UIKit.button("Volver", "SmallGhost", func(): _sub(back_to), "back")
	_body.add_child(UIKit.hbox(8, [UIKit.label(title, 22, UIKit.GOLD), UIKit.spacer(0, 0, true), b]))

## SpriteCollab artists of CREDITS.md (shipped with the game): the names of its table, in order.
static func credit_artists() -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(CREDITS, FileAccess.READ)
	if f == null:
		return out
	var head := 0
	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if not ln.begins_with("|"):
			continue
		head += 1
		if head <= 2:                # "| Artista | Contacto | Sprites |" + "|---|"
			continue
		var name := ln.split("|")[1].strip_edges().replace("\\_", "_").replace("\\*", "*")    # markdown escapes
		if name != "":
			out.append(name)
	return out

## CREDITS.md in the app (CC BY-NC 4.0 attribution, PokeAPI, OFL fonts, trademark).
func _credits() -> void:
	_sub_head("Créditos")
	_h("Sprites", "Los sprites estilo Pokémon Mundo Misterioso vienen de SpriteCollab (github.com/PMDCollab/SpriteCollab), bajo licencia CC BY-NC 4.0 (creativecommons.org/licenses/by-nc/4.0): uso no comercial y con atribución a sus artistas.")
	var names := credit_artists()
	_body.add_child(UIKit.label("Artistas (%d)" % names.size(), 16))
	_para(" · ".join(names), UIKit.INK, false)      # names are never translated (e.g. "Audino")
	_para("Los sprites de cada artista (por número de Pokédex) están en CREDITS.md, incluido con el juego.")
	_h("Datos", "Stats base y nombres en español: PokeAPI (pokeapi.co).")
	_h("Fuentes", "Pixelify Sans (SIL Open Font License 1.1). El juego usa una versión modificada, «Pixelify PS», con los números redibujados para distinguirlos mejor.")
	_para("Para el chino: Fusion Pixel Font de TakWolf, 12 px proporcional, chino simplificado (SIL Open Font License 1.1), sin modificar.")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_child(UIKit.button("Licencia de Pixelify Sans", "SmallButton", func(): _sub("pixelify"), "click"))
	row.add_child(UIKit.button("Licencia de Fusion Pixel Font", "SmallButton", func(): _sub("fusion"), "click"))
	_body.add_child(row)
	_h("Marca", "Pokémon es propiedad de Nintendo, Creatures Inc. y GAME FREAK. Este es un proyecto de fan sin ánimo de lucro.")

## The font licence texts shipped with the game (SIL OFL 1.1; Fusion Pixel adds its sources').
func _license(which: String) -> void:
	_sub_head("Licencia de Pixelify Sans" if which == "pixelify" else "Licencia de Fusion Pixel Font", "credits")
	var files := ["res://assets/fonts/OFL.txt"] if which == "pixelify" else \
		["res://assets/fonts/fusion-pixel/OFL.txt", "res://assets/fonts/fusion-pixel/LICENSES/ark-pixel/OFL.txt",
		"res://assets/fonts/fusion-pixel/LICENSES/cubic-11/OFL.txt", "res://assets/fonts/fusion-pixel/LICENSES/galmuri/LICENSE.txt"]
	for path in files:
		var txt := FileAccess.get_file_as_string(path)
		if txt != "":
			_para(txt.strip_edges(), UIKit.INK, false).add_theme_font_size_override("font_size", UIKit.fs(12))

## dev.html #scr-legal without the online parts (account deletion, cloud, friends, co-op).
func _legal() -> void:
	_sub_head("Aviso legal")
	_h("Proyecto de fan", "PokéSurvivor es un juego hecho por fans, gratuito y sin ánimo de lucro. No tiene anuncios ni compras. Se puede apoyar con donaciones voluntarias, que se usan sólo para pagar los servidores y el dominio, y que no dan ninguna ventaja en el juego.")
	_para("No está afiliado, patrocinado ni aprobado por Nintendo, Creatures Inc., GAME FREAK ni The Pokémon Company. Pokémon y todos los nombres y personajes relacionados son marcas y propiedad de sus respectivos dueños.")
	_h("Criptomonedas", "PokéSurvivor no tiene ninguna criptomoneda, token ni NFT oficial, y su autor no ha creado ninguno. Cualquier token que use el nombre del juego lo han creado terceros: no nos hacemos cargo de ninguna compra, venta o inversión que hagas con ellos, y nada de lo que hay aquí es una recomendación de inversión.")
	_h("Contenido de terceros", "Sprites de SpriteCollab (CC BY-NC 4.0, créditos completos en CREDITS.md del repositorio). Datos de la Pokédex de PokeAPI. Fuentes Pixelify Sans y Fusion Pixel Font (OFL). La música y los efectos de sonido son originales del proyecto.")
	_h("Contacto y retirada de contenido", "Si eres titular de derechos y quieres que retiremos algo, escríbenos y lo quitaremos lo antes posible:")
	_para(CONTACT, UIKit.GOLD, false)
	_body.add_child(UIKit.hbox(8, [UIKit.label("Código fuente:", 14, UIKit.MUTED), _no_tr(UIKit.label(REPO.replace("https://", ""), 14, UIKit.GOLD))]))
	_h("Privacidad", "Esta versión no tiene cuentas ni conexión: tu partida se guarda sólo en este dispositivo y no se envía a ningún sitio. No hay publicidad ni seguimiento.")

static func _no_tr(c: Control) -> Control:
	c.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return c
