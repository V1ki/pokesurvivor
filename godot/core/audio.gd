class_name AudioMgr
extends Node
## Audio of the port (js/core/audio.js): plays the music loops and SFX pre-rendered offline from
## the unchanged JS synth (tools/render_audio/render.js -> assets/audio/, PORTING.md §9.5).
## Autoload "Audio"; game code only uses the static facade in core/sfx.gd:
##   Sfx.play("hit") · Sfx.play("shot", {"kind": "beam", "type": "fire"}) · Sfx.music("boss") · Sfx.music("")
##
## Buses (created here if the project has no layout for them):
##   Music  -> Master   gain music * 0.7 (0 when muted), smoothed with tau 0.05 s (setTargetAtTime)
##   SFX    -> Master   gain sfx (the JS x2.4 bus gain is baked into the files)
##   Master             x0.9 output gain + 0.59 dB: the makeup gain of the JS DynamicsCompressor
##                      (-14 dB, ratio 4, knee 30) measured in Chrome — its curve moves levels by
##                      < 1 dB below 0 dBFS, so instead of Godot's hard-knee compressor a hard
##                      limiter (-0.3 dB) only catches overs.
## Music: idempotent like music(name); the old track fades out linearly in 0.7 s, the new one
## fades in 0 -> 1 over 0.8 s from the call and starts 0.1 s after it; each file is one whole loop.
## SFX: AudioLogic (MIN_GAP, 25-voice cap, variants) -> a pool of 32 players (the oldest is
## stolen when all are busy). Muted / sfx 0: nothing is played (and the limiter is untouched).
## The game is not ducked or silenced while paused (as in JS); when the app goes to the
## background on a phone the Master bus is muted until it comes back.
## Headless runs (tests, --script, CI) keep the logic but load and play nothing.
##
## Debug options (after `--`): --audiolog (also --autoplay) prints an "[audio]" line every 5 s;
## --sfx-stress fires 40 SFX in one frame every 10 s (shows the voice cap in the log);
## --audio-rec=<file.wav> records the Master output and writes it when the game quits.

const MANIFEST := "res://assets/audio/manifest.json"
const POOL := 32
const MUSIC_PLAYERS := 3
const OUT_GAIN := 0.9
const LIMIT_DB := -0.3

var logic := AudioLogic.new()
var manifest: Dictionary = {}
var enabled := true
var wanted := ""                 # requested track ("" = silence)
var track := ""                  # track of the current (fading-in or playing) music player
var errors := 0
var steals := 0
var players_max := 0

var _clock := 0.0
var _music_bus := -1
var _sfx_bus := -1
var _vm := 0.0
var _vs := 0.0
var _streams: Dictionary = {}    # id -> AudioStream (loaded on demand / warmed up a few per frame)
var _warm: Array = []
var _pool: Array[AudioStreamPlayer] = []
var _pool_t := PackedFloat64Array()
var _mus: Array[AudioStreamPlayer] = []
var _mus_state: Array[Dictionary] = []   # per music player: name, t0, from, to, dur, start_at, stop
var _log := false
var _log_t := 0.0
var _stress := false
var _stress_t := 0.0
var _rec: AudioEffectRecord
var _rec_path := ""

func _enter_tree() -> void:
	Sfx.mgr = self

func _exit_tree() -> void:
	_save_recording()
	if Sfx.mgr == self:
		Sfx.mgr = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.get_name() != "headless"
	var args := {}
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_log = OS.is_debug_build() and (args.has("audiolog") or args.has("autoplay"))
	_stress = OS.is_debug_build() and args.has("sfx-stress")
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			manifest = j
	if manifest.is_empty():
		push_warning("audio: no manifest at %s (run godot/tools/render_audio/render.js); audio is off" % MANIFEST)
		enabled = false
	_setup_buses()
	if not enabled:
		return
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
		_pool_t.append(-1.0e9)
	for i in MUSIC_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_mus.append(p)
		_mus_state.append({})
	for n in (manifest.get("music", {}) as Dictionary).keys():
		_warm.append("music:" + n)
	_warm.append_array((manifest.get("sfx", {}) as Dictionary).keys())
	if args.has("audio-rec") and OS.is_debug_build():
		_rec_path = str(args["audio-rec"])
		_rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _rec)
		_rec.set_recording_active(true)
	if _log:
		print("[audio] on: driver=%s mix=%dHz latency=%.1fms, %d tracks, %d sfx" % [AudioServer.get_driver_name(),
			AudioServer.get_mix_rate(), AudioServer.get_output_latency() * 1000.0, (manifest.get("music", {}) as Dictionary).size(),
			(manifest.get("sfx", {}) as Dictionary).size()])

