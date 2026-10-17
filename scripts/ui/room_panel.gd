class_name RoomPanel
extends PanelContainer
## What's in the room you're in: objects (each a possible hidden exit),
## things you can switch off, doors.

signal move_requested(room: String, sneak: bool)

var game: Game
var title: Label
var busy_bar: ProgressBar
var busy_label: Label
var objects_box: HBoxContainer
var actions_box: HBoxContainer
var doors_box: HBoxContainer
var sneak_toggle: CheckButton
var sneak := false
var _busy_total := 1.0


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	busy_label = Label.new()
	head.add_child(busy_label)
	busy_bar = ProgressBar.new()
	busy_bar.custom_minimum_size = Vector2(120, 10)
	busy_bar.show_percentage = false
	busy_bar.visible = false
	head.add_child(busy_bar)
	objects_box = HBoxContainer.new()
	v.add_child(objects_box)
	actions_box = HBoxContainer.new()
	v.add_child(actions_box)
	doors_box = HBoxContainer.new()
	v.add_child(doors_box)


func bind(g: Game) -> void:
	game = g
	g.event.connect(_on_event)
	rebuild()


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"player_arrive", "feature_toggled", "exit_try", "weather", "game_over", "player_move_start":
			rebuild()
		"busy":
			_busy_total = maxf(d.dur, 0.01)
			busy_label.text = d.label
			busy_bar.visible = d.label != ""
			busy_bar.value = 0
			rebuild()


func _process(_dt: float) -> void:
	if game and game.busy != "":
		busy_bar.value = (1.0 - game.busy_timer / _busy_total) * 100.0


func _btn(parent: Node, text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _small(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Style.c("dim"))
	parent.add_child(l)


func rebuild() -> void:
	if game == null:
		return
	for box in [objects_box, actions_box, doors_box]:
		for c in box.get_children():
			c.queue_free()
	var h := game.house
	var r: Dictionary = h.rooms[game.player_room]
	var ok := game.can_act()
	title.text = "%s   ·   hidden-exit tries left: %s" % [r.name.to_upper(), "● ".repeat(game.attempts_left) + "○ ".repeat(3 - game.attempts_left)]
	if game.moving_to != "":
		title.text = "…walking to the %s" % h.rooms[game.moving_to].name
	_small(objects_box, "Search:")
	for o in r.objects:
		var label: String = o.name
		if game.tried.has(o.id):
			label += " ✗"
		var b := _btn(objects_box, label, func(): game.try_exit(o.id), ok and not game.tried.has(o.id))
		b.tooltip_text = o.desc + "\n\nClick: try to open a hidden exit here.\nA wrong guess makes a LOUD noise."
	_small(actions_box, "Sounds:")
	var s: Dictionary = game.room_state[game.player_room]
	var any := false
	if h.has_feature(game.player_room, "clock"):
		_btn(actions_box, "Stop the clock" if s.clock else "Wind the clock", func(): game.toggle_feature("clock"), ok)
		any = true
	if h.has_feature(game.player_room, "fan"):
		_btn(actions_box, "Switch off fan" if s.fan else "Switch on fan", func(): game.toggle_feature("fan"), ok)
		any = true
	if h.has_feature(game.player_room, "rain"):
		_btn(actions_box, "Close window" if s.window else "Open window", func(): game.toggle_feature("rain"), ok)
		any = true
	if h.has_feature(game.player_room, "radiator"):
		_small(actions_box, "· the radiator clanks (can't stop it)")
	if not any and not h.has_feature(game.player_room, "radiator"):
		_small(actions_box, "· nothing here makes a sound")
	_small(doors_box, "Doors:")
	for dir in House.DIRS:
		var to := h.step(game.player_room, dir)
		if to != "":
			_btn(doors_box, "%s → %s" % [dir.capitalize(), h.rooms[to].name], func():
				move_requested.emit(to, sneak), ok)
	sneak_toggle = CheckButton.new()
	sneak_toggle.text = "sneak (slow, quiet)"
	sneak_toggle.focus_mode = Control.FOCUS_NONE
	sneak_toggle.button_pressed = sneak
	sneak_toggle.toggled.connect(func(v): sneak = v)
	doors_box.add_child(sneak_toggle)
