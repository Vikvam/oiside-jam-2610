class_name PhonePanel
extends PanelContainer
## The line: transcript, typing, tapping, hanging up.

signal voice_char(c: String, kind: String, contour: float)

var game: Game
var log_view: RichTextLabel
var scope: LineScope
var status: Label
var thinking: Label
var input: LineEdit
var tap_btn: Button
var hook_btn: Button
var tap_hint: Label
var lines: Array = []        # {kind, text, shown, house, tap, heard}
var house_view: RichTextLabel  # the strip under the plan: what you hear in the HOUSE
var _tapped := false         # as far as the player can tell, someone else is on the line
var reveal_speed := 30.0     # chars per second for her voice
var _acc := 0.0
var _think_t := 0.0
var _is_thinking := false
var _dirty := true
var _render_acc := 0.0
var hints := true
var active := true          # false while paused / on the title
var _hinted := {}


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true  # long "also: …" lists must not widen the panel
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size.x = 50
	head.add_child(status)
	thinking = Label.new()
	head.add_child(thinking)
	scope = LineScope.new()
	v.add_child(scope)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.selection_enabled = false
	log_view.focus_mode = Control.FOCUS_NONE
	v.add_child(log_view)
	input = LineEdit.new()
	input.placeholder_text = "Whisper into the receiver… (Enter)"
	input.max_length = 160
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(func(ev):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			input.release_focus()
			input.accept_event())
	v.add_child(input)
	var row := HBoxContainer.new()
	v.add_child(row)
	tap_btn = Button.new()
	tap_btn.text = "Tap  [Ctrl+T]"
	tap_btn.focus_mode = Control.FOCUS_NONE
	tap_btn.pressed.connect(func(): if game: game.tap())
	row.add_child(tap_btn)
	hook_btn = Button.new()
	hook_btn.focus_mode = Control.FOCUS_NONE
	hook_btn.pressed.connect(_toggle_hook)
	row.add_child(hook_btn)
	tap_hint = Label.new()
	tap_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tap_hint.add_theme_font_size_override("font_size", 12)
	row.add_child(tap_hint)


func bind(g: Game) -> void:
	game = g
	_is_thinking = false
	scope.bind(g)
	lines.clear()
	_tapped = false
	_dirty = true
	g.event.connect(_on_event)


func add_line(kind: String, text: String, instant := true, heard := false) -> void:
	lines.append({"kind": kind, "text": text, "shown": text.length() if instant else 0, "house": false, "tap": _tapped, "heard": heard})
	_dirty = true


## Sounds of the house (not of the line) go to the strip under the plan.
func house_line(kind: String, text: String) -> void:
	lines.append({"kind": kind, "text": text, "shown": text.length(), "house": true, "tap": false, "heard": false})
	_dirty = true


func _rule(key: String, on: bool) -> void:
	_tapped = on
	add_line("rule", Loc.t(key))


func hint(key: String) -> void:
	if hints and not _hinted.has(key):
		_hinted[key] = true
		add_line("hint", "» " + Loc.t("h_" + key))


## Intonation: rises towards the end of a question, falls at the end of a
## statement. Returns a pitch multiplier offset for the current position.
static func _contour(text: String, pos: int) -> float:
	var end := text.length()
	for p in [".", "?", "!"]:
		var i := text.find(p, pos - 1)
		if i != -1 and i < end:
			end = i
	var start := 0
	for p in [". ", "? ", "! "]:
		var j := text.rfind(p, pos - 1)
		if j != -1 and j + 2 > start:
			start = j + 2
	var f := clampf(float(pos - start) / maxf(1.0, float(end - start)), 0.0, 1.0)
	var q := end < text.length() and text[end] == "?"
	return 0.16 * f * f if q else -0.07 * f


func _toggle_hook() -> void:
	if game == null:
		return
	if game.receiver_up:
		game.hang_up()
	else:
		game.pick_up()


func _on_submit(t: String) -> void:
	if t.strip_edges() == "":
		input.release_focus()  # empty Enter hands the keys back to walking
		return
	if game and active and game.say(t):
		input.clear()


func _unhandled_key_input(e: InputEvent) -> void:
	if game == null or not active or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.ctrl_pressed and e.keycode == KEY_T:
		game.tap()
		get_viewport().set_input_as_handled()
	elif e.ctrl_pressed and e.keycode == KEY_H:
		_toggle_hook()
		get_viewport().set_input_as_handled()


