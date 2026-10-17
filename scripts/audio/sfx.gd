class_name Sfx
extends Node
## Audio director. Builds buses (Room / Line / Walls), generates all sounds
## with Synth and reacts to game events.
##   Room  — your own room, direct
##   Line  — everything heard through the receiver: band-limited 300–3400 Hz
##   Walls — the house through walls: heavily low-passed

var game: Game
var s := {}                    # name -> AudioStreamWAV
var room_amb := {}             # feature -> player (your room)
var line_amb := {}             # feature -> player (the other extension)
var hiss: AudioStreamPlayer
var heart: AudioStreamPlayer
var voices: Array = []
var _voice_i := 0
var _char_n := 0
var danger := 0.0              # perceived danger 0..1, decays
var active := true             # false on the title / while paused: everything fades
var master_db := 0.0
## Per-feature loudness in your room (the clock loop is sparse, so it gets more gain).
const FEATURE_DB := {"clock": -1.0, "fan": -11.0, "rain": -9.0, "radiator": -8.0}


func _ready() -> void:
	_buses()
	_generate()
	for f in House.FEATURES:
		room_amb[f] = _loop_player(f, "Room")
		line_amb[f] = _loop_player(f, "Line")
	hiss = _loop_player("hiss", "Line")
	heart = _loop_player("heart", "Master")
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Line"
		add_child(p)
		voices.append(p)


