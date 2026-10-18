class_name RoomPanel
extends PanelContainer
## What's in the room you're in: objects (each a possible hidden exit),
## hiding, sneaking and the things you can switch off. Doors live on the plan.

signal move_requested(room: String, sneak: bool)

var game: Game
var title: Label
var busy_bar: ProgressBar
var busy_label: Label
var objects_box: HFlowContainer
var actions_box: HFlowContainer
var sneak_toggle: CheckButton
var sneak := false
var armed := ""
var _armed_t := 0.0
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
	objects_box = HFlowContainer.new()
	v.add_child(objects_box)
	actions_box = HFlowContainer.new()
	v.add_child(actions_box)


func bind(g: Game) -> void:
	game = g
	armed = ""
	g.event.connect(_on_event)
	rebuild()


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"player_arrive", "feature_toggled", "exit_try", "weather", "heating", "game_over", "player_move_start", "hidden", "backed_out":
			rebuild()
		"busy":
			_busy_total = maxf(d.dur, 0.01)
			busy_label.text = d.label
			busy_bar.visible = d.label != ""
			busy_bar.value = 0
			rebuild()


func _search(obj: String) -> void:
	if armed == obj:
		armed = ""
		game.try_exit(obj)
	else:
		armed = obj
		_armed_t = 3.0
		rebuild()


func _process(dt: float) -> void:
	if armed != "":
		_armed_t -= dt
		if _armed_t <= 0.0:
			armed = ""
			rebuild()
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
	for box in [objects_box, actions_box]:
		for c in box.get_children():
			c.queue_free()
	var h := game.house
	var r: Dictionary = h.rooms[game.player_room]
	var ok := game.can_act()
	title.text = Loc.t("tries", [h.room_name(game.player_room).to_upper(), "● ".repeat(game.attempts_left) + "○ ".repeat(3 - game.attempts_left)])
	if game.moving_to != "":
		title.text = Loc.t("walking_to", [h.room_to(game.moving_to) if game.visited.has(game.moving_to) else "?"])
	# Row 1: what you can search (each is a possible hidden exit).
	_small(objects_box, Loc.t("search"))
	for o in r.objects:
		var label: String = h.obj_name(o.id)
		var tip := Loc.t("obj_tip", [h.obj_desc(o.id)])
		if h.is_obvious(o.id):
			label += " ◉"
			tip += Loc.t("obj_tip_obvious")
		elif o.has("nick"):
			label += " ♥ " + h.obj_nick(o.id)
			tip += Loc.t("obj_tip_nick", [h.obj_nick(o.id)])
		if game.tried.has(o.id):
			label += " ✗"
		if armed == o.id:
			label = Loc.t("really")
		var b := _btn(objects_box, label, func(): _search(o.id), ok and not game.tried.has(o.id))
		b.tooltip_text = tip
	# Row 2: hide, sneak, and the things in this room that make noise.
	# (Doors are on the plan: click a room, or use the arrow keys.)
	var hb := _btn(actions_box, Loc.t("hidden_btn") if game.hidden else Loc.t("hide"), func(): game.toggle_hide(), ok)
	hb.tooltip_text = Loc.t("hide_tip")
	sneak_toggle = CheckButton.new()
	sneak_toggle.text = Loc.t("sneak")
	sneak_toggle.focus_mode = Control.FOCUS_NONE
	sneak_toggle.button_pressed = sneak
	sneak_toggle.toggled.connect(func(v): sneak = v)
	actions_box.add_child(sneak_toggle)
	var s: Dictionary = game.room_state[game.player_room]
	if h.has_feature(game.player_room, "clock"):
		_btn(actions_box, Loc.t("clock_stop_b") if s.clock else Loc.t("clock_wind_b"), func(): game.toggle_feature("clock"), ok)
	if h.has_feature(game.player_room, "fan"):
		_btn(actions_box, Loc.t("fan_off_b") if s.fan else Loc.t("fan_on_b"), func(): game.toggle_feature("fan"), ok)
	if h.has_feature(game.player_room, "rain"):
		_btn(actions_box, Loc.t("win_close_b") if s.window else Loc.t("win_open_b"), func(): game.toggle_feature("rain"), ok)
	if h.has_feature(game.player_room, "radiator"):
		_small(actions_box, Loc.t("radiator_on") if game.heating else Loc.t("radiator_off"))
