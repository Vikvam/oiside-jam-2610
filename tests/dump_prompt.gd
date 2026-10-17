extends SceneTree
## Dumps the rescuer system prompt + a line transcript as JSON, for testing
## the proxy by hand:  godot --headless --path . -s tests/dump_prompt.gd -- out.json "player line" ...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var g := Game.new()
	g.setup(5)
	for l in [
		"It's me. Don't say my name. Listen.",
		"There's a way out of the house. He doesn't know about it. I'll get you there.",
		"But every phone in that house is on one line. If he picks up an extension, he hears every word.",
		"So don't tell me where you are. Not straight out. One tap means yes, two taps mean no.",
	]:
		g.line_log.append({"who": "rescuer", "text": l})
	for i in range(1, args.size()):
		var a: String = args[i]
		if a.begins_with("["):
			g.line_log.append({"who": "line", "text": a})
		else:
			g.line_log.append({"who": "player", "text": a})
	var out := {"system": LlmRescuer.build_system(g), "prompt": LlmRescuer.build_prompt(g, "speech"),
		"truth": {"player": g.player_room, "exit": g.exit_room, "obj": g.exit_obj}}
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	quit()