func _buses() -> void:
	if AudioServer.get_bus_index("Line") != -1:
		return
	for name in ["Room", "Line", "Walls"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	var line := AudioServer.get_bus_index("Line")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 320.0
	AudioServer.add_bus_effect(line, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3200.0
	AudioServer.add_bus_effect(line, lp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_LOFI
	dist.drive = 0.25
	dist.post_gain = -4.0
	AudioServer.add_bus_effect(line, dist)
	var walls := AudioServer.get_bus_index("Walls")
	var wlp := AudioEffectLowPassFilter.new()
	wlp.cutoff_hz = 500.0
	AudioServer.add_bus_effect(walls, wlp)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.7
	rev.wet = 0.25
	AudioServer.add_bus_effect(walls, rev)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	var room := AudioServer.get_bus_index("Room")
	var rrev := AudioEffectReverb.new()
	rrev.room_size = 0.35
	rrev.wet = 0.12
	AudioServer.add_bus_effect(room, rrev)


func _generate() -> void:
	s.clock = Synth.to_wav(Synth.clock_loop(), true)
	s.fan = Synth.to_wav(Synth.fan_loop(), true)
	s.rain = Synth.to_wav(Synth.rain_loop(), true)
	s.radiator = Synth.to_wav(Synth.radiator_loop(), true)
	s.hiss = Synth.to_wav(Synth.hiss_loop(), true)
	s.heart = Synth.to_wav(Synth.heartbeat(), true)
	s.click = Synth.to_wav(Synth.receiver_click())
	s.tap = Synth.to_wav(Synth.tap_knock())
	s.step_heavy = [Synth.to_wav(Synth.footstep(true)), Synth.to_wav(Synth.footstep(true)), Synth.to_wav(Synth.footstep(true))]
	s.step_light = [Synth.to_wav(Synth.footstep(false)), Synth.to_wav(Synth.footstep(false))]
	s.breath = Synth.to_wav(Synth.breath())
	s.bell = Synth.to_wav(Synth.bell(392.0))
	s.crash = Synth.to_wav(Synth.crash())
	s.toggle = Synth.to_wav(Synth.fade_out(Synth.tick(800.0, 0.08), 0.02))
	# Her voice: a handful of vowel syllables around a female-ish pitch.
	var vowels := [[800.0, 1200.0], [500.0, 1900.0], [330.0, 2300.0], [520.0, 950.0], [380.0, 900.0], [650.0, 1700.0]]
	s.syll = []
	for v in vowels:
		s.syll.append(Synth.to_wav(Synth.syllable(randf_range(195.0, 225.0), v[0], v[1], randf_range(0.09, 0.15))))


func _loop_player(name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s[name]
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play(randf() * 1.5)
	return p


func one_shot(name: String, bus := "Master", db := 0.0, pitch := 1.0) -> void:
	if not active and name != "crash":
		return
	var st = s[name]
	if st is Array:
		st = st[randi() % st.size()]
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func steps(n: int, heavy: bool, bus: String, db: float, gap := 0.5) -> void:
	for i in n:
		get_tree().create_timer(i * gap + randf() * 0.05).timeout.connect(func():
			one_shot("step_heavy" if heavy else "step_light", bus, db, randf_range(0.9, 1.1)))


func bind(g: Game) -> void:
	game = g
	danger = 0.0
	g.event.connect(_on_event)


func on_voice_char(c: String, kind := "her") -> void:
	if kind not in ["her", "him", "fake"]:
		return
	# A syllable every few letters; spaces and punctuation are pauses.
	if c == " " or c in ".,!?—…-":
		_char_n = 0
		return
	_char_n += 1
	if _char_n % 3 != 1:
		return
	var p: AudioStreamPlayer = voices[_voice_i]
	_voice_i = (_voice_i + 1) % voices.size()
	p.stream = s.syll[randi() % s.syll.size()]
	p.pitch_scale = {"her": randf_range(0.92, 1.1), "fake": randf_range(0.78, 0.86), "him": randf_range(0.5, 0.56)}[kind]
	p.volume_db = -6.0 if kind == "her" else -3.0
	p.play()


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"receiver":
			one_shot("click", "Room", -4.0)
		"line_click":
			one_shot("click", "Line", -2.0, randf_range(0.9, 1.1))
			danger = maxf(danger, 0.6)
		"line_breath":
			one_shot("breath", "Line", -8.0)
			danger = maxf(danger, 0.7)
		"line_quiet_presence":
			danger = maxf(danger, 0.5)
		"player_tap":
			one_shot("tap", "Line", -4.0)
		"footsteps":
			var gap := 0.32 if d.running else 0.55
			if d.dist == 1:
				steps(4, true, "Walls", 0.0, gap)
				danger = 1.0
			elif d.dist == 2:
				steps(4, true, "Walls", -12.0, gap)
				danger = maxf(danger, 0.6)
			else:
				steps(4, true, "Walls", -22.0, gap)
				danger = maxf(danger, 0.35)
		"player_move_start":
			steps(4 if not d.sneak else 3, false, "Room", -16.0 if not d.sneak else -28.0, d.dur / 4.0)
		"feature_toggled":
			one_shot("toggle", "Room", -6.0)
		"clock_strike":
			var here: bool = game.room_state[game.player_room].clock
			for i in 3:
				get_tree().create_timer(i * 1.4).timeout.connect(func():
					one_shot("bell", "Room" if here else "Walls", -6.0 if here else -12.0))
		"exit_try":
			if not d.ok:
				one_shot("crash", "Room", 0.0)
				danger = 1.0
		"presence":
			one_shot("breath", "Walls", -6.0, 0.8)
			danger = maxf(danger, 0.75)
		"murderer_in_room":
			one_shot("breath", "Room", -4.0, 0.85)
			if not d.get("still", false):
				steps(2, true, "Room", -2.0, 0.6)
			danger = 1.0
		"murderer_found_exit":
			one_shot("crash", "Walls", -10.0, 0.8)
		"game_over":
			if not d.won:
				one_shot("crash", "Room", 0.0, 0.7)


func _process(dt: float) -> void:
	if game == null:
		return
	if not active or game.over:
		for p in room_amb.values() + line_amb.values() + [hiss, heart]:
			_fade(p, -80.0, dt)
		return
	danger = maxf(0.0, danger - dt * 0.12)
	var mine := game.active_features(game.player_room) if game.moving_to == "" else []
	for f in House.FEATURES:
		var target: float = FEATURE_DB[f] if f in mine else -80.0
		if f == "rain" and game.raining and game.house.has_feature(game.player_room, "rain") and not game.room_state[game.player_room].window:
			target = -24.0  # muffled through the closed window
		_fade(room_amb[f], target, dt)
	var on := game.player_on_line()
	_fade(hiss, -20.0 if on else -80.0, dt * 2.0)
	var theirs := game.active_features(game.murderer.room) if (on and game.murderer.on_line) else []
	for f in House.FEATURES:
		_fade(line_amb[f], FEATURE_DB[f] - 12.0 if f in theirs else -80.0, dt)
	_fade(heart, lerpf(-40.0, -4.0, danger) if danger > 0.05 else -80.0, dt * 2.0)
	heart.pitch_scale = lerpf(0.9, 1.35, danger)


func _fade(p: AudioStreamPlayer, target: float, dt: float) -> void:
	p.volume_db = move_toward(p.volume_db, target, dt * 40.0)
