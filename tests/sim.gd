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
	var plan_dir := ""
	var plan_obj := ""
	var hiding := 0.0
	var spoke_in := ""
	var danger_room := ""
	var danger_t := 0.0
	var line_hot := 0.0
	var target := ""        # room the riddle points to
	var target_obj := ""    # what to search there
	var riddle_nick := ""   # nickname object she named; its room is unknown until seen
	var riddle_text := ""

	func _init(game, p: String) -> void:
		g = game
		policy = p

	func on_event(t: String, d: Dictionary) -> void:
		match t:
			"rescuer_says":
				var txt: String = d.text
				if txt.contains("One tap yes") or txt.contains("Tap once for yes"):
					g.tap()
				var dirs := Words.directions(txt)
				if not dirs.is_empty():
					plan_dir = dirs[0]
				var nh: Array = Words.nicknames_named(txt, g.house)
				if riddle_nick == "" and target == "" and not nh.is_empty() and policy != "random":
					riddle_nick = nh[0].obj
					riddle_text = txt
					_resolve_riddle()
				var hits: Array = nh
				if hits.is_empty():
					hits = Words.objects_named(txt, g.house, {g.player_room: true})
				for h in hits:
					if h.room == g.player_room:
						plan_obj = h.obj
			"presence":
				danger_room = g.house.step(g.player_room, d.dir)
				danger_t = 10.0
			"murderer_searching":
				# Slip out through another door than his.
				var opts: Array = g.house.neighbors(g.player_room).filter(func(n): return n != g._search_from)
				if not opts.is_empty() and policy != "silent":
					g.move_to(opts[randi() % opts.size()], false)
			"line_click":
				if policy in ["careful", "smart"] and d.kind == "pickup":
					hiding = randf_range(6.0, 12.0)
			"line_quiet_presence", "line_breath", "line_fake_tell":
				if policy == "smart":
					hiding = randf_range(8.0, 14.0)
			"footsteps":
				danger_room = d.room if d.dist == 1 else g.house.step(g.player_room, d.dir)
				danger_t = 8.0
				if d.dist >= 2 and policy == "smart" and g.can_act() and (d.running or d.dist == 2):
					var bad: String = g.house.step(g.player_room, d.dir)
					danger_room = bad
					var opts := []
					for n in g.house.neighbors(g.player_room):
						if n != bad and g.house.neighbors(n).size() > 1:
							opts.append(n)
					if not opts.is_empty():
						g.move_to(opts[randi() % opts.size()], false)
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

	## The player only knows a nickname's room once they've been in it.
	func _resolve_riddle() -> void:
		if riddle_nick == "":
			return
		var at: String = g.house.object_room[riddle_nick]
		if not g.visited.has(at):
			return
		# Seen it and it was moved? Then it's the room it used to be in.
		target = g.house.home_room[riddle_nick] if g.house.was_moved(riddle_nick) else at
		target_obj = riddle_nick
		for oh in Words.objects_named(riddle_text, g.house):
			if g.house.home_room[oh.obj] == target:
				target_obj = oh.obj
		riddle_nick = ""

	func tick(dt: float) -> void:
		think -= dt
		_resolve_riddle()
		danger_t -= dt
		if policy == "silent":
			if not g.hidden and g.can_act():
				if g.receiver_up:
					g.hang_up()
				g.hide()
			return
		if hiding > 0.0:
			hiding -= dt
			if g.receiver_up and policy == "careful":
				g.hang_up()
			if hiding <= 0.0 and g.house.rooms[g.player_room].phone:
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
		if policy == "random":
			var ns: Array = g.house.neighbors(g.player_room)
			if randf() < 0.3:
				var objs: Array = g.house.rooms[g.player_room].objects
				g.try_exit(objs[randi() % objs.size()].id)
			else:
				g.move_to(ns[randi() % ns.size()])
			return
		if plan_obj != "":
			var o := plan_obj
			plan_obj = ""
			if g.try_exit(o):
				return
		if riddle_nick != "" and target == "":
			# Explore: the nearest room not seen yet.
			var best := ""
			var bd := 99
			for r in g.house.room_ids:
				if not g.visited.has(r) and g.house.distance(g.player_room, r) < bd:
					bd = g.house.distance(g.player_room, r)
					best = r
			if best != "":
				var p0: Array = g.house.path(g.player_room, best)
				if not p0.is_empty() and not (policy == "smart" and p0[0] == danger_room and danger_t > 0.0):
					g.move_to(p0[0], policy == "smart" and danger_t > 0.0)
					return
		if target != "":
			if g.player_room == target:
				var o2 := target_obj
				target = ""
				if g.house.object_room.get(o2, "") == g.player_room and g.try_exit(o2):
					return
			else:
				var p: Array = g.house.path(g.player_room, target)
				if not p.is_empty() and not (policy == "smart" and p[0] == danger_room and danger_t > 0.0):
					g.move_to(p[0], policy == "smart" and danger_t > 0.0)
					return
		if plan_dir != "":
			var to: String = g.house.step(g.player_room, plan_dir)
			plan_dir = ""
			if to != "" and not (policy == "smart" and to == danger_room and danger_t > 0.0):
				g.move_to(to, policy == "smart" and danger_t > 0.0)
				return
		var here: Dictionary = g.house.rooms[g.player_room]
		if not here.phone:
			var ns: Array = g.house.neighbors(g.player_room)
			if policy == "smart" and danger_t > 0.0:
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
