class_name Words
extends RefCounted
## Tiny keyword parser. Deliberately dumb and transparent: the murderer
## "understands" exactly these words and nothing else.

const FEATURE_WORDS := {
	"clock": ["clock", "clocks", "tick", "ticking", "tock", "chime", "chiming"],
	"fan": ["fan", "hum", "humming", "whir", "whirring", "buzz", "buzzing"],
	"rain": ["rain", "raining", "window", "windows", "drizzle", "storm"],
	"radiator": ["radiator", "heater", "clank", "clanking", "pipes", "pipe", "heating"],
}
const DIR_WORDS := {
	"north": "north", "northern": "north", "up": "", "south": "south", "southern": "south",
	"east": "east", "eastern": "east", "west": "west", "western": "west",
}
const ROOM_WORDS := {
	"library": "library", "study": "study", "office": "study", "nursery": "nursery",
	"parlor": "parlor", "parlour": "parlor", "lounge": "parlor", "hall": "hall", "hallway": "hall",
	"entrance": "hall", "foyer": "hall", "kitchen": "kitchen", "conservatory": "conservatory",
	"greenhouse": "conservatory", "dining": "dining", "pantry": "pantry", "larder": "pantry",
}


static func tokens(text: String) -> PackedStringArray:
	var t := text.to_lower()
	var clean := ""
	for c in t:
		if (c >= "a" and c <= "z") or c == "'" or (c >= "0" and c <= "9"):
			clean += c
		else:
			clean += " "
	var out := PackedStringArray()
	for w in clean.split(" ", false):
		w = w.trim_suffix("'s").replace("'", "")
		if w != "":
			out.append(w)
	return out


static func directions(text: String) -> Array:
	var out := []
	for w in tokens(text):
		var d: String = DIR_WORDS.get(w, "")
		if d != "":
			out.append(d)
	return out


static func rooms_named(text: String) -> Array:
	var out := []
	for w in tokens(text):
		var r: String = ROOM_WORDS.get(w, "")
		if r != "" and r not in out:
			out.append(r)
	return out


static func features_named(text: String) -> Array:
	var out := []
	var toks := tokens(text)
	for f in FEATURE_WORDS:
		for w in FEATURE_WORDS[f]:
			if w in toks:
				out.append(f)
				break
	return out


## Objects mentioned, restricted to objects in `known_rooms` (null = all).
## Returns [{obj, room}].
static func objects_named(text: String, house: House, known_rooms = null) -> Array:
	var toks := tokens(text)
	var out := []
	for rid in house.room_ids:
		if known_rooms != null and not known_rooms.has(rid):
			continue
		for o in house.rooms[rid].objects:
			for k in o.keys:
				if k in toks:
					out.append({"obj": o.id, "room": rid})
					break
	return out


## Childhood nicknames: only the player (after seeing the object) and the
## rescuer know them. Returns [{obj, room}].
static func nicknames_named(text: String, house: House) -> Array:
	var low := " " + " ".join(tokens(text)) + " "
	var out := []
	for rid in house.room_ids:
		for o in house.rooms[rid].objects:
			if o.has("nick"):
				var n := " " + " ".join(tokens(o.nick)) + " "
				var bare := n.replace(" the ", " ").replace(" mr ", " ")
				if low.contains(n) or (bare.strip_edges().length() > 3 and low.contains(bare)):
					out.append({"obj": o.id, "room": rid})
	return out
