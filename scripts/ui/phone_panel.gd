class_name PhonePanel
extends PanelContainer
## The line: transcript, typing, tapping, hanging up.

signal voice_char(c: String, kind: String)

var game: Game
var log_view: RichTextLabel
var scope: LineScope
var status: Label
var thinking: Label
var input: LineEdit
var tap_btn: Button
var hook_btn: Button
var tap_hint: Label
var lines: Array = []        # {kind, text, shown}
var reveal_speed := 30.0     # chars per second for her voice
var _acc := 0.0
var _think_t := 0.0
var _is_thinking := false
var _dirty := true
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
	_dirty = true
	g.event.connect(_on_event)


func add_line(kind: String, text: String, instant := true) -> void:
	lines.append({"kind": kind, "text": text, "shown": text.length() if instant else 0})
	_dirty = true


func hint(key: String) -> void:
	if hints and not _hinted.has(key):
		_hinted[key] = true
		add_line("hint", "» " + Loc.t("h_" + key))


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
			add_line("you", d.text)
			if d.get("loud", false):
				add_line("danger", Loc.t("shouted"))
		"player_tap":
			add_line("sound", Loc.t("tap"))
		"rescuer_says":
			if game.player_on_line():
				add_line("her", d.text, false)
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
			add_line("danger", Loc.t("click_" + d.kind))
			if d.kind == "pickup":
				hint("click")
		"line_breath":
			add_line("danger", Loc.t("breath_line"))
		"line_quiet_presence":
			add_line("danger", Loc.t("open_line"))
		"line_background":
			hint("bg")
			var labels: Array = d.features.map(func(f): return Loc.feature(f))
			if labels.is_empty():
				add_line("danger", Loc.t("his_silence"))
			else:
				add_line("danger", Loc.t("his_sounds", [", ".join(labels)]))
		"receiver":
			add_line("sound", Loc.t("pickup_me") if d.up else Loc.t("hangup_me"))
		"footsteps":
			hint("steps")
			var kind := Loc.t("steps_run") if d.running else Loc.t("steps_heavy")
			var dr := Loc.dir(d.dir)
			if d.get("leaving", false):
				add_line("danger", Loc.t("steps_leave", [Loc.t("steps_right") if d.dist == 1 else Loc.t("steps_some"), dr, kind]))
			elif d.dist == 1:
				add_line("danger", Loc.t("steps_1", [kind, dr]))
			elif d.dist == 2:
				add_line("danger", Loc.t("steps_2", [kind, dr]))
			else:
				add_line("danger", Loc.t("steps_3", [kind, dr]))
		"player_arrive":
			var r: Dictionary = h.rooms[d.room]
			add_line("narr", Loc.t("slip_in", [h.room_to(d.room)]) + ("" if r.phone else Loc.t("no_phone_here")))
			if r.phone and not game.receiver_up:
				hint("pickup")
			if d.first:
				for o in r.objects:
					if o.has("memory"):
						add_line("memory", h.obj_memory(o.id))
		"feature_toggled":
			var what := {"clock": ["clock_stop", "clock_go"], "fan": ["fan_off", "fan_on"], "window": ["win_shut", "win_open"]}
			add_line("narr", Loc.t(what[d.feature][1 if d.on else 0]))
		"weather":
			add_line("narr", Loc.t("rain_on") if d.raining else Loc.t("rain_off"))
		"heating":
			if h.has_feature(game.player_room, "radiator"):
				add_line("narr", Loc.t("heat_on") if d.on else Loc.t("heat_off"))
		"clock_strike":
			add_line("narr", Loc.t("strike_here") if game.room_state[game.player_room].clock else Loc.t("strike_far"))
		"exit_try":
			if d.ok:
				add_line("narr", Loc.t("exit_ok"))
			else:
				add_line("danger", Loc.t("exit_bad", [d.attempts_left]))
		"presence":
			add_line("danger", Loc.t("presence", [Loc.dir(d.dir)]))
			hint("presence")
		"hidden":
			add_line("narr", Loc.t("hide_on") if d.on else Loc.t("hide_off"))
		"murderer_in_room":
			add_line("danger", Loc.t("in_room_still") if d.get("still", false) else Loc.t("in_room"))
		"murderer_found_exit":
			add_line("danger", Loc.t("found_exit"))
		"line_fake_tell":
			add_line("danger", Loc.t("fake_tell"))
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
				voice_char.emit(c, l.kind)
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
	if _dirty:
		_dirty = false
		_render()


func _render() -> void:
	var col := func(k: String) -> String: return (Style.c(k) as Color).to_html(false)
	var out := ""
	for l in lines:
		var txt: String = l.text.substr(0, l.shown).replace("[", "[lb]")
		match l.kind:
			"you":
				out += "[color=#%s]%s[/color] %s\n" % [col.call("you"), Loc.t("you"), txt]
			"her":
				out += "[color=#%s]%s[/color] [color=#%s]%s[/color]\n" % [col.call("dim"), Loc.t("her"), col.call("her"), txt]
			"danger":
				out += "[color=#%s][i]%s[/i][/color]\n" % [col.call("danger"), txt]
			"fake":
				var tint := (Style.c("her") as Color).lerp(Style.c("danger"), 0.18).to_html(false)
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
