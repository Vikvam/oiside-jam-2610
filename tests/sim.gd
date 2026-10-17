extends SceneTree
## Headless balance simulation: bot player + mock rescuer vs the murderer.
## Run:  godot --headless --path . -s tests/sim.gd -- [games] [policy] [verbose]
## policy: follow (listens to rescuer), careful (also hides from clicks), random

var stats := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 200
	var policy: String = args[1] if args.size() > 1 else "careful"
	var verbose := args.size() > 2
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
	return {"reason": g.end_reason if g.over else "timeout", "t": g.time}


class Bot:
	var g
	var policy := ""
	var think := 1.0
	var plan_dir := ""
	var plan_obj := ""
	var hiding := 0.0
	var spoke_in := ""

	func _init(game, p: String) -> void:
		g = game
		policy = p

	func on_event(t: String, d: Dictionary) -> void:
		match t:
			"rescuer_says":
				var txt: String = d.text
				var dirs := Words.directions(txt)
				if not dirs.is_empty():
					plan_dir = dirs[0]
				var hits: Array = Words.nicknames_named(txt, g.house)
				if hits.is_empty():
					hits = Words.objects_named(txt, g.house, {g.player_room: true})
				for h in hits:
					if h.room == g.player_room:
						plan_obj = h.obj
			"line_click":
				if policy == "careful" and d.kind == "pickup":
					hiding = randf_range(6.0, 12.0)
			"footsteps":
				if d.dist == 1 and policy != "random":
					var opts := []
					for n in g.house.neighbors(g.player_room):
						if n != d.room:
							opts.append(n)
					if not opts.is_empty():
						g.move_to(opts[randi() % opts.size()])

	func tick(dt: float) -> void:
		think -= dt
		if hiding > 0.0:
			hiding -= dt
			if g.receiver_up and policy == "careful":
				g.hang_up()
			if hiding <= 0.0 and g.house.rooms[g.player_room].phone:
				g.pick_up()
				g.tap(); g.tap()
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
		if plan_dir != "":
			var to: String = g.house.step(g.player_room, plan_dir)
			plan_dir = ""
			if to != "":
				g.move_to(to)
				return
		var here: Dictionary = g.house.rooms[g.player_room]
		if not here.phone:
			var ns: Array = g.house.neighbors(g.player_room)
			var phones := ns.filter(func(x): return g.house.rooms[x].phone)
			var pool: Array = phones if not phones.is_empty() else ns
			g.move_to(pool[randi() % pool.size()])
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
			if nick != "" and policy == "careful":
				g.say("I'm next to %s." % nick)
			else:
				var o: Dictionary = here.objects[randi() % here.objects.size()]
				g.say("I can see a %s." % o.name)
