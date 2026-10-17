class_name Murderer
extends RefCounted
## The murderer: pure code, no LLM. Keeps a set of candidate rooms where the
## player might be and cycles listen -> think -> move -> listen.
## Everything it concludes is written to `log` so the player can read the
## post-mortem ("I said clock, and he came").

enum S { THINK, MOVE, LISTEN, FAKE_HANGUP, SEARCH, GUARD }

var game  # Game (untyped to avoid a cyclic class reference)
var house: House
var room := ""
var state := S.THINK
var timer := 4.0
var path: Array = []
var goal := ""            # phone / hunt / suspect / guard
var goal_room := ""

var candidates := {}      # room id -> true
var exact := {}           # rooms that matched the heard background exactly
var seen := {}            # rooms whose objects it knows
var memory := {}          # room id -> feature state when last seen
var suspects := {}        # rooms the rescuer pointed at -> true
var searched_thoroughly := {}
var exit_known := ""
var lead_time := -100.0
var dirty := false        # new evidence since the current plan

var listening := false    # hears the line
var on_line := false      # the player can hear its breathing/background
var listen_overlap := 0.0
var heard_bg := []        # last background it identified
var last_phone := ""
var last_listen_at := {}  # room -> time
var breath_timer := 5.0

var log: Array = []       # [{t, text}]

# Tunables (exposed so A/B settings can poke them)
var walk_time := 4.0
var hunt_time := 2.6
var listen_min := 18.0
var listen_max := 28.0
var hunt_threshold := 2
var identify_time := 5.0
var fake_hangup_chance := 0.3
var hearing_range := 2
var far_step_chance := 0.35
var sneak_heard_chance := 0.25


func _init(g, start_room: String) -> void:
	game = g
	house = g.house
	room = start_room
	seen[room] = true
	memory[room] = g.room_state_snapshot(room)
	_reset_candidates()


func note(text: String) -> void:
	if not log.is_empty() and log[-1].text == text and game.time - log[-1].t < 3.0:
		return
	log.append({"t": game.time, "text": text})
	game.emit("murderer_log", {"text": text})


func _reset_candidates() -> void:
	candidates.clear()
	exact.clear()
	for r in house.room_ids:
		if r != room:
			candidates[r] = true


func _set_candidates(rs: Array, why: String, strong := true) -> void:
	var before := candidates.size()
	candidates.clear()
	for r in rs:
		candidates[r] = true
	if candidates.is_empty():
		_reset_candidates()
	exact.clear()
	if strong:
		lead_time = game.time
	dirty = true
	if why != "":
		note("%s → %s" % [why, _cand_str()])
	elif candidates.size() != before:
		dirty = true


func _intersect(rs: Array, why: String, strong := true) -> void:
	var out := []
	for r in rs:
		if candidates.has(r):
			out.append(r)
	if out.is_empty():
		out = rs  # contradiction: trust the newest evidence
	_set_candidates(out, why, strong)


func _cand_str() -> String:
	var names := []
	for r in candidates:
		names.append(house.rooms[r].name)
	if names.size() >= house.room_ids.size() - 1:
		return "could be anywhere"
	return "maybe: " + ", ".join(names)


func _expand() -> Array:
	var out := {}
	for r in candidates:
		out[r] = true
		for n in house.neighbors(r):
			out[n] = true
	return out.keys()


# ---------------------------------------------------------------- hearing

func on_player_step(dest: String, sneaking := false) -> void:
	var rng := 1 if listening else hearing_range
	var d := house.distance(room, dest)
	var heard := d <= rng and state != S.MOVE
	if heard and d >= 2 and randf() > far_step_chance:
		heard = false
	if heard and sneaking and randf() > sneak_heard_chance:
		heard = false
	if heard:
		var ring := house.rooms_at(room, d)
		var out := []
		for r in _expand():
			if r in ring:
				out.append(r)
		if out.is_empty():
			out = ring
		_set_candidates(out, "Footsteps, %s" % ("right next door" if d <= 1 else "two rooms away"))
	else:
		var near := house.rooms_within(room, 0 if (sneaking or state == S.MOVE) else 1)
		var out := []
		for r in _expand():
			if r not in near:
				out.append(r)
		candidates.clear()
		for r in out:
			candidates[r] = true
		if candidates.is_empty():
			_reset_candidates()


func on_loud_noise(src: String, what: String) -> void:
	_set_candidates([src], "A loud %s from the %s" % [what, house.rooms[src].name])


func on_small_noise(src: String, what: String) -> void:
	var d := house.distance(room, src)
	if d <= 1 and not listening:
		_intersect(house.rooms_at(room, d), "A %s nearby" % what)


