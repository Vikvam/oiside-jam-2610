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
var move_total := 1.0
var busy := ""            # current action label
var busy_timer := 0.0
var _busy_done: Callable
var receiver_up := true
var hidden := false
var _searching := false     # he came for this room and is searching it
var _search_timer := 0.0
var _search_from := ""      # the room he came in from: that door is blocked
var _presence_timer := 0.0
var attempts_left := 3
var tried := {}           # obj id -> true
var visited := {}         # rooms the player has seen
var trail: Array = []     # rooms the player walked through, in order
var facing := "north"     # the way you walked in (you start facing the phone wall)
var off_line_since := 0.0

# World
var room_state := {}      # room id -> {clock: bool, fan: bool, window: bool}
var raining := true
var heating := true
var heating_timer := 0.0
var weather_timer := 0.0
var strike_timer := 0.0
var exit_room := ""
var exit_obj := ""

var murderer: Murderer
var murderer_awake := true  # main keeps him still until her intro is over
var rescuer               # backend with request(ctx) and optional tick(dt)
var rescuer_pending := false
var rescuer_again := false
var line_log: Array = []  # what the rescuer heard: [{who, text}]
## What her monitors show: anonymous figures moving in camera rooms.
## [{t, room, kind ("in"/"out"), dir, text, who}] — `who` is for tests
## and the post-game log only; the rescuer must never read it.
var cam_log: Array = []
var cam_ask_gap := 10.0     # at most one "something changed on the monitors" per this
var _last_cam_ask := -100.0
var transcript: Array = []
var _bg_timer := -1.0
var _tap_count := 0
var _tap_timer := -1.0

# Tunables
var difficulty := "normal"
var explore_mode := false   # player only knows sounds of visited rooms
var rearranged := false     # random doors/phones/sounds each game
var large := false          # 12-room house
const DIFFICULTY := {
	"gentle": {"identify_time": 8.0, "hunt_threshold": 1, "far_step_chance": 0.15, "fake_hangup_chance": 0.15, "walk_time": 5.5, "hunt_time": 3.6, "search_time": 5.0},
	"normal": {"identify_time": 6.0, "hunt_threshold": 2, "far_step_chance": 0.3, "fake_hangup_chance": 0.25, "walk_time": 4.0, "hunt_time": 2.6, "search_time": 4.0},
	"hard": {"identify_time": 4.0, "hunt_threshold": 2, "far_step_chance": 0.5, "fake_hangup_chance": 0.35, "walk_time": 4.0, "hunt_time": 2.6, "search_time": 3.0, "imitate_chance": 0.6},
}
var hide_time := 1.0
var unhide_time := 0.6
## Hiding has one visible rule, no dice: if he only passes through, he
## doesn't see you while you keep still. If he came FOR this room, he searches
## it and finds you after search_time, unless you slip out another door.
var search_time := 4.0
var player_walk := 2.0
var player_sneak := 4.5
var toggle_time := 2.0
var try_time := 1.5
var wrong_freeze := 3.0
var strike_interval := 75.0


func setup(seed_value := -1) -> void:
	if seed_value >= 0:
		seed(seed_value)
	else:
		randomize()
	if large:
		house = House.new(true)
	if rearranged:
		house.rearrange()
	house.relocate_movables()
	for r in house.room_ids:
		room_state[r] = default_room_state(r)
	raining = true
	weather_timer = randf_range(70.0, 110.0)
	strike_timer = randf_range(35.0, 55.0)
	heating = randf() < 0.5
	heating_timer = randf_range(10.0, 25.0)
	var phones := house.phone_rooms()
	player_room = phones[randi() % phones.size()]
	visited[player_room] = true
	trail = [player_room]
	# Exit: three rooms away from the start if possible, else two.
	var far := []
	for min_d in [3, 2]:
		for r in house.room_ids:
			if house.distance(player_room, r) >= min_d:
				far.append(r)
		if not far.is_empty():
			break
	exit_room = far[randi() % far.size()]
	# A hidden passage is built in: never obvious furniture, never something
	# that gets carried around.
	var objs: Array = house.rooms[exit_room].objects.filter(func(o):
		return not o.get("obvious", false) and not house.is_movable(o.id) and house.home_room[o.id] == exit_room)
	if objs.is_empty():
		objs = house.rooms[exit_room].objects
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
	apply_difficulty(difficulty)
	murderer.timer = 15.0
	receiver_up = true
	_bg_timer = 2.0


func apply_difficulty(level: String) -> void:
	difficulty = level
	var d: Dictionary = DIFFICULTY.get(level, DIFFICULTY.normal)
	for k in d:
		if k in murderer:
			murderer.set(k, d[k])
		else:
			set(k, d[k])


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
	if heating and house.has_feature(r, "radiator"):
		out.append("radiator")
	return out


