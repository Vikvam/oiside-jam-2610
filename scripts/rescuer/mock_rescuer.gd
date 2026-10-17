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
	if cautious:
		if said_cautious:
			return ""
		said_cautious = true
		return "Shh. Someone else is on the line. Tap twice when they're gone."
	if guess == "":
		if picked_up:
			return "I'm here. Where are you? Don't name the room. Tell me something you can see."
		return "I can't place you. Describe one thing near you. Not the room."
	if guess != game.exit_room:
		var p: Array = h.path(guess, game.exit_room)
		var dir := h.door_to(guess, p[0])
		expect_next = p[0]
		if p.size() == 1:
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
		var exp: Array = game.expected_features(r, {})
		exp.sort()
		if exp == feats:
			out.append(r)
	return out
