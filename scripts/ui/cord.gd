class_name Cord
extends Control
## A coiled telephone cord from the handset in your room to the phone panel.
## Only drawn while you're on the line. Purely decorative, but it makes
## "you are on the line right now" impossible to miss.

var game: Game
var plan: PlanView
var phone: Control
var _t := 0.0
var _extend := 0.0   # 0..1, animates the cord in and out


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	var on := game != null and not game.over and game.player_on_line()
	_extend = move_toward(_extend, 1.0 if on else 0.0, dt * 3.0)
	queue_redraw()


func _draw() -> void:
	if game == null or plan == null or phone == null or _extend <= 0.01:
		return
	var r := plan._rect(game.player_room)
	var a := plan.get_global_rect().position + r.position + Vector2(r.size.x - 22, 26) - get_global_rect().position
	var pr := phone.get_global_rect()
	var b := pr.position + Vector2(0, 34) - get_global_rect().position
	b = a.lerp(b, _extend)
	var col: Color = Style.c("her")
	col.a = 0.5
	var loops := a.distance_to(b) / 11.0
	var n := int(loops * 12.0) + 16
	var dir := (b - a).normalized()
	var perp := dir.orthogonal()
	var pts := PackedVector2Array()
	var sag := a.distance_to(b) * 0.18
	for i in n + 1:
		var f := float(i) / n
		var base := a.lerp(b, f) + Vector2(0, sin(PI * f) * sag + sin(_t * 1.3 + f * 3.0) * 3.0 * sin(PI * f))
		var ang := f * loops * TAU
		var rad := 4.5 * minf(1.0, f * 6.0) * minf(1.0, (1.0 - f) * 6.0)
		pts.append(base + perp * sin(ang) * rad + dir * cos(ang) * rad * 0.6)
	draw_polyline(pts, col, 1.3, true)
