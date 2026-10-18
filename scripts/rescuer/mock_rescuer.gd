class_name MockRescuer
extends RefCounted
## The scripted rescuer: her brain. She knows the house and the exit, and she
## watches the security monitors (game.cam_log): grainy, so she sees a figure
## move, never who it is. She does NOT know where the player is: she works it
## out from the line (game.line_log) and the monitors, then guides them one
## step at a time around him. In Haiku mode this still decides what she says;
## the LLM only rephrases it.
##
## Directions come in three registers, picked per line:
##   compass  ("the west door")        when the line seems quiet — clear, but he
##                                      can use it if he's listening
##   relative ("the door on your left") when he may be listening — useless to
##                                      him without your heading
##   nickname ("go to Old Gregor")      when she thinks you've seen that room

var game
var guess := ""           # the room she thinks the player is in
var expect_next := ""     # where she just sent them
var p_facing := ""        # the way she thinks they're facing ("" = no idea)
var him := ""             # where she last saw a figure she thinks is him
var him_t := -100.0
var tentative := ""       # a figure she saw while the player was off the line
var known := {}           # rooms she believes the player has been in
var cautious := false     # a pickup click with no hang-up since
var said_cautious := false
var pending_q := {}       # {feature, cands} — asked "tap once if you hear X"
var bg_cands: Array = []
var imposter := false
var played_along := false
var confirm_room := ""    # asked "was that you on the camera?" about this room
var warned := ""          # "him|guess" she last warned about
var last_draft_urgent := false
var _toggles: Array = []  # [[t, on]] the player's pickups / hang-ups
var _pending := -1.0
var _reason := ""
var _read := 0            # line_log index already processed
var _cam_read := 0        # cam_log index already processed
const L := {
	"en": {
		"cautious": ["Shh. Someone else is on the line. I'll whisper.", "A click. He's listening. Carefully now."],
		"wait_quiet": ["Not now. Tap twice when he's gone.", "He's still there. Two taps when it's clear."],
		"ask_feat": ["Listen. Is there a %s in that room, even if it's quiet now? One tap yes, two no.", "I can't tell where you are. Is there a %s near you? Tap once for yes, twice for no."],
		"things": {"clock": "clock", "fan": "fan", "rain": "window", "radiator": "radiator"},
		"lost": ["I can't see you on any camera. Tell me one thing you can see — a nickname, if you can. Not the room.", "Where are you? Something small. Something only we'd know."],
		"step": ["Okay. Take %s. Then call me again.", "%s. Go. Call me from the next phone.", "Take %s. Quietly."],
		"step2": ["Take %s, then %s. No phone in between, so remember it.", "%s — then %s. Don't stop in between."],
		"nick_go": ["Go to %s. Call me from there.", "Make for %s. Quietly."],
		"exit_nick": ["That's the room. Search %s. You know what I mean.", "You're there. It's %s. Go."],
		"exit_obj": ["You're in the right room. Search the %s.", "This is it. The %s. Go."],
		"then_search": ["In there, search %s.", "In that room it's %s."],
		"exit_wait": ["You're in the right room. I'll tell you what to search when he's off the line. Tap twice when it's quiet.", "Right room. Not a word now. Two taps when he's gone."],
		"warn": ["He's right behind %s. Go another way — or hide.", "Stop. He's just past %s. Don't go that way."],
		"warn_here": ["Don't move. Don't make a sound.", "He's close. Hide. Now."],
		"blocked": ["Wait. He's between you and the way out. Hide and wait for me.", "Not yet. He's in the way. Stay hidden."],
		"imposter": ["That wasn't me! Don't go anywhere he tells you.", "That voice — it wasn't me. Stay put."],
		"play_along": ["Okay. Stay %s. Don't move, I'm thinking.", "Right, %s. Hide there. Don't make a sound."],
		"confirm": ["Someone just moved on a camera. Was that you? One tap yes, two no.", "Did you just come through a door? One tap yes, two no."],
		"seen_you": ["I see you. ", "There you are. "],
		"compass": "the %s door",
		"rel": {"straight": "the door straight ahead", "left": "the door on your left", "right": "the door on your right", "back": "the door you came in by"},
	},
	"cs": {
		"cautious": ["Pst. Na lince je ještě někdo. Budu šeptat.", "Cvaklo to. Poslouchá. Teď opatrně."],
		"wait_quiet": ["Teď ne. Ťukni dvakrát, až bude pryč.", "Pořád tam je. Dvě ťuknutí, až bude čisto."],
		"ask_feat": ["Poslouchej. Je v té místnosti %s, i když je teď potichu? Jedno ťuknutí ano, dvě ne.", "Nevím, kde jsi. Je u tebe %s? Ťukni jednou pro ano, dvakrát pro ne."],
		"things": {"clock": "hodiny", "fan": "větrák", "rain": "okno", "radiator": "radiátor"},
		"lost": ["Na žádné kameře tě nevidím. Řekni mi jednu věc, kterou vidíš — přezdívku, jestli můžeš. Ne místnost.", "Kde jsi? Něco malého. Něco, co víme jen my dva."],
		"step": ["Dobře. Jdi %s. Pak mi zase zavolej.", "Jdi %s. Zavolej mi z dalšího telefonu.", "Jdi %s. Potichu."],
		"step2": ["Jdi %s a pak %s. Mezi tím není telefon, tak si to pamatuj.", "Jdi %s — a pak %s. Nezastavuj se."],
		"nick_go": ["Jdi tam, kde je %s. Zavolej mi odtamtud.", "Zamiř tam, kde je %s. Potichu."],
		"exit_nick": ["To je ta místnost. Prohledej: %s. Víš, co myslím.", "Jsi tam. Je to %s. Jdi."],
		"exit_obj": ["Jsi ve správné místnosti. Prohledej: %s.", "Tady to je. %s. Jdi."],
		"then_search": ["Tam prohledej: %s.", "V té místnosti je to %s."],
		"exit_wait": ["Jsi ve správné místnosti. Co prohledat, ti řeknu, až zavěsí. Ťukni dvakrát, až bude ticho.", "Správná místnost. Teď ani slovo. Dvě ťuknutí, až odejde."],
		"warn": ["Je hned za %s. Jdi jinudy — nebo se schovej.", "Stůj. Je hned za %s. Tudy ne."],
		"warn_here": ["Nehýbej se. Ani hlásku.", "Je blízko. Schovej se. Hned."],
		"blocked": ["Počkej. Je mezi tebou a cestou ven. Schovej se a čekej na mě.", "Ještě ne. Je v cestě. Zůstaň schovaný."],
		"imposter": ["To jsem nebyla já! Nikam, kam ti řekne, nechoď.", "Ten hlas — to jsem nebyla já. Zůstaň, kde jsi."],
		"play_along": ["Dobře. Zůstaň %s. Nehýbej se, přemýšlím.", "Jasně, %s. Schovej se tam. Ani muk."],
		"confirm": ["Na kameře se teď někdo pohnul. Byl jsi to ty? Jedno ťuknutí ano, dvě ne.", "Prošel jsi teď dveřmi? Jedno ťuknutí ano, dvě ne."],
		"seen_you": ["Vidím tě. ", "Tady jsi. "],
		"compass": "%s dveřmi",
		"rel": {"straight": "dveřmi rovně před sebou", "left": "dveřmi po levé ruce", "right": "dveřmi po pravé ruce", "back": "dveřmi, kterými jsi přišel"},
	},
}
var min_delay := 1.2
var max_delay := 2.8


