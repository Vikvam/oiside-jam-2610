extends SceneTree
## Text-mode playtest: reads commands from a file that grows (tail -f style),
## prints only what the PLAYER perceives. For balance testing by a human/agent.
##   godot --headless --path . -s tests/play_cli.gd -- <cmdfile> <seed> [difficulty]
## Commands (one per line):
##   say <text> | tap <n> | up | down | go <dir> [sneak] | hide | toggle <clock|fan|rain>
##   try <object id> | wait <secs> | look | quit
## Typing a message costs time (about 4 chars per second) before it is said.

var g: Game
var f: FileAccess
var path := ""
var pos := 0
var queue: Array = []
var wait_left := 0.0
var pending_say := ""
var say_delay := 0.0
var real_dt := 0.1
var think_time := 2.0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	path = a[0]
	if a.size() > 3:
		Loc.lang = a[3]
	g = Game.new()
	g.difficulty = a[2] if a.size() > 2 else "normal"
	g.rearranged = OS.get_environment("REARRANGE") != ""
	g.large = OS.get_environment("LARGE") != ""
	g.setup(int(a[1]))
	g.rescuer = MockRescuer.new(g)
	g.murderer.timer += 12.0
	for l in ["It's me. Don't say my name. Listen.", "There's a way out of the house. He doesn't know about it. I'll get you there.",
			"But every phone in that house is on one line. If he picks up an extension, he hears every word.",
			"So don't tell me where you are. Not straight out. One tap means yes, two taps mean no."]:
		g.line_log.append({"who": "rescuer", "text": l})
	g.event.connect(_on_event)
	_p("You are in the %s, receiver up. HER: (intro: there's a way out; he can listen on any extension; 1 tap yes, 2 no)" % g.house.rooms[g.player_room].name)
	_look()


func _p(s: String) -> void:
	print("[%5.1f] %s" % [g.time, s])


func _look() -> void:
	var h := g.house
	var r: Dictionary = h.rooms[g.player_room]
	var doors := []
	for d in House.DIRS:
		if h.step(g.player_room, d) != "":
			doors.append("%s→%s" % [d, h.rooms[h.step(g.player_room, d)].name])
	var objs := []
	for o in r.objects:
		objs.append(o.id + ("(" + o.nick + ")" if o.has("nick") else ""))
	_p("ROOM %s | phone:%s receiver:%s hidden:%s | sounds now: %s | objects: %s | doors: %s | tries:%d raining:%s heating:%s" % [
		r.name, r.phone, g.receiver_up, g.hidden, g.player_active_features(), objs, doors, g.attempts_left, g.raining, g.heating])
	if g.player_on_line():
		_p("LINE extra sounds: %s" % [g.foreign_sounds()])


func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"rescuer_says": _p("HER: " + d.text)
		"murderer_says": _p("??? (male voice): " + d.text)
		"imposter_says": _p("HER(?) [no crackle before, slightly low]: " + d.text)
		"line_click": _p("!! " + d.text)
		"line_breath": _p("!! breathing on the line")
		"line_quiet_presence": _p("!! the line sounds open, someone already listening")
		"line_background": _p("!! through the receiver (not yours): %s" % [d.features])
		"line_fake_tell": _p("!! line still sounds too full")
		"footsteps": _p("!! %s footsteps %s dist %d via %s door" % ["RUNNING" if d.running else "heavy", "SETTING OFF" if d.get("leaving", false) else "arriving", d.dist, d.dir])
		"murderer_in_room": _p("!!! HE IS IN YOUR ROOM")
		"presence": _p("!! someone standing behind the %s door" % d.dir)
		"player_arrive":
			_p("arrived %s" % g.house.rooms[d.room].name)
			_look()
		"exit_try": _p("exit try %s: %s (left %d)" % [d.obj, d.ok, d.attempts_left])
		"weather": _p("rain: %s" % d.raining)
		"heating": pass
		"clock_strike": _p("clocks strike")
		"murderer_found_exit": _p("!! far off: wood splintering, a pleased laugh")
		"game_over": _p("GAME OVER won=%s reason=%s" % [d.won, d.reason])
		"hidden": _p("hidden: %s" % d.on)
		"feature_toggled": _p("toggled %s → %s" % [d.feature, d.on])


func _read_cmds() -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return
	var txt := fa.get_as_text()
	if txt.length() > pos:
		var chunk := txt.substr(pos)
		var nl := chunk.rfind("\n")
		if nl >= 0:
			pos += nl + 1
			for l in chunk.substr(0, nl).split("\n", false):
				queue.append(l.strip_edges())


func _exec(c: String) -> void:
	_p("> " + c)
	var parts := c.split(" ", false, 1)
	var cmd := parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	var ok := true
	match cmd:
		"say":
			pending_say = arg
			say_delay = arg.length() / 4.0
			wait_left = say_delay + 0.1
		"tap":
			for i in int(arg):
				g.tap()
			wait_left = 2.0
		"up": ok = g.pick_up(); wait_left = 1.0
		"down": ok = g.hang_up(); wait_left = 0.5
		"go":
			var ps := arg.split(" ")
			ok = g.move_to(g.house.step(g.player_room, ps[0]), ps.size() > 1)
			wait_left = 0.2
		"hide": ok = g.hide(); wait_left = 1.2
		"toggle": ok = g.toggle_feature(arg); wait_left = 2.2
		"try": ok = g.try_exit(arg); wait_left = 1.7
		"wait": wait_left = float(arg)
		"look": _look()
		"quit": quit()
	if not ok:
		_p("(couldn't do that)")
	if cmd != "look":
		wait_left += think_time  # a human needs a moment between actions


func _process(_delta: float) -> bool:
	if g.over:
		print("END. His notebook:")
		for e in g.murderer.log:
			print("   %5.1f %s" % [e.t, e.text])
		print("Exit was %s in %s" % [g.exit_obj, g.exit_room])
		return true
	if wait_left <= 0.0:
		_read_cmds()
		if queue.is_empty():
			OS.delay_msec(100)
			return false
		_exec(queue.pop_front())
	# Advance simulated time quickly.
	var steps := 0
	while wait_left > 0.0 and steps < 50 and not g.over:
		g.tick(real_dt)
		wait_left -= real_dt
		if pending_say != "":
			say_delay -= real_dt
			if say_delay <= 0.0:
				if not g.say(pending_say):
					_p("(couldn't say that — not on the line)")
				pending_say = ""
		steps += 1
	return false
