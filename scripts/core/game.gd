class_name Game
extends RefCounted
## The fast loop: physics of the house, who hears what, win and lose.
## Pure logic, driven by tick(dt) so it can run headless in simulations.
## UI listens to `event`.

signal event(type: String, data: Dictionary)

var house := House.new()
var time := 0.0
var over := false
var won := false
var end_reason := ""

# Player
var player_room := ""
var moving_to := ""
var sneaking := false
var move_timer := 0.0
var busy := ""            # current action label
var busy_timer := 0.0
var _busy_done: Callable
var receiver_up := true
var attempts_left := 3
var tried := {}           # obj id -> true
var visited := {}         # rooms the player has seen
var off_line_since := 0.0

# World
var room_state := {}      # room id -> {clock: bool, fan: bool, window: bool}
var raining := true
var weather_timer := 0.0
var strike_timer := 0.0
var exit_room := ""
var exit_obj := ""

var murderer: Murderer
var rescuer               # backend with request(ctx) and optional tick(dt)
var rescuer_pending := false
var rescuer_again := false
var line_log: Array = []  # what the rescuer heard: [{who, text}]
var transcript: Array = []
var _bg_timer := -1.0
var _tap_count := 0
var _tap_timer := -1.0

# Tunables
var player_walk := 2.0
var player_sneak := 4.5
var toggle_time := 2.0
var try_time := 1.5
var strike_interval := 75.0


func setup(seed_value := -1) -> void:
	if seed_value >= 0:
		seed(seed_value)
	else:
		randomize()
	for r in house.room_ids:
		room_state[r] = default_room_state(r)
	raining = true
	weather_timer = randf_range(70.0, 110.0)
	strike_timer = randf_range(35.0, 55.0)
	var phones := house.phone_rooms()
	player_room = phones[randi() % phones.size()]
	visited[player_room] = true
	# Exit: at least two rooms away from the start.
	var far := []
	for r in house.room_ids:
		if house.distance(player_room, r) >= 2:
			far.append(r)
	exit_room = far[randi() % far.size()]
	var objs: Array = house.rooms[exit_room].objects
	exit_obj = objs[randi() % objs.size()].id
	# Murderer: at least three rooms away if possible.
	var mstart := []
	for r in house.room_ids:
		if house.distance(player_room, r) >= 3 and r != exit_room:
			mstart.append(r)
	if mstart.is_empty():
		for r in house.room_ids:
			if house.distance(player_room, r) >= 2 and r != exit_room:
				mstart.append(r)
	murderer = Murderer.new(self, mstart[randi() % mstart.size()])
	murderer.timer = 15.0
	receiver_up = true


func emit(type: String, data := {}) -> void:
	event.emit(type, data)


# ---------------------------------------------------------------- world queries

func default_room_state(r: String) -> Dictionary:
	return {
		"clock": house.has_feature(r, "clock"),
		"fan": house.has_feature(r, "fan"),
		"window": house.has_feature(r, "rain"),
	}


func room_state_snapshot(r: String) -> Dictionary:
	return room_state[r].duplicate()


func active_features(r: String) -> Array:
	var s: Dictionary = room_state[r]
	var out := []
	if s.clock:
		out.append("clock")
	if s.fan:
		out.append("fan")
	if s.window and raining:
		out.append("rain")
	if house.has_feature(r, "radiator"):
		out.append("radiator")
	return out


func possible_features(r: String) -> Array:
	var out := []
	for f in house.rooms[r].features:
		if f == "rain" and not raining:
			continue
		out.append(f)
	return out


func permanent_features(r: String) -> Array:
	return ["radiator"] if house.has_feature(r, "radiator") else []


func expected_features(r: String, mem: Dictionary) -> Array:
	var s: Dictionary = mem if not mem.is_empty() else default_room_state(r)
	var out := []
	if s.clock:
		out.append("clock")
	if s.fan:
		out.append("fan")
	if s.window and raining:
		out.append("rain")
	if house.has_feature(r, "radiator"):
		out.append("radiator")
	return out


func player_on_line() -> bool:
	return receiver_up and moving_to == "" and house.rooms[player_room].phone


func player_active_features() -> Array:
	return active_features(player_room)


func can_act() -> bool:
	return not over and moving_to == "" and busy == ""


# ---------------------------------------------------------------- player verbs