func _init(g) -> void:
	game = g
	p_facing = g.facing  # everyone starts facing the phone wall


func request(ctx: Dictionary) -> void:
	_reason = ctx.get("reason", "")
	# After a pickup, wait until the line's background has been heard.
	_pending = randf_range(2.3, 3.0) if _reason == "pickup" else randf_range(min_delay, max_delay)
	if _reason == "camera":
		_pending = 0.4  # she's watching: warnings come fast


func tick(dt: float) -> void:
	if _pending >= 0.0:
		_pending -= dt
		if _pending < 0.0:
			game.rescuer_says(decide(), guess)


## What she says now. Also used as the draft in Haiku mode.
func decide() -> String:
	return _compose()


func _tx() -> Dictionary:
	return L[Loc.lang]


func _was_on_line(t: float) -> bool:
	var on := true
	for tg in _toggles:
		if tg[0] <= t:
			on = tg[1]
	return on


func _set_guess(r: String, facing := "") -> void:
	guess = r
	known[r] = true
	if facing != "":
		p_facing = facing
	expect_next = ""
	tentative = ""


## Read the monitors. A figure that moves while the player's receiver is up
## must be him: you can't walk with the phone at your ear.
func _read_cams() -> bool:
	var h: House = game.house
	var saw_you := false
	for e in game.cam_log.slice(_cam_read):
		var dest: String = e.room if e.kind == "in" else h.step(e.room, e.dir)
		if _was_on_line(e.t):
			him = dest
			him_t = e.t
			continue
		if e.kind == "out" and guess != "" and e.room == guess:
			tentative = dest  # probably you, leaving
			p_facing = e.dir
		elif e.kind == "in" and e.room != guess and (e.room == tentative or e.room == expect_next or (guess != "" and h.step(e.room, e.dir) == guess)):
			_set_guess(e.room, House.opposite(e.dir))
			saw_you = true
		elif guess == "" and tentative == "":
			tentative = dest  # someone moved; could be either of you
		else:
			him = dest
			him_t = e.t
	_cam_read = game.cam_log.size()
	return saw_you