func _on_event(t: String, d: Dictionary) -> void:
	var h: House = game.house
	match t:
		"player_says":
			add_line("you", d.text, true, d.get("heard", false))
			if d.get("loud", false):
				add_line("danger", Loc.t("shouted"))
		"player_tap":
			add_line("sound", Loc.t("tap"), true, d.get("heard", false))
		"rescuer_says":
			if game.player_on_line():
				add_line("her", d.text, false, d.get("heard", false))
			else:
				add_line("sound", Loc.t("her_missed"))
		"imposter_says":
			add_line("fake", d.text, false)
			hint("imposter")
		"murderer_says":
			add_line("him", d.text, false)
			hint("taunt")
		"rescuer_thinking":
			_is_thinking = d.on
		"line_click":
			_rule("rule_" + d.kind, d.kind == "pickup")
			if d.kind == "pickup":
				hint("click")
		"line_breath":
			add_line("danger", Loc.t("breath_line"))
		"line_quiet_presence":
			add_line("danger", Loc.t("open_line"))
			_rule("rule_open", true)
		"line_background":
			hint("bg")
			var labels: Array = d.features.map(func(f): return Loc.feature(f))
			if labels.is_empty():
				add_line("danger", Loc.t("his_silence"))
			else:
				add_line("danger", Loc.t("his_sounds", [", ".join(labels)]))
		"receiver":
			add_line("sound", Loc.t("pickup_me") if d.up else Loc.t("hangup_me"))
			if not d.up:
				_tapped = false  # off the line you can't tell any more
		"footsteps":
			hint("steps")
			var kind := Loc.t("steps_run") if d.running else Loc.t("steps_heavy")
			var dr := Loc.dir(d.dir)
			var txt := ""
			if d.get("leaving", false):
				txt = Loc.t("steps_leave", [Loc.t("steps_right") if d.dist == 1 else Loc.t("steps_some"), dr, kind])
			elif d.dist == 1:
				txt = Loc.t("steps_1", [kind, dr])
			elif d.dist == 2:
				txt = Loc.t("steps_2", [kind, dr])
			else:
				txt = Loc.t("steps_3", [kind, dr])
			if d.get("for_you", false):
				txt += Loc.t("for_you")
			house_line("danger", txt)
		"player_arrive":
			var r: Dictionary = h.rooms[d.room]
			house_line("narr", Loc.t("slip_in", [h.room_to(d.room)]) + ("" if r.phone else Loc.t("no_phone_here")))
			if r.phone and not game.receiver_up:
				hint("pickup")
			if d.first:
				for o in r.objects:
					if o.has("memory"):
						var m := h.obj_memory(o.id)
						if h.was_moved(o.id):
							m += Loc.t("moved_note", [h.room_in(h.home_room[o.id])])
						house_line("memory", m)
		"feature_toggled":
			var what := {"clock": ["clock_stop", "clock_go"], "fan": ["fan_off", "fan_on"], "window": ["win_shut", "win_open"]}
			house_line("narr", Loc.t(what[d.feature][1 if d.on else 0]))
		"weather":
			house_line("narr", Loc.t("rain_on") if d.raining else Loc.t("rain_off"))
		"heating":
			if h.has_feature(game.player_room, "radiator"):
				house_line("narr", Loc.t("heat_on") if d.on else Loc.t("heat_off"))
		"clock_strike":
			house_line("narr", Loc.t("strike_here") if game.room_state[game.player_room].clock else Loc.t("strike_far"))
		"exit_try":
			if d.ok:
				house_line("narr", Loc.t("exit_ok"))
			else:
				house_line("danger", Loc.t("exit_bad", [d.attempts_left]))
		"presence":
			house_line("danger", Loc.t("presence", [Loc.dir(d.dir)]))
			hint("presence")
		"hidden":
			house_line("narr", Loc.t("hide_on") if d.on else Loc.t("hide_off"))
		"murderer_in_room":
			house_line("danger", Loc.t("in_room"))
		"murderer_searching":
			house_line("danger", Loc.t("searching", [Loc.dir(d.dir)]))
		"murderer_left":
			house_line("narr", Loc.t("he_left", [Loc.dir(d.dir)]))
		"slipped_out":
			house_line("narr", Loc.t("slipped_out"))
		"murderer_found_exit":
			house_line("danger", Loc.t("found_exit"))
		"game_over":
			_dirty = true  # re-render with what he really heard
		"line_fake_tell":
			add_line("danger", Loc.t("fake_tell"))
			_tapped = true
		"rescuer_error":
			add_line("sound", Loc.t("llm_err"))