func _setup_buses() -> void:
	var m := (manifest.get("mix", {}) as Dictionary).get("compressor", {}) as Dictionary
	var makeup := float(m.get("makeup_db", 0.59))
	AudioServer.set_bus_volume_db(0, linear_to_db(OUT_GAIN) + makeup)
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = LIMIT_DB
		AudioServer.add_bus_effect(0, lim)
	_music_bus = _bus("Music")
	_sfx_bus = _bus("SFX")
	_vm = _target_music()
	_vs = _target_sfx()
	_apply_volumes()

func _bus(nm: String) -> int:
	var i := AudioServer.get_bus_index(nm)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, "Master")
	return i

func _target_music() -> float:
	return 0.0 if Settings.muted else Settings.music * 0.7

func _target_sfx() -> float:
	return 0.0 if Settings.muted else Settings.sfx

func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(_vm, 1.0e-5)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(_vs, 1.0e-5)))
	AudioServer.set_bus_mute(_music_bus, _vm < 1.0e-4)
	AudioServer.set_bus_mute(_sfx_bus, _vs < 1.0e-4)

# ---------------- SFX ----------------

## G.Audio.sfx(name, opts)
func play_sfx(name: String, opts: Dictionary = {}) -> void:
	if name == "" or Settings.muted or Settings.sfx <= 0.0:
		return
	var id := logic.resolve(name, opts, Time.get_ticks_usec() / 1000.0)
	if id == "" or not enabled:
		return
	var e: Dictionary = (manifest.get("sfx", {}) as Dictionary).get(id, {})
	var st := _stream(id, e)
	if st == null:
		return
	var best := -1
	var now := _clock
	for i in _pool.size():
		if not _pool[i].playing:
			best = i
			break
		if best < 0 or _pool_t[i] < _pool_t[best]:
			best = i
	var p := _pool[best]
	if p.playing:
		steals += 1
	p.stream = st
	p.volume_db = float(e.get("gain_db", 0.0))
	p.pitch_scale = float(e.get("pitch", 1.0))
	p.play()
	_pool_t[best] = now

func _stream(id: String, e: Dictionary) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var st: AudioStream = null
	var path := "res://assets/audio/" + str(e.get("file", ""))
	if e.has("file") and ResourceLoader.exists(path):
		st = load(path) as AudioStream
	if st == null:
		errors += 1
		push_warning("audio: missing %s (%s)" % [id, path])
	_streams[id] = st
	return st

# ---------------- music ----------------

## G.Audio.music(name): crossfade to `name` ("" = silence); same name = nothing.
func play_music(name: String) -> void:
	if name == wanted:
		return
	wanted = name
	if not enabled:
		track = name
		return
	# stopCurrent(): every sounding player ramps from where it is to 0 in 0.7 s
	for i in _mus.size():
		var s := _mus_state[i]
		if s.is_empty() or s.get("stop", false):
			continue
		var a := _amp(s)
		_mus_state[i] = {"name": s["name"], "t0": _clock, "from": a, "to": 0.0, "dur": 0.7, "start_at": -1.0, "stop": true}
	track = ""
	if name == "":
		return
	var e: Dictionary = (manifest.get("music", {}) as Dictionary).get(name, {})
	var st := _stream("music:" + name, e)
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	# a free player, else the quietest fading one
	var best := 0
	var best_a := INF
	for i in _mus.size():
		var s := _mus_state[i]
		var a := -1.0 if s.is_empty() else _amp(s)
		if a < best_a:
			best_a = a
			best = i
	var p := _mus[best]
	p.stop()
	p.stream = st
	p.volume_db = -80.0
	_mus_state[best] = {"name": name, "t0": _clock, "from": 0.0, "to": 1.0, "dur": 0.8, "start_at": _clock + 0.1,
		"stop": false, "gain_db": float(e.get("gain_db", 0.0))}
	track = name

