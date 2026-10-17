extends Node
## Builds the whole UI in code, runs the game loop, switches styles.

const INTRO := {
	"en": [
		"It's me. Don't say my name. Listen.",
		"There's a way out of the house. He doesn't know about it. I'll get you there.",
		"But every phone in that house is on one line. If he picks up an extension, he hears every word.",
		"So don't tell me where you are. Not straight out. One tap means yes, two taps mean no.",
	],
	"cs": [
		"To jsem já. Neříkej moje jméno. Poslouchej.",
		"Z domu vede cesta ven. On o ní neví. Dostanu tě tam.",
		"Ale všechny telefony v tom domě jsou na jedné lince. Když zvedne jiný telefon, slyší každé slovo.",
		"Tak mi neříkej, kde jsi. Ne přímo. Jedno ťuknutí je ano, dvě jsou ne.",
	],
}

var game: Game
var sfx: Sfx
var bg: ColorRect
var ui: Control
var plan: PlanView
var phone: PhonePanel
var room_panel: RoomPanel
var post: ColorRect
var title_layer: CanvasLayer
var over_layer: CanvasLayer
var over_text: RichTextLabel
var over_panel: PanelContainer
var header_label: Label
var peek_btn: Button
var cord: Cord
var flash: ColorRect
var pause_layer: CanvasLayer
var paused := false
var backend := "mock"
var difficulty := "gentle"
var explore_mode := false
var hints_on := true
var rearranged := false
var running := false
var _intro_queue: Array = []
var _intro_t := 0.0
var _settings := ConfigFile.new()
var cfg := {}
var autobot = null
var _dev := false
var _autoplay_policy := ""
var _soak_left := 0
var _soak_stats := {}


func _attach_bot() -> void:
	var BotScript = load("res://tests/sim.gd")
	autobot = BotScript.Bot.new(game, _autoplay_policy)
	game.event.connect(autobot.on_event)


func _ready() -> void:
	_load_settings()
	bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	sfx = Sfx.new()
	add_child(sfx)
	_build_game_ui()
	_build_post()
	_build_title()
	_build_over()
	_build_pause()
	_apply_style()
	_show_title()
	# Draw the house behind the title screen.
	var demo := Game.new()
	demo.setup(1)
	randomize()  # setup() seeded the global RNG; don't make every first game identical
	plan.bind(demo)
	_dev_args()


