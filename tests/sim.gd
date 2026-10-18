extends SceneTree
## Headless balance simulation: bot player + mock rescuer vs the murderer.
## Run:  godot --headless --path . -s tests/sim.gd -- [games] [policy] [verbose]
## policy: follow (listens to rescuer), careful (also hides from clicks), random

var stats := {}
var diff := "normal"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 200
	var policy: String = args[1] if args.size() > 1 else "careful"
	var verbose := args.size() > 2 and args[2] == "v"
	diff = args[3] if args.size() > 3 else "normal"
	var times := []
	for i in n:
		var r := _play(i, policy, verbose and i < 3)
		stats[r.reason] = stats.get(r.reason, 0) + 1
		times.append(r.t)
	times.sort()
	print("policy=%s games=%d  %s  median_t=%.0fs" % [policy, n, stats, times[times.size() / 2]])
	quit()


func _play(seed_value: int, policy: String, verbose: bool) -> Dictionary:
	var g := Game.new()
	g.difficulty = diff
	g.rearranged = OS.get_environment("REARRANGE") != ""
	g.large = OS.get_environment("LARGE") != ""
	g.setup(seed_value)
	g.rescuer = MockRescuer.new(g)
	var bot := Bot.new(g, policy)
	if verbose:
		print("--- game %d: start %s, exit %s/%s, murderer %s" % [seed_value, g.player_room, g.exit_room, g.exit_obj, g.murderer.room])
		g.event.connect(func(t, d):
			if t in ["murderer_log", "rescuer_says", "player_says", "player_arrive", "line_click", "footsteps", "exit_try", "game_over"]:
				print("  %6.1f %-14s %s" % [g.time, t, d]))
	g.event.connect(bot.on_event)
	var dt := 0.1
	while not g.over and g.time < 900.0:
		g.tick(dt)
		bot.tick(dt)
	var reason: String = g.end_reason if g.over else "timeout"
	if g.murderer.exit_known != "":
		stats["exit_found"] = stats.get("exit_found", 0) + 1
	if reason in ["caught", "walked_in"]:
		reason += ":" + g.murderer.goal
		if OS.get_environment("WHY") != "" and g.murderer.goal == "hunt":
			for e in g.murderer.log.slice(-4):
				if "→" in e.text:
					print("WHY ", e.text.split("→")[0].split("'")[0].left(40))
	g.dispose()
	return {"reason": reason, "t": g.time}


