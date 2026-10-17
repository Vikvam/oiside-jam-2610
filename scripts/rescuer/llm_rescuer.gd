class_name LlmRescuer
extends Node
## The slow loop: the rescuer as an LLM. It gets only what came over the
## line (game.line_log) plus her knowledge of the house, and must answer with
## JSON {thinking, say, guess_room}. Code validates everything.
## mode "proxy": local proxy (proxy/rescuer_proxy.py) -> `claude -p --model haiku`
## mode "api":   an HTTP endpoint from rescuer_config.cfg (Anthropic Messages
##               format, or the same simple format as the proxy).
## On any failure it falls back to the scripted MockRescuer for that turn.

var game
var mode := "proxy"
var cfg := {}
var fallback               # MockRescuer
var http: HTTPRequest
var busy := false
var timeout_s := 40.0
var last_error := ""


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	http.request_completed.connect(_on_done)


func tick(dt: float) -> void:
	if fallback:
		fallback.tick(dt)


func request(ctx: Dictionary) -> void:
	var system := build_system(game)
	var prompt := build_prompt(game, ctx.get("reason", ""))
	var url := ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := {}
	if mode == "api" and cfg.get("format", "anthropic") == "anthropic":
		url = cfg.get("url", "https://api.anthropic.com/v1/messages")
		headers.append("x-api-key: %s" % cfg.get("key", ""))
		headers.append("anthropic-version: 2023-06-01")
		body = {
			"model": cfg.get("model", "claude-haiku-5-5"),
			"max_tokens": 400,
			"system": system,
			"messages": [{"role": "user", "content": prompt}],
		}
	else:
		url = cfg.get("proxy_url", "http://127.0.0.1:8765/rescuer") if mode == "proxy" else cfg.get("url", "")
		if mode == "api" and cfg.has("key"):
			headers.append("Authorization: Bearer %s" % cfg.key)
		body = {"system": system, "prompt": prompt}
	busy = true
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_fail("request error %d" % err, ctx)


func _on_done(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("http result %d code %d %s" % [result, code, raw.get_string_from_utf8().left(200)], {})
		return
	var data = JSON.parse_string(raw.get_string_from_utf8())
	var text := ""
	if data is Dictionary:
		if data.has("content"):
			for part in data.content:
				if part.get("type", "") == "text":
					text += part.text
		else:
			text = str(data.get("text", ""))
	var reply := parse_reply(text, game.house)
	if reply.is_empty():
		_fail("unparseable: " + text.left(200), {})
		return
	game.rescuer_says(reply.say, reply.guess)


func _fail(why: String, ctx: Dictionary) -> void:
	busy = false
	last_error = why
	push_warning("Rescuer LLM failed: " + why)
	game.emit("rescuer_error", {"why": why})
	if fallback:
		fallback.request(ctx)
	else:
		game.rescuer_says("", "")


## Extract {say, guess} from the model output; tolerant of code fences.
static func parse_reply(text: String, house: House) -> Dictionary:
	var a := text.find("{")
	var b := text.rfind("}")
	if a == -1 or b <= a:
		return {}
	var d = JSON.parse_string(text.substr(a, b - a + 1))
	if not (d is Dictionary):
		return {}
	var say := str(d.get("say", "")).strip_edges()
	# Keep her terse even if the model rambles; strip stage directions.
	var rx := RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)")
	say = rx.sub(say, "", true).strip_edges()
	if say.length() > 240:
		say = say.left(240).rsplit(" ", true, 1)[0] + "…"
	var guess := str(d.get("guess_room", "")).to_lower().strip_edges()
	if guess not in house.rooms:
		guess = ""
	return {"say": say, "guess": guess}