func _process(dt: float) -> void:
	if game == null:
		return
	# Typewriter reveal of her lines.
	_acc += dt * reveal_speed
	while _acc >= 1.0:
		_acc -= 1.0
		var advanced := false
		for l in lines:
			if l.shown < l.text.length():
				var c: String = l.text[l.shown]
				l.shown += 1
				voice_char.emit(c, l.kind, _contour(l.text, l.shown))
				if c != " ":
					scope.voice()
				advanced = true
				_dirty = true
				break
		if not advanced:
			_acc = 0.0
			break
	_think_t += dt
	thinking.text = (Loc.t("crackle") + ".".repeat(int(_think_t * 2.0) % 3)) if _is_thinking else ""
	var on := game.player_on_line()
	var here: Dictionary = game.house.rooms[game.player_room]
	if game.hidden:
		status.text = Loc.t("st_hidden")
	elif game.moving_to != "":
		status.text = Loc.t("st_moving")
	elif not here.phone:
		status.text = Loc.t("st_nophone")
	elif game.receiver_up:
		var mine := game.player_active_features()
		var foreign := []
		for f in game.foreign_sounds():
			foreign.append(Loc.t("second_x", [Loc.feature(f)]) if f in mine else Loc.feature(f))
		if foreign.is_empty():
			status.text = Loc.t("st_hiss")
		else:
			status.text = Loc.t("st_also", [", ".join(foreign)])
	else:
		status.text = Loc.t("st_hook")
	input.editable = on and not game.over
	input.placeholder_text = Loc.t("whisper") if on else Loc.t("need_line")
	tap_btn.disabled = not on
	hook_btn.disabled = not here.phone or game.moving_to != "" or game.over
	hook_btn.text = Loc.t("hang_btn") if game.receiver_up else Loc.t("pick_btn")
	tap_btn.text = Loc.t("tap_btn")
	tap_hint.text = Loc.t("tap_hint")
	_render_acc += dt
	if _dirty and _render_acc >= 1.0 / 20.0:  # re-parse the log at most 20x/s
		_render_acc = 0.0
		_dirty = false
		_render()


func _render() -> void:
	var out := ""
	var phone_lines := lines.filter(func(l): return not l.house)
	var fresh_from := phone_lines.size() - 10  # older lines fade back
	var truth := game.over  # after the call: what he REALLY heard
	var danger_hex := (Style.c("danger") as Color).to_html(false)
	for idx in range(maxi(0, phone_lines.size() - 120), phone_lines.size()):  # only the recent past
		var l: Dictionary = phone_lines[idx]
		var txt: String = l.text.substr(0, l.shown).replace("[", "[lb]")
		var a := "8c" if idx < fresh_from and not game.over else ""
		var col := func(k: String) -> String: return (Style.c(k) as Color).to_html(false) + a
		var mark := ""
		if l.kind in ["you", "her", "sound"]:
			if truth and l.heard:
				mark = "[color=#%s]◉[/color] " % danger_hex
			elif not truth and l.tap:
				mark = "[color=#%s]┃[/color] " % (danger_hex + a)
				if idx >= fresh_from:
					txt = "[shake rate=7.0 level=3 connected=1]%s[/shake]" % txt
		out += mark
		match l.kind:
			"rule":
				out += "[center][color=#%s]──── %s ────[/color][/center]\n" % [col.call("danger"), txt]
			"you":
				out += "[color=#%s]%s[/color] %s\n" % [col.call("you"), Loc.t("you"), txt]
			"her":
				out += "[color=#%s]%s[/color] [color=#%s]%s[/color]\n" % [col.call("dim"), Loc.t("her"), col.call("her"), txt]
			"danger":
				out += "[color=#%s][i]%s[/i][/color]\n" % [col.call("danger"), txt]
			"fake":
				var tint := (Style.c("her") as Color).lerp(Style.c("danger"), 0.18).to_html(false) + a
				out += "[color=#%s]%s[/color] [color=#%s][i]%s[/i][/color]\n" % [col.call("dim"), Loc.t("her"), tint, txt]
			"him":
				out += "[color=#%s][b]???:[/b] [i]%s[/i][/color]\n" % [col.call("danger"), txt]
			"hint":
				out += "[color=#%s][font_size=13]%s[/font_size][/color]\n" % [col.call("hint"), txt]
			"memory":
				out += "[color=#%s][i]%s[/i][/color]\n" % [col.call("accent"), txt]
			"sound":
				out += "[color=#%s][i]· %s ·[/i][/color]\n" % [col.call("dim"), txt]
			_:
				out += "[color=#%s]%s[/color]\n" % [col.call("text"), txt]
	log_view.text = out
	if house_view:
		var hv := ""
		# Newest on top, so the latest warning is never cut off.
		var house := lines.filter(func(l): return l.house)
		for idx in range(house.size() - 1, maxi(-1, house.size() - 6), -1):
			var l: Dictionary = house[idx]
			var a := "" if idx == house.size() - 1 else ("bb" if idx >= house.size() - 3 else "77")
			var k: String = {"danger": "danger", "memory": "accent"}.get(l.kind, "text")
			var t: String = l.text.replace("[", "[lb]")
			if l.kind == "danger" or l.kind == "memory":
				t = "[i]%s[/i]" % t
			hv += "[color=#%s]%s[/color]\n" % [(Style.c(k) as Color).to_html(false) + a, t]
		house_view.text = hv