class Bot:
	var g
	var policy := ""
	var think := 1.0
	var steps: Array = []   # compass doors she told us to take, in order
	var target := ""        # a room she pointed at by nickname
	var want_obj := ""      # what she told us to search
	var hiding := 0.0
	var spoke_in := ""
	var danger_room := ""
	var danger_t := 0.0
	var arrived_t := -100.0
	var he_is_here := false

	const REL := {"straight ahead": "straight", "on your left": "left", "on your right": "right", "you came in by": "back"}

	func _init(game, p: String) -> void:
		g = game
		policy = p

	## Her directions in the order she said them, as compass doors. Turns are
	## read from the way we'll be facing at that point.
	func _parse_steps(txt: String) -> Array:
		var low := txt.to_lower()
		var marks := []
		for d in House.DIRS:
			var at := low.find("the %s door" % d)
			while at != -1:
				marks.append([at, "c", d])
				at = low.find("the %s door" % d, at + 1)
		for k in REL:
			var at := low.find(k)
			while at != -1:
				marks.append([at, "r", REL[k]])
				at = low.find(k, at + 1)
		marks.sort_custom(func(a, b): return a[0] < b[0])
		var out := []
		var facing: String = g.facing
		for m in marks:
			var d: String = m[2] if m[1] == "c" else House.absolute(facing, m[2])
			out.append(d)
			facing = d
		return out

	func on_event(t: String, d: Dictionary) -> void:
		match t:
			"rescuer_says":
				_heard_her(d.text)
			"player_arrive":
				arrived_t = g.time
			"murderer_in_room":
				he_is_here = true
				hiding = maxf(hiding, 3.0)
			"murderer_left", "slipped_out":
				he_is_here = false
			"backed_out":
				# He saw us. Out another door, or hide.
				steps = []
				danger_room = g.house.step(g.player_room, d.dir)
				danger_t = 12.0
				var opts: Array = g.house.neighbors(g.player_room).filter(func(n): return n != danger_room)
				if not opts.is_empty() and policy != "follow":
					g.move_to(opts[randi() % opts.size()], false)
				else:
					g.hide()
					hiding = 10.0
			"presence":
				danger_room = g.house.step(g.player_room, d.dir)
				danger_t = 10.0
			"murderer_searching":
				# Slip out through another door than his.
				var opts: Array = g.house.neighbors(g.player_room).filter(func(n): return n != g._search_from)
				if not opts.is_empty() and policy != "silent":
					g.move_to(opts[randi() % opts.size()], policy == "smart")
			"line_click":
				if policy in ["careful", "smart"] and d.kind == "pickup":
					hiding = randf_range(6.0, 12.0)
			"line_quiet_presence", "line_breath", "line_fake_tell":
				if policy == "smart":
					hiding = randf_range(8.0, 14.0)
			"footsteps":
				danger_room = d.room if d.dist == 1 else g.house.step(g.player_room, d.dir)
				danger_t = 8.0
				if d.dist == 1 and policy == "smart":
					g.hide()
					hiding = randf_range(8.0, 12.0)
				elif d.dist == 1 and policy != "random":
					var opts := []
					for n in g.house.neighbors(g.player_room):
						if n != d.room:
							opts.append(n)
					if not opts.is_empty():
						g.move_to(opts[randi() % opts.size()])

	func _heard_her(txt: String) -> void:
		if policy == "random":
			var dirs := Words.directions(txt)
			if not dirs.is_empty():
				steps = [dirs[0]]
			return
		var low := txt.to_lower()
		if low.contains("one tap yes") or low.contains("tap once for yes"):
			var yes: bool = g.time - arrived_t < 12.0  # "did you just come through a door?"
			for f in House.FEATURES:
				var word: String = {"clock": "clock", "fan": "fan", "rain": "window", "radiator": "radiator"}[f]
				if low.contains(word):
					yes = g.house.has_feature(g.player_room, f)
			g.tap()
			if not yes:
				g.tap()
		if low.contains("right behind") or low.contains("just past"):
			var ds := _parse_steps(txt)
			if not ds.is_empty():
				danger_room = g.house.step(g.player_room, ds[0])
				danger_t = 12.0
			steps = []
			return
		if low.contains("hide") or low.contains("don't move"):
			if policy != "follow":
				g.hide()
				hiding = randf_range(8.0, 14.0)
			steps = []
			return
		var parsed := _parse_steps(txt)
		if not parsed.is_empty():
			steps = parsed
		# "Go to Old Gregor": only useful if we've seen where he is.
		for nh in Words.nicknames_named(txt, g.house):
			if low.contains("go to") or low.contains("make for"):
				if g.visited.has(nh.room):
					target = nh.room
			elif low.contains("search") or low.contains("it's"):
				want_obj = nh.obj
		if low.contains("search"):
			for o in Words.objects_named(txt, g.house):
				want_obj = o.obj

	func tick(dt: float) -> void:
		think -= dt
		danger_t -= dt
		if policy == "silent":
			if not g.hidden and g.can_act():
				if g.receiver_up:
					g.hang_up()
				g.hide()
			return
		if he_is_here and g.hidden:
			return  # never come out while he's standing here
		if hiding > 0.0:
			hiding -= dt
			if g.receiver_up and policy == "careful":
				g.hang_up()
			if hiding <= 0.0:
				if g.hidden:
					g.unhide()
				if g.house.rooms[g.player_room].phone:
					g.pick_up()
					if policy == "smart" and not g.foreign_sounds().is_empty():
						hiding = randf_range(5.0, 9.0)
						return
					g.tap(); g.tap()
			return
		if policy == "smart" and g.receiver_up and not g.foreign_sounds().is_empty():
			hiding = randf_range(5.0, 9.0)
			return
		if think > 0.0 or not g.can_act():
			return
		think = randf_range(3.0, 6.0)
		if g.hidden:
			g.unhide()
			return
		if policy == "random":
			var ns: Array = g.house.neighbors(g.player_room)
			if randf() < 0.3:
				var objs: Array = g.house.rooms[g.player_room].objects
				g.try_exit(objs[randi() % objs.size()].id)
			else:
				g.move_to(ns[randi() % ns.size()])
			return
		if want_obj != "" and g.house.object_room.get(want_obj, "") == g.player_room:
			var o := want_obj
			want_obj = ""
			if g.try_exit(o):
				return
		var sneak: bool = policy == "smart" and danger_t > 0.0
		if not steps.is_empty():
			var to: String = g.house.step(g.player_room, steps[0])
			steps.pop_front()
			if to != "" and not (to == danger_room and danger_t > 0.0):
				g.move_to(to, sneak)
				return
			steps = []
		if target != "" and target != g.player_room:
			var p: Array = g.house.path(g.player_room, target)
			if not p.is_empty() and not (p[0] == danger_room and danger_t > 0.0):
				g.move_to(p[0], sneak)
				return
		target = ""
		var here: Dictionary = g.house.rooms[g.player_room]
		if not here.phone:
			var ns: Array = g.house.neighbors(g.player_room)
			if danger_t > 0.0:
				ns = ns.filter(func(x): return x != danger_room)
				if ns.is_empty():
					return
			var phones := ns.filter(func(x): return g.house.rooms[x].phone)
			var pool: Array = phones if not phones.is_empty() else ns
			g.move_to(pool[randi() % pool.size()])
			return
		if policy == "smart":
			var st: Dictionary = g.room_state[g.player_room]
			for f in ["clock", "fan"]:
				if st[f]:
					g.toggle_feature(f)
					return
			if st.window and g.raining:
				g.toggle_feature("rain")
				return
		if not g.receiver_up:
			g.pick_up()
			return
		if spoke_in != g.player_room and not g.rescuer_pending:
			spoke_in = g.player_room
			var nick := ""
			for o in here.objects:
				if o.has("nick"):
					nick = o.nick
			if nick != "" and policy in ["careful", "smart"]:
				g.say("I'm next to %s." % nick)
			else:
				var o: Dictionary = here.objects[randi() % here.objects.size()]
				g.say("I can see a %s." % o.name)
