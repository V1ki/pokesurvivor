class_name Sfx
extends RefCounted
## Static facade of the audio system (G.Audio of js/core/audio.js), called at the same sites as
## the JS. The work is done by the "Audio" autoload (core/audio.gd, AudioMgr), which registers
## itself in `mgr`; without it (e.g. a bare --script run) every call is a no-op.
##   Sfx.play(name, opts)   G.Audio.sfx(name, opts): ids of audio.js (shot {kind, type},
##                          burst/reveal {rarity}); MIN_GAP + voice cap apply
##   Sfx.music(name)        G.Audio.music(name): crossfade; "" = silence (JS null)

static var mgr: AudioMgr = null
static var test_log: Variant = null         # tests: an Array collects every requested SFX name

static func play(name: String, opts: Dictionary = {}) -> void:
	if test_log is Array:
		(test_log as Array).append(name)
	if mgr != null:
		mgr.play_sfx(name, opts)

static func music(name: String) -> void:
	if mgr != null:
		mgr.play_music(name)

## Track that is playing / fading in ("" = none).
static func current_track() -> String:
	return mgr.track if mgr != null else ""
