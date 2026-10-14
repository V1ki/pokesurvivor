class_name I18nTranslation
extends Translation
## Bridge to TranslationServer: every auto-translated Control text (Label, Button, tooltips,
## OptionButton / PopupMenu items, placeholders...) goes through I18n.t(), the same way the web
## game translates the DOM with a MutationObserver. Player-typed text (names) sets
## auto_translate_mode = DISABLED on its Control.

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(I18n.t(String(src_message)))
