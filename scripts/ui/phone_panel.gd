class_name PhonePanel
extends PanelContainer
## The line: transcript, typing, tapping, hanging up.

signal voice_char(c: String)

var game: Game
var log_view: RichTextLabel
var status: Label
var thinking: Label
var input: LineEdit
var tap_btn: Button
var hook_btn: Button
var lines: Array = []        # {kind, text, shown}
var reveal_speed := 30.0     # chars per second for her voice
var _acc := 0.0
var _think_t := 0.0
var _is_thinking := false
var _dirty := true


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(status)
	thinking = Label.new()
	head.add_child(thinking)
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
	var hint := Label.new()
	hint.text = "1 tap = yes · 2 taps = no"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 12)
	row.add_child(hint)


func bind(g: Game) -> void:
	game = g
	lines.clear()
	_dirty = true
	g.event.connect(_on_event)


func add_line(kind: String, text: String, instant := true) -> void:
	lines.append({"kind": kind, "text": text, "shown": text.length() if instant else 0})
	_dirty = true


func _toggle_hook() -> void:
	if game == null:
		return
	if game.receiver_up:
		game.hang_up()
	else:
		game.pick_up()


func _on_submit(t: String) -> void:
	if game and game.say(t):
		input.clear()


func _unhandled_key_input(e: InputEvent) -> void:
	if game == null or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.ctrl_pressed and e.keycode == KEY_T:
		game.tap()
		get_viewport().set_input_as_handled()
	elif e.ctrl_pressed and e.keycode == KEY_H:
		_toggle_hook()
		get_viewport().set_input_as_handled()


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"player_says":
			add_line("you", d.text)
		"player_tap":
			add_line("sound", "tap")
		"rescuer_says":
			add_line("her", d.text, false)
		"rescuer_thinking":
			_is_thinking = d.on
		"line_click":
			add_line("danger", d.text)
		"line_breath":
			add_line("danger", "…slow breathing on the line. Not yours.")
		"line_quiet_presence":
			add_line("danger", "The line sounds… open. As if someone is already listening.")
		"line_background":
			var labels: Array = d.features.map(func(f): return House.FEATURE_LABEL[f])
			if labels.is_empty():
				add_line("danger", "Behind the other extension: dead silence.")
			else:
				add_line("danger", "Faintly, through the receiver: %s. Not from your room." % ", ".join(labels))
		"receiver":
			add_line("sound", "you pick up the receiver" if d.up else "you hang up")
		"footsteps":
			if d.dist == 1:
				add_line("danger", "Heavy footsteps — right behind the %s door!" % d.dir if d.dir != "" else "Heavy footsteps, very close.")
			else:
				add_line("danger", "Footsteps somewhere nearby. Two rooms away?")
		"player_arrive":
			var r: Dictionary = game.house.rooms[d.room]
			add_line("narr", "You slip into the %s.%s" % [r.name, "" if r.phone else " There is no phone here."])
			if d.first:
				for o in r.objects:
					if o.has("memory"):
						add_line("memory", o.memory)
		"feature_toggled":
			var what := {"clock": ["The clock stops.", "The clock ticks again."], "fan": ["The fan whirs down.", "The fan hums back to life."], "window": ["The window shuts. The rain goes muffled.", "The window creaks open."]}
			add_line("narr", what[d.feature][1 if d.on else 0])
		"weather":
			add_line("narr", "The rain picks up again." if d.raining else "The rain stops. Suddenly everything is quieter.")
		"clock_strike":
			if game.room_state[game.player_room].clock:
				add_line("narr", "The clock in this room strikes. Loud. Every clock in the house joins in.")
			else:
				add_line("narr", "Somewhere in the house, clocks are striking.")
		"exit_try":
			if d.ok:
				add_line("narr", "Something gives way. Cold air. A way out.")
			else:
				add_line("danger", "Nothing — and it made a terrible noise. %d tries left." % d.attempts_left)
		"murderer_found_exit":
			pass


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
				voice_char.emit(c)
				advanced = true
				_dirty = true
				break
		if not advanced:
			_acc = 0.0
			break
	_think_t += dt
	thinking.text = ("…the line crackles" + ".".repeat(int(_think_t * 2.0) % 3)) if _is_thinking else ""
	var on := game.player_on_line()
	var here: Dictionary = game.house.rooms[game.player_room]
	if game.moving_to != "":
		status.text = "○ moving…"
	elif not here.phone:
		status.text = "○ no phone in this room"
	elif game.receiver_up:
		status.text = "● ON THE LINE — anyone could be listening"
	else:
		status.text = "○ receiver on the hook"
	input.editable = on and not game.over
	input.placeholder_text = "Whisper into the receiver… (Enter)" if on else "(you need to be on the line)"
	tap_btn.disabled = not on
	hook_btn.disabled = not here.phone or game.moving_to != "" or game.over
	hook_btn.text = ("Hang up  [Ctrl+H]" if game.receiver_up else "Pick up  [Ctrl+H]")
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
				out += "[color=#%s]YOU:[/color] %s\n" % [col.call("you"), txt]
			"her":
				out += "[color=#%s]HER:[/color] [color=#%s]%s[/color]\n" % [col.call("dim"), col.call("her"), txt]
			"danger":
				out += "[color=#%s][i]%s[/i][/color]\n" % [col.call("danger"), txt]
			"memory":
				out += "[color=#%s][i]%s[/i][/color]\n" % [col.call("accent"), txt]
			"sound":
				out += "[color=#%s][i]· %s ·[/i][/color]\n" % [col.call("dim"), txt]
			_:
				out += "[color=#%s]%s[/color]\n" % [col.call("text"), txt]
	log_view.text = out