## Dev harness: godot --path . -- --shot=/tmp/x.png --style=ink --at=8 --play --debug --seed=3
func _dev_args() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.is_empty():
		return
	_dev = true
	if a.has("style"):
		Style.current = a.style
		_apply_style()
		_refresh_title_buttons()
	if a.has("seed"):
		seed(int(a.seed))
	if a.has("backend"):
		backend = a.backend
	if a.has("lang"):
		_set_lang(a.lang)
	if a.has("rearranged"):
		rearranged = true
	if a.has("play"):
		_start_game()
		if a.has("debug"):
			plan.show_debug = true
		if a.has("autoplay"):
			_autoplay_policy = a.autoplay if a.autoplay != "1" else "smart"
			_attach_bot()
		if a.has("soak"):
			_soak_left = int(a.soak)
		if a.has("hidetest"):
			get_tree().create_timer(3.0).timeout.connect(func():
				game.find_chance_pass = 0.0
				game.find_chance_stay = 0.0
				game.hang_up()
				game.hidden = true
				game.emit("hidden", {"on": true})
				var n: String = game.house.neighbors(game.player_room)[0]
				game.murderer.room = n
				game.murderer._go(game.player_room, "phone"))
		if a.has("speed"):
			Engine.time_scale = float(a.speed)
		if a.has("say"):
			get_tree().create_timer(float(a.get("say_at", "2"))).timeout.connect(func(): game.say(a.say))
	if a.has("over"):
		get_tree().create_timer(float(a.get("at", "3")) - 3.0, true, false, true).timeout.connect(func():
			game._end(false, "caught"))
	if a.has("shot"):
		await get_tree().create_timer(float(a.get("at", "3")), true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(a.shot)
		get_tree().quit()


# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	_settings.load("user://settings.cfg")
	Style.current = _settings.get_value("ui", "style", "blueprint")
	backend = _settings.get_value("ui", "backend", "mock")
	difficulty = _settings.get_value("ui", "difficulty", "gentle")
	Loc.lang = _settings.get_value("ui", "lang", "en")
	explore_mode = _settings.get_value("ui", "explore", false)
	hints_on = _settings.get_value("ui", "hints", true)
	rearranged = _settings.get_value("ui", "rearranged", false)
	# Rescuer endpoint config lives next to the project (gitignored) or in user://.
	var rc := ConfigFile.new()
	if rc.load("res://rescuer_config.cfg") == OK or rc.load("user://rescuer_config.cfg") == OK:
		for k in rc.get_section_keys("rescuer"):
			cfg[k] = rc.get_value("rescuer", k)


func _save_settings() -> void:
	if _dev:
		return  # dev/test runs never overwrite the player's settings
	_settings.set_value("ui", "style", Style.current)
	_settings.set_value("ui", "backend", backend)
	_settings.set_value("ui", "difficulty", difficulty)
	_settings.set_value("ui", "lang", Loc.lang)
	_settings.set_value("ui", "explore", explore_mode)
	_settings.set_value("ui", "hints", hints_on)
	_settings.set_value("ui", "rearranged", rearranged)
	_settings.save("user://settings.cfg")


# ---------------------------------------------------------------- layout

func _build_game_ui() -> void:
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	ui.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	margin.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size.x = 12 * PlanView.U + 8
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	h.add_child(left)
	var header := Label.new()
	header.text = Loc.t("header")
	header_label = header
	left.add_child(header)
	plan = PlanView.new()
	plan.room_clicked.connect(_on_room_clicked)
	left.add_child(plan)
	room_panel = RoomPanel.new()
	room_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_panel.custom_minimum_size.x = 12 * PlanView.U + 8
	room_panel.clip_contents = true
	room_panel.move_requested.connect(func(r, sn): if game: game.move_to(r, sn))
	left.add_child(room_panel)
	phone = PhonePanel.new()
	phone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phone.voice_char.connect(func(c, k): sfx.on_voice_char(c, k))
	h.add_child(phone)
	cord = Cord.new()
	cord.plan = plan
	cord.phone = phone
	ui.add_child(cord)
	ui.move_child(cord, 0)  # under the plan, like a cord under the paper


func _build_post() -> void:
	var fl := CanvasLayer.new()
	fl.layer = 49
	add_child(fl)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	fl.add_child(flash)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post.gdshader")
	post.material = mat
	layer.add_child(post)


func _panel_box(parent: Node, min_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	return v


func _build_title() -> void:
	title_layer = CanvasLayer.new()
	title_layer.layer = 10
	add_child(title_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	title_layer.add_child(dim)
	var v := _panel_box(title_layer, Vector2(720, 0))
	var t := Label.new()
	t.name = "Title"
	t.text = Loc.t("title")
	t.add_theme_font_size_override("font_size", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := Label.new()
	sub.text = Loc.t("title_quote")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(660, 0)
	body.text = Loc.t("title_body")
	v.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var lab := Label.new()
	lab.text = Loc.t("look")
	row.add_child(lab)
	for st in Style.ORDER:
		var b := Button.new()
		b.text = Style.STYLES[st].label
		b.toggle_mode = true
		b.button_pressed = st == Style.current
		b.name = "style_" + st
		b.pressed.connect(func():
			Style.current = st
			_apply_style()
			_refresh_title_buttons())
		row.add_child(b)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	var lab2 := Label.new()
	lab2.text = Loc.t("her_voice")
	row2.add_child(lab2)
	for be in [["mock", Loc.t("be_mock")], ["proxy", Loc.t("be_proxy")], ["api", Loc.t("be_api")]]:
		var b := Button.new()
		b.text = be[1]
		b.toggle_mode = true
		b.name = "backend_" + be[0]
		b.pressed.connect(func():
			backend = be[0]
			_refresh_title_buttons())
		row2.add_child(b)
	var row3 := HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row3)
	var lab3 := Label.new()
	lab3.text = Loc.t("he_is")
	row3.add_child(lab3)
	for df in [["gentle", Loc.t("diff_gentle")], ["normal", Loc.t("diff_normal")], ["hard", Loc.t("diff_hard")]]:
		var b := Button.new()
		b.text = df[1]
		b.toggle_mode = true
		b.name = "diff_" + df[0]
		b.pressed.connect(func():
			difficulty = df[0]
			_refresh_title_buttons())
		row3.add_child(b)
	var row4 := HBoxContainer.new()
	row4.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row4)
	var lab4 := Label.new()
	lab4.text = Loc.t("plan")
	row4.add_child(lab4)
	for pm in [[false, Loc.t("plan_full")], [true, Loc.t("plan_explore")]]:
		var b := Button.new()
		b.text = pm[1]
		b.toggle_mode = true
		b.name = "plan_" + ("explore" if pm[0] else "full")
		b.pressed.connect(func():
			explore_mode = pm[0]
			_refresh_title_buttons())
		row4.add_child(b)
	var rb := CheckButton.new()
	rb.text = Loc.t("rearranged")
	rb.tooltip_text = Loc.t("rearranged_tip")
	rb.button_pressed = rearranged
	rb.toggled.connect(func(v): rearranged = v)
	row4.add_child(rb)
	var hb := CheckButton.new()
	hb.name = "hints_toggle"
	hb.text = Loc.t("hints")
	hb.button_pressed = hints_on
	hb.toggled.connect(func(v): hints_on = v)
	row4.add_child(hb)
	var row5 := HBoxContainer.new()
	row5.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row5)
	var lab5 := Label.new()
	lab5.text = Loc.t("lang")
	row5.add_child(lab5)
	for lg in [["en", "English"], ["cs", "Čeština"]]:
		var b := Button.new()
		b.text = lg[1]
		b.toggle_mode = true
		b.button_pressed = Loc.lang == lg[0]
		b.pressed.connect(func(): _set_lang(lg[0]))
		row5.add_child(b)
	var start := Button.new()
	start.text = Loc.t("start")
	start.custom_minimum_size = Vector2(260, 44)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_start_game)
	v.add_child(start)
	_refresh_title_buttons()


