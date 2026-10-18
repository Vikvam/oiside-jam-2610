extends SceneTree
## One real-time game: smart bot player vs murderer, with the LLM rescuer via
## the local Haiku proxy. Capped at max_calls requests. Prints a transcript.
##   godot --headless --path . -s tests/llm_game.gd -- [seed] [lang] [max_calls]

const BotScript = preload("res://tests/sim.gd")

var g: Game
var bot
var r: LlmRescuer
var calls := 0
var max_calls := 12


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var intros: Dictionary = load("res://scripts/main.gd").INTRO  # load before setting Loc.lang
	if args.size() > 1:
		Loc.lang = args[1]
	if args.size() > 2:
		max_calls = int(args[2])
	g = Game.new()
	g.difficulty = "normal"
	g.setup(int(args[0]) if args.size() > 0 else 42)
	r = LlmRescuer.new()
	r.game = g
	r.mode = "proxy"
	r.fallback = MockRescuer.new(g)
	root.add_child.call_deferred(r)
	g.rescuer = self
	for l in intros[Loc.lang]:
		g.line_log.append({"who": "rescuer", "text": l})
	bot = BotScript.Bot.new(g, "smart")
	g.event.connect(bot.on_event)
	g.event.connect(func(t, d):
		if t in ["murderer_log", "rescuer_says", "player_says", "player_arrive", "line_click", "footsteps", "exit_try", "game_over", "murderer_says", "rescuer_error"]:
			print("%6.1f %-14s %s" % [g.time, t, d]))
	print("start %s exit %s/%s murderer %s" % [g.player_room, g.exit_room, g.exit_obj, g.murderer.room])


func request(ctx: Dictionary) -> void:
	calls += 1
	if calls > max_calls:
		r.fallback.request(ctx)
	else:
		r.request(ctx)


func tick(dt: float) -> void:
	r.tick(dt)


func _process(dt: float) -> bool:
	if g.over or g.time > 400.0:
		print("END reason=%s t=%.0f calls=%d" % [g.end_reason, g.time, calls])
		return true
	g.tick(dt)
	bot.tick(dt)
	return false
