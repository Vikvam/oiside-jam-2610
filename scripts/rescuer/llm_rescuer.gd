class_name LlmRescuer
extends Node
## Optional Haiku voice. The scripted brain (MockRescuer) still decides what
## she says; the LLM only rephrases the draft like a person and reads the
## player's free text for a location hint. Code validates the rephrasing
## (safe_rephrase) and urgent warnings skip the LLM entirely.
## mode "proxy": local proxy (proxy/rescuer_proxy.py) -> `claude -p --model haiku`
## mode "api":   an HTTP endpoint from rescuer_config.cfg (Anthropic Messages
##               format, or the same simple format as the proxy).
## On any failure she just says the draft.

var game
var mode := "proxy"
var cfg := {}
var fallback               # MockRescuer
var http: HTTPRequest
var busy := false
var timeout_s := 40.0
var last_error := ""
var _draft := ""
var _wait := -1.0
var _ctx := {}


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	http.request_completed.connect(_on_done)


func tick(dt: float) -> void:
	if _wait >= 0.0:
		_wait -= dt
		if _wait < 0.0:
			_send(_ctx)


func request(ctx: Dictionary) -> void:
	# Like the scripted voice: after a pickup, wait to hear the background.
	_ctx = ctx
	var reason: String = ctx.get("reason", "")
	_wait = 2.4 if reason == "pickup" else (0.4 if reason == "camera" else 0.3)


func _send(ctx: Dictionary) -> void:
	# The scripted brain decides WHAT she says. Haiku only says it like a
	# person would, and reads the player's free text for a location hint.
	fallback._reason = ctx.get("reason", "")
	_draft = fallback.decide()
	if _draft == "" or fallback.last_draft_urgent or busy:
		game.rescuer_says(_draft, fallback.guess)  # silence, or a warning: no time to wait
		return
	var system := build_system(game)
	var prompt := build_prompt(game, ctx.get("reason", ""), _draft)
	var url := ""
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := {}
	if mode == "api" and cfg.get("format", "anthropic") == "anthropic":
		url = cfg.get("url", "https://api.anthropic.com/v1/messages")
		headers.append("x-api-key: %s" % cfg.get("key", ""))
		headers.append("anthropic-version: 2023-06-01")
		body = {
			"model": cfg.get("model", "claude-haiku-5-5"),
			"max_tokens": 300,
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
	var say: String = reply.say
	if not safe_rephrase(_draft, say, game):
		say = _draft  # it added something he could use: say the draft instead
	if reply.guess != "" and fallback.guess == "":
		fallback.tentative = reply.guess  # a hint for her next turn, not a fact
	game.rescuer_says(say, fallback.guess)


func _fail(why: String, _ctx: Dictionary) -> void:
	busy = false
	last_error = why
	push_warning("Rescuer LLM failed: " + why)
	game.emit("rescuer_error", {"why": why})
	game.rescuer_says(_draft, fallback.guess if fallback else "")


## Haiku may change the words, never the facts. Reject a rephrasing that
## names a room or object the draft didn't, or adds compass directions.
static func safe_rephrase(draft: String, say: String, g) -> bool:
	if say.strip_edges() == "":
		return draft == ""
	var h: House = g.house
	for r in Words.rooms_named(say, h):
		if r not in Words.rooms_named(draft, h):
			return false
	var d_objs := Words.objects_named(draft, h).map(func(o): return o.obj)
	for o in Words.objects_named(say, h):
		if o.obj not in d_objs:
			return false
	var d_dirs := Words.directions(draft)
	var s_dirs := Words.directions(say)
	for x in s_dirs:
		if x not in d_dirs:
			return false
	for x in d_dirs:
		if x not in s_dirs:
			return false  # dropped the direction she meant
	return say.length() <= draft.length() * 2 + 40


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
	while say.contains("  "):
		say = say.replace("  ", " ")
	if say.length() > 240:
		say = say.left(240).rsplit(" ", true, 1)[0] + "…"
	var guess := str(d.get("guess_room", "")).to_lower().strip_edges()
	if guess not in house.rooms:
		guess = ""
	return {"say": say, "guess": guess}


static func build_system(g) -> String:
	var h: House = g.house
	var s := ""
	s += "You are the voice of Mara in a tense horror game. Output ONLY a JSON object.\n"
	if Loc.lang == "cs":
		s += "IMPORTANT: the player speaks CZECH. \"say\" MUST be natural, informal Czech (tykání).\n"
	s += "\nSITUATION: Your younger sibling is hiding in your old family house from a murderer, whispering to you over a party-line phone. "
	s += "He can listen on any extension. You watch grainy security cameras.\n\n"
	s += "YOUR JOB: a planner has already decided what you say this turn (DRAFT). Say the same thing the way a terrified, loving sister would whisper it. "
	s += "Keep every fact, door and instruction exactly; you may shorten, never add. "
	s += "NEVER add a room name, an object name, or a compass direction that the draft doesn't have. Max 2 short sentences. No stage directions, no emojis.\n\n"
	s += "ALSO: if the player's latest words describe where they are (an object, a nickname, a sound), put the room id in guess_room, else leave it empty. Room ids:\n"
	for rid in h.room_ids:
		var objs := []
		for oid in h.home_room:
			if h.home_room[oid] == rid:
				var o := h.object_def(oid)
				var nm: String = House.cs_obj(oid)[0] if Loc.lang == "cs" else o.name
				if o.has("nick"):
					nm += " (\"%s\")" % (House.cs_obj(oid)[3] if Loc.lang == "cs" else o.nick)
				objs.append(nm)
		s += "- %s: %s\n" % [rid, ", ".join(objs)]
	s += "\nOUTPUT: {\"say\": \"...\", \"guess_room\": \"room id or empty\"}\n"
	return s


static func build_prompt(g, reason: String, draft := "") -> String:
	var p := "THE LINE, LAST FEW EXCHANGES:\n"
	var lines: Array = g.line_log.slice(maxi(0, g.line_log.size() - 10))
	for e in lines:
		match e.who:
			"player": p += "PLAYER: %s\n" % e.text
			"rescuer": p += "YOU: %s\n" % e.text
			_: pass
	p += "\nDRAFT (say this, in your own words): %s\n" % draft
	p += "Reply with the JSON object."
	return p