func possible_features(r: String) -> Array:
	var out := []
	for f in house.rooms[r].features:
		if f == "rain" and not raining:
			continue
		out.append(f)
	return out


func permanent_features(_r: String) -> Array:
	return []


func expected_features(r: String, mem: Dictionary) -> Array:
	var s: Dictionary = mem if not mem.is_empty() else default_room_state(r)
	var out := []
	if s.clock:
		out.append("clock")
	if s.fan:
		out.append("fan")
	if s.window and raining:
		out.append("rain")
	if heating and house.has_feature(r, "radiator"):
		out.append("radiator")
	return out


func player_on_line() -> bool:
	return receiver_up and moving_to == "" and house.rooms[player_room].phone


func player_active_features() -> Array:
	return active_features(player_room)


func can_act() -> bool:
	return not over and moving_to == "" and busy == ""


func _unhide() -> void:
	if hidden:
		hidden = false
		emit("hidden", {"on": false})


## Coming out of hiding: fine, unless he is standing in the room.
func _leave_hiding() -> bool:
	if not hidden:
		return true
	if murderer.room == player_room:
		_end(false, "caught")
		return false
	_unhide()
	return true


## The first thing the player does (or the end of her intro) wakes him.
func wake() -> void:
	if not murderer_awake:
		murderer_awake = true
		murderer.timer = minf(murderer.timer, 6.0)


## Break reference cycles so finished games are freed.
func dispose() -> void:
	_busy_done = Callable()
	for c in event.get_connections():
		event.disconnect(c.callable)
	if murderer:
		murderer.game = null
	if rescuer != null and "game" in rescuer:
		if rescuer is Node:
			rescuer.queue_free()
		else:
			if "fallback" in rescuer and rescuer.fallback:
				rescuer.fallback.game = null
			rescuer.game = null
	murderer = null
	rescuer = null


func hide() -> bool:
	if not can_act() or hidden:
		return false
	wake()
	if receiver_up and house.rooms[player_room].phone:
		hang_up()
	_start_busy(Loc.t("busy_hide"), hide_time, func():
		hidden = true
		emit("hidden", {"on": true})
	)
	return true


func unhide() -> bool:
	if not hidden or not can_act():
		return false
	if not _leave_hiding():
		return true
	_start_busy(Loc.t("busy_unhide"), unhide_time, func(): pass)
	return true


func toggle_hide() -> bool:
	return unhide() if hidden else hide()


# ---------------------------------------------------------------- player verbs

func move_to(r: String, sneak := false) -> bool:
	if not can_act() or house.door_to(player_room, r) == "":
		return false
	wake()
	if hidden and murderer.room == player_room:
		_unhide()
		if not (_searching and r != _search_from):
			_end(false, "caught")
			return true
		# Slipping out the other door while he searches the corners.
		_searching = false
		emit("slipped_out", {})
	_unhide()
	if receiver_up and house.rooms[player_room].phone:
		hang_up()
	moving_to = r
	sneaking = sneak
	_cam(player_room, "out", house.door_to(player_room, r), "p")
	move_timer = player_sneak if sneak else player_walk
	move_total = move_timer
	emit("player_move_start", {"from": player_room, "to": r, "dur": move_timer, "sneak": sneak})
	return true


func pick_up() -> bool:
	if receiver_up or not can_act() or not house.rooms[player_room].phone:
		return false
	if hidden and murderer.room == player_room:
		_end(false, "caught")
		return true
	_unhide()
	receiver_up = true
	emit("receiver", {"up": true})
	_line_note("[the player's extension picks up]")
	murderer.on_line_noise("m_n_pickup")
	if murderer.on_line:
		emit("line_quiet_presence", {})
	_bg_timer = 2.0
	if time - off_line_since > 4.0:
		_ask_rescuer("pickup")
	return true


func hang_up() -> bool:
	if not receiver_up or over:
		return false
	receiver_up = false
	off_line_since = time
	emit("receiver", {"up": false})
	_line_note("[click: the caller hangs up]")
	murderer.on_line_noise("m_n_click")
	return true


func say(text: String) -> bool:
	text = text.strip_edges()
	if text == "" or over or not player_on_line():
		return false
	wake()
	var heard := murderer.listening
	transcript.append({"t": time, "who": "you", "text": text, "heard": heard})
	var loud := is_shouting(text)
	line_log.append({"who": "player", "text": text + (" [shouted]" if loud else ""), "heard": heard})
	emit("player_says", {"text": text, "loud": loud, "heard": heard})
	if loud:
		murderer.on_shout(player_room)
	murderer.on_line_noise("m_n_voice")
	murderer.on_words("player", text)
	_ask_rescuer("speech")
	return true


