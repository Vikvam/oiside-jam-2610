extends SceneTree
## Writes every synthesised sound to WAV files for inspection.
##   godot --headless --path . -s tests/export_audio.gd -- <outdir>

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var s := Sfx.new()
	s._generate()
	for k in s.s:
		var v = s.s[k]
		if v is Array:
			for i in v.size():
				v[i].save_to_wav("%s/%s_%d.wav" % [out, k, i])
		else:
			v.save_to_wav("%s/%s.wav" % [out, k])
	s.free()
	quit()