func _compose() -> String:
	var h: House = game.house
	var new_lines: Array = game.line_log.slice(_read)
	_read = game.line_log.size()
	var player_text := ""
	var bg := ""
	var picked_up := false
	for e in new_lines:
		if e.who == "player":
			player_text += " " + e.text
		elif e.who == "line":
			if e.text.contains("another extension picks up"):
				cautious = true
				said_cautious = false
				played_along = false
			elif e.text.contains("imitating you"):
				imposter = true
			elif e.text.contains("an extension hangs up"):
				cautious = false
			elif e.text.begins_with("[background"):
				bg = e.text
			elif e.text.contains("player's extension picks up"):
				picked_up = true
				_toggles.append([e.get("t", game.time), true])
			elif e.text.contains("the caller hangs up"):
				_toggles.append([e.get("t", game.time), false])
	var saw_you := _read_cams()
	var low := Loc.fold(player_text)
	var toks := Words.tokens(player_text)
	var yes := low.contains("[1 tap") or "yes" in toks or "ano" in toks or "jo" in toks
	var no := low.contains("[2 taps") or "no" in toks or "ne" in toks or "nope" in toks
	if cautious and (low.contains("clear") or low.contains("gone") or low.contains("2 taps") or low.contains("hung up") or low.contains("pryc") or low.contains("cisto") or low.contains("zavesil")):
		cautious = false
	# Answer to "was that you on the camera?"
	if confirm_room != "" and not picked_up and (yes or no):
		if yes:
			_set_guess(confirm_room)
		else:
			him = confirm_room
			him_t = game.time
		confirm_room = ""
	# Answer to a sound question?
	if not pending_q.is_empty() and (yes or no):
		var keep := []
		for r in pending_q.cands:
			if h.has_feature(r, pending_q.feature) == yes:
				keep.append(r)
		pending_q = {}
		if keep.size() == 1:
			_set_guess(keep[0])
		else:
			bg_cands = keep
	if picked_up and not saw_you:
		# Did they get where she sent them? Trust it only if the sounds agree.
		var cand := expect_next if expect_next != "" else tentative
		if cand != "":
			guess = ""
			if _plausible(cand, bg):
				if bg != "" and _from_background(bg) == [cand]:
					_set_guess(cand)
				else:
					confirm_room = cand
			expect_next = ""
			tentative = ""
	# What they said: nicknames first (safe), then objects, then rooms.
	var hits: Array = Words.nicknames_named(player_text, h)
	if hits.is_empty():
		hits = Words.objects_named(player_text, h)
	if not hits.is_empty():
		_set_guess(hits[0].room)
		confirm_room = ""
	else:
		var rooms := Words.rooms_named(player_text, h)
		if not rooms.is_empty() and not cautious:
			_set_guess(rooms[0])
			confirm_room = ""
		elif bg != "" and guess == "" and confirm_room == "":
			var cands := _from_background(bg)
			if cands.size() == 1:
				_set_guess(cands[0])
			elif cands.size() > 1:
				bg_cands = cands
	var tx := _tx()
	last_draft_urgent = false
	if imposter:
		imposter = false
		return _pick(tx.imposter)
	var pre := ""
	if cautious:
		# A room named while he's listening is probably a lure: play along.
		var lure := Words.rooms_named(player_text, h)
		if not lure.is_empty() and not played_along:
			played_along = true
			return _pick(tx.play_along) % h.room_in(lure[0])
		if not said_cautious:
			said_cautious = true
			pre = _pick(tx.cautious) + " "
	# 1. Danger first: she can see him coming.
	var warn := _warning()
	if warn != "":
		last_draft_urgent = true
		return pre + warn
	if _reason == "camera" and not saw_you:
		return pre.strip_edges()  # nothing new worth the risk of talking
	if saw_you and pre == "":
		pre = _pick(tx.seen_you)
	# 2. Was that you?
	if confirm_room != "" and guess == "":
		return pre + _pick(tx.confirm)
	if guess == "" and bg_cands.size() > 1:
		for f in House.FEATURES:
			var n := 0
			for r in bg_cands:
				if h.has_feature(r, f):
					n += 1
			if n > 0 and n < bg_cands.size():
				pending_q = {"feature": f, "cands": bg_cands.duplicate()}
				return pre + _pick(tx.ask_feat) % tx.things[f]
	if guess == "":
		return pre + _pick(tx.lost)
	# 3. Guide, one step at a time, around him.
	return pre + _guide()


