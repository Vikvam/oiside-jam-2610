class_name PlanView
extends Control
## Procedurally drawn floor plan. Click an adjacent room to walk there,
## shift-click to sneak.

signal room_clicked(room: String, sneak: bool)

const U := 52.0           # pixels per plan unit
const DOOR_W := 0.9

var game: Game
var show_debug := false
var show_guess := true
var guess := ""
var hover := ""
var ripples: Array = []   # {pos, t, col, r}
var _boil := 0
var _t := 0.0
var _walk_from := Vector2.ZERO
var _walk_door := Vector2.ZERO
var _walk_to := Vector2.ZERO
var _walk_t := 0.0
var _walk_dur := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(12 * U, 9 * U) + Vector2(8, 8)
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(g: Game) -> void:
	game = g
	guess = ""
	ripples.clear()
	g.event.connect(_on_event)


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"player_move_start":
			_walk_from = _c(d.from)
			_walk_to = _c(d.to)
			_walk_door = _door_point(d.from, d.to)
			_walk_t = 0.0
			_walk_dur = d.dur
		"footsteps":
			var col: Color = Style.c("danger")
			if d.dist == 1:
				ripple(_c(d.room), col, 1.0)
			else:
				# Only the direction is known: ripple at the door on that side.
				var to := game.house.step(game.player_room, d.dir)
				var at := _door_point(game.player_room, to) if to != "" else _c(game.player_room)
				ripple(at, col, 0.9 if d.dist == 2 else 0.5, (2.4 if d.dist == 2 else 1.6) * U)
		"exit_try":
			if not d.ok:
				ripple(_c(game.player_room), Style.c("accent"), 1.0, 5.0 * U)
		"rescuer_says", "rescuer_guess":
			if d.get("guess", "") in game.house.rooms:
				guess = d.guess
		"clock_strike":
			for r in d.rooms:
				ripple(_c(r), Style.c("dim"), 0.35, 1.2 * U)


func ripple(pos: Vector2, col: Color, strength: float, radius := 2.2 * U) -> void:
	ripples.append({"pos": pos, "t": 0.0, "col": col, "s": strength, "r": radius})


func _process(dt: float) -> void:
	_t += dt
	_walk_t += dt
	var b := int(_t * 7.0)
	if b != _boil:
		_boil = b
	for r in ripples:
		r.t += dt
	ripples = ripples.filter(func(r): return r.t < 2.2)
	queue_redraw()


func _c(room: String) -> Vector2:
	return game.house.center(room) * U + Vector2(4, 4)


func _rect(room: String) -> Rect2:
	var r := game.house.rect(room)
	return Rect2(r.position * U + Vector2(4, 4), r.size * U)


func _door_point(a: String, b: String) -> Vector2:
	var ra := _rect(a)
	var rb := _rect(b)
	var i := ra.grow(1).intersection(rb.grow(1))
	return i.get_center()


func room_at(p: Vector2) -> String:
	if game == null:
		return ""
	for id in game.house.room_ids:
		if _rect(id).has_point(p):
			return id
	return ""


func _gui_input(e: InputEvent) -> void:
	if game == null:
		return
	if e is InputEventMouseMotion:
		hover = room_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var r := room_at(e.position)
		if r != "":
			room_clicked.emit(r, e.shift_pressed)


# ---------------------------------------------------------------- drawing helpers

func _noise(a: Vector2, k: int) -> float:
	var h := sin(a.x * 12.9898 + a.y * 78.233 + float(k) * 37.719 + float(_boil) * 11.13) * 43758.5453
	return (h - floor(h)) * 2.0 - 1.0