func on_line_noise(what: String) -> void:
	if listening:
		_intersect(house.phone_rooms(), "%s on the line. They're at a phone" % what, false)


func on_words(speaker: String, text: String) -> void:
	if not listening:
		return
	var rooms := Words.rooms_named(text)
	for o in Words.objects_named(text, house, seen):
		if o.room not in rooms:
			rooms.append(o.room)
		note("Heard '%s' — I know where that is: the %s" % [house.object_def(o.obj).name, house.rooms[o.room].name])
	var dirs := Words.directions(text)
	if speaker == "player":
		if not rooms.is_empty():
			_intersect(rooms, "The prey mentioned it")
		if not dirs.is_empty():
			_shift(dirs, "The prey said '%s'" % ", ".join(dirs))
	else:
		for r in rooms:
			if not suspects.has(r) and not searched_thoroughly.has(r):
				suspects[r] = true
				dirty = true
				note("The voice on the line pointed at the %s. Interesting." % house.rooms[r].name)
		if not dirs.is_empty():
			_shift(dirs, "The voice said '%s'" % ", ".join(dirs))
	# Feature words the player says about their own room narrow things too.
	if speaker == "player":
		var feats := Words.features_named(text)
		if not feats.is_empty():
			var out := []
			for r in candidates:
				var ok := true
				for f in feats:
					if not house.has_feature(r, f):
						ok = false
				if ok:
					out.append(r)
			if not out.is_empty() and out.size() < candidates.size():
				_set_candidates(out, "They talked about a %s" % ", ".join(feats))


func _shift(dirs: Array, why: String) -> void:
	if candidates.size() > 4:
		note(why + " — useless while I don't know where they are.")
		return
	var cur: Array = candidates.keys()
	for d in dirs:
		var nxt := []
		for r in cur:
			var s := house.step(r, d)
			if s != "" and s not in nxt:
				nxt.append(s)
		if nxt.is_empty():
			break
		cur = nxt
	_set_candidates(cur, why)


func _hear_background() -> void:
	var bg: Array = game.player_active_features()
	bg.sort()
	if bg == heard_bg:
		return
	heard_bg = bg
	var out := []
	var ex := []
	for r in house.phone_rooms():
		var possible: Array = game.possible_features(r)
		if house.has_feature(r, "radiator") and "radiator" not in possible:
			possible.append("radiator")
		var ok := true
		for f in bg:
			if f not in possible:
				ok = false
		for f in game.permanent_features(r):
			if f not in bg:
				ok = false
		if ok:
			out.append(r)
			var expect: Array = game.expected_features(r, memory.get(r, {}))
			expect.sort()
			if expect == bg:
				ex.append(r)
	var label := "silence" if bg.is_empty() else ", ".join(bg.map(func(f): return House.FEATURE_LABEL[f]))
	if out.is_empty():
		_intersect(house.phone_rooms(), "Heard %s behind them. Doesn't fit anything I know" % label)
		return
	_intersect(out, "Heard %s behind their voice" % label)
	exact.clear()
	for r in ex:
		if candidates.has(r):
			exact[r] = true


# ---------------------------------------------------------------- moving

func tick(dt: float) -> void:
	match state:
		S.THINK:
			timer -= dt
			if timer <= 0.0:
				_decide()
		S.MOVE:
			timer -= dt
			if timer <= 0.0:
				_enter(path.pop_front())
				if game.over:
					return
				if path.is_empty():
					_arrive()
				elif dirty and goal != "hunt":
					dirty = false
					state = S.THINK
					timer = 0.3
				else:
					timer = hunt_time if goal == "hunt" else walk_time
		S.LISTEN:
			_tick_listen(dt)
		S.FAKE_HANGUP:
			_tick_listen_ears(dt)
			timer -= dt
			if timer <= 0.0:
				listening = false
				on_line = false
				state = S.THINK
				timer = 0.5
		S.SEARCH:
			timer -= dt
			if timer <= 0.0:
				searched_thoroughly[room] = true
				suspects.erase(room)
				if room == game.exit_room:
					exit_known = room
					note("Found it. A hidden way out in the %s. Nobody leaves." % house.rooms[room].name)
					game.emit("murderer_found_exit", {"room": room})
				else:
					note("Nothing hidden in the %s." % house.rooms[room].name)
				state = S.THINK
				timer = 0.5
		S.GUARD:
			if listening:
				_tick_listen_ears(dt)
				breath_timer -= dt
				if breath_timer <= 0.0:
					breath_timer = randf_range(6.0, 10.0)
					if randf() < 0.4:
						game.on_murderer_breath()
			timer -= dt
			if timer <= 0.0:
				timer = 1.0
				if candidates.size() == 1 and game.time - lead_time < 8.0 and not candidates.has(room):
					note("A fresh lead. I'll leave the exit for a moment.")
					_stop_listening()
					_decide()