func _him_fresh() -> bool:
	return him != "" and game.time - him_t < 25.0


func _warning() -> String:
	if guess == "" or not _him_fresh():
		return ""
	var key: String = him + "|" + guess
	if key == warned:
		return ""
	var h: House = game.house
	var d := h.distance(guess, him)
	if d == 0:
		warned = key
		return _pick(_tx().warn_here)
	if d == 1:
		warned = key
		return _cap(_pick(_tx().warn) % _door_phrase(guess, h.door_to(guess, him)))
	return ""


func _guide() -> String:
	var h: House = game.house
	var tx := _tx()
	if guess == game.exit_room:
		var od := h.object_def(game.exit_obj)
		if od.has("nick"):
			return _cap(_pick(tx.exit_nick) % h.obj_nick(game.exit_obj))
		if cautious:
			return _pick(tx.exit_wait)
		return _cap(_pick(tx.exit_obj) % h.obj_name(game.exit_obj))
	var p := _route(guess, game.exit_room)
	if p.is_empty():
		return _pick(tx.blocked)
	var dir := h.door_to(guess, p[0])
	# A room she believes they know by its nickname: the safest way to say it.
	var nick_obj := h.nick_obj(p[0])
	if cautious and known.has(p[0]) and nick_obj != "" and h.object_room.get(nick_obj, "") == p[0]:
		expect_next = p[0]
		return _cap(_pick(tx.nick_go) % h.obj_nick(nick_obj))
	if cautious and p_facing == "":
		return _pick(tx.wait_quiet)  # no safe way to say it yet
	var first := _door_phrase(guess, dir)
	if p.size() >= 2 and not h.rooms[p[0]].phone and p[0] != game.exit_room:
		# No phone in the next room: give two steps.
		var second := _door_phrase(p[0], h.door_to(p[0], p[1]), dir)
		expect_next = p[1]
		p_facing = h.door_to(p[0], p[1])
		return _cap(_pick(tx.step2) % [first, second])
	expect_next = p[0]
	p_facing = dir
	if p.size() == 1 and not h.rooms[p[0]].phone:
		# The exit room has no phone: tell them what to search before they go.
		var od := h.object_def(game.exit_obj)
		var what: String = h.obj_nick(game.exit_obj) if od.has("nick") else ("" if cautious else ("the " if Loc.lang == "en" else "") + h.obj_name(game.exit_obj))
		if what != "":
			return _cap(_pick(tx.step) % first) + " " + _cap(_pick(tx.then_search) % what)
	return _cap(_pick(tx.step) % first)


## "the west door" / "the door on your left", depending on who might hear.
func _door_phrase(from_room: String, dir: String, facing := "") -> String:
	var tx := _tx()
	var f := facing if facing != "" else p_facing
	if cautious and f != "":
		return tx.rel[House.relative(f, dir)]
	return tx.compass % Loc.dir(dir)


## Shortest way to the exit that keeps out of his room and, if possible, away
## from the rooms next to it.
func _route(from_room: String, to_room: String) -> Array:
	var h: House = game.house
	if not _him_fresh():
		return h.path(from_room, to_room)
	var hard := {him: true}
	var soft := hard.duplicate()
	for n in h.neighbors(him):
		soft[n] = true
	for blocked in [soft, hard]:
		var p := _bfs(from_room, to_room, blocked)
		if not p.is_empty():
			return p
	return []


func _bfs(a: String, b: String, blocked: Dictionary) -> Array:
	var h: House = game.house
	var prev := {a: ""}
	var q := [a]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == b:
			break
		for n in h.neighbors(cur):
			if not prev.has(n) and (not blocked.has(n) or n == b):
				prev[n] = cur
				q.append(n)
	if not prev.has(b):
		return []
	var out := []
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	return out


func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


func _pick(options: Array) -> String:
	return options[randi() % options.size()]


func _plausible(r: String, bg: String) -> bool:
	if not game.house.rooms[r].phone:
		return false
	for f in House.FEATURE_LABEL:
		if bg.contains(House.FEATURE_LABEL[f]) and not game.house.has_feature(r, f):
			return false
	return true


func _from_background(bg: String) -> Array:
	var feats := []
	for f in House.FEATURE_LABEL:
		if bg.contains(House.FEATURE_LABEL[f]):
			feats.append(f)
	feats.sort()
	var out := []
	for r in game.house.phone_rooms():
		var ok := true
		for f in feats:
			if not game.house.has_feature(r, f):
				ok = false
		if ok:
			out.append(r)
	return out