func wline(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var wob: float = Style.c("wobble")
	if wob <= 0.0:
		draw_line(a, b, col, w, true)
		return
	var n := maxi(2, int(a.distance_to(b) / 14.0))
	var perp := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var f := float(i) / n
		var p := a.lerp(b, f)
		var amp := wob * (1.0 if (i > 0 and i < n) else 0.4)
		pts.append(p + perp * _noise(p, i) * amp)
	draw_polyline(pts, col, w, true)


func wcircle(p: Vector2, r: float, col: Color, w := 1.5, filled := false) -> void:
	var wob: float = Style.c("wobble")
	var n := 18
	var pts := PackedVector2Array()
	for i in n + 1:
		var ang := TAU * i / n
		var rr := r + (_noise(p, i % n) * wob * 0.6 if wob > 0.0 else 0.0)
		pts.append(p + Vector2(cos(ang), sin(ang)) * rr)
	if filled:
		draw_colored_polygon(pts, col)
	else:
		draw_polyline(pts, col, w, true)


# ---------------------------------------------------------------- draw

func _draw() -> void:
	if game == null:
		return
	var h := game.house
	var wall: Color = Style.c("wall")
	var dim: Color = Style.c("dim")
	var grid: Color = Style.c("grid")
	var size_px := Vector2(12 * U, 9 * U)
	if Style.c("grid_on"):
		var step := U * 0.5
		var x := 4.0
		while x <= size_px.x + 4.0:
			draw_line(Vector2(x, 4), Vector2(x, size_px.y + 4), grid, 1.0)
			x += step
		var y := 4.0
		while y <= size_px.y + 4.0:
			draw_line(Vector2(4, y), Vector2(size_px.x + 4, y), grid, 1.0)
			y += step
	var reachable := []
	if game.can_act():
		reachable = h.neighbors(game.player_room)
	# Fills
	for id in h.room_ids:
		var rc := _rect(id)
		var fill: Color = Style.c("visited_fill") if game.visited.has(id) else Style.c("room_fill")
		if show_debug and game.murderer.candidates.has(id):
			fill = fill.lerp(Style.c("danger"), 0.18)
		if id == hover and id in reachable:
			fill = fill.lerp(Style.c("accent"), 0.15)
		draw_rect(rc.grow(-2), fill)
	# Guess
	if show_guess and guess != "" and not game.over:
		var gr := _rect(guess).grow(-9)
		var col: Color = Style.c("her")
		col.a = 0.55
		_dashed_rect(gr, col)
	# Walls with door gaps
	var ww: float = Style.c("wall_width")
	for id in h.room_ids:
		_draw_walls(id, wall, ww)
	# Labels + icons
	var font := get_theme_default_font()
	for id in h.room_ids:
		var rc := _rect(id)
		var name_col: Color = Style.c("text") if game.visited.has(id) else dim
		if id == game.player_room:
			name_col = Style.c("accent")
		draw_string(font, rc.position + Vector2(10, 22), h.rooms[id].name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_col)
		_draw_icons(id, rc)
		if h.rooms[id].phone:
			_icon_phone(rc.position + Vector2(rc.size.x - 22, 18), dim if id != game.player_room else Style.c("text"))
	# Compass
	_draw_compass(Vector2(size_px.x - 30, size_px.y - 34))
	# Ripples
	for r in ripples:
		var f: float = r.t / 2.2
		var col: Color = r.col
		col.a = (1.0 - f) * r.s
		wcircle(r.pos, 8.0 + f * r.r, col, 2.0)
		if f > 0.25:
			var col2 := col
			col2.a *= 0.5
			wcircle(r.pos, 8.0 + (f - 0.25) * r.r, col2, 1.5)
	# Murderer (debug)
	if show_debug:
		var mp := _c(game.murderer.room) + Vector2(0, 26)
		var dc: Color = Style.c("danger")
		draw_line(mp - Vector2(8, 8), mp + Vector2(8, 8), dc, 3.0)
		draw_line(mp - Vector2(8, -8), mp + Vector2(8, -8), dc, 3.0)
		draw_string(font, mp + Vector2(12, 5), Murderer.S.keys()[game.murderer.state], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dc)
		var er := _c(game.exit_room) + Vector2(-30, 26)
		draw_string(font, er, "EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Style.c("accent"))
	# Player
	var pp := _c(game.player_room)
	if game.moving_to != "":
		var f := clampf(_walk_t / _walk_dur, 0.0, 1.0)
		pp = _walk_from.lerp(_walk_door, f * 2.0) if f < 0.5 else _walk_door.lerp(_walk_to, (f - 0.5) * 2.0)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var yc: Color = Style.c("you")
	var halo := yc
	halo.a = 0.25 * pulse
	draw_circle(pp, 13.0 + pulse * 3.0, halo)
	wcircle(pp, 7.0, yc, 2.0, true)
	if game.receiver_up and game.player_on_line():
		var lc := yc
		lc.a = 0.6
		draw_arc(pp, 15.0, -PI * 0.8, -PI * 0.2, 12, lc, 1.5, true)
		draw_arc(pp, 20.0, -PI * 0.75, -PI * 0.25, 12, lc, 1.5, true)
	# Hover hint
	if hover != "" and hover in reachable:
		var hr := _rect(hover)
		draw_string(font, hr.position + Vector2(10, hr.size.y - 34), "walk · shift: sneak", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Style.c("accent"))


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 10.0)
		for k in range(0, n, 2):
			draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, 1.5)