func move_to(r: String, sneak := false) -> bool:
	if not can_act() or house.door_to(player_room, r) == "":
		return false
	if receiver_up and house.rooms[player_room].phone:
		hang_up()
	moving_to = r
	sneaking = sneak
	move_timer = player_sneak if sneak else player_walk
	emit("player_move_start", {"from": player_room, "to": r, "dur": move_timer, "sneak": sneak})
	return true


func pick_up() -> bool:
	if receiver_up or not can_act() or not house.rooms[player_room].phone:
		return false
	receiver_up = true
	emit("receiver", {"up": true})
	_line_note("[the player's extension picks up]")
	if murderer.on_line:
		emit("line_quiet_presence", {})
	_bg_timer = 2.0
	if time - off_line_since > 4.0:
		_ask_rescuer("pickup")
	return true


func hang_up() -> bool:
	if not receiver_up:
		return false
	receiver_up = false
	off_line_since = time
	emit("receiver", {"up": false})
	_line_note("[click: the caller hangs up]")
	murderer.on_line_noise("A click")
	return true


func say(text: String) -> bool:
	text = text.strip_edges()
	if text == "" or over or not player_on_line():
		return false
	transcript.append({"t": time, "who": "you", "text": text})
	line_log.append({"who": "player", "text": text})
	emit("player_says", {"text": text})
	murderer.on_line_noise("A voice")
	murderer.on_words("player", text)
	_ask_rescuer("speech")
	return true


func tap() -> bool:
	if over or not player_on_line():
		return false
	emit("player_tap", {})
	murderer.on_line_noise("Tapping")
	_tap_count += 1
	_tap_timer = 1.6
	return true


func toggle_feature(f: String) -> bool:
	if not can_act():
		return false
	var key := "window" if f == "rain" else f
	if not room_state[player_room].has(key) or not house.has_feature(player_room, "rain" if key == "window" else key):
		return false
	var label: String = {"clock": "the clock", "fan": "the fan", "window": "the window"}[key]
	var now_on: bool = room_state[player_room][key]
	var verb := ""
	match key:
		"clock": verb = "Stopping " if now_on else "Winding "
		"fan": verb = "Switching off " if now_on else "Switching on "
		"window": verb = "Closing " if now_on else "Opening "
	_start_busy(verb + label + "...", toggle_time, func():
		room_state[player_room][key] = not now_on
		emit("feature_toggled", {"room": player_room, "feature": key, "on": not now_on})
		murderer.on_small_noise(player_room, "click")
		if player_on_line():
			_line_note("[a click and a scrape somewhere on the line]")
			murderer.on_line_noise("A click")
		_bg_timer = 1.0
	)
	return true


func try_exit(obj: String) -> bool:
	if not can_act() or tried.has(obj) or attempts_left <= 0:
		return false
	var od := house.object_def(obj)
	if od.is_empty() or house.object_room[obj] != player_room:
		return false
	_start_busy("Searching the %s for a way out..." % od.name, try_time, func():
		tried[obj] = true
		if obj == exit_obj:
			emit("exit_try", {"obj": obj, "ok": true, "attempts_left": attempts_left})
			_end(true, "escaped")
			return
		attempts_left -= 1
		emit("exit_try", {"obj": obj, "ok": false, "attempts_left": attempts_left})
		murderer.on_loud_noise(player_room, "crash")
		if player_on_line():
			_line_note("[a loud crash on the line]")
		if attempts_left <= 0:
			_end(false, "noise")
	)
	return true


func _start_busy(label: String, dur: float, done: Callable) -> void:
	busy = label
	busy_timer = dur
	_busy_done = done
	emit("busy", {"label": label, "dur": dur})


# ---------------------------------------------------------------- murderer hooks

func on_murderer_entered(r: String) -> void:
	var d := house.distance(player_room, r)
	if r == player_room:
		_end(false, "caught")
		return
	if d <= 2:
		emit("footsteps", {"room": r, "dist": d, "dir": house.door_to(player_room, r)})


func on_murderer_pickup() -> void:
	_line_note("[click: another extension picks up]")
	if player_on_line():
		emit("line_click", {"text": "Click. Someone else picked up an extension.", "kind": "pickup"})
		_bg_timer = 2.0


func on_murderer_hangup() -> void:
	_line_note("[click: an extension hangs up]")
	if player_on_line():
		emit("line_click", {"text": "Click. An extension hung up.", "kind": "hangup"})


