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
var imposter := false
var _pending := -1.0
var _reply := ""
var _read := 0            # line_log index already processed
const L := {
	"en": {
		"cautious": ["Shh. Someone else is on the line. Tap twice when they're gone.", "Wait. I heard a click. He's listening. Two taps when it's clear.", "Quiet. We're not alone. Tap twice when he's gone."],
		"ask_feat": ["Listen. Is there a %s in that room, even if it's quiet now? One tap yes, two no.", "I can't tell where you are. Is there a %s near you? Tap once for yes, twice for no."],
		"things": {"clock": "clock", "fan": "fan", "rain": "window", "radiator": "radiator"},
		"pickup": ["I'm here. Where are you? Don't name the room. Tell me something you can see.", "You're back. Tell me something you can see — not the room's name."],
		"unknown": ["I can't place you. Describe one thing near you. Not the room.", "Where are you? Something small. Something only we'd know, if you can."],
		"last_nophone": ["Take the %s door. No phone in there, so listen: it's %s.", "Through the %s door. Then %s. Only that."],
		"last": ["Good. Take the %s door. It's in the next room.", "Almost. The %s door — it's right there."],
		"step": ["Okay. From there, take the %s door. Then call me again.", "The %s door. Go. Call me from the next phone.", "Take the %s door. Quietly."],
		"exit_nick": ["You're there. It's %s. You know what I mean.", "That's the room. %s. Remember?"],
		"exit_obj": ["You're in the right room. Check the %s.", "This is it. The %s. Go."],
		"the": "the ",
		"imposter": ["That wasn't me! Don't go anywhere he tells you.", "That voice — it wasn't me. Stay put."],
	},
	"cs": {
		"cautious": ["Pst. Na lince je ještě někdo. Ťukni dvakrát, až bude pryč.", "Počkej. Slyšela jsem cvaknutí. Poslouchá. Dvě ťuknutí, až bude čisto.", "Ticho. Nejsme sami. Ťukni dvakrát, až odejde."],
		"ask_feat": ["Poslouchej. Je v té místnosti %s, i když je teď potichu? Jedno ťuknutí ano, dvě ne.", "Nevím, kde jsi. Je u tebe %s? Ťukni jednou pro ano, dvakrát pro ne."],
		"things": {"clock": "hodiny", "fan": "větrák", "rain": "okno", "radiator": "radiátor"},
		"pickup": ["Jsem tady. Kde jsi? Neříkej název místnosti. Řekni mi něco, co vidíš.", "Jsi zpátky. Řekni mi, co vidíš — ne název místnosti."],
		"unknown": ["Nevím, kde jsi. Popiš jednu věc u sebe. Ne místnost.", "Kde jsi? Něco malého. Něco, co víme jen my dva, jestli můžeš."],
		"last_nophone": ["Jdi %s dveřmi. Tam není telefon, tak poslouchej: je to %s.", "Projdi %s dveřmi. Pak %s. Jen to."],
		"last": ["Dobře. Jdi %s dveřmi. Je to hned vedle.", "Skoro. %s dveře — je to tam."],
		"step": ["Dobře. Odtud jdi %s dveřmi. Pak mi zase zavolej.", "%s dveře. Jdi. Zavolej mi z dalšího telefonu.", "Jdi %s dveřmi. Potichu."],
		"exit_nick": ["Jsi tam. Je to %s. Víš, co myslím.", "To je ta místnost. %s. Pamatuješ?"],
		"exit_obj": ["Jsi ve správné místnosti. Zkus %s.", "Tady to je. %s. Jdi."],
		"the": "",
		"imposter": ["To jsem nebyla já! Nikam, kam ti řekne, nechoď.", "Ten hlas — to jsem nebyla já. Zůstaň, kde jsi."],
	},
}
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
			elif e.text.contains("imitating you"):
				imposter = true
			elif e.text.contains("an extension hangs up"):
				cautious = false
			elif e.text.begins_with("[background"):
				bg = e.text
			elif e.text.contains("player's extension picks up"):
				picked_up = true
	var low := Loc.fold(player_text)
	var toks := Words.tokens(player_text)
	if cautious and (low.contains("clear") or low.contains("gone") or low.contains("2 taps") or low.contains("hung up") or low.contains("pryc") or low.contains("cisto") or low.contains("zavesil")):
		cautious = false
	# Answer to our tap question?
	if not pending_q.is_empty():
		var yes := low.contains("[1 tap") or "yes" in toks or "ano" in toks or "jo" in toks
		var no := low.contains("[2 taps") or "no" in toks or "ne" in toks or "nope" in toks
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
	var tx: Dictionary = L[Loc.lang]
	if imposter:
		imposter = false
		return _pick(tx.imposter)
	if cautious:
		if said_cautious:
			return ""
		said_cautious = true
		return _pick(tx.cautious)
	if guess == "" and bg_cands.size() > 1:
		# Ask about a sound that splits the candidates.
		for f in House.FEATURES:
			var n := 0
			for r in bg_cands:
				if h.has_feature(r, f):
					n += 1
			if n > 0 and n < bg_cands.size():
				pending_q = {"feature": f, "cands": bg_cands.duplicate()}
				return _pick(tx.ask_feat) % tx.things[f]
	if guess == "":
		return _pick(tx.pickup) if picked_up else _pick(tx.unknown)
	var od := h.object_def(game.exit_obj)
	var what: String = h.obj_nick(game.exit_obj) if od.has("nick") else tx.the + h.obj_name(game.exit_obj)
	var asks_which := low.contains("which") or low.contains("what") or low.contains("where is") or low.contains("?") or "ktery" in toks or "ktera" in toks or "co" in toks or "kde" in toks
	if guess != game.exit_room:
		var p: Array = h.path(guess, game.exit_room)
		var dir := Loc.dir(h.door_to(guess, p[0]))
		expect_next = p[0]
		if p.size() == 1:
			if not h.rooms[game.exit_room].phone or asks_which:
				return _pick(tx.last_nophone) % [dir, what]
			return _cap(_pick(tx.last) % dir)
		return _cap(_pick(tx.step) % dir)
	if od.has("nick"):
		return _pick(tx.exit_nick) % h.obj_nick(game.exit_obj)
	return _cap(_pick(tx.exit_obj) % h.obj_name(game.exit_obj))


func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


func _pick(options: Array) -> String:
	return options[randi() % options.size()]


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