func _draw_walls(id: String, col: Color, w: float) -> void:
	var rc := _rect(id)
	var corners := [rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y)]
	var gaps := []
	for n in game.house.neighbors(id):
		gaps.append(_door_point(id, n))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var segs := [[0.0, 1.0]]
		var len := a.distance_to(b)
		for g: Vector2 in gaps:
			# Project gap onto this edge.
			var ab := b - a
			var t: float = (g - a).dot(ab) / ab.length_squared()
			var proj: Vector2 = a + ab * t
			if proj.distance_to(g) < 4.0 and t > 0.0 and t < 1.0:
				var half := DOOR_W * U * 0.5 / len
				var nsegs := []
				for s in segs:
					if t - half > s[0]:
						nsegs.append([s[0], minf(s[1], t - half)])
					if t + half < s[1]:
						nsegs.append([maxf(s[0], t + half), s[1]])
				segs = nsegs
		for s in segs:
			wline(a.lerp(b, s[0]), a.lerp(b, s[1]), col, w)


func _draw_icons(id: String, rc: Rect2) -> void:
	var h := game.house
	var s: Dictionary = game.room_state[id]
	var x := rc.position.x + 16.0
	var y := rc.end.y - 18.0
	var on: Color = Style.c("text")
	var off: Color = Style.c("dim")
	off.a = 0.6
	for f in h.rooms[id].features:
		var active := true
		match f:
			"clock": active = s.clock
			"fan": active = s.fan
			"rain": active = s.window and game.raining
			"radiator": active = game.heating
		var col := on if active else off
		match f:
			"clock": _icon_clock(Vector2(x, y), col, active)
			"fan": _icon_fan(Vector2(x, y), col, active)
			"rain": _icon_window(Vector2(x, y), col, s.window, game.raining)
			"radiator": _icon_radiator(Vector2(x, y), col)
		if not active:
			draw_line(Vector2(x - 9, y + 9), Vector2(x + 9, y - 9), off, 1.5)
		x += 26.0


func _icon_clock(p: Vector2, col: Color, running: bool) -> void:
	wcircle(p, 8.0, col, 1.5)
	var a := _t * 2.0 if running else 0.7
	draw_line(p, p + Vector2(cos(a), sin(a)) * 6.0, col, 1.5)
	draw_line(p, p + Vector2(0, -4.5), col, 1.5)


func _icon_fan(p: Vector2, col: Color, running: bool) -> void:
	var a := _t * 9.0 if running else 0.0
	for i in 3:
		var ang := a + TAU * i / 3.0
		var tip := p + Vector2(cos(ang), sin(ang)) * 8.0
		var side := p + Vector2(cos(ang + 0.6), sin(ang + 0.6)) * 6.0
		draw_colored_polygon(PackedVector2Array([p, tip, side]), col)
	draw_circle(p, 1.8, Style.c("bg"))


func _icon_window(p: Vector2, col: Color, open: bool, raining: bool) -> void:
	var r := Rect2(p - Vector2(7, 8), Vector2(14, 16))
	wline(r.position, Vector2(r.end.x, r.position.y), col, 1.5)
	wline(Vector2(r.end.x, r.position.y), r.end, col, 1.5)
	wline(r.end, Vector2(r.position.x, r.end.y), col, 1.5)
	wline(Vector2(r.position.x, r.end.y), r.position, col, 1.5)
	draw_line(Vector2(p.x, r.position.y), Vector2(p.x, r.end.y), col, 1.0)
	if raining and open:
		for i in 3:
			var off := fmod(_t * 18.0 + i * 5.3, 16.0)
			var q := Vector2(r.position.x + 3 + i * 4, r.position.y + off)
			draw_line(q, q + Vector2(-1.5, 3), col, 1.0)


func _icon_radiator(p: Vector2, col: Color) -> void:
	for i in 4:
		var x := p.x - 7 + i * 4.6
		draw_line(Vector2(x, p.y - 7), Vector2(x, p.y + 7), col, 2.0)
	draw_line(Vector2(p.x - 8, p.y + 5), Vector2(p.x + 8, p.y + 5), col, 1.0)


func _icon_phone(p: Vector2, col: Color) -> void:
	# A chunky old handset: two ear cups and a handle.
	draw_line(p + Vector2(-8, 2), p + Vector2(8, 2), col, 3.0)
	draw_circle(p + Vector2(-8, 4), 3.2, col)
	draw_circle(p + Vector2(8, 4), 3.2, col)
	draw_rect(Rect2(p + Vector2(-5, 7), Vector2(10, 6)), col, false, 1.5)


func _draw_compass(p: Vector2) -> void:
	var col: Color = Style.c("dim")
	var font := get_theme_default_font()
	wline(p + Vector2(0, -16), p + Vector2(0, 16), col, 1.5)
	wline(p + Vector2(-16, 0), p + Vector2(16, 0), col, 1.5)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -20), p + Vector2(-4, -12), p + Vector2(4, -12)]), col)
	draw_string(font, p + Vector2(-4, -24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
