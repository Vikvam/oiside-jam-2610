class_name House
extends RefCounted
## Static description of the house: rooms, doors, sound features, objects.
## Everybody knows the layout and the room names. Objects are only known to
## whoever has been in the room (the rescuer knows them all). Nicknames are
## childhood memories shared only by the player and the rescuer.

const FEATURES := ["clock", "fan", "rain", "radiator"]
const FEATURE_LABEL := {
	"clock": "ticking clock",
	"fan": "humming fan",
	"rain": "rain on a window",
	"radiator": "clanking radiator",
}
const DIRS := ["north", "east", "south", "west"]
const DIR_VEC := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}

## rect is in plan units (the plan is 12 x 9 units).
## features: what the room CAN sound like. "rain" means it has a window.
const ROOMS := [
	{
		"id": "library", "name": "Library", "rect": [0, 0, 4, 3], "phone": true,
		"features": ["clock", "rain"],
		"objects": [
			{"id": "bookcase", "name": "tall bookcase", "keys": ["bookcase", "bookshelf", "shelf", "shelves", "books"],
				"desc": "A tall bookcase. One volume is missing, leaving a dark gap."},
			{"id": "globe", "name": "old globe", "keys": ["globe", "world", "map"],
				"desc": "A dusty globe. Someone drew a tiny skull on Bohemia."},
			{"id": "armchair", "name": "leather armchair", "keys": ["armchair", "leather", "chair"],
				"desc": "A cracked leather armchair, still warm-looking somehow."},
		],
	},
	{
		"id": "study", "name": "Study", "rect": [4, 0, 4, 3], "phone": true,
		"features": ["clock", "fan"],
		"objects": [
			{"id": "desk", "name": "heavy oak desk", "keys": ["desk", "oak", "drawer", "drawers"],
				"desc": "A heavy oak desk. The drawers are locked."},
			{"id": "horse_painting", "name": "painting of a horse", "keys": ["painting", "horse", "portrait", "picture", "frame"],
				"desc": "A painting of a grey horse.", "nick": "Captain",
				"memory": "A grey horse in a gilt frame... Captain. You used to salute him every morning."},
			{"id": "typewriter", "name": "typewriter", "keys": ["typewriter", "typing", "keys"],
				"desc": "A black typewriter with a half-written letter in it."},
		],
	},
	{
		"id": "nursery", "name": "Nursery", "rect": [8, 0, 4, 3], "phone": false,
		"features": ["rain", "radiator"],
		"objects": [
			{"id": "bear", "name": "stuffed bear", "keys": ["bear", "teddy", "stuffed", "toy"],
				"desc": "A stuffed bear with one button eye.", "nick": "Mr. Buttons",
				"memory": "A one-eyed stuffed bear... Mr. Buttons! He used to guard your bed."},
			{"id": "rocking_horse", "name": "rocking horse", "keys": ["rocking", "horse"],
				"desc": "A wooden rocking horse. It creaks when you look at it."},
			{"id": "dollhouse", "name": "dollhouse", "keys": ["dollhouse", "dolls", "doll", "miniature"],
				"desc": "A dollhouse — a tiny copy of this very house."},
		],
	},
	{
		"id": "parlor", "name": "Parlor", "rect": [0, 3, 4, 3], "phone": true,
		"features": ["clock", "radiator"],
		"objects": [
			{"id": "piano", "name": "grand piano", "keys": ["piano", "keys", "grand"],
				"desc": "Grandma's grand piano, lid closed."},
			{"id": "fireplace", "name": "fireplace", "keys": ["fireplace", "fire", "hearth", "chimney", "mantel"],
				"desc": "A cold fireplace full of grey ash."},
			{"id": "mirror", "name": "tall mirror", "keys": ["mirror", "reflection"],
				"desc": "A tall mirror. You don't look at it for long."},
		],
	},
	{
		"id": "hall", "name": "Hall", "rect": [4, 3, 4, 3], "phone": true,
		"features": ["clock", "rain"],
		"objects": [
			{"id": "stag", "name": "stag head", "keys": ["stag", "antlers", "deer", "trophy"],
				"desc": "A mounted stag head with glass eyes.", "nick": "Old Gregor",
				"memory": "The stag head... Old Gregor. You both swore he blinked once."},
			{"id": "staircase", "name": "staircase", "keys": ["stairs", "staircase", "steps", "banister"],
				"desc": "A broad staircase. The upstairs is boarded off."},
			{"id": "umbrella_stand", "name": "umbrella stand", "keys": ["umbrella", "umbrellas", "stand", "cane"],
				"desc": "An umbrella stand made from an elephant's foot. Grim."},
		],
	},
	{
		"id": "kitchen", "name": "Kitchen", "rect": [8, 3, 4, 3], "phone": true,
		"features": ["fan", "rain", "radiator"],
		"objects": [
			{"id": "stove", "name": "iron stove", "keys": ["stove", "oven", "iron", "cooker"],
				"desc": "A big iron stove. The floorboards in front of it are loose."},
			{"id": "dumbwaiter", "name": "dumbwaiter", "keys": ["dumbwaiter", "lift", "hatch", "shaft"],
				"desc": "A dumbwaiter hatch in the wall.", "nick": "the ghost lift",
				"memory": "The dumbwaiter... the ghost lift. You rode it once and got stuck for an hour."},
			{"id": "knife_block", "name": "knife block", "keys": ["knife", "knives", "block"],
				"desc": "A knife block. One slot is empty. You try not to think about it."},
		],
	},
	{
		"id": "conservatory", "name": "Conservatory", "rect": [0, 6, 4, 3], "phone": false,
		"features": ["rain"],
		"objects": [
			{"id": "birdcage", "name": "empty birdcage", "keys": ["birdcage", "cage", "bird", "canary"],
				"desc": "An empty brass birdcage.", "nick": "Pip's palace",
				"memory": "The brass birdcage... Pip's palace. Pip was the canary. You buried him by the roses."},
			{"id": "fern", "name": "dead fern", "keys": ["fern", "plant", "plants", "pot"],
				"desc": "A huge dead fern in a cracked pot."},
			{"id": "wicker_chair", "name": "wicker chair", "keys": ["wicker", "chair"],
				"desc": "A wicker chair, rocking slightly. There is no wind."},
		],
	},
	{
		"id": "dining", "name": "Dining Room", "rect": [4, 6, 4, 3], "phone": true,
		"features": ["fan", "radiator"],
		"objects": [
			{"id": "long_table", "name": "long table", "keys": ["table", "tablecloth", "dinner"],
				"desc": "A long table set for twelve. Nobody has eaten here in years."},
			{"id": "china_cabinet", "name": "china cabinet", "keys": ["cabinet", "china", "plates", "porcelain", "cups"],
				"desc": "A cabinet of porcelain. Every cup has a chip."},
			{"id": "chandelier", "name": "chandelier", "keys": ["chandelier", "crystal", "crystals"],
				"desc": "A crystal chandelier, swaying very slightly."},
		],
	},
	{
		"id": "pantry", "name": "Pantry", "rect": [8, 6, 4, 3], "phone": false,
		"features": ["radiator"],
		"objects": [
			{"id": "jam_shelf", "name": "shelf of jam jars", "keys": ["jam", "jars", "jar", "preserves"],
				"desc": "Shelves of jam jars, labelled in a shaky hand: 1987, 1988, 1989..."},
			{"id": "flour_sacks", "name": "flour sacks", "keys": ["flour", "sacks", "sack", "bags"],
				"desc": "A pile of flour sacks. Something small has nested in them."},
			{"id": "meat_hook", "name": "meat hook", "keys": ["hook", "hooks", "meat"],
				"desc": "A rusty meat hook on a rail. It is empty. Thankfully."},
		],
	},
]

