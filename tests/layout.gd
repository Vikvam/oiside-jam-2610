extends SceneTree
## Layout check: starts a game in the real scene and fails if any control
## that matters ends up outside the visible area.
##   godot --path . -s tests/layout.gd      (needs a window, not --headless)
## Runs EN/CS × classic/large house at 1280×720. With aspect "expand" the
## virtual screen is never smaller than that, so it's the worst case.

var m
var n := 0
var cases := [["en", false], ["cs", false], ["cs", true], ["en", true]]
var fails := 0


func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)


func _process(_dt: float) -> bool:
	n += 1
	var i := n / 20
	if i >= cases.size():
		print("layout %s: %s" % [root.get_visible_rect().size, "OK" if fails == 0 else "%d FAILURES" % fails])
		quit(1 if fails > 0 else 0)
		return true
	if n % 20 == 1:
		m.backend = "mock"
		m._set_lang(cases[i][0])
		m.large = cases[i][1]
		m._start_game()
		# The longest possible status and room panel content.
		m.game.hidden = false
	if n % 20 == 19:
		var vp := root.get_visible_rect()
		var checks := {
			"plan": m.plan, "room panel": m.room_panel, "objects": m.room_panel.objects_box,
			"actions": m.room_panel.actions_box, "house box": m.house_view, "phone": m.phone,
			"input": m.phone.input, "tap": m.phone.tap_btn, "hook": m.phone.hook_btn,
		}
		for k in checks:
			var c: Control = checks[k]
			var r := c.get_global_rect()
			if not vp.grow(0.5).encloses(r) or r.size.x < 2 or r.size.y < 2:
				fails += 1
				print("FAIL %s %s: %s outside %s" % [cases[i][0], "large" if cases[i][1] else "classic", k, r])
		var p: Control = m.plan
		print("  %s %s: plan %dx%d (U=%.0f) room panel h=%d" % [cases[i][0], "large" if cases[i][1] else "classic", p.size.x, p.size.y, p.U, m.room_panel.size.y])
	return false
