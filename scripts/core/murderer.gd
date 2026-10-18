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
var prev_room := ""       # where he came in from (that door is blocked)
var state := S.THINK
var timer := 4.0
var path: Array = []
var trail: Array = []     # rooms visited, in order (for the post-game reveal)
var goal := ""            # phone / hunt / suspect / guard
var goal_room := ""

var candidates := {}      # room id -> true
var exact := {}           # rooms that matched the heard background exactly
var seen := {}            # rooms whose objects it knows
var memory := {}          # room id -> feature state when last seen
var suspects := {}        # rooms the rescuer pointed at -> true
var searched_thoroughly := {}
var exit_known := ""
var guard_since := 0.0
var guard_break_until := -1.0  # he got bored of guarding: hunting until then
var guard_patience := 40.0
var lead_time := -100.0
var dirty := false        # new evidence since the current plan

var listening := false    # hears the line
var on_line := false      # the player can hear its breathing/background
var listen_overlap := 0.0
var heard_bg = null       # last background it identified (null = nothing yet)
var last_phone := ""
var last_listen_at := {}  # room -> time
var breath_timer := 5.0

var log: Array = []       # [{t, text}]
var last_evidence := ""   # what most recently narrowed things down
var taunt_chance := 0.5
var imitate_chance := 0.0   # hard mode: he whispers in HER voice
var _last_imitate := -100.0

# Tunables (exposed so A/B settings can poke them)
var walk_time := 4.0
var hunt_time := 2.6
var listen_min := 12.0
var listen_max := 20.0
var just_listened := false
var gained := false        # new evidence during the current listen
var empty_listens := 0     # listens in a row that taught him nothing
var sweep_after := 2       # ...before he gives up on the phones and looks around
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
	trail.append(room)
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


func _set_candidates(rs: Array, why: String, strong := true, kind := "") -> void:
	var before := candidates.size()
	if kind != "":
		last_evidence = kind
	candidates.clear()
	for r in rs:
		if r != room:  # he can see his own room is empty
			candidates[r] = true
	if candidates.is_empty():
		_reset_candidates()
	exact.clear()
	if strong:
		lead_time = game.time
		gained = true
	dirty = true
	if why != "":
		note("%s → %s" % [why, _cand_str()])


func _intersect(rs: Array, why: String, strong := true, kind := "") -> void:
	var out := []
	for r in rs:
		if candidates.has(r):
			out.append(r)
	if out.is_empty():
		out = rs  # contradiction: trust the newest evidence
	_set_candidates(out, why, strong, kind)


func _cand_str() -> String:
	var names := []
	for r in candidates:
		names.append(house.room_name(r))
	if names.size() >= house.room_ids.size() - 1:
		return Loc.t("m_anywhere")
	return Loc.t("m_maybe", [", ".join(names)])


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
		_set_candidates(out, Loc.t("m_steps1") if d <= 1 else Loc.t("m_steps2"), true, "steps")
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
	_set_candidates([src], Loc.t("m_crash", [house.room_name(src)]), true, "crash")


func on_small_noise(src: String, what: String) -> void:
	var d := house.distance(room, src)
	if d <= 1 and not listening and state != S.MOVE:
		_intersect(house.rooms_at(room, d), Loc.t("m_click_near"), true, "steps")


func on_shout(src: String) -> void:
	var d := house.distance(room, src)
	if d <= 2 and state != S.MOVE:
		_intersect(house.rooms_at(room, d), Loc.t("m_shout"), true, "prey")


func on_line_noise(what: String) -> void:
	if listening:
		_intersect(house.phone_rooms(), Loc.t("m_on_line", [Loc.t(what)]), false)


func on_words(speaker: String, text: String) -> void:
	if not listening:
		return
	var rooms := Words.rooms_named(text, house)
	for o in Words.objects_named(text, house, seen):
		if o.room not in rooms:
			rooms.append(o.room)
		note(Loc.t("m_known_obj", [house.obj_name(o.obj), house.room_name(o.room)]))
	var dirs := Words.directions(text)
	if speaker == "player":
		if not rooms.is_empty():
			_intersect(rooms, Loc.t("m_prey_said"), true, "prey")
		if not dirs.is_empty():
			_shift(dirs, Loc.t("m_prey_dir", [", ".join(dirs.map(func(x): return Loc.t(x)))]), "prey")
	else:
		for r in rooms:
			if r != room and not suspects.has(r) and not searched_thoroughly.has(r):
				suspects[r] = true
				dirty = true
				note(Loc.t("m_pointed", [house.room_name(r)]))
		if not dirs.is_empty():
			_shift(dirs, Loc.t("m_voice_dir", [", ".join(dirs.map(func(x): return Loc.t(x)))]), "voice")
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
				_set_candidates(out, Loc.t("m_talked_feat", [", ".join(feats.map(func(f): return Loc.feature(f)))]), true, "prey")


func _shift(dirs: Array, why: String, kind := "") -> void:
	if candidates.size() > 4:
		note(Loc.t("m_useless", [why]))
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
	_set_candidates(cur, why, true, kind)