const DOORS := [
	["library", "study"], ["study", "nursery"],
	["library", "parlor"], ["study", "hall"], ["nursery", "kitchen"],
	["parlor", "hall"], ["hall", "kitchen"],
	["parlor", "conservatory"], ["hall", "dining"], ["kitchen", "pantry"],
	["dining", "pantry"],
]

## How each exit spot opens. Only the rescuer knows this.
const EXIT_FLAVOR := {
	"bookcase": "pull the missing-volume gap and the bookcase swings out onto old servants' stairs",
	"globe": "the globe's base is a hatch to a crawlspace that runs under the garden",
	"armchair": "under the armchair a trapdoor drops into the old coal tunnel",
	"desk": "the knee-hole of the desk has a false back into a passage",
	"horse_painting": "behind Captain the horse there is a small door into the wall passage",
	"typewriter": "the typewriter table hides a floor hatch",
	"bear": "Mr. Buttons sits on a loose panel that opens to a chute",
	"rocking_horse": "under the rocking horse is a trapdoor",
	"dollhouse": "the dollhouse wall panel behind it is a hidden door",
	"piano": "under the piano the floorboards lift to a tunnel",
	"fireplace": "the back plate of the fireplace slides into a chimney passage",
	"mirror": "the mirror is a door, push its left edge",
	"stag": "pull Old Gregor's left antler and a panel opens",
	"staircase": "the cupboard under the stairs has a false floor",
	"umbrella_stand": "behind the umbrella stand a low panel opens",
	"stove": "the loose floorboards in front of the stove open to the cellar",
	"dumbwaiter": "the dumbwaiter shaft goes down to the coal tunnel",
	"knife_block": "the tiled wall behind the knife block is a hatch",
	"birdcage": "the birdcage hook is a lever for a glass door in the garden wall",
	"fern": "the fern pot hides a drain cover big enough to crawl through",
	"wicker_chair": "under the wicker chair a grate opens",
	"long_table": "under the long table a trapdoor",
	"china_cabinet": "the china cabinet swings out on hinges",
	"chandelier": "the chandelier chain is a pull that opens a wall panel",
	"jam_shelf": "the jam shelf swings out into the old ice cellar",
	"flour_sacks": "under the flour sacks is a hatch",
	"meat_hook": "pull the meat hook down and the back wall opens",
}