## ALL CAPS means raising your voice: heard through walls.
static func is_shouting(text: String) -> bool:
	var letters := 0
	var upper := 0
	for c in text:
		if c.to_lower() != c.to_upper():
			letters += 1
			if c == c.to_upper():
				upper += 1
	return letters >= 4 and upper >= letters * 0.7


func tap() -> bool:
	if over or not player_on_line():
		return false
	wake()
	emit("player_tap", {"heard": murderer.listening})
	murderer.on_line_noise("m_n_tap")
	_tap_count += 1
	_tap_timer = 1.6
	return true


func toggle_feature(f: String) -> bool:
	if not can_act():
		return false
	if not _leave_hiding():
		return false
	var key := "window" if f == "rain" else f
	if not room_state[player_room].has(key) or not house.has_feature(player_room, "rain" if key == "window" else key):
		return false
	var label: String = Loc.t("the_" + key)
	var now_on: bool = room_state[player_room][key]
	var verb := ""
	match key:
		"clock": verb = Loc.t("busy_stop") if now_on else Loc.t("busy_wind")
		"fan": verb = Loc.t("busy_off") if now_on else Loc.t("busy_on")
		"window": verb = Loc.t("busy_close") if now_on else Loc.t("busy_open")
	_start_busy(verb + label + "...", toggle_time, func():
		room_state[player_room][key] = not now_on
		emit("feature_toggled", {"room": player_room, "feature": key, "on": not now_on})
		murderer.on_small_noise(player_room, "click")
		if player_on_line():
			_line_note("[a click and a scrape somewhere on the line]")
			murderer.on_line_noise("m_n_click")
		_bg_timer = 1.0
	)
	return true