func _set_lang(lg: String) -> void:
	Loc.lang = lg
	_save_settings()
	# Rebuild the menus in the new language.
	for layer in [title_layer, over_layer, pause_layer]:
		remove_child(layer)
		layer.queue_free()
	over_panel = null
	_build_title()
	_build_over()
	_build_pause()
	header_label.text = Loc.t("header")
	_apply_style()
	_show_title()


func _refresh_title_buttons() -> void:
	for n in title_layer.find_children("style_*", "Button", true, false):
		n.button_pressed = n.name == "style_" + Style.current
	for n in title_layer.find_children("backend_*", "Button", true, false):
		n.button_pressed = n.name == "backend_" + backend
	for n in title_layer.find_children("diff_*", "Button", true, false):
		n.button_pressed = n.name == "diff_" + difficulty
	for n in title_layer.find_children("plan_*", "Button", true, false):
		n.button_pressed = n.name == ("plan_explore" if explore_mode else "plan_full")


func _build_over() -> void:
	over_layer = CanvasLayer.new()
	over_layer.layer = 11
	over_layer.visible = false
	add_child(over_layer)
	# Right-hand panel: the plan on the left stays visible for the reveal.
	var panel := PanelContainer.new()
	over_panel = panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -616
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = -16
	over_layer.add_child(panel)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	over_text = RichTextLabel.new()
	over_text.bbcode_enabled = true
	over_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	over_text.scroll_following = false
	v.add_child(over_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var peek := Button.new()
	peek_btn = peek
	peek.text = Loc.t("peek")
	peek.toggle_mode = true
	peek.toggled.connect(func(on):
		over_text.visible = not on
		over_panel.self_modulate.a = 0.0 if on else 1.0)
	row.add_child(peek)
	var again := Button.new()
	again.text = Loc.t("again")
	again.pressed.connect(_start_game)
	row.add_child(again)
	var menu := Button.new()
	menu.text = Loc.t("to_title")
	menu.pressed.connect(_show_title)
	row.add_child(menu)


func _build_pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 12
	pause_layer.visible = false
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	pause_layer.add_child(dim)
	var v := _panel_box(pause_layer, Vector2(360, 0))
	var l := Label.new()
	l.text = Loc.t("hold")
	l.add_theme_font_size_override("font_size", 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var hint := Label.new()
	hint.text = Loc.t("hold_sub")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	for b in [[Loc.t("resume"), func(): _set_paused(false)], [Loc.t("next_look"), func():
			Style.next_style()
			_apply_style()], [Loc.t("quit_title"), func():
			_set_paused(false)
			_show_title()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		v.add_child(btn)


func _set_paused(on: bool) -> void:
	paused = on and running
	pause_layer.visible = paused


# ---------------------------------------------------------------- style

func _apply_style() -> void:
	bg.color = Style.c("bg")
	var th := Theme.new()
	var font := SystemFont.new()
	if Style.c("mono"):
		font.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "Courier New", "monospace"])
	else:
		font.font_names = PackedStringArray(["DejaVu Serif", "Liberation Serif", "Noto Serif", "Georgia", "serif"])
	th.default_font = font
	th.default_font_size = 15
	var text: Color = Style.c("text")
	var accent: Color = Style.c("accent")
	var dim: Color = Style.c("dim")
	for cls in ["Label", "Button", "LineEdit", "CheckButton", "RichTextLabel"]:
		th.set_color("font_color", cls, text)
	th.set_color("default_color", "RichTextLabel", text)
	th.set_color("font_hover_color", "Button", accent)
	th.set_color("font_pressed_color", "Button", accent)
	th.set_color("font_disabled_color", "Button", dim)
	th.set_color("font_placeholder_color", "LineEdit", dim)
	th.set_color("caret_color", "LineEdit", accent)
	th.set_color("font_hover_color", "CheckButton", accent)
	th.set_color("font_pressed_color", "CheckButton", accent)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Style.c("panel")
	panel.border_color = Style.c("panel_line")
	panel.set_border_width_all(1)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(text, 0.06)
	btn.border_color = Color(text, 0.35)
	btn.set_border_width_all(1)
	btn.set_content_margin_all(6)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	var hov := btn.duplicate()
	hov.border_color = accent
	hov.bg_color = Color(accent, 0.12)
	var prs := btn.duplicate()
	prs.bg_color = Color(accent, 0.25)
	prs.border_color = accent
	var dis := btn.duplicate()
	dis.border_color = Color(text, 0.12)
	dis.bg_color = Color(text, 0.02)
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", hov)
	th.set_stylebox("pressed", "Button", prs)
	th.set_stylebox("hover_pressed", "Button", prs)
	th.set_stylebox("disabled", "Button", dis)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var le := btn.duplicate()
	le.bg_color = Color(text, 0.04)
	var lef := le.duplicate()
	lef.border_color = accent
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_stylebox("read_only", "LineEdit", dis)
	var pb := StyleBoxFlat.new()
	pb.bg_color = accent
	th.set_stylebox("fill", "ProgressBar", pb)
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(text, 0.1)
	th.set_stylebox("background", "ProgressBar", pbg)
	ui.theme = th
	for layer in [title_layer, over_layer, pause_layer]:
		if layer:
			for c in layer.get_children():
				if c is Control:
					c.theme = th
	if over_panel:
		var solid := panel.duplicate()
		solid.bg_color = Color(Style.c("panel"), 1.0)
		over_panel.add_theme_stylebox_override("panel", solid)
	(post.material as ShaderMaterial).set_shader_parameter("mode", Style.c("post"))
	(post.material as ShaderMaterial).set_shader_parameter("danger_color", Style.c("danger"))
	if phone:
		phone._dirty = true
	_save_settings()


# ---------------------------------------------------------------- flow

func _show_title() -> void:
	running = false
	over_layer.visible = false
	title_layer.visible = true
	_refresh_title_buttons()


func _make_rescuer(g: Game):
	if backend == "mock":
		return MockRescuer.new(g)
	var r := LlmRescuer.new()
	r.game = g
	r.mode = backend
	r.cfg = cfg
	r.fallback = MockRescuer.new(g)
	add_child(r)
	return r


func _start_game() -> void:
	_save_settings()
	if game:
		game.dispose()
	game = Game.new()
	game.difficulty = difficulty
	game.explore_mode = explore_mode
	game.rearranged = rearranged
	game.setup(randi() % 100000)
	game.murderer.timer += 15.0  # let the call connect and her finish the intro
	game.rescuer = _make_rescuer(game)
	game.event.connect(_on_game_event)
	plan.bind(game)
	cord.game = game
	plan.explore_mode = explore_mode
	phone.hints = hints_on
	phone._hinted.clear()
	phone.bind(game)
	room_panel.bind(game)
	sfx.bind(game)
	title_layer.visible = false
	over_layer.visible = false
	running = true
	var r: Dictionary = game.house.rooms[game.player_room]
	phone.add_line("narr", Loc.t("start_narr", [game.house.room_in(game.player_room)]))
	for o in r.objects:
		if o.has("memory"):
			phone.add_line("memory", game.house.obj_memory(o.id))
	phone.hint("start")
	_intro_queue = INTRO[Loc.lang].duplicate()
	_intro_t = 4.6
	sfx.ring_in()
	phone.add_line("sound", Loc.t("ringing"))
	if backend != "mock":
		phone.add_line("sound", Loc.t("her_voice_line", [Loc.t("be_" + backend)]))


func _on_game_event(t: String, d: Dictionary) -> void:
	if t == "game_over" and _soak_left > 0:
		_soak_stats[game.end_reason] = _soak_stats.get(game.end_reason, 0) + 1
		_soak_left -= 1
		print("soak: %s lang=%s style=%s diff=%s explore=%s t=%.0f" % [game.end_reason, Loc.lang, Style.current, difficulty, explore_mode, game.time])
		if _soak_left == 0:
			print("soak done: ", _soak_stats)
			get_tree().quit()
			return
		get_tree().create_timer(0.5).timeout.connect(func():
			Style.current = Style.ORDER.pick_random()
			Loc.lang = ["en", "cs"].pick_random()
			difficulty = ["gentle", "normal", "hard"].pick_random()
			explore_mode = randf() < 0.5
			_apply_style()
			_start_game()
			_attach_bot())
		return
	if t == "game_over":
		running = false
		var ended := game
		var c: Color = Color(1, 0.97, 0.9) if d.won else Style.c("danger")
		flash.color = Color(c, 0.0)
		var tw := create_tween()
		tw.tween_property(flash, "color:a", 0.85 if d.won else 0.6, 0.25)
		tw.tween_property(flash, "color:a", 0.0, 1.3)
		phone.add_line("narr" if d.won else "danger", Loc.t("outro_won") if d.won else Loc.t("outro_" + d.reason))
		get_tree().create_timer(1.6).timeout.connect(func():
			if game == ended and not title_layer.visible:
				_show_over())
	elif t == "murderer_log" and plan.show_debug:
		phone.add_line("sound", "☠ " + d.text)


func _on_room_clicked(r: String, sneak: bool) -> void:
	if game and running:
		game.move_to(r, sneak or room_panel.sneak)


func _show_over() -> void:
	var g := game
	var h := g.house
	var dc: String = (Style.c("danger") as Color).to_html(false)
	var ac: String = (Style.c("accent") as Color).to_html(false)
	var dm: String = (Style.c("dim") as Color).to_html(false)
	var col := ac if g.won else dc
	var t := "[color=#%s][font_size=34]%s[/font_size][/color]\n" % [col, Loc.t("end_" + g.end_reason)]
	t += Loc.t("end_way", [h.obj_name(g.exit_obj), h.room_name(g.exit_room), h.exit_flavor(g.exit_obj)]) + "\n"
	t += "[color=#%s]%s[/color]\n\n" % [dm, Loc.t("end_time", [int(g.time) / 60, int(g.time) % 60])]
	t += Loc.t("notebook") + "\n"
	for e in g.murderer.log:
		t += "[color=#%s]%d:%02d[/color]  %s\n" % [dm, int(e.t) / 60, int(e.t) % 60, str(e.text).replace("[", "[lb]")]
	if g.murderer.log.is_empty():
		t += Loc.t("notebook_empty") + "\n"
	over_text.text = t
	over_layer.visible = true
	peek_btn.set_pressed_no_signal(false)
	over_text.visible = true
	over_panel.self_modulate.a = 1.0


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				if running and not over_layer.visible:
					_set_paused(not paused)
			KEY_F2:
				Style.next_style()
				_apply_style()
				_refresh_title_buttons()
			KEY_F3:
				plan.show_debug = not plan.show_debug
			KEY_F4:
				plan.show_guess = not plan.show_guess
			KEY_F11:
				var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(dt: float) -> void:
	var mat := post.material as ShaderMaterial
	phone.active = running and not paused
	sfx.active = running and not paused
	if not running or game == null or paused:
		mat.set_shader_parameter("danger", 0.0)
		mat.set_shader_parameter("hidden", 0.0)
		return
	if _intro_queue.size() > 0 and game.player_on_line():
		_intro_t -= dt
		if _intro_t <= 0.0 and not phone.lines.any(func(l): return l.shown < l.text.length()):
			var line: String = _intro_queue.pop_front()
			game.line_log.append({"who": "rescuer", "text": line})
			game.transcript.append({"t": game.time, "who": "rescuer", "text": line})
			phone.add_line("her", line, false)
			_intro_t = 0.6
			if _intro_queue.is_empty():
				phone.hint("first")
	game.tick(dt)
	var cursor := (" █" if int(game.time * 2.0) % 2 == 0 else "  ") if Style.current == "phosphor" else ""
	header_label.text = "%s     %s%s" % [Loc.t("header"), Loc.t("call_time", [int(game.time) / 60, int(game.time) % 60]), cursor]
	if autobot != null and not game.over:
		autobot.tick(dt)
	mat.set_shader_parameter("danger", sfx.danger)
	mat.set_shader_parameter("on_line", 1.0 if game.player_on_line() else 0.0)
	var hv: float = mat.get_shader_parameter("hidden") if mat.get_shader_parameter("hidden") != null else 0.0
	mat.set_shader_parameter("hidden", move_toward(hv, 1.0 if game.hidden else 0.0, dt * 2.0))