var rooms := {}          # id -> room dict
var room_ids: Array[String] = []
var adj := {}            # id -> {dir: other_id}
var object_room := {}    # object id -> room id
var _dist := {}          # id -> {id: int}


func _init() -> void:
	for r in ROOMS:
		rooms[r.id] = r
		room_ids.append(r.id)
		adj[r.id] = {}
		for o in r.objects:
			object_room[o.id] = r.id
	for d in DOORS:
		var a: String = d[0]
		var b: String = d[1]
		var dir := direction_between(a, b)
		adj[a][dir] = b
		adj[b][opposite(dir)] = a
	for a in room_ids:
		_dist[a] = _bfs(a)


static func opposite(dir: String) -> String:
	return {"north": "south", "south": "north", "east": "west", "west": "east"}[dir]


func center(id: String) -> Vector2:
	var r: Array = rooms[id].rect
	return Vector2(r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)


func rect(id: String) -> Rect2:
	var r: Array = rooms[id].rect
	return Rect2(r[0], r[1], r[2], r[3])


func direction_between(a: String, b: String) -> String:
	var v := center(b) - center(a)
	if absf(v.x) >= absf(v.y):
		return "east" if v.x > 0 else "west"
	return "south" if v.y > 0 else "north"


func neighbors(id: String) -> Array:
	return adj[id].values()


func door_to(a: String, b: String) -> String:
	for dir in adj[a]:
		if adj[a][dir] == b:
			return dir
	return ""


func step(id: String, dir: String) -> String:
	return adj[id].get(dir, "")


func distance(a: String, b: String) -> int:
	return _dist[a].get(b, 99)


func path(a: String, b: String) -> Array:
	## Rooms after `a` up to and including `b`.
	if a == b:
		return []
	var prev := {a: ""}
	var q := [a]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == b:
			break
		for n in neighbors(cur):
			if not prev.has(n):
				prev[n] = cur
				q.append(n)
	var out := []
	var c := b
	while c != a and c != "":
		out.push_front(c)
		c = prev.get(c, "")
	return out


func rooms_within(id: String, d: int) -> Array:
	var out := []
	for r in room_ids:
		if distance(id, r) <= d:
			out.append(r)
	return out


func rooms_at(id: String, d: int) -> Array:
	var out := []
	for r in room_ids:
		if distance(id, r) == d:
			out.append(r)
	return out


func phone_rooms() -> Array:
	var out := []
	for r in room_ids:
		if rooms[r].phone:
			out.append(r)
	return out


func has_feature(id: String, f: String) -> bool:
	return f in rooms[id].features


func object_def(obj_id: String) -> Dictionary:
	var rid: String = object_room.get(obj_id, "")
	if rid == "":
		return {}
	for o in rooms[rid].objects:
		if o.id == obj_id:
			return o
	return {}


func _bfs(a: String) -> Dictionary:
	var d := {a: 0}
	var q := [a]
	while not q.is_empty():
		var cur: String = q.pop_front()
		for n in neighbors(cur):
			if not d.has(n):
				d[n] = d[cur] + 1
				q.append(n)
	return d
