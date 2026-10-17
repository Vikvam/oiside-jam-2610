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
var lines: Array = []        # {kind, text, shown}
var reveal_speed := 30.0     # chars per second for her voice
var _acc := 0.0
var _think_t := 0.0
var _is_thinking := false
var _dirty := true
var hints := true
var _hinted := {}


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
	scope.bind(g)
	lines.clear()
	_dirty = true
	g.event.connect(_on_event)


func add_line(kind: String, text: String, instant := true) -> void:
	lines.append({"kind": kind, "text": text, "shown": text.length() if instant else 0})
	_dirty = true


func hint(key: String, text: String) -> void:
	if hints and not _hinted.has(key):
		_hinted[key] = true
		add_line("hint", "» " + text)


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
		"murderer_says":
			add_line("him", d.text, false)
			hint("taunt", "He's sure where you are. Move. Now.")
		"rescuer_thinking":
			_is_thinking = d.on
		"line_click":
			add_line("danger", d.text)
			if d.kind == "pickup":
				hint("click", "That's him on another extension. He hears every word — and the sounds of your room. Hang up, go quiet, or lie.")
		"line_breath":
			add_line("danger", "…slow breathing on the line. Not yours.")
		"line_quiet_presence":
			add_line("danger", "The line sounds… open. As if someone is already listening.")
		"line_background":
			hint("bg", "Those are the sounds of HIS room. Check the plan icons: which phone room sounds like that?")
			var labels: Array = d.features.map(func(f): return House.FEATURE_LABEL[f])
			if labels.is_empty():
				add_line("danger", "Behind the other extension: dead silence.")
			else:
				add_line("danger", "Faintly, through the receiver: %s. Not from your room." % ", ".join(labels))
		"receiver":
			add_line("sound", "you pick up the receiver" if d.up else "you hang up")
		"footsteps":
			hint("steps", "Footsteps come with a direction. Move away — or Hide. Walking makes noise too (sneak is quieter).")
			var kind := "Running footsteps" if d.running else "Heavy footsteps"
			if d.dist == 1:
				add_line("danger", "%s — right behind the %s door!" % [kind, d.dir])
			elif d.dist == 2:
				add_line("danger", "%s, two rooms away — beyond the %s door." % [kind, d.dir])
			else:
				add_line("danger", "%s, far off, somewhere past the %s door. Coming closer?" % [kind, d.dir])
		"player_arrive":
			var r: Dictionary = game.house.rooms[d.room]
			add_line("narr", "You slip into the %s.%s" % [r.name, "" if r.phone else " There is no phone here."])
			if r.phone and not game.receiver_up:
				hint("pickup", "There's a phone here. Pick up (Ctrl+H) to talk to her again — but first think about what this room sounds like.")
			if d.first:
				for o in r.objects:
					if o.has("memory"):
						add_line("memory", o.memory)
		"feature_toggled":
			var what := {"clock": ["The clock stops.", "The clock ticks again."], "fan": ["The fan whirs down.", "The fan hums back to life."], "window": ["The window shuts. The rain goes muffled.", "The window creaks open."]}
			add_line("narr", what[d.feature][1 if d.on else 0])
		"weather":
			add_line("narr", "The rain picks up again." if d.raining else "The rain stops. Suddenly everything is quieter.")
		"heating":
			if game.house.has_feature(game.player_room, "radiator"):
				add_line("narr", "The radiator starts knocking — the heating came on." if d.on else "The radiator goes quiet.")
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
		"presence":
			add_line("danger", ["Behind the %s door: a floorboard creaks. Someone is standing there.", "A slow breath behind the %s door. Very close.", "Something shifts its weight behind the %s door."].pick_random() % d.dir)
			hint("presence", "He's in the next room, standing still. Don't go through that door.")
		"hidden":
			add_line("narr", "You squeeze into the darkest corner and hold still." if d.on else "You come out of hiding.")
		"murderer_in_room":
			if d.get("still", false):
				add_line("danger", "He's still here. Floorboards creak a few steps from you.")
			else:
				add_line("danger", "The door creaks open. He is IN THE ROOM. Don't. Breathe.")
		"murderer_found_exit":
			add_line("danger", "Far off in the house: wood splintering. Then a low, pleased laugh.")
		"line_fake_tell":
			add_line("danger", "…but the line still sounds a little too full.")
		"rescuer_error":
			add_line("sound", "the line hisses — her voice comes through thin and strange")


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
	thinking.text = ("…the line crackles" + ".".repeat(int(_think_t * 2.0) % 3)) if _is_thinking else ""
	var on := game.player_on_line()
	var here: Dictionary = game.house.rooms[game.player_room]
	if game.hidden:
		status.text = "○ HIDDEN — hold still"
	elif game.moving_to != "":
		status.text = "○ moving…"
	elif not here.phone:
		status.text = "○ no phone in this room"
	elif game.receiver_up:
		var mine := game.player_active_features()
		var foreign := []
		for f in game.foreign_sounds():
			foreign.append(("a second " + House.FEATURE_LABEL[f] + ", out of step") if f in mine else House.FEATURE_LABEL[f])
		if foreign.is_empty():
			status.text = "● ON THE LINE — just hiss"
		else:
			status.text = "● ON THE LINE — also: " + ", ".join(foreign)
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