func _hear_background() -> void:
	var bg: Array = game.player_active_features()
	bg.sort()
	if heard_bg != null and bg == heard_bg:
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
	var label := Loc.t("m_silence") if bg.is_empty() else ", ".join(bg.map(func(f): return Loc.feature(f)))
	if out.is_empty():
		_intersect(house.phone_rooms(), Loc.t("m_bg_weird", [label]))
		return
	var narrowed := 0
	for r in out:
		if candidates.has(r):
			narrowed += 1
	_intersect(out, Loc.t("m_heard_bg", [label]), narrowed <= 3, bg[0] if bg.size() > 0 else "")
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
					game.on_murderer_leaves(room, path[0])
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
					note(Loc.t("m_found_exit", [house.room_in(room)]))
					game.emit("murderer_found_exit", {"room": room})
				else:
					note(Loc.t("m_no_exit", [house.room_in(room)]))
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
					note(Loc.t("m_fresh"))
					_stop_listening()
					_decide()
				elif game.time - guard_since > guard_patience:
					# Nobody comes. Go and flush them out, then come back.
					note(Loc.t("m_bored"))
					guard_break_until = game.time + 45.0
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
	game.on_murderer_sets_off(room)


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
	if exit_known != "" and game.time >= guard_break_until:
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
		note(Loc.t("m_going", [house.room_to(t)]))
		_go(t, "hunt")
		return
	if not suspects.is_empty():
		var t := _nearest(suspects.keys())
		note(Loc.t("m_special", [house.room_name(t)]))
		_go(t, "suspect")
		return
	# He is a listener: an empty listen sends him to another phone. Only
	# after several empty ones in a row does he go and look around.
	if just_listened:
		empty_listens = 0 if gained else empty_listens + 1
	if just_listened and empty_listens >= sweep_after:
		just_listened = false
		empty_listens = 0
		var pool := []
		for r in candidates:
			if house.distance(room, r) <= 2 and r != room:
				pool.append(r)
		if not pool.is_empty():
			var unseen := pool.filter(func(r): return not seen.has(r))
			var t: String = (unseen if not unseen.is_empty() else pool).pick_random()
			note(Loc.t("m_sweep", [house.room_in(t)]))
			_go(t, "sweep")
			return
	var moved_on := just_listened and not gained
	just_listened = false
	# Go listen at a phone: not the one he just used, preferably not one
	# used recently, and preferably not right next door to it.
	var phones := []
	for p in house.phone_rooms():
		if p != room and game.time - last_listen_at.get(p, -100.0) > 25.0:
			phones.append(p)
	if phones.is_empty():
		phones = house.phone_rooms().filter(func(p): return p != room)
	if phones.is_empty():
		phones = house.phone_rooms()
	var far := phones.filter(func(p): return house.distance(room, p) >= 2)
	if moved_on and not far.is_empty():
		phones = far
	var t := _nearest(phones)
	if moved_on:
		note(Loc.t("m_other_phone", [house.room_to(t)]))
	_go(t, "phone")


## He saw the player in a doorway: no doubt where they went.
func saw_player(r: String) -> void:
	_set_candidates([r], Loc.t("m_saw"), true, "seen")
	_stop_listening()
	_go(r, "hunt")


## Stand still for at least `t` seconds (searching the room the player is in).
func hold(t: float) -> void:
	state = S.THINK
	timer = maxf(timer, t)


func _enter(r: String) -> void:
	prev_room = room
	room = r
	trail.append(r)
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
		_intersect(house.rooms_within(r, 2), Loc.t("m_touched", [", ".join(what.map(func(k): return Loc.t("k_" + k))), house.room_in(r)]), true, "touched")
	memory[r] = snap
	if first:
		var names := []
		for o in house.rooms[r].objects:
			names.append(house.obj_name(o.id))
		note(Loc.t("m_searched", [house.room_name(r), ", ".join(names)]))


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
	guard_since = game.time
	if house.rooms[room].phone and not listening:
		listening = true
		on_line = true
		listen_overlap = 0.0
		heard_bg = null
		game.on_murderer_pickup()


func _stop_listening() -> void:
	if listening:
		listening = false
		on_line = false
		game.on_murderer_hangup()


# ---------------------------------------------------------------- listening

func _start_listen() -> void:
	state = S.LISTEN
	gained = false
	listening = true
	on_line = true
	listen_overlap = 0.0
	heard_bg = null
	last_phone = room
	last_listen_at[room] = game.time
	timer = randf_range(listen_min, listen_max)
	breath_timer = randf_range(3.0, 7.0)
	game.on_murderer_pickup()


func _maybe_imitate() -> void:
	## Pretend to be her and send the prey toward me.
	if imitate_chance <= 0.0 or not game.player_on_line() or game.time - _last_imitate < 60.0:
		return
	if candidates.size() > 3 or candidates.has(room):
		return
	_last_imitate = game.time
	if randf() > imitate_chance:
		return
	var c: String = candidates.keys().pick_random()
	var p := house.path(c, room)
	if p.is_empty():
		return
	var dir := house.door_to(c, p[0])
	note(Loc.t("m_imitate", [house.room_name(c)]))
	game.on_murderer_imitate(Loc.t("imitate_say", [Loc.dir(dir)]))


func _taunt() -> String:
	match last_evidence:
		"clock", "fan", "rain", "radiator":
			return Loc.t("m_t_" + last_evidence)
		"voice":
			return Loc.t("m_t_voice")
		"prey":
			return Loc.t("m_t_prey")
		"steps":
			return Loc.t("m_t_steps")
		"touched":
			return Loc.t("m_t_touched")
	return Loc.t("m_t_any")


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
	_maybe_imitate()
	timer -= dt
	var leave := timer <= 0.0 or candidates.size() <= hunt_threshold or (dirty and not suspects.is_empty())
	if leave:
		just_listened = true
		if candidates.size() <= hunt_threshold and randf() < taunt_chance:
			game.on_murderer_taunt(_taunt())
		on_line = false
		game.on_murderer_hangup()
		if randf() < fake_hangup_chance and candidates.size() > hunt_threshold:
			state = S.FAKE_HANGUP
			on_line = true  # his room's background is still on the line: the tell
			timer = randf_range(5.0, 8.0)
			note(Loc.t("m_fake"))
			game.on_murderer_fake_hangup()
		else:
			listening = false
			state = S.THINK
			timer = 0.8