func _amp(s: Dictionary) -> float:
	return AudioLogic.ramp(_clock, s["t0"], s["dur"], s["from"], s["to"])

func _update_music() -> void:
	for i in _mus.size():
		var s := _mus_state[i]
		if s.is_empty():
			continue
		var p := _mus[i]
		if s.get("stop", false) and _clock >= float(s["t0"]) + float(s["dur"]):
			p.stop()
			_mus_state[i] = {}
			continue
		if float(s.get("start_at", -1.0)) >= 0.0 and _clock >= float(s["start_at"]):
			s["start_at"] = -1.0
			p.play()
		p.volume_db = linear_to_db(maxf(_amp(s), 1.0e-5)) + float(s.get("gain_db", 0.0))

# ---------------- frame ----------------

func _process(delta: float) -> void:
	_clock += delta
	var tm := _target_music()
	var ts := _target_sfx()
	if _clock < 0.5:
		_vm = tm            # main.gd loads settings.cfg after this node starts: no ramp from the defaults
		_vs = ts
		_apply_volumes()
	elif absf(tm - _vm) > 1.0e-6 or absf(ts - _vs) > 1.0e-6:
		_vm = AudioLogic.smooth(_vm, tm, delta)
		_vs = AudioLogic.smooth(_vs, ts, delta)
		if absf(tm - _vm) < 1.0e-5:
			_vm = tm
		if absf(ts - _vs) < 1.0e-5:
			_vs = ts
		_apply_volumes()
	if not enabled:
		return
	_update_music()
	# warm the cache 2 files per frame after the first second (155 SFX + 6 tracks, ~1.5 s at
	# 120 Hz), so the first hit of a run or the boss theme doesn't load from disk mid-game
	if _clock > 1.0 and not _warm.is_empty():
		for k in 2:
			if _warm.is_empty():
				break
			var id: String = _warm.pop_back()
			if id.begins_with("music:"):
				_stream(id, (manifest["music"] as Dictionary)[id.substr(6)])
			else:
				_stream(id, (manifest["sfx"] as Dictionary)[id])
	var busy := 0
	for p in _pool:
		if p.playing:
			busy += 1
	players_max = maxi(players_max, busy)
	if _stress:
		_stress_t += delta
		if _stress_t >= 10.0:
			_stress_t = 0.0
			for k in 40:
				play_sfx(AudioLogic.NAMES[k % AudioLogic.NAMES.size()], {"kind": "beam", "type": "fire", "rarity": 3})
	if _log:
		_log_t += delta
		if _log_t >= 5.0:
			_log_t = 0.0
			print(stats_line())
			players_max = 0
			logic.max_voices = 0

func stats_line() -> String:
	var mp := 0
	for p in _mus:
		if p.playing:
			mp += 1
	return "[audio] music=%s (players %d, bus %.1f dB) sfx played=%d gap_drop=%d cap_drop=%d voices_max=%d/%d players_max=%d/%d steals=%d errors=%d" % [
		track if track != "" else "-", mp, linear_to_db(maxf(_vm, 1.0e-5)), logic.played, logic.gap_drops, logic.cap_drops,
		logic.max_voices, AudioLogic.VOICE_CAP + 1, players_max, POOL, steals, errors]

func _notification(what: int) -> void:
	# phone: no sound while the app is in the background
	if what == NOTIFICATION_APPLICATION_PAUSED:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		AudioServer.set_bus_mute(0, false)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_recording()

func _save_recording() -> void:
	if _rec == null or _rec_path == "":
		return
	var wav := _rec.get_recording()
	_rec.set_recording_active(false)
	if wav != null:
		var err := wav.save_to_wav(_rec_path)
		print("[audio] recording %.1f s -> %s (%s)" % [wav.get_length(), _rec_path, error_string(err)])
	_rec_path = ""