static func build_system(g) -> String:
	var h: House = g.house
	var s := ""
	s += "You are voicing Mara in a tense horror game. Stay in character. Output ONLY a JSON object.\n\n"
	s += "SITUATION: Your younger sibling (the player) is trapped in the old family house with a murderer. "
	s += "They found a wired phone and called you. You grew up in that house and know a hidden way out that the murderer does not know. "
	s += "Guide them to it.\n\n"
	s += "THE DANGER: every room's phone is on ONE party line. The murderer can pick up any extension and silently listen. "
	s += "He knows the floor plan, the room names and which rooms have which sounds (clock, fan, rain window, radiator). "
	s += "He knows the objects inside a room ONLY if he has already searched it (you don't know which ones he has). "
	s += "He NEVER knows the childhood nicknames below — those are safe, but the player only knows a nickname after seeing that object. "
	s += "If he hears a room name or an object he knows, he will go there. Compass directions ('take the east door') "
	s += "only help him if he already knows where the player is. He also hears the background sounds behind the player's voice.\n\n"
	s += "THE HOUSE (single floor; doors listed by compass direction):\n"
	for rid in h.room_ids:
		var r: Dictionary = h.rooms[rid]
		var doors := []
		for d in House.DIRS:
			var to := h.step(rid, d)
			if to != "":
				doors.append("%s door → %s" % [d, h.rooms[to].name])
		var feats: Array = r.features.map(func(f): return House.FEATURE_LABEL[f])
		var cs_name := " / Czech: %s" % House.CS_ROOMS[rid][0] if Loc.lang == "cs" else ""
		s += "- %s%s (id: %s). %s. Sounds: %s. Doors: %s.\n" % [r.name, cs_name, rid, "Has a phone" if r.phone else "NO phone", ", ".join(feats) if not feats.is_empty() else "none", "; ".join(doors)]
		for o in r.objects:
			var line := "    · %s" % o.name
			if Loc.lang == "cs":
				line += " (Czech: %s)" % House.CS_OBJECTS[o.id][0]
			if o.has("nick"):
				if Loc.lang == "cs":
					line += " — childhood nickname \"%s\" (%s)" % [House.CS_OBJECTS[o.id][3], House.CS_OBJECTS[o.id][4]]
				else:
					line += " — childhood nickname \"%s\" (%s)" % [o.nick, o.memory]
			s += line + "\n"
	var od := h.object_def(g.exit_obj)
	s += "\nTHE WAY OUT: the %s in the %s — %s. The player must stand in that room and search that exact object. " % [od.name, h.rooms[g.exit_room].name, House.EXIT_FLAVOR.get(g.exit_obj, "")]
	s += "They get only 3 tries in total and a wrong try makes a loud crash that gives away their room.\n\n"
	s += "WHAT YOU HEAR: only the line. You do NOT know where the player is — work it out from what they say and from the background sounds. "
	s += "Background sounds on the line are mixed from every open extension. '[click: another extension picks up]' means someone, probably him, is now listening. "
	s += "Hang-up clicks can be faked. Taps: one tap = yes, two taps = no. The player may lie on purpose to lure him away — if it sounds like a lie, play along.\n"
	s += "Rooms without a phone: the player can't talk from there.\n"
	if g.explore_mode:
		s += "The player sees a floor plan with every room's name and doors, but only knows the sounds and objects of rooms they have visited. "
	else:
		s += "The player sees a floor plan with every room's name, doors and sound icons, but not the objects of rooms they haven't visited. "
	s += "Describing a room by its sounds ('the room with the clock and the fan') is as unsafe as naming it — he knows the sounds too.\n"
	s += "After '[click: another extension picks up]' with no hang-up since, assume he IS listening: say almost nothing, or ask a yes/no question, or use a nickname. "
	s += "If you hear '[a man's voice on the line ...]', he is sure where the player is — tell them to move, now, without naming where.\n"
	s += "If NO other extension has picked up since the last hang-up, he is probably not listening right now: that is the moment to be clear and efficient — "
	s += "give the next compass direction or the exact spot (prefer a nickname over an object name). Don't waste safe moments on questions you can already answer.\n"
	s += "The exit room %s a phone.%s\n\n" % ["HAS" if h.rooms[g.exit_room].phone else "has NO", "" if h.rooms[g.exit_room].phone else " So tell the player which object to search BEFORE they walk in — they can't call you from in there."]
	s += "HOW TO TALK: whispered, scared, focused. Max 2 short sentences, under 30 words. No stage directions, no emojis. "
	s += "Prefer nicknames, yes/no questions the player can answer with taps, and compass directions from where you think they are. "
	s += "Avoid saying room names or object names when he might be listening. Ask before you guide if you are unsure where they are. "
	s += "It is fine to stay silent (empty say) if speaking now is too dangerous.\n\n"
	if Loc.lang == "cs":
		s += "LANGUAGE: the player speaks Czech. Whisper in natural, informal Czech (tykání). Use the Czech room and object names and the Czech nicknames. "
		s += "Directions in Czech: severními / východními / jižními / západními dveřmi. Note: in Czech 'východ' means both 'east' and 'exit' — avoid the ambiguity.\n\n"
	s += "OUTPUT FORMAT (JSON only, no prose around it):\n"
	s += "{\"thinking\": \"one short private sentence\", \"say\": \"what you whisper\", \"guess_room\": \"room id where you think the player is, or empty\"}\n"
	return s


static func build_prompt(g, reason: String) -> String:
	var p := "THE LINE SO FAR (oldest first):\n"
	var lines: Array = g.line_log.slice(maxi(0, g.line_log.size() - 40))
	for e in lines:
		match e.who:
			"player": p += "PLAYER: %s\n" % e.text
			"rescuer": p += "YOU (Mara): %s\n" % e.text
			_: p += "%s\n" % e.text
	var why := {
		"speech": "The player just spoke.",
		"tap": "The player just tapped.",
		"pickup": "The player just picked up a receiver again after being away.",
		"followup": "More happened on the line while you were answering.",
		"imposter": "Someone just imitated YOUR voice on the line to mislead the player. Warn them, briefly.",
	}
	p += "\n%s It is %d:%02d into the call. Reply with the JSON object." % [why.get(reason, ""), int(g.time) / 60, int(g.time) % 60]
	return p
