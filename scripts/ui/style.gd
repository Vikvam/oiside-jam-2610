class_name Style
extends RefCounted
## Visual styles. Everything is drawn procedurally from these values,
## plus one full-screen post-processing shader (shaders/post.gdshader).

const ORDER := ["blueprint", "phosphor", "ink"]

const STYLES := {
	"blueprint": {
		"label": "Blueprint",
		"bg": Color("0b2340"), "grid": Color("16406b"), "wall": Color("e6f0ff"),
		"room_fill": Color(0.55, 0.75, 1.0, 0.06), "visited_fill": Color(0.55, 0.75, 1.0, 0.13),
		"text": Color("c9ddf7"), "dim": Color("6f8fb8"), "accent": Color("ffd23f"),
		"danger": Color("ff5a4e"), "you": Color("ffd23f"), "her": Color("e6f0ff"),
		"panel": Color(0.04, 0.12, 0.22, 0.92), "panel_line": Color("2c5d92"),
		"wobble": 0.0, "wall_width": 3.0, "grid_on": true, "mono": true, "post": 0,
	},
	"phosphor": {
		"label": "Phosphor CRT",
		"bg": Color("020a05"), "grid": Color("0a2312"), "wall": Color("5cff8a"),
		"room_fill": Color(0.2, 1.0, 0.4, 0.03), "visited_fill": Color(0.2, 1.0, 0.4, 0.09),
		"text": Color("49d873"), "dim": Color("1f7a3c"), "accent": Color("d4ffd9"),
		"danger": Color("ffb000"), "you": Color("d4ffd9"), "her": Color("5cff8a"),
		"panel": Color(0.0, 0.05, 0.02, 0.92), "panel_line": Color("1a5a2c"),
		"wobble": 0.0, "wall_width": 2.0, "grid_on": true, "mono": true, "post": 1,
	},
	"ink": {
		"label": "Ink & Paper",
		"bg": Color("ece2cc"), "grid": Color("d9ccb0"), "wall": Color("1d1712"),
		"room_fill": Color(0.1, 0.07, 0.04, 0.03), "visited_fill": Color(0.1, 0.07, 0.04, 0.09),
		"text": Color("2b221a"), "dim": Color("8a7a63"), "accent": Color("b3121b"),
		"danger": Color("b3121b"), "you": Color("b3121b"), "her": Color("1d1712"),
		"panel": Color(0.93, 0.89, 0.8, 0.95), "panel_line": Color("8a7a63"),
		"wobble": 1.6, "wall_width": 2.6, "grid_on": false, "mono": false, "post": 2,
	},
}

static var current := "blueprint"


static func c(key: String) -> Variant:
	return STYLES[current][key]


static func next_style() -> String:
	var i := ORDER.find(current)
	current = ORDER[(i + 1) % ORDER.size()]
	return current