func on_murderer_breath() -> void:
	if player_on_line():
		emit("line_breath", {})
		_line_note("[slow breathing on the line]")


# ---------------------------------------------------------------- rescuer

func _line_note(text: String) -> void:
	line_log.append({"who": "line", "text": text})


func _ask_rescuer(reason: String) -> void:
	if rescuer == null or over:
		return
	if rescuer_pending:
		rescuer_again = true
		return
	rescuer_pending = true
	emit("rescuer_thinking", {"on": true})
	rescuer.request({"reason": reason, "game": self})


func rescuer_says(text: String, guess := "") -> void:
	rescuer_pending = false
	emit("rescuer_thinking", {"on": false})
	if over:
		return
	text = text.strip_edges()
	if text != "":
		transcript.append({"t": time, "who": "rescuer", "text": text})
		line_log.append({"who": "rescuer", "text": text})
		emit("rescuer_says", {"text": text, "guess": guess})
		murderer.on_words("rescuer", text)
	elif guess != "":
		emit("rescuer_guess", {"guess": guess})
	if rescuer_again:
		rescuer_again = false
		_ask_rescuer("followup")


func line_background() -> Array:
	## What anyone on the line can hear, unattributed.
	var out := []
	if player_on_line():
		for f in player_active_features():
			if f not in out:
				out.append(f)
	if murderer.on_line:
		for f in active_features(murderer.room):
			if f not in out:
				out.append(f)
	return out


# ---------------------------------------------------------------- loop

func tick(dt: float) -> void:
	if over:
		return
	time += dt
	if rescuer != null and rescuer.has_method("tick"):
		rescuer.tick(dt)
	if moving_to != "":
		move_timer -= dt
		if move_timer <= 0.0:
			var from := player_room
			player_room = moving_to
			moving_to = ""
			var first := not visited.has(player_room)
			visited[player_room] = true
			emit("player_arrive", {"room": player_room, "from": from, "first": first})
			murderer.on_player_step(player_room, sneaking)
			if murderer.room == player_room:
				_end(false, "walked_in")
				return
			if house.rooms[player_room].phone and not receiver_up:
				pass  # player picks up manually
	if busy != "":
		busy_timer -= dt
		if busy_timer <= 0.0:
			busy = ""
			var cb := _busy_done
			_busy_done = Callable()
			emit("busy", {"label": "", "dur": 0.0})
			cb.call()
			if over:
				return
	if _tap_timer >= 0.0:
		_tap_timer -= dt
		if _tap_timer < 0.0:
			var n := _tap_count
			_tap_count = 0
			var txt := "[%d tap%s on the receiver]" % [n, "" if n == 1 else "s"]
			transcript.append({"t": time, "who": "you", "text": txt})
			line_log.append({"who": "player", "text": txt})
			_ask_rescuer("tap")
	if _bg_timer >= 0.0:
		_bg_timer -= dt
		if _bg_timer < 0.0:
			_emit_backgrounds()
	_tick_world(dt)
	murderer.tick(dt)


func _emit_backgrounds() -> void:
	if player_on_line() and murderer.on_line:
		var theirs := active_features(murderer.room)
		emit("line_background", {"features": theirs})
	var bg := line_background()
	var labels := bg.map(func(f): return House.FEATURE_LABEL[f])
	_line_note("[background on the line: %s]" % (", ".join(labels) if not labels.is_empty() else "nothing"))


func _tick_world(dt: float) -> void:
	weather_timer -= dt
	if weather_timer <= 0.0:
		raining = not raining
		weather_timer = randf_range(60.0, 100.0) if raining else randf_range(35.0, 60.0)
		emit("weather", {"raining": raining})
		_bg_timer = 0.5
	strike_timer -= dt
	if strike_timer <= 0.0:
		strike_timer = strike_interval
		var rs := []
		for r in house.room_ids:
			if room_state[r].clock:
				rs.append(r)
		emit("clock_strike", {"rooms": rs})
		if player_on_line() and room_state[player_room].clock and murderer.listening:
			murderer.listen_overlap = murderer.identify_time
			murderer.note("The clocks struck. One of them was right behind their voice.")
		if player_on_line() and murderer.on_line and room_state[murderer.room].clock:
			_line_note("[a clock strikes, loud, through the line]")


func _end(win: bool, reason: String) -> void:
	if over:
		return
	over = true
	won = win
	end_reason = reason
	emit("game_over", {"won": win, "reason": reason})
