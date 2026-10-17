class_name LineScope
extends Control
## A little oscilloscope of the party line. Bright trace: what's on the line
## (hiss, voices, clicks). Danger-coloured trace: sounds that are NOT from your
## room — someone else's extension is open.

const N := 220

var game: Game
var line := PackedFloat32Array()
var foreign := PackedFloat32Array()
var _voice := 0.0
var _you := 0.0
var _click := 0.0
var _breath := 0.0
var _t := 0.0
var _acc := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 46)
	line.resize(N)
	foreign.resize(N)
	line.fill(0.0)
	foreign.fill(0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(g: Game) -> void:
	game = g
	g.event.connect(_on_event)


func voice() -> void:
	_voice = 1.0


func _on_event(t: String, _d: Dictionary) -> void:
	match t:
		"line_click", "receiver":
			_click = 1.0
		"player_says":
			_you = 1.0
		"player_tap":
			_click = 0.6
		"line_breath":
			_breath = 2.6


func _process(dt: float) -> void:
	_t += dt
	_acc += dt
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		_push()
	queue_redraw()


func _push() -> void:
	var on := game != null and game.player_on_line()
	var v := 0.0
	var f := 0.0
	if on:
		v = randf_range(-0.06, 0.06)
		if _voice > 0.0:
			v += sin(_t * 90.0) * randf_range(0.2, 0.7) * _voice
		if _you > 0.0:
			v += randf_range(-0.5, 0.5) * _you
		if _click > 0.0:
			v += (1.0 if int(_t * 120.0) % 2 == 0 else -1.0) * _click
		var fs: Array = game.foreign_sounds()
		for feat in fs:
			match feat:
				"clock":
					var ph := fmod(_t, 1.0)
					if ph < 0.04:
						f += 0.7 * (1.0 if int(_t * 200.0) % 2 == 0 else -1.0)
				"fan":
					f += sin(_t * 48.0) * 0.25
				"rain":
					f += randf_range(-0.3, 0.3)
				"radiator":
					if fmod(_t, 2.3) < 0.12:
						f += sin(_t * 70.0) * 0.6
		if _breath > 0.0:
			var env := sin(PI * clampf(1.0 - _breath / 2.6, 0.0, 1.0))
			f += randf_range(-0.5, 0.5) * env
	_voice = maxf(0.0, _voice - 1.0 / 60.0 * 6.0)
	_you = maxf(0.0, _you - 1.0 / 60.0 * 1.5)
	_click = maxf(0.0, _click - 1.0 / 60.0 * 8.0)
	_breath = maxf(0.0, _breath - 1.0 / 60.0)
	line.remove_at(0)
	line.append(clampf(v, -1.0, 1.0))
	foreign.remove_at(0)
	foreign.append(clampf(f, -1.0, 1.0))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var mid := h * 0.5
	var grid: Color = Style.c("panel_line")
	draw_rect(Rect2(Vector2.ZERO, size), Color(grid, 0.15))
	draw_line(Vector2(0, mid), Vector2(w, mid), Color(grid, 0.6), 1.0)
	for i in range(1, 8):
		var x := w * i / 8.0
		draw_line(Vector2(x, 2), Vector2(x, h - 2), Color(grid, 0.25), 1.0)
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in N:
		var x := w * i / float(N - 1)
		a.append(Vector2(x, mid - line[i] * mid * 0.85))
		b.append(Vector2(x, mid - foreign[i] * mid * 0.85))
	draw_polyline(b, Color(Style.c("danger"), 0.9), 1.5, true)
	draw_polyline(a, Style.c("her"), 1.5, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(6, 13), "LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Style.c("dim"))