func try_exit(obj: String) -> bool:
	if not can_act() or tried.has(obj) or attempts_left <= 0 or not _leave_hiding():
		return false
	var od := house.object_def(obj)
	if od.is_empty() or house.object_room[obj] != player_room:
		return false
	_start_busy(Loc.t("busy_search", [house.obj_name(obj)]), try_time, func():
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
			return
		# You freeze while the crash echoes through the house.
		_start_busy(Loc.t("busy_frozen"), wrong_freeze, func(): pass)
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
	_cam(r, "in", house.door_to(r, murderer.prev_room), "m")
	if murderer.prev_room == player_room and moving_to == "":
		# Only now is he really out: the doorway takes a few seconds.
		emit("murderer_left", {"dir": house.door_to(player_room, r)})
	if r == player_room and moving_to != "" and move_timer < move_total * 0.5:
		var came_from: String = murderer.trail[-2] if murderer.trail.size() > 1 else ""
		if came_from != moving_to:
			return  # you were already halfway through the far door
		_end(false, "caught")  # you met him in the doorway
		return
	if r == player_room:
		if hidden and moving_to == "":
			var came_from: String = murderer.prev_room
			if murderer.goal_room == r and murderer.goal in ["hunt", "suspect"]:
				_searching = true
				_search_timer = search_time
				_search_from = came_from
				emit("murderer_searching", {"dir": house.door_to(r, came_from), "dur": search_time})
				murderer.note(Loc.t("m_searching", [house.room_in(r)]))
			else:
				emit("murderer_in_room", {})
				murderer.note(Loc.t("m_nobody", [house.room_in(r)]))
			return
		_end(false, "caught")
		return
	var running := murderer.goal == "hunt"
	if d <= 2 or (running and d <= 3):
		var p := house.path(player_room, r)
		var dir := house.door_to(player_room, p[0]) if not p.is_empty() else ""
		emit("footsteps", {"room": r, "dist": d, "dir": dir, "running": running, "for_you": _coming_for_you()})


func _coming_for_you() -> bool:
	return murderer.goal_room == player_room and murderer.goal in ["hunt", "suspect"]


## He walks out of room `r` towards `next`.
func on_murderer_leaves(r: String, next: String) -> void:
	_cam(r, "out", house.door_to(r, next), "m")


func on_murderer_sets_off(r: String) -> void:
	var d := house.distance(player_room, r)
	if not murderer.path.is_empty():
		on_murderer_leaves(r, murderer.path[0])
	if r != player_room and d <= 2:
		var p := house.path(player_room, r)
		var dir := house.door_to(player_room, p[0]) if not p.is_empty() else ""
		emit("footsteps", {"room": r, "dist": d, "dir": dir, "running": murderer.goal == "hunt", "leaving": true, "for_you": _coming_for_you()})


func on_murderer_pickup() -> void:
	_line_note("[click: another extension picks up]")
	if player_on_line():
		emit("line_click", {"text": "Click. Someone else picked up an extension.", "kind": "pickup"})
		_bg_timer = 2.0


func on_murderer_hangup() -> void:
	_line_note("[click: an extension hangs up]")
	if player_on_line():
		emit("line_click", {"text": "Click. An extension hung up.", "kind": "hangup"})


func on_murderer_taunt(text: String) -> void:
	_line_note("[a man's voice on the line, low]: " + text)
	if player_on_line():
		emit("murderer_says", {"text": text})


func on_murderer_imitate(text: String) -> void:
	_line_note("[a voice imitating you (Mara), slightly too low]: " + text)
	emit("imposter_says", {"text": text})
	_ask_rescuer("imposter")


func on_murderer_fake_hangup() -> void:
	if player_on_line() and randf() < 0.5:
		emit("line_fake_tell", {})


func on_murderer_breath() -> void:
	if player_on_line():
		emit("line_breath", {})
		_line_note("[slow breathing on the line]")


# ---------------------------------------------------------------- cameras

## A figure moved in a camera room. Standing still, nobody shows up on her
## grainy monitors: she only sees movement.
func _cam(room: String, kind: String, dir: String, who: String) -> void:
	if not house.has_camera(room) or over:
		return
	var verb := "comes in through the %s door" if kind == "in" else "leaves through the %s door"
	var text := "[monitor, %s] a figure %s" % [house.rooms[room].name, verb % dir]
	cam_log.append({"t": time, "room": room, "kind": kind, "dir": dir, "text": text, "who": who})
	# She'll want to say something about it, if you're there to hear it.
	if player_on_line() and time - _last_cam_ask >= cam_ask_gap:
		_last_cam_ask = time
		_ask_rescuer("camera")


# ---------------------------------------------------------------- rescuer

func _line_note(text: String) -> void:
	line_log.append({"who": "line", "text": text, "t": time})


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
		var heard := murderer.listening
		transcript.append({"t": time, "who": "rescuer", "text": text, "heard": heard})
		line_log.append({"who": "rescuer", "text": text, "heard": heard})
		emit("rescuer_says", {"text": text, "guess": guess, "heard": heard})
		murderer.on_words("rescuer", text)
	elif guess != "":
		emit("rescuer_guess", {"guess": guess})
	if rescuer_again:
		rescuer_again = false
		_ask_rescuer("followup")


func foreign_sounds() -> Array:
	## What the player hears on the line that isn't from their own room.
	if not player_on_line() or not murderer.on_line:
		return []
	return active_features(murderer.room)


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
			facing = house.door_to(from, player_room)
			trail.append(player_room)
			_cam(player_room, "in", house.door_to(player_room, from), "p")
			var first := not visited.has(player_room)
			visited[player_room] = true
			emit("player_arrive", {"room": player_room, "from": from, "first": first})
			_presence_timer = 0.0
			_check_presence(true)
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
			transcript.append({"t": time, "who": "you", "text": txt, "heard": murderer.listening})
			line_log.append({"who": "player", "text": txt, "heard": murderer.listening})
			_ask_rescuer("tap")
	if _bg_timer >= 0.0:
		_bg_timer -= dt
		if _bg_timer < 0.0:
			_emit_backgrounds()
	_tick_world(dt)
	if not murderer_awake:
		return
	murderer.tick(dt)
	if over:
		return
	_presence_timer -= dt
	if _presence_timer <= 0.0:
		_check_presence(false)
	if _searching:
		if not hidden or murderer.room != player_room:
			_searching = false
		else:
			murderer.hold(0.5)  # he stays until he has looked everywhere
			_search_timer -= dt
			if _search_timer <= 0.0:
				_searching = false
				_end(false, "caught")


func _check_presence(arrived: bool) -> void:
	## Standing still next door? You hear him behind that door.
	_presence_timer = randf_range(5.0, 8.0)
	if over or moving_to != "" or murderer.state == Murderer.S.MOVE:
		return
	if house.distance(player_room, murderer.room) != 1:
		return
	if arrived or randf() < 0.6:
		emit("presence", {"dir": house.door_to(player_room, murderer.room)})


func _emit_backgrounds() -> void:
	if player_on_line() and murderer.on_line:
		var theirs := active_features(murderer.room)
		emit("line_background", {"features": theirs})
	var bg := line_background()
	var labels := bg.map(func(f): return House.FEATURE_LABEL[f])
	_line_note("[background on the line: %s]" % (", ".join(labels) if not labels.is_empty() else "nothing"))


func _tick_world(dt: float) -> void:
	heating_timer -= dt
	if heating_timer <= 0.0:
		heating = not heating
		heating_timer = randf_range(12.0, 25.0) if heating else randf_range(15.0, 35.0)
		emit("heating", {"on": heating})
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
			murderer.note(Loc.t("m_strike"))
		if player_on_line() and murderer.on_line and room_state[murderer.room].clock:
			_line_note("[a clock strikes, loud, through the line]")


func _end(win: bool, reason: String) -> void:
	if over:
		return
	over = true
	won = win
	end_reason = reason
	emit("game_over", {"won": win, "reason": reason})
