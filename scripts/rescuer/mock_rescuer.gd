class_name MockRescuer
extends RefCounted
## Scripted rescuer. Knows the house and the exit, but NOT where the player
## is — it only uses what came over the line (game.line_log). Talks a bit
## too freely on purpose, which makes it a good sparring partner for the
## murderer in simulations.

var game
var guess := ""
var expect_next := ""     # room the player should be in after following us
var cautious := false
var said_cautious := false
var pending_q := {}       # {feature, cands} — asked "tap once if you hear X"
var bg_cands: Array = []
var _pending := -1.0
var _reply := ""
var _read := 0            # line_log index already processed
var min_delay := 1.2
var max_delay := 2.8


func _init(g) -> void:
	game = g


func request(_ctx: Dictionary) -> void:
	_reply = _compose()
	_pending = randf_range(min_delay, max_delay)


func tick(dt: float) -> void:
	if _pending >= 0.0:
		_pending -= dt
		if _pending < 0.0:
			game.rescuer_says(_reply, guess)


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
			elif e.text.contains("an extension hangs up"):
				cautious = false
			elif e.text.begins_with("[background"):
				bg = e.text
			elif e.text.contains("player's extension picks up"):
				picked_up = true
	var low := player_text.to_lower()
	if cautious and (low.contains("clear") or low.contains("gone") or low.contains("2 taps") or low.contains("hung up")):
		cautious = false
	# Answer to our tap question?
	if not pending_q.is_empty():
		var yes := low.contains("[1 tap") or low.contains("yes")
		var no := low.contains("[2 taps") or low.contains("no")
		if yes or no:
			var keep := []
			for r in pending_q.cands:
				if h.has_feature(r, pending_q.feature) == yes:
					keep.append(r)
			pending_q = {}
			if keep.size() == 1:
				guess = keep[0]
			else:
				bg_cands = keep
	if picked_up and expect_next != "":
		guess = expect_next
		expect_next = ""
	# Update the guess from words, strongest first.
	var hits: Array = Words.nicknames_named(player_text, h)
	if hits.is_empty():
		hits = Words.objects_named(player_text, h)
	if not hits.is_empty():
		guess = hits[0].room
		expect_next = ""
	else:
		var rooms := Words.rooms_named(player_text)
		if not rooms.is_empty():
			guess = rooms[0]
			expect_next = ""
		elif bg != "" and guess == "":
			var cands := _from_background(bg)
			if cands.size() == 1:
				guess = cands[0]
			elif cands.size() > 1:
				bg_cands = cands
	if cautious:
		if said_cautious:
			return ""
		said_cautious = true
		return "Shh. Someone else is on the line. Tap twice when they're gone."
	if guess == "" and bg_cands.size() > 1:
		# Ask about a sound that splits the candidates.
		for f in House.FEATURES:
			var n := 0
			for r in bg_cands:
				if h.has_feature(r, f):
					n += 1
			if n > 0 and n < bg_cands.size():
				pending_q = {"feature": f, "cands": bg_cands.duplicate()}
				return "Listen. Is there a %s somewhere in that room, even if it's quiet now? One tap yes, two no." % {"clock": "clock", "fan": "fan", "rain": "window", "radiator": "radiator"}[f]
	if guess == "":
		if picked_up:
			return "I'm here. Where are you? Don't name the room. Tell me something you can see."
		return "I can't place you. Describe one thing near you. Not the room."
	if guess != game.exit_room:
		var p: Array = h.path(guess, game.exit_room)
		var dir := h.door_to(guess, p[0])
		expect_next = p[0]
		if p.size() == 1:
			var od0 := h.object_def(game.exit_obj)
			var what: String = od0.nick if od0.has("nick") else "the " + od0.name
			if not h.rooms[game.exit_room].phone:
				return "Take the %s door. No phone in there, so listen: it's %s." % [dir, what]
			return "Good. Take the %s door. It's in the next room." % dir
		return "Okay. From there, take the %s door. Then call me again." % dir
	var od := h.object_def(game.exit_obj)
	if od.has("nick"):
		return "You're there. It's %s. You know what I mean." % od.nick
	return "You're in the right room. Check the %s." % od.name


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
