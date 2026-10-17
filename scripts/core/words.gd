class_name Words
extends RefCounted
## Tiny keyword parser. Deliberately dumb and transparent: the murderer
## "understands" exactly these words and nothing else — in English and Czech.
## Keys ending in * are stems: they match any word starting with them
## (after lower-casing and stripping diacritics), which copes with Czech cases.
## Fun fact kept on purpose: in Czech "východ" means both "east" and "exit".

const FEATURE_WORDS := {
	"clock": ["clock", "clocks", "tick", "ticking", "tock", "chime", "chiming", "hodin*", "tik*", "odbij*"],
	"fan": ["fan", "hum", "humming", "whir", "whirring", "buzz", "buzzing", "vetrak*", "ventilator*", "bzuc*", "huci", "hucen*"],
	"rain": ["rain", "raining", "window", "windows", "drizzle", "storm", "dest", "deste", "destem", "prsi*", "okn*", "oken*", "kapk*"],
	"radiator": ["radiator", "heater", "clank", "clanking", "pipes", "pipe", "heating", "radiator*", "topen*", "trubk*", "klep*"],
}
const DIR_WORDS := {
	"north": "north", "northern": "north", "south": "south", "southern": "south",
	"east": "east", "eastern": "east", "west": "west", "western": "west",
	"sever*": "north", "jih*": "south", "jizn*": "south", "vychod*": "east", "zapad*": "west",
}
const ROOM_WORDS := {
	"library": "library", "study": "study", "office": "study", "nursery": "nursery",
	"parlor": "parlor", "parlour": "parlor", "lounge": "parlor", "hall": "hall", "hallway": "hall",
	"entrance": "hall", "foyer": "hall", "kitchen": "kitchen", "conservatory": "conservatory",
	"greenhouse": "conservatory", "dining": "dining", "pantry": "pantry", "larder": "pantry",
	"billiard": "billiard", "billiards": "billiard", "music": "music", "bathroom": "bathroom", "toilet": "bathroom",
}


static func tokens(text: String) -> PackedStringArray:
	var t := Loc.fold(text)
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


static func match_key(token: String, key: String) -> bool:
	if key.ends_with("*"):
		return token.begins_with(key.left(-1))
	return token == key


static func _any(toks: PackedStringArray, keys: Array) -> bool:
	for w in toks:
		for k in keys:
			if match_key(w, k):
				return true
	return false


static func directions(text: String) -> Array:
	var out := []
	for w in tokens(text):
		for k in DIR_WORDS:
			if match_key(w, k):
				out.append(DIR_WORDS[k])
				break
	return out


## Rooms mentioned that exist in `house` (the large house has more names).
static func rooms_named(text: String, house: House) -> Array:
	var out := []
	var toks := tokens(text)
	for w in toks:
		var r: String = ROOM_WORDS.get(w, "")
		if r != "" and r not in out:
			out.append(r)
	for table in [House.CS_ROOMS, House.CS_EXTRA_ROOMS]:
		for rid in table:
			if rid not in out and _any(toks, table[rid][3]):
				out.append(rid)
	out = out.filter(func(r): return house.rooms.has(r))
	return out


static func features_named(text: String) -> Array:
	var out := []
	var toks := tokens(text)
	for f in FEATURE_WORDS:
		if _any(toks, FEATURE_WORDS[f]):
			out.append(f)
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
			var keys: Array = o.keys.duplicate()
			keys.append_array(House.cs_obj(o.id)[2])
			if _any(toks, keys):
				out.append({"obj": o.id, "room": rid})
	return out


## Childhood nicknames: only the player (after seeing the object) and the
## rescuer know them. Returns [{obj, room}].
static func nicknames_named(text: String, house: House) -> Array:
	var low := " " + " ".join(tokens(text)) + " "
	var out := []
	for rid in house.room_ids:
		for o in house.rooms[rid].objects:
			if not o.has("nick"):
				continue
			for nick in [o.nick, House.cs_obj(o.id)[3]]:
				var n := " " + " ".join(tokens(nick)) + " "
				var bare := n.replace(" the ", " ").replace(" mr ", " ").replace(" pan ", " ").replace(" stary ", " ")
				if low.contains(n) or (bare.strip_edges().length() > 3 and low.contains(bare)):
					out.append({"obj": o.id, "room": rid})
					break
	return out