func _go(target: String, kind: String) -> void:
	goal = kind
	goal_room = target
	path = house.path(room, target)
	dirty = false
	if path.is_empty():
		_arrive()
		return
	state = S.MOVE
	timer = hunt_time if kind == "hunt" else walk_time


func _nearest(rs: Array) -> String:
	var best := ""
	var bd := 99
	for r in rs:
		var d := house.distance(room, r)
		if d < bd or (d == bd and randf() < 0.5):
			bd = d
			best = r
	return best


func _decide() -> void:
	dirty = false
	if candidates.is_empty():
		_reset_candidates()
	if exit_known != "":
		if candidates.size() == 1 and game.time - lead_time < 8.0 and not candidates.has(room):
			_go(candidates.keys()[0], "hunt")
		elif room != exit_known:
			_go(exit_known, "guard")
		else:
			_arrive_guard()
		return
	if candidates.size() <= hunt_threshold:
		var pool: Array = exact.keys() if not exact.is_empty() else candidates.keys()
		var t := _nearest(pool)
		note("Going for the %s." % house.rooms[t].name)
		_go(t, "hunt")
		return
	if not suspects.is_empty():
		var t := _nearest(suspects.keys())
		note("Let's see what's so special about the %s." % house.rooms[t].name)
		_go(t, "suspect")
		return
	# Go listen at a phone. Prefer one not used recently.
	var phones := []
	for p in house.phone_rooms():
		if game.time - last_listen_at.get(p, -100.0) > 25.0:
			phones.append(p)
	if phones.is_empty():
		phones = house.phone_rooms()
	var t := _nearest(phones)
	_go(t, "phone")


func _enter(r: String) -> void:
	room = r
	game.on_murderer_entered(r)
	if game.over:
		return
	var first := not seen.has(r)
	seen[r] = true
	if candidates.has(r):
		candidates.erase(r)
		exact.erase(r)
		if candidates.is_empty():
			_reset_candidates()
	var snap: Dictionary = game.room_state_snapshot(r)
	var expected: Dictionary = memory.get(r, game.default_room_state(r))
	if snap != expected:
		var what := []
		for k in snap:
			if snap[k] != expected.get(k):
				what.append(k)
		_intersect(house.rooms_within(r, 2), "Someone touched the %s in the %s. They were here" % [", ".join(what), house.rooms[r].name])
	memory[r] = snap
	if first:
		var names := []
		for o in house.rooms[r].objects:
			names.append(o.name)
		note("Searched the %s: %s." % [house.rooms[r].name, ", ".join(names)])


func _arrive() -> void:
	match goal:
		"phone":
			_start_listen()
		"suspect":
			state = S.SEARCH
			timer = 5.0
		"guard":
			_arrive_guard()
		_:
			state = S.THINK
			timer = 0.6


func _arrive_guard() -> void:
	state = S.GUARD
	timer = 1.0
	if house.rooms[room].phone and not listening:
		listening = true
		on_line = true
		listen_overlap = 0.0
		heard_bg = []
		game.on_murderer_pickup()


func _stop_listening() -> void:
	if listening:
		listening = false
		on_line = false
		game.on_murderer_hangup()


# ---------------------------------------------------------------- listening

func _start_listen() -> void:
	state = S.LISTEN
	listening = true
	on_line = true
	listen_overlap = 0.0
	heard_bg = []
	last_phone = room
	last_listen_at[room] = game.time
	timer = randf_range(listen_min, listen_max)
	breath_timer = randf_range(3.0, 7.0)
	game.on_murderer_pickup()


func _tick_listen_ears(dt: float) -> void:
	if game.player_on_line():
		listen_overlap += dt
		if listen_overlap >= identify_time:
			_hear_background()
	else:
		listen_overlap = 0.0


func _tick_listen(dt: float) -> void:
	_tick_listen_ears(dt)
	breath_timer -= dt
	if breath_timer <= 0.0:
		breath_timer = randf_range(5.0, 9.0)
		if randf() < 0.45:
			game.on_murderer_breath()
	timer -= dt
	var leave := timer <= 0.0 or candidates.size() <= hunt_threshold or (dirty and not suspects.is_empty())
	if leave:
		on_line = false
		game.on_murderer_hangup()
		if randf() < fake_hangup_chance and candidates.size() > hunt_threshold:
			state = S.FAKE_HANGUP
			on_line = true  # his room's background is still on the line: the tell
			timer = randf_range(5.0, 8.0)
			note("Pretended to hang up. Still listening.")
			game.on_murderer_fake_hangup()
		else:
			listening = false
			state = S.THINK
			timer = 0.8
