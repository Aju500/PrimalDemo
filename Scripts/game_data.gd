extends Node
# ──────────────────────────────────────────────────────────────────────────────
#  GameData — autoload singleton.  Loads all content from res://Data/*.json so
#  the design data lives OUT of the game code.  battle.gd holds the behaviour;
#  this holds the numbers, text, and behaviour *indicators* (flags).
# ──────────────────────────────────────────────────────────────────────────────

var animals        : Dictionary = {}
var bestiary_order : Array      = []
var visuals        : Dictionary = {}
var moves          : Dictionary = {}
var player_moves   : Dictionary = {}
const LOADOUT_CAP := { "atk": 2, "def": 2, "spc": 2 }
var instincts      : Dictionary = {}
var cat_names      : Dictionary = {}
var items          : Dictionary = {}
var events         : Dictionary = {}
var events_cooldown: int        = 4
var modifiers      : Dictionary = {}
var adaptations    : Dictionary = {}
var altar_boons     : Dictionary = {}


func _ready() -> void:
	var a := _load("res://Data/animals.json")
	animals        = a.get("species", {})
	bestiary_order = a.get("order", [])

	visuals      = _load("res://Data/creature_visuals.json")
	moves        = _load("res://Data/moves.json")
	player_moves = _load("res://Data/player_moves.json")

	var ins := _load("res://Data/instincts.json")
	instincts = ins.get("instincts", {})
	cat_names = ins.get("categories", {})

	items       = _load("res://Data/items.json")
	modifiers   = _load("res://Data/modifiers.json")
	adaptations = _load("res://Data/adaptations.json")
	altar_boons = _load("res://Data/altar_boons.json")

	var ev := _load("res://Data/events.json")
	events          = ev.get("events", {})
	events_cooldown = int(ev.get("cooldown", 4))


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("GameData: missing data file " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: failed to parse " + path)
		return {}
	return parsed


func bestiary_bbcode() -> String:
	var s := "[i][color=#8faab5]You are not the only thing that hunts here. Learn what it does before it teaches you.[/color][/i]\n"
	for group in bestiary_order:
		s += "\n[color=#ffcc66][b]" + str(group[0]) + "[/b][/color]\n"
		for id in group[1]:
			var sp : Dictionary = animals[id]
			s += "\n[font_size=19][b]" + str(sp["name"]) + "[/b][/font_size]   [color=#777777]" + str(sp["tier"]) + "[/color]\n"
			s += "[i][color=#9fbfd0]" + str(sp["flavor"]) + "[/color][/i]\n"
			s += "[color=#aa8888]HP " + str(sp["hp"]) + "[/color]   [color=#88aacc]Breath " + str(sp["breath"]) + "[/color]\n"
			s += "[color=#cccccc]Moveset:[/color]\n"
			var mnames : Dictionary = sp.get("move_names", {})
			var seen : Dictionary = {}
			for mv in sp["moves"]:
				if seen.has(mv):
					continue
				seen[mv] = true
				var md : Dictionary = moves.get(mv, {})
				var nm : String = str(mnames.get(mv, md.get("name", mv)))
				s += "   • " + nm + " - " + str(md.get("bestiary", "")) + "\n"
			if not seen.has("rest"):
				s += "   • Rest - " + str(moves.get("rest", {}).get("bestiary", "")) + "\n"
			var tells : Array = sp["tells"]
			s += "[color=#cccccc]Tells:[/color]\n"
			s += "   [color=#ffdd88]1.[/color] " + str(tells[0]) + "\n"
			s += "   [color=#ffdd88]2.[/color] " + str(tells[1]) + "\n"
			s += "[color=#888888]Read profile: " + str(sp["read"]) + "[/color]\n"
	s += "\n[color=#666666][i]Bosses (Ancient Stag, Alpha Wolf, Giant Bear, The White Predator, Forest Warden) are a later pass. The two-way reads-you-back mechanic is designed but not yet live.[/i][/color]\n"
	return s
