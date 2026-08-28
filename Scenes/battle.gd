extends Node2D

# ──────────────────────────────────────────────────────────────────────────────
#  PRIMAL — combat core + run flow.  Behaviour lives here; content lives in
#  res://Data/*.json (loaded by the GameData autoload).
#  Dominance (−5..+5) replaces Focus.  Debug overlay: press ` (backtick).
# ──────────────────────────────────────────────────────────────────────────────

const BASE_MAX_HP         := 6
const BASE_MAX_BREATH     := 5
const PLAYER_START_BREATH := 3
const CLAW_COST           := 2
const CLAW_BASE_DAMAGE    := 2
const GUARD_COST          := 1
const OBSERVE_BREATH_GAIN := 2
const CAT_CAP             := 3
const DOM_MIN             := -5
const DOM_MAX             := 5
const MOD_CHANCE          := 0.15

# Move numbers/verbs/flags are data — see res://Data/moves.json (loaded by GameData).
func mcost(m: String) -> int:    return int(GameData.moves.get(m, {}).get("cost", 0))
func mdmg(m: String) -> int:     return int(GameData.moves.get(m, {}).get("damage", 0))
func mverb(m: String) -> String: return str(GameData.moves.get(m, {}).get("verb", "attacks"))

const OBSERVE_TEXT := "OBSERVE\n0 Breath  →  +2 Breath\nReveals next tell"
const CLAW_TEXT    := "CLAW\n2 Breath  →  2 + Dominance"
const GUARD_TEXT   := "GUARD\n1 Breath  →  -1 Damage Taken"

# Scroll or SPACE raises the move wheel; scroll to pick, middle-click (or click a
# move) to commit.  Observe isn't in the wheel — you Observe by clicking the creature.
const WHEEL_HIDE_DELAY := 2.0

# Run is generated fresh each time from these tier-bands (species live in animals.json).
# Randomized within each band, escalating; slot 1 is the teaching fight, last is the boss.
const RUN_BANDS := [
	["deer", "rabbit"],
	["rabbit", "deer", "stoat"],
	["fox", "stoat", "boar"],
	["fox", "boar", "lynx", "stoat"],
	["boar", "lynx", "wolf_cub"],
	["lynx", "razorback", "wolf_cub"],
	["boar", "razorback", "stag"],
	["razorback", "stag", "wolf"],
	["stag", "wolf", "wolf_cub"],
	["stag", "wolf", "leadwolf"],
	["wolf", "leadwolf"],
	["leadwolf", "greaterstag"],
	["leadwolf", "greaterstag"],
	["greaterstag"],
	["greaterstag", "leadwolf"],
	["bear"],
]
const REWARD_AFTER := [1, 4, 8, 13]
const EVENT_AFTER  := [2, 3, 6, 7, 9, 10, 11, 12, 14, 15]
const REPRIEVE_CHANCE := 0.2   # chance a slot pulls a slightly easier enemy

const RARITY_WEIGHT := { "common": 12, "uncommon": 5, "rare": 2 }

# ── Player state ──────────────────────────────────────────────────────────────
var player_hp       : int
var player_breath   : int
var dominance       : int
var player_blood    : int
var player_fragments: Dictionary = {}   # {"atk":n, "def":n, "spc":n}
var player_mitigate : int   # 0 = not defending, 1 = guard-style, 99 = full dodge
var player_counter  : int   # damage dealt back on a successful mitigation
var owned_instincts : Array = []
var inventory       : Array = []
var unlocked_moves  : Array = []
var equipped_moves  : Array = []   # loadout order: attack, defense, special (Observe excluded)
var adaptation_max_hp_bonus     : int  = 0
var adaptation_max_breath_bonus : int  = 0
var altar_double_first_kill     : bool = false

# ── Per-turn / per-battle trackers ────────────────────────────────────────────
var did_attack_this_battle : bool
var atk_streak       : int
var def_streak       : int
var obs_streak       : int
var observes_battle  : int
var last_was_observe : bool
var next_attack_bonus: int
var ws_bonus          : int   # Watchful Silence's banked overflow, capped at +3
var turn_attack_bonus: int   # this-turn only (Sharp Stone)
var turn_shield      : int   # this-turn only (Pelt)
var next_ignores_defense : bool
var reveal_battle    : bool
var unyielding_active : bool   # Unyielding: usable THIS turn (earned last turn)
var unyielding_staged : bool   # mitigated this turn → becomes active next turn
var _prior_attacks   : bool
var _attack_hit      : bool
var _missed          : bool
var _fully_mitigated : bool
var _took_unmitigated: int
var _took_any_hit    : bool

# ── Enemy state ───────────────────────────────────────────────────────────────
var enemy_name         : String
var enemy_species      : String
var enemy_hp           : int
var enemy_max_hp       : int
var enemy_breath       : int
var enemy_max_breath   : int
var sp_moves           : Dictionary
var sp_calm            : float
var sp_flags           : Dictionary
var enemy_blood_reward : int
var enemy_planned_move : String
var enemy_acted_move   : String
var enemy_last_move    : String
var enemy_block_suppress : int
var enemy_forced_rest  : int
var mod_flags          : Dictionary = {}
var current_mod        : String = ""
var raccoon_stock      : Array = []

# ── Flow ──────────────────────────────────────────────────────────────────────
var run_encounters  : Array = []
var steps           : Array = []
var step_ptr        : int   = -1
var battle_num      : int   = 0
var player_turn     : bool  = false
var battle_over     : bool  = false
var ui_mode         : String = "combat"
var selected_move   : int   = 0
var wheel_open      : bool  = false
var wheel_from_scroll : bool = false
var wheel_timer     : float = 0.0
var pending_choices : Array = []
var pending_followup: String = ""
var deck            : EventDeck

# ── Debug ─────────────────────────────────────────────────────────────────────
var debug_open   : bool   = false
var debug_cat    : String = ""
var debug_buffer : String = ""

# ── Scene node refs ───────────────────────────────────────────────────────────
@onready var dom_bar           : ProgressBar   = $UILayer/UI/VBox/DomBox/DomBar
@onready var dom_label         : Label         = $UILayer/UI/VBox/DomBox/DomLabel
@onready var enemy_name_label  : Label         = $UILayer/UI/VBox/EnemyPanel/EnemyName
@onready var enemy_hp_bar      : ProgressBar   = $UILayer/UI/VBox/EnemyPanel/EnemyHPBar
@onready var enemy_hp_label    : Label         = $UILayer/UI/VBox/EnemyPanel/EnemyHPLabel
@onready var enemy_tell_label  : Label         = $UILayer/UI/VBox/EnemyPanel/EnemyTell
@onready var creature          : Control       = $UILayer/UI/VBox/EnemyPanel/Creature
@onready var combat_log        : RichTextLabel = $UILayer/UI/VBox/MiddleHBox/LogPanel/CombatLog
@onready var phase_label       : Label         = $UILayer/UI/VBox/MiddleHBox/InfoPanel/PhaseLabel
@onready var player_hp_bar     : ProgressBar   = $UILayer/UI/VBox/MiddleHBox/InfoPanel/PlayerHPBar
@onready var player_hp_label   : Label         = $UILayer/UI/VBox/MiddleHBox/InfoPanel/PlayerHPLabel
@onready var breath_label      : Label         = $UILayer/UI/VBox/MiddleHBox/InfoPanel/BreathLabel
@onready var status_label      : Label         = $UILayer/UI/VBox/MiddleHBox/InfoPanel/FocusLabel
@onready var blood_label       : Label         = $UILayer/UI/VBox/MiddleHBox/InfoPanel/BloodLabel
@onready var observe_btn       : Button        = $UILayer/UI/VBox/ButtonHBox/ObserveBtn
@onready var claw_btn          : Button        = $UILayer/UI/VBox/ButtonHBox/ClawBtn
@onready var guard_btn         : Button        = $UILayer/UI/VBox/ButtonHBox/GuardBtn
@onready var restart_btn       : Button        = $UILayer/UI/RestartBtn
@onready var cave_btn          : Button        = $UILayer/UI/CaveBtn
@onready var hint_label        : Label         = $UILayer/UI/HintLabel
@onready var move_wheel        : Control       = $UILayer/UI/MoveWheel
@onready var wheel_list        : VBoxContainer = $UILayer/UI/MoveWheel/WheelList
@onready var button_hbox       : HBoxContainer = $UILayer/UI/VBox/ButtonHBox
@onready var menu_btn          : Button        = $UILayer/UI/MenuBtn
@onready var bestiary_btn      : Button        = $UILayer/UI/BestiaryBtn
@onready var exit_btn          : Button        = $UILayer/UI/ExitBtn
@onready var pouch_overlay     : Control       = $UILayer/UI/PouchOverlay
@onready var pouch_title       : Label         = $UILayer/UI/PouchOverlay/Panel/Title
@onready var pouch_list        : VBoxContainer = $UILayer/UI/PouchOverlay/Panel/Scroll/PouchList
@onready var pouch_close       : Button        = $UILayer/UI/PouchOverlay/Panel/CloseBtn
@onready var bestiary_overlay  : Control       = $UILayer/UI/BestiaryOverlay
@onready var bestiary_text     : RichTextLabel = $UILayer/UI/BestiaryOverlay/Panel/Scroll/BestiaryText
@onready var bestiary_close    : Button        = $UILayer/UI/BestiaryOverlay/Panel/CloseBtn
@onready var debug_panel       : Panel         = $DebugLayer/DebugPanel
@onready var debug_text        : RichTextLabel = $DebugLayer/DebugPanel/DebugText
@onready var overlay           : ColorRect     = $FadeLayer/Overlay


# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	deck = EventDeck.new()
	observe_btn.pressed.connect(func(): _on_button(0))
	claw_btn.pressed.connect(func(): _on_button(1))
	guard_btn.pressed.connect(func(): _on_button(2))
	restart_btn.pressed.connect(_on_restart_pressed)
	cave_btn.pressed.connect(_on_cave_pressed)
	menu_btn.pressed.connect(_toggle_pouch)
	pouch_close.pressed.connect(_toggle_pouch)
	bestiary_btn.pressed.connect(_toggle_bestiary)
	bestiary_close.pressed.connect(_toggle_bestiary)
	exit_btn.pressed.connect(_on_exit_pressed)
	creature.clicked.connect(_on_creature_clicked)
	bestiary_text.text = GameData.bestiary_bbcode()
	_init_run()
	_buttons_enabled(false)
	_fade_in()
	await get_tree().create_timer(0.9).timeout
	_next_step()


# ── Effective stats ───────────────────────────────────────────────────────────
func has(id: String) -> bool:   return owned_instincts.has(id)
func max_hp() -> int:           return BASE_MAX_HP + (1 if has("thick_hide") else 0) + adaptation_max_hp_bonus
func max_breath() -> int:       return BASE_MAX_BREATH + (1 if has("deep_lungs") else 0) + (1 if has("endurance") else 0) + adaptation_max_breath_bonus
func cat_count(cat: String) -> int:
	var n := 0
	for id in owned_instincts:
		if GameData.instincts[id]["cat"] == cat:
			n += 1
	return n

func dom_attack_bonus() -> int:
	if dominance > 0:
		var b := mini(dominance, 3)
		if has("momentum") and dominance >= 3:
			b += 1
		return b
	elif dominance <= -3:
		return -1
	return 0

func guard_reduction() -> int:  return 2 if dominance >= 4 else 1
func incoming_extra() -> int:   return 1 if dominance <= -5 else 0
func _is_attack(m: String) -> bool: return GameData.moves.get(m, {}).has("damage")
func _move_category(move: String) -> String: return str(GameData.moves.get(move, {}).get("read", "tired"))
func _move_weight(move: String) -> String:   return str(GameData.moves.get(move, {}).get("weight", "heavy"))


func _init_run() -> void:
	dominance   = 0
	battle_over = false
	altar_double_first_kill = false
	owned_instincts.clear()
	inventory.clear()

	# Meta progression (persists across runs, lives at the save root).
	var slot := Save.read_slot(Save.active_slot)
	player_fragments = _load_fragments(slot.get("fragments", {}))
	unlocked_moves.clear()
	for m in slot.get("unlocked", []):
		unlocked_moves.append(str(m))
	if unlocked_moves.is_empty():
		for id in GameData.player_moves.keys():
			if GameData.player_moves[id].get("start", false) or GameData.player_moves[id].get("always", false):
				unlocked_moves.append(id)
	_load_loadout(slot)
	_load_adaptation_bonuses(slot)   # max HP/Breath adaptation caps apply whether resuming or fresh

	var loaded := false
	if Save.resume:
		var r : Dictionary = Save.read_slot(Save.active_slot).get("run", {})
		if not r.is_empty():
			run_encounters = r.get("encounters", [])
			for e in run_encounters:                       # JSON numbers load as floats
				e["hp"] = int(e["hp"]); e["breath"] = int(e["breath"]); e["blood"] = int(e["blood"])
			player_hp     = int(r.get("hp", BASE_MAX_HP))
			player_breath = int(r.get("breath", PLAYER_START_BREATH))
			player_blood  = int(r.get("blood", 0))
			for x in r.get("instincts", []):
				owned_instincts.append(str(x))
			for x in r.get("inventory", []):
				inventory.append(str(x))
			battle_num = int(r.get("battle_num", 0))
			_rebuild_steps()
			step_ptr = int(r.get("step", 0)) - 1
			loaded = true
	Save.resume = false

	if not loaded:
		player_hp      = max_hp()          # adaptation HP bonus starts you at the new full
		player_breath  = PLAYER_START_BREATH
		player_blood   = 0
		battle_num     = 0
		run_encounters = _generate_run()
		_rebuild_steps()
		step_ptr = -1
		_apply_fresh_run_boons(slot)       # one-time: equipped adaptations' start bonuses, altar boon, trader stock


func _load_fragments(raw) -> Dictionary:
	var out := { "atk": 0, "def": 0, "spc": 0 }
	if typeof(raw) == TYPE_DICTIONARY:
		for k in out.keys():
			out[k] = int(raw.get(k, 0))
	return out


func _load_adaptation_bonuses(slot: Dictionary) -> void:
	adaptation_max_hp_bonus = 0
	adaptation_max_breath_bonus = 0
	var owned : Array = slot.get("adaptations_owned", [])
	for id in slot.get("adaptations_equipped", []):
		if not owned.has(str(id)):
			continue
		var fl : Dictionary = GameData.adaptations.get(str(id), {}).get("flags", {})
		adaptation_max_hp_bonus += int(fl.get("max_hp", 0))
		adaptation_max_breath_bonus += int(fl.get("max_breath", 0))


func _apply_fresh_run_boons(slot: Dictionary) -> void:
	var owned : Array = slot.get("adaptations_owned", [])
	for id in slot.get("adaptations_equipped", []):
		if not owned.has(str(id)):
			continue
		var fl : Dictionary = GameData.adaptations.get(str(id), {}).get("flags", {})
		if fl.has("start_dominance"):
			dominance = clampi(dominance + int(fl["start_dominance"]), DOM_MIN, DOM_MAX)
		if fl.has("start_blood"):
			player_blood += int(fl["start_blood"])
		if fl.has("start_item"):
			_give_item(_resolve_drop_token(str(fl["start_item"])))
		if fl.has("unlock_move"):
			var mv := str(fl["unlock_move"])
			if not unlocked_moves.has(mv):
				unlocked_moves.append(mv)

	var altered := false
	var pboon := str(slot.get("pending_boon", ""))
	if pboon != "" and GameData.altar_boons.has(pboon):
		_apply_altar_boon(pboon)
		slot.erase("pending_boon")
		altered = true
	var pitems : Array = slot.get("pending_items", [])
	for it in pitems:
		inventory.append(str(it))
	if not pitems.is_empty():
		slot.erase("pending_items")
		altered = true
	if altered:
		Save.write_slot(Save.active_slot, slot)


func _apply_altar_boon(id: String) -> void:
	var boon : Dictionary = GameData.altar_boons.get(id, {})
	var fl : Dictionary = boon.get("flags", {})
	if fl.has("max_breath"):
		adaptation_max_breath_bonus += int(fl["max_breath"])
		player_breath = mini(player_breath + int(fl["max_breath"]), max_breath())
	if fl.has("start_dominance"):
		dominance = clampi(dominance + int(fl["start_dominance"]), DOM_MIN, DOM_MAX)
	if fl.has("double_first_kill"):
		altar_double_first_kill = true
	_log("[i][color=#ffb3b3]The altar's boon settles over you: " + str(boon.get("name", id)) + ".[/color][/i]")


func _load_loadout(slot: Dictionary) -> void:
	equipped_moves.clear()
	var lo : Dictionary = slot.get("loadout", {})
	for cat in ["atk", "def", "spc"]:
		for m in lo.get(cat, []):
			if GameData.player_moves.has(str(m)):
				equipped_moves.append(str(m))
	if equipped_moves.is_empty():                       # default kit
		equipped_moves = ["claw", "guard"]
	selected_move = 0


func _rebuild_steps() -> void:
	steps.clear()
	for i in run_encounters.size():
		steps.append({ "type": "battle", "data": run_encounters[i] })
		var n := i + 1
		if REWARD_AFTER.has(n):
			steps.append({ "type": "instinct" })
		elif EVENT_AFTER.has(n):
			steps.append({ "type": "event" })


func _save_now() -> void:
	if Save.active_slot < 0:
		return
	var data := Save.read_slot(Save.active_slot)
	data["stage"] = "run"
	data["fragments"] = player_fragments
	data["unlocked"] = unlocked_moves
	data["run"] = {
		"encounters": run_encounters,
		"step": maxi(step_ptr, 0),
		"hp": player_hp, "breath": player_breath, "blood": player_blood,
		"instincts": owned_instincts, "inventory": inventory,
		"battle_num": battle_num,
	}
	Save.write_slot(Save.active_slot, data)


func _clear_run_save() -> void:
	var data := Save.read_slot(Save.active_slot)
	data["blood_bank"]  = int(data.get("blood_bank", 0)) + player_blood
	data["fragments"]   = player_fragments
	data["unlocked"]    = unlocked_moves
	data["best_battle"] = maxi(int(data.get("best_battle", 0)), battle_num)
	data.erase("run")
	data["stage"] = "hub"
	Save.write_slot(Save.active_slot, data)


func _generate_run() -> Array:
	var out : Array = []
	var prev := ""
	var last := RUN_BANDS.size() - 1
	for slot in RUN_BANDS.size():
		# Small chance of a reprieve: pull from an earlier band (never on the boss).
		var band_idx := slot
		if slot > 1 and slot < last and randf() < REPRIEVE_CHANCE:
			band_idx = slot - 2
		var band : Array = RUN_BANDS[band_idx]
		var choices : Array = band.filter(func(s): return s != prev)
		if choices.is_empty():
			choices = band
		var sp_id : String = choices.pick_random()
		prev = sp_id
		var base : Dictionary = GameData.animals[sp_id]
		out.append({
			"sp": sp_id,
			"hp": int(base["hp"]) + int(slot * 0.4),
			"breath": int(base["breath"]) + (1 if slot >= 8 else 0),
			"blood": 2 + int((slot + 1) * 0.7),
		})
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  STEP MACHINE
# ══════════════════════════════════════════════════════════════════════════════
func _next_step() -> void:
	step_ptr += 1
	if step_ptr >= steps.size():
		_run_complete()
		return
	_save_now()
	match steps[step_ptr]["type"]:
		"battle":   start_battle(steps[step_ptr]["data"])
		"instinct": _offer_instinct()
		"event":    _offer_event(deck.next_event())


func _run_complete() -> void:
	battle_over = true
	ui_mode = "over"
	_buttons_enabled(false)
	_clear_run_save()
	_log("")
	_log("[color=#ffdd44][b]YOU ARE THE APEX.  The forest is yours.[/b][/color]")
	_log("Blood banked: " + str(player_blood))
	phase_label.text = "SURVIVED"
	restart_btn.visible = true
	cave_btn.visible = true
	hint_label.visible = false
	_hide_wheel()


# ══════════════════════════════════════════════════════════════════════════════
#  BATTLE
# ══════════════════════════════════════════════════════════════════════════════
func start_battle(data: Dictionary) -> void:
	battle_num += 1
	enemy_species      = data["sp"]
	var sp : Dictionary = GameData.animals[enemy_species]
	enemy_name         = data.get("name", sp["name"])
	enemy_hp           = int(data["hp"])
	enemy_max_hp       = int(data["hp"])
	enemy_max_breath   = int(data["breath"])
	enemy_breath       = enemy_max_breath
	enemy_blood_reward = int(data["blood"])
	sp_moves           = sp["moves"]
	sp_calm            = float(sp["calm"])
	sp_flags           = sp["flags"]

	dominance = 0
	player_mitigate = 0
	player_counter = 0
	unyielding_active = false
	unyielding_staged = false
	did_attack_this_battle = false
	atk_streak = 0
	def_streak = 0
	obs_streak = 0
	observes_battle = 0
	last_was_observe = false
	next_attack_bonus = 0
	ws_bonus = 0
	turn_attack_bonus = 0
	turn_shield = 0
	next_ignores_defense = false
	reveal_battle = false
	_prior_attacks = false
	enemy_last_move = ""
	enemy_block_suppress = 0
	enemy_forced_rest = 0

	# Battle modifier (low chance, never the teaching fight or the boss).
	mod_flags = {}
	current_mod = ""
	if battle_num > 1 and battle_num < run_encounters.size() and not GameData.modifiers.is_empty() and randf() < MOD_CHANCE:
		_apply_modifier(GameData.modifiers.keys().pick_random())

	var vis : Dictionary = GameData.visuals.get(enemy_species, {})
	creature.setup(Color(str(vis.get("color", "#999999"))), str(vis.get("shape", "circle")))
	creature.modulate.a = 1.0
	creature.visible = true

	_restore_combat_buttons()
	enemy_planned_move = _plan_move()
	if sp_flags.get("ambush_opener", false):
		var atks := sp_moves.keys().filter(func(m): return _is_attack(m) and mcost(m) <= enemy_breath)
		if not atks.is_empty():
			enemy_planned_move = atks.pick_random()

	if has("predators_memory"):
		_reveal_tell(false)
	else:
		enemy_tell_label.text = "Tell: observe to reveal"

	_refresh_ui()
	_log("")
	_log("[b]A " + enemy_name.to_upper() + " blocks your path.[/b]   [color=#888888](" + str(battle_num) + "/" + str(run_encounters.size()) + ")[/color]")
	_log("[i][color=#8faab5]" + str(sp["flavor"]) + "[/color][/i]")
	if current_mod != "":
		_log("[i][color=#ff9966]" + str(GameData.modifiers[current_mod]["name"]).to_upper() + " — " + str(GameData.modifiers[current_mod]["desc"]) + "[/color][/i]")
	_log("[color=#444444]─────────────────────────────[/color]")
	_set_player_turn(true)


func _apply_modifier(id: String) -> bool:
	var flags : Dictionary = GameData.modifiers[id].get("flags", {})
	# Ambush-style start damage never fires when the player is already at 1 HP.
	if int(flags.get("start_hp", 0)) < 0 and player_hp <= 1:
		return false
	current_mod = id
	mod_flags = flags.duplicate()
	if mod_flags.has("start_breath"):
		player_breath = maxi(player_breath + int(mod_flags["start_breath"]), 0)
	if mod_flags.has("start_hp"):
		player_hp = maxi(player_hp + int(mod_flags["start_hp"]), 1)
	if mod_flags.has("enemy_hp"):
		var bonus := int(mod_flags["enemy_hp"])
		enemy_max_hp += bonus
		enemy_hp += bonus
	if mod_flags.has("blood_bonus"):
		enemy_blood_reward += int(mod_flags["blood_bonus"])
	return true


func _execute_turn(action: String) -> void:
	if battle_over or not player_turn:
		return
	var md : Dictionary = GameData.player_moves.get(action, {})
	if md.is_empty():
		return
	var kind := str(md.get("kind", "utility"))

	_hide_wheel()
	_set_player_turn(false)
	player_mitigate   = 0
	player_counter    = 0
	_attack_hit       = false
	_missed           = false
	_fully_mitigated  = false
	_took_unmitigated = 0
	_took_any_hit     = false
	var prev_was_observe := last_was_observe

	var cost := int(md.get("cost", 0))
	if kind == "attack" and has("hunters_patience") and not did_attack_this_battle and prev_was_observe:
		cost = 0   # Hunter's Patience: the FIRST attack of the battle, if after an Observe, is free.
	player_breath -= cost
	if kind == "attack":
		did_attack_this_battle = true
	elif kind == "defend":
		player_mitigate = int(md.get("mitigate", 1))
		player_counter  = int(md.get("counter", 0))

	# ── ENEMY PHASE (resolved + narrated first) ────────────────────────────────
	_resolve_enemy_phase(enemy_planned_move)
	_refresh_ui()
	if player_hp <= 0:
		player_hp = 0
		_refresh_ui()
		await get_tree().create_timer(0.35).timeout
		_game_over("The " + enemy_name + " overwhelms you.")
		return

	await get_tree().create_timer(0.5).timeout

	# ── PLAYER PHASE ───────────────────────────────────────────────────────────
	_resolve_player_phase(action, enemy_acted_move, prev_was_observe)
	turn_attack_bonus = 0   # this-turn items expire whether or not they were used
	turn_shield = 0
	unyielding_active = unyielding_staged   # Unyielding pays out on the turn AFTER mitigating
	unyielding_staged = false

	if action == "observe":
		observes_battle += 1
		var gain := maxi(OBSERVE_BREATH_GAIN - int(mod_flags.get("observe_penalty", 0)), 0)
		player_breath += gain
		_log("[color=#44ccff]You observe carefully.[/color]  Breath +" + str(gain) + ".")

	if player_breath > max_breath():
		if has("watchful_silence"):
			var excess := player_breath - max_breath()
			var before_ws := ws_bonus
			ws_bonus = mini(ws_bonus + excess, 3)
			player_breath = max_breath()
			_log("[color=#88ccff]Watchful Silence banks the overflow: " + str(ws_bonus) + "/3 stored for your next attack.[/color]" if ws_bonus > before_ws else "[color=#6699cc]Watchful Silence is already at capacity (+3).[/color]")
		else:
			player_breath -= 1
			_log("[i][color=#6699cc]Your overcharged breath escapes you.[/color][/i]  Breath: " + str(player_breath))

	_apply_dominance(action)

	match kind:
		"attack":
			def_streak = 0; obs_streak = 0
			atk_streak = atk_streak + 1 if _attack_hit else 0
		"defend":
			atk_streak = 0; obs_streak = 0; def_streak += 1
			if has("defensive_posture") and def_streak >= 2:
				player_breath = mini(player_breath + 1, max_breath())
				_log("[color=#88ffaa]Defensive Posture restores 1 Breath.[/color]")
		_:
			atk_streak = 0; def_streak = 0; obs_streak += 1

	last_was_observe = action == "observe"
	_refresh_ui()

	if enemy_hp <= 0:
		_finish_kill()
		return

	enemy_planned_move = _plan_move()
	if reveal_battle:
		_reveal_tell(true)
	elif action == "observe":
		_reveal_tell(false)
	else:
		enemy_tell_label.text = "Tell: observe to reveal"

	_refresh_ui()
	_log("[color=#444444]─────────────────────────────[/color]")
	_set_player_turn(true)


func _apply_dominance(action: String) -> void:
	var d := 0
	if _attack_hit:            d += 1
	if _fully_mitigated:       d += 1
	d -= _took_unmitigated
	if _missed:                d -= (2 if dominance > 0 else 1)   # a whiff while ahead stings more
	if action == "observe":
		# Stalk: only the FIRST observe of the battle, and only if unhit.
		if has("stalk") and observes_battle == 1 and not _took_any_hit:
			d += 1
		if dominance < 0 and not _took_any_hit:
			d += 1
	if d == 0:
		return
	var before := dominance
	dominance = clampi(dominance + d, DOM_MIN, DOM_MAX)
	if dominance != before:
		var arrow := "▲" if dominance > before else "▼"
		_log("[color=#b0a0e0]Dominance " + arrow + "  " + _dom_signed(dominance) + "[/color]")


func _resolve_enemy_phase(move: String) -> void:
	if enemy_breath < mcost(move):
		move = "rest"
	enemy_breath -= mcost(move)
	enemy_acted_move = move
	enemy_last_move  = move

	if _is_attack(move):
		var base_dmg : int = mdmg(move)
		var enraged : bool = sp_flags.get("enraged", false) and enemy_hp <= int(enemy_max_hp * 0.4)
		if enraged:
			base_dmg += 1
		var verb : String = mverb(move)
		var rage_note : String = "  [color=#ff6644](enraged)[/color]" if enraged else ""

		if player_mitigate > 0:
			var mit := player_mitigate
			if mit < 99:
				mit += guard_reduction() - 1     # Dominance ≥4 blocks an extra point
			var reduced := maxi(base_dmg - mit + incoming_extra(), 0)
			if reduced > 0:
				player_hp -= reduced
				_took_any_hit = true
				_log(enemy_name + " [color=#ff4444]" + verb + "![/color]  You hold — take [b]" + str(reduced) + "[/b]." + rage_note)
			else:
				_fully_mitigated = true
				_log(enemy_name + " " + verb + " — [color=#44ff88]fully turned aside![/color]")
			if player_counter > 0:
				enemy_hp -= player_counter
				_log("[color=#ffaa44]You counter for " + str(player_counter) + ".[/color]")
			_on_mitigate(reduced == 0)
			if move == "bite":
				enemy_breath = maxi(enemy_breath - 1, 0)
				_log("[i][color=#88ccff]You caught the Bite — it cost the " + enemy_name + " dearly.[/color][/i]")
			if sp_flags.get("block_suppress", false):
				enemy_block_suppress = 2
				_log("[i][color=#88ccff]Its rhythm breaks. It hesitates to press.[/color][/i]")
		else:
			var final_dmg := maxi(base_dmg + incoming_extra() - turn_shield, 0)
			if turn_shield > 0:
				_log("[color=#88ccff]Pelt absorbs " + str(base_dmg + incoming_extra() - final_dmg) + ".[/color]")
			if final_dmg <= 0:
				_fully_mitigated = true
				_log(enemy_name + " " + verb + " — [color=#44ff88]but it glances off![/color]")
			else:
				player_hp -= final_dmg
				_took_unmitigated += final_dmg
				_took_any_hit = true
				_log(enemy_name + " [color=#ff4444]" + verb + "![/color]  You take [b]" + str(final_dmg) + "[/b]." + rage_note)
			if move == "bite":
				enemy_breath = mini(enemy_breath + 1, enemy_max_breath)
				_log("[i][color=#ffaa88]The Bite lands raw — it barely paid a breath for it.[/color][/i]")
		return

	match move:
		"dig":
			var dh := int(GameData.moves["dig"].get("heal", 3))
			if randf() < 0.5:
				enemy_hp = mini(enemy_hp + dh, enemy_max_hp)
				_log(enemy_name + " [color=#88ff44]roots up a truffle and heals " + str(dh) + "![/color]")
			else:
				_log(enemy_name + " digs furiously... but finds nothing.")
		"feint":
			# Feint only pays off (recovers Breath) if the player takes the bait and defends.
			if player_mitigate > 0:
				enemy_breath = mini(enemy_breath + int(GameData.moves["feint"].get("breath_gain", 0)), enemy_max_breath)
				_log(enemy_name + " [color=#ffaa44]" + mverb("feint") + "[/color] — [i]a feint! Your guard was the bait; it catches its breath.[/i]")
			else:
				_log(enemy_name + " [color=#ffaa44]" + mverb("feint") + "[/color] — [i]a feint, but you didn't bite.[/i]")
		"rest":
			enemy_breath = enemy_max_breath
			_log(enemy_name + " " + mverb("rest") + ".")
		_:
			_log(enemy_name + " " + mverb(move) + ".")


func _on_mitigate(full: bool) -> void:
	if has("unyielding"):
		unyielding_staged = true   # pays out next turn
	if has("counter_reflex") and randf() < 0.5:
		enemy_hp -= 1
		_log("[color=#ffaa44]Counter Reflex bites for 1.[/color]")
	if full and has("iron_nerves"):
		player_breath = mini(player_breath + 1, max_breath())
		_log("[color=#88ffaa]Iron Nerves restores 1 Breath.[/color]")
	if full and has("evasive_reflexes"):
		enemy_breath = maxi(enemy_breath - 1, 0)
		_log("[color=#88ccff]Evasive Reflexes drains 1 enemy Breath.[/color]")


func _resolve_player_phase(action: String, enemy_move: String, prev_was_observe: bool) -> void:
	var md : Dictionary = GameData.player_moves.get(action, {})
	match str(md.get("kind", "utility")):
		"attack":
			# Wolf Fang / Pounce: ignore the enemy's defense.
			var defends := enemy_move == "dodge" or enemy_move == "block"
			var bypass := false
			if next_ignores_defense:
				next_ignores_defense = false
				if defends:
					bypass = true
					defends = false
			if md.get("ignore_block", false) and enemy_move == "block":
				bypass = true
				defends = false          # Pounce goes through a Guard, but a Dodge still evades
			var unguarded := not defends

			var dmg := int(md.get("damage", 2)) + dom_attack_bonus()
			var tags : PackedStringArray = []
			if dom_attack_bonus() != 0:
				tags.append(_dom_signed(dom_attack_bonus()) + " edge")
			if bypass:
				tags.append("unstoppable")
			if unyielding_active:
				dmg += 1; tags.append("unyielding")
			if has("ambush") and not _attacked_before_this():
				dmg += 1; tags.append("ambush")
			if has("perfect_read") and prev_was_observe and unguarded:
				dmg += 1; tags.append("read")
			if has("frenzy") and atk_streak > 0:
				var f := mini(atk_streak, 3)
				dmg += f; tags.append("frenzy+" + str(f))
			if has("apex_predator") and enemy_move == "rest":
				dmg += 1; tags.append("opportunist")
			if has("executioner") and unguarded and enemy_hp <= enemy_max_hp / 2:
				dmg += 1; tags.append("exec")
			if next_attack_bonus > 0:
				dmg += next_attack_bonus; tags.append("+" + str(next_attack_bonus) + " primed"); next_attack_bonus = 0
			if turn_attack_bonus > 0:
				dmg += turn_attack_bonus; tags.append("+" + str(turn_attack_bonus) + " sharp")
			if ws_bonus > 0:
				dmg += ws_bonus; tags.append("+" + str(ws_bonus) + " stored"); ws_bonus = 0
			dmg = maxi(dmg, 0)
			var note : String = "  [color=#888888](" + ", ".join(tags) + ")[/color]" if not tags.is_empty() else ""

			if not defends:
				enemy_hp -= dmg
				_attack_hit = true
				_on_attack_land()
				_log("[color=#ffdd44]You strike![/color]  " + enemy_name + " takes [b]" + str(dmg) + "[/b]." + note)
			elif enemy_move == "dodge":
				_missed = true
				_log("[color=#ffdd44]You strike![/color]  " + enemy_name + " slips aside — nothing lands.")
			else:  # block
				var through := maxi(dmg - 1, 0)
				if through > 0:
					enemy_hp -= through
					_attack_hit = true
					_on_attack_land()
					_log("[color=#ffdd44]You strike![/color]  " + enemy_name + " braces — [b]" + str(through) + "[/b] through." + note)
				else:
					_missed = true
					_log("[color=#ffdd44]You strike![/color]  " + enemy_name + " weathers it.")

		"defend":
			var nm := str(md.get("name", "Guard"))
			if _is_attack(enemy_move):
				_log("[color=#44ff88]You " + nm.to_lower() + ".[/color]  It cut the blow.")
			elif enemy_move == "feint":
				_log("[color=#ffaa44]You defended a feint.[/color]  It cost you the turn.")
			else:
				_log("[color=#44ff88]You " + nm.to_lower() + ".[/color]  Nothing came.")

		_:
			if action == "observe":
				pass   # handled in _execute_turn
			else:
				if md.has("enemy_breath"):
					enemy_breath = maxi(enemy_breath + int(md["enemy_breath"]), 0)
					_log("[color=#88ccff]" + str(md.get("name", "You")) + " — the " + enemy_name + " loses " + str(absi(int(md["enemy_breath"]))) + " Breath.[/color]")
				if md.has("next_attack"):
					next_attack_bonus += int(md["next_attack"])
					_log("[color=#ffdd88]" + str(md.get("name", "You")) + " — your next attack deals +" + str(int(md["next_attack"])) + ".[/color]")


func _attacked_before_this() -> bool:
	return atk_streak > 0 or _prior_attacks


func _on_attack_land() -> void:
	if has("crushing_pressure") and atk_streak >= 1:
		enemy_breath = maxi(enemy_breath - 1, 0)
		_log("[color=#88ccff]Crushing Pressure drains 1 enemy Breath.[/color]")
	_prior_attacks = true


func _finish_kill() -> void:
	enemy_hp = 0
	var gain := enemy_blood_reward
	if altar_double_first_kill:
		gain *= 2
		altar_double_first_kill = false
		_log("[color=#ffaaaa]Bloodrush doubles the take.[/color]")
	player_blood += gain
	var extra := 0
	if has("blood_scent"):
		extra += 2
		player_blood += 2
	var heal := 1 + (1 if has("predators_hunger") else 0)
	player_hp = mini(player_hp + heal, max_hp())
	_refresh_ui()
	_log("[color=#ff8888]+" + str(gain + extra) + " Blood.[/color]  [color=#88ffaa]Heal " + str(heal) + " HP.[/color]")

	# Behaviour Fragment — a rare scrap of what it knew (rarer prey, better odds).
	if randf() < 0.10 + 0.02 * float(_tier_of(enemy_species)):
		var cat := _pick_fragment_category(enemy_species)
		player_fragments[cat] = int(player_fragments.get(cat, 0)) + 1
		_log("[i][color=#cfa0ff]You watched how it moved. Something of it stays with you.[/color][/i]  [color=#cfa0ff]+1 " + _frag_cat_name(cat) + " Fragment[/color]")

	# Item drops — configured per species in animals.json ("drops": {chance, items}).
	var drops : Dictionary = GameData.animals.get(enemy_species, {}).get("drops", {})
	if not drops.is_empty() and randf() < float(drops.get("chance", 0.0)):
		var table : Array = drops.get("items", [])
		if not table.is_empty():
			_give_item(_resolve_drop_token(str(table.pick_random())))

	_prior_attacks = false
	# The shape fades out of the dark.
	var tw := create_tween()
	tw.tween_property(creature, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(0.8).timeout
	_win_battle()


func _win_battle() -> void:
	var br := 1 + (1 if has("second_wind") else 0)
	player_breath = mini(player_breath + br, max_breath())
	_refresh_ui()
	_log("[color=#44ff88][b]The " + enemy_name + " falls.[/b][/color]")
	phase_label.text = ""
	await get_tree().create_timer(0.7).timeout
	_next_step()


func _game_over(reason: String) -> void:
	battle_over = true
	ui_mode = "over"
	_buttons_enabled(false)
	_clear_run_save()
	_log("")
	_log("[color=#ff4444][b]DEFEATED.[/b][/color]  " + reason)
	_log("You reached encounter " + str(battle_num) + "/" + str(run_encounters.size()) + ".")
	phase_label.text = "DEFEATED"
	restart_btn.visible = true
	cave_btn.visible = true
	hint_label.visible = false
	_hide_wheel()


func _frag_cat_name(cat: String) -> String:
	match cat:
		"atk": return "Attack"
		"def": return "Defense"
	return "Special"


func _pick_fragment_category(sp_id: String) -> String:
	# Weighted by the species' own moveset: aggressive-leaning drops Attack fragments,
	# skittish-leaning drops Defense, tired/special-leaning drops Special.
	var mv : Dictionary = GameData.animals.get(sp_id, {}).get("moves", {})
	var w := { "atk": 0.0, "def": 0.0, "spc": 0.0 }
	for m in mv.keys():
		var wt := float(_resolve_weight(mv[m], 1.0))
		if wt <= 0.0:
			continue
		match _move_category(m):
			"aggressive": w["atk"] += wt
			"skittish":   w["def"] += wt
			_:            w["spc"] += wt
	var total : float = w["atk"] + w["def"] + w["spc"]
	if total <= 0.0:
		return ["atk", "def", "spc"].pick_random()
	var roll := randf() * total
	for k in ["atk", "def", "spc"]:
		roll -= w[k]
		if roll <= 0.0:
			return k
	return "spc"


func _tier_of(sp_id: String) -> int:
	var t : String = str(GameData.animals.get(sp_id, {}).get("tier", "")).to_lower()
	if t.contains("apex"):                        return 4
	if t.contains("elite") or t.contains("boss"): return 3
	if t.contains("late"):                        return 2
	if t.contains("mid"):                         return 1
	return 0


func _resolve_drop_token(tok: String) -> String:
	match tok:
		"random":          return _random_item()
		"random_common":   return _random_item_rarity("common")
		"random_uncommon": return _random_item_rarity("uncommon")
		"random_rare":     return _random_item_rarity("rare")
	return tok   # a specific item id (e.g. an exclusive)


func _random_item_rarity(r: String) -> String:
	var pool : Array = []
	for id in GameData.items.keys():
		if str(GameData.items[id].get("rarity", "common")) == r:
			pool.append(id)
	if pool.is_empty():
		return _random_item()
	return pool.pick_random()


func _random_item() -> String:
	var pool : Array = []
	var weights : Array = []
	for id in GameData.items.keys():
		var r : String = str(GameData.items[id].get("rarity", "common"))
		if not RARITY_WEIGHT.has(r):
			continue   # exclusive items never appear in random rolls
		pool.append(id)
		weights.append(int(RARITY_WEIGHT[r]))
	if pool.is_empty():
		return GameData.items.keys()[0]
	var total := 0
	for w in weights:
		total += w
	var roll := randi() % total
	for i in pool.size():
		roll -= weights[i]
		if roll < 0:
			return pool[i]
	return pool[0]


# ══════════════════════════════════════════════════════════════════════════════
#  ENEMY AI + READS
# ══════════════════════════════════════════════════════════════════════════════
func _resolve_weight(spec, hp_frac: float) -> int:
	if typeof(spec) == TYPE_DICTIONARY:
		var full := float(spec.get("full", 0))
		var empty := float(spec.get("empty", 0))
		return maxi(0, int(round(empty + (full - empty) * hp_frac)))
	return maxi(0, int(spec))


func _plan_move() -> String:
	# Boss: a spent Bear heaves through a two-turn rest (a wide, readable punish window).
	if enemy_forced_rest > 0:
		enemy_forced_rest -= 1
		return "rest"

	var hp_frac := float(enemy_hp) / float(maxi(enemy_max_hp, 1))
	var pool : Array = []
	for m in sp_moves.keys():
		for i in _resolve_weight(sp_moves[m], hp_frac):
			pool.append(m)

	var atks := pool.filter(_is_attack)
	var defs := pool.filter(func(m): return _move_category(m) == "skittish")

	# Dominance bends behaviour: behind → it presses; ahead → prey turn skittish.
	if dominance < 0 and not atks.is_empty():
		for i in mini(2, int(ceil(-dominance / 2.0))):
			pool.append(atks.pick_random())
		if dominance <= -3:
			var heavy := pool.filter(func(m): return _is_attack(m) and _move_weight(m) == "heavy")
			if not heavy.is_empty():
				pool.append(heavy.pick_random())
	elif dominance > 0 and not defs.is_empty():
		for i in mini(2, int(ceil(dominance / 2.0))):
			pool.append(defs.pick_random())

	# Battle modifier: extra aggression.
	for i in int(mod_flags.get("enemy_aggression", 0)):
		if not atks.is_empty():
			pool.append(atks.pick_random())

	if sp_flags.get("aggressive_low_breath", false) and player_breath <= 2 and not atks.is_empty():
		pool.append(atks.pick_random())

	# Block-suppress: after a clean block, drop up to 2 attacks — less likely to press, not impossible.
	if enemy_block_suppress > 0:
		enemy_block_suppress -= 1
		var removed := 0
		var trimmed : Array = []
		for m in pool:
			if removed < 2 and _is_attack(m):
				removed += 1
				continue
			trimmed.append(m)
		pool = trimmed

	# Rhythm (deer): lean opposite its last move.
	if sp_flags.get("rhythm", false) and enemy_last_move != "":
		if _is_attack(enemy_last_move):
			pool.append_array(defs)
		elif not atks.is_empty():
			pool.append(atks.pick_random())

	var affordable := pool.filter(func(m): return mcost(m) <= enemy_breath)
	if affordable.is_empty():
		if sp_flags.get("boss_double_rest", false):
			enemy_forced_rest = 1   # this rest + one more forced next turn
		return "rest"
	return affordable.pick_random()


func _reveal_tell(force_exact: bool) -> void:
	var move := enemy_planned_move
	var cat := _move_category(move)
	var special := cat == "special"
	var display_cat := "distracted" if special else cat   # a revealed special (e.g. Dig) reads "distracted"
	var pierce := force_exact or (has("pattern_recognition") and observes_battle >= 2)
	var is_calm := false
	if not pierce:
		var cc := sp_calm + float(mod_flags.get("calm_up", 0.0))
		if special:
			cc += 0.3   # special moves are slightly more likely to read Calm
		if dominance < 0:
			cc += 0.06 * float(-dominance)
		elif dominance > 0:
			cc -= 0.05 * float(dominance)
		if sp_flags.get("calm_cornered", false) and enemy_hp <= enemy_max_hp / 2:
			cc += 0.35
		if has("keen_eye"):
			cc *= 0.35
		cc = clampf(cc, 0.0, 0.9)
		is_calm = randf() < cc
	var display := "calm — unreadable" if is_calm else display_cat

	# Weight class only makes sense on concrete reads — not Calm, not Tired.
	var weight_ok := not is_calm and cat != "tired"
	if weight_ok and force_exact:
		display += "  ·  " + _move_weight(move)
	elif weight_ok and observes_battle >= 2 and randf() < minf(0.12 * float(observes_battle - 1), 0.45):
		display += "  ·  " + _move_weight(move) + " read"
	enemy_tell_label.text = "Tell: " + display


# ══════════════════════════════════════════════════════════════════════════════
#  INSTINCT REWARDS
# ══════════════════════════════════════════════════════════════════════════════
func _offer_instinct() -> void:
	var candidates : Array = []
	for id in GameData.instincts.keys():
		if not has(id) and cat_count(GameData.instincts[id]["cat"]) < CAT_CAP:
			candidates.append(id)
	candidates.shuffle()
	if candidates.is_empty():
		_log("[color=#888888]Your instincts are already honed (all categories full).[/color]")
		_next_step()
		return

	var picks : Array = candidates.slice(0, mini(3, candidates.size()))
	var choices : Array = []
	for i in picks.size():
		var id : String = picks[i]
		var cost := 0
		if i == picks.size() - 1 and picks.size() >= 2:
			cost = 4 + battle_num / 2
		choices.append({
			"text": _instinct_text(id, cost),
			"cost": cost,
			"outcome": _grant_instinct.bind(id),
		})
	_log("")
	_log("[color=#ffcc66][b]An instinct sharpens.[/b]  Choose one:[/color]")
	pending_followup = ""
	_show_choices("INSTINCT", choices)


func _instinct_text(id: String, cost: int) -> String:
	var info : Dictionary = GameData.instincts[id]
	var t : String = str(info["name"]).to_upper() + "  [" + str(GameData.cat_names[info["cat"]]) + "]\n" + str(info["desc"])
	if cost > 0:
		t += "\n[ Blood " + str(cost) + " ]"
	return t


func _grant_instinct(id: String) -> void:
	if cat_count(GameData.instincts[id]["cat"]) >= CAT_CAP:
		_log("[color=#888888]" + str(GameData.cat_names[GameData.instincts[id]["cat"]]) + " is full — open the Pouch to make room.[/color]")
		return
	owned_instincts.append(id)
	_apply_instinct_stats(id)
	_log("[color=#ffcc66]Gained " + str(GameData.instincts[id]["name"]) + ".[/color]")
	_refresh_ui()


func _apply_instinct_stats(id: String) -> void:
	if id == "thick_hide":
		player_hp += 1
	if id == "deep_lungs" or id == "endurance":
		player_breath += 1


# ══════════════════════════════════════════════════════════════════════════════
#  EVENTS
# ══════════════════════════════════════════════════════════════════════════════
func _offer_event(id: String) -> void:
	if id == "raccoon":
		_start_raccoon()
		return
	var ev : Dictionary = GameData.events[id]
	_log("")
	_log("[color=#aaeeff][b]" + str(ev["title"]) + "[/b][/color]")
	_log("[i]" + str(ev["intro"]) + "[/i]")
	var choices : Array = []
	for c in ev["choices"]:
		var cost : int = int(c.get("cost", 0))
		choices.append({
			"text": str(c["text"]),
			"cost": cost,
			"outcome": _apply_event_effect.bind(c["eff"]),
		})
	_show_choices(str(ev["title"]), choices)


func _start_raccoon() -> void:
	var pool : Array = []
	for id in GameData.items.keys():
		if RARITY_WEIGHT.has(str(GameData.items[id].get("rarity", "common"))):
			pool.append(id)
	pool.shuffle()
	raccoon_stock = pool.slice(0, mini(2, pool.size()))
	_log("")
	_log("[color=#aaeeff][b]THE TRADER[/b][/color]")
	_log("[i]A ring-eyed raccoon spreads its wares on a flat stone and grins.[/i]")
	_offer_raccoon()


func _offer_raccoon() -> void:
	var choices : Array = []
	for id in raccoon_stock:
		var cost := _raccoon_price(id)
		choices.append({
			"text": "BUY " + str(GameData.items[id]["name"]).to_upper() + "\n" + str(GameData.items[id]["desc"]) + "\n[ Blood " + str(cost) + " ]",
			"cost": cost,
			"outcome": _raccoon_buy.bind(id),
		})
	choices.append({ "text": "LEAVE\nMove on", "cost": 0, "outcome": func(): _log("[i]You leave the trader to its trinkets.[/i]") })
	_show_choices("THE TRADER", choices)


func _raccoon_price(id: String) -> int:
	match str(GameData.items[id].get("rarity", "common")):
		"rare":     return 6
		"uncommon": return 4
		_:          return 3


func _raccoon_buy(id: String) -> void:
	_give_item(id)
	raccoon_stock.erase(id)
	pending_followup = "raccoon"   # re-open the stall instead of moving on


func _apply_event_effect(eff: Dictionary) -> void:
	if eff.has("heal"):
		if int(eff["heal"]) >= 90:
			player_hp = max_hp()
		else:
			var h : int = int(eff["heal"]) + (1 if has("efficient_metabolism") else 0)
			player_hp = mini(player_hp + h, max_hp())
		_log("[color=#88ffaa]Healed.  HP " + str(player_hp) + "/" + str(max_hp()) + ".[/color]")
	if eff.has("breath"):
		if int(eff["breath"]) >= 90:
			player_breath = max_breath()
		else:
			player_breath = mini(player_breath + int(eff["breath"]), max_breath())
		_log("[color=#88ccff]Breath restored to " + str(player_breath) + ".[/color]")
	if eff.has("blood"):
		var b : int = int(eff["blood"])
		if b > 0 and has("scavenger"):
			b += 2
		player_blood = maxi(player_blood + b, 0)
		_log("[color=#ff8888]Blood " + ("+" if b >= 0 else "") + str(b) + ".  Total " + str(player_blood) + ".[/color]")
	if eff.has("max_breath"):
		if not has("endurance") and cat_count("sur") < CAT_CAP:
			owned_instincts.append("endurance")
			player_breath += 1
		_log("[i][color=#88ccff]Your lungs deepen.[/color][/i]  +1 Max Breath.")
	if eff.has("item"):
		var iid : String = eff["item"]
		if iid == "random":
			iid = _random_item()
		_give_item(iid)
	if eff.has("fragment"):
		var cat : String = ["atk", "def", "spc"].pick_random()
		player_fragments[cat] = int(player_fragments.get(cat, 0)) + 1
		_log("[i][color=#cfa0ff]You commit a behaviour to memory.[/color][/i]  [color=#cfa0ff]+1 " + _frag_cat_name(cat) + " Fragment[/color]")
	if eff.has("gamble"):
		_gamble(eff["gamble"])
	if eff.has("random_instinct"):
		_grant_random_instinct()
	if eff.has("instinct_choice"):
		pending_followup = "instinct"
	_refresh_ui()


func _gamble(id: String) -> void:
	match id:
		"bear":
			if randf() < 0.55:
				player_blood += 6
				_log("[color=#88ff44]You drag off the kill before it stirs! +6 Blood and a prize.[/color]")
				_give_item("ancient_acorn")
			else:
				var d := mini(3, player_hp - 1) if player_hp > 1 else 1
				player_hp = maxi(player_hp - d, 1)
				_log("[color=#ff4444]Its eyes snap open![/color]  It mauls you for " + str(d) + ".")
		"eyes":
			if randf() < 0.5:
				player_blood += 5
				_log("[color=#88ff44]It decides you aren't worth it and slinks off. +5 Blood.[/color]")
			else:
				var d := mini(2, player_hp - 1) if player_hp > 1 else 1
				player_hp = maxi(player_hp - d, 1)
				_log("[color=#ff4444]It lunges first![/color]  You take " + str(d) + ".")
		"berries":
			if randf() < 0.6:
				player_hp = mini(player_hp + 4, max_hp())
				_log("[color=#88ffaa]Sweet and safe. Heal 4.[/color]")
			else:
				var d := mini(2, player_hp - 1) if player_hp > 1 else 1
				player_hp = maxi(player_hp - d, 1)
				_log("[color=#aa66ff]Poison! You lose " + str(d) + " HP.[/color]")
		"trapped":
			if randf() < 0.7:
				_log("[color=#88ff44]It bolts free — and leaves something behind.[/color]")
				_give_item(_random_item())
			else:
				_log("[i]It scrambles into the dark. Nothing for you.[/i]")
		"cub":
			if randf() < 0.6:
				player_blood += 6
				_log("[color=#88ff44]At dawn its mother returns and leads you to a kill. +6 Blood.[/color]")
			else:
				var d := mini(2, player_hp - 1) if player_hp > 1 else 1
				player_hp = maxi(player_hp - d, 1)
				_log("[color=#ff4444]Its mother finds you first and drives you off (-" + str(d) + ").[/color]")
		"altar":
			var d := mini(2, player_hp - 1) if player_hp > 1 else 1
			player_hp = maxi(player_hp - d, 1)
			player_blood += d * 4
			_log("[color=#ff8888]You give " + str(d) + " HP; the altar gives " + str(d * 4) + " Blood.[/color]")
		_:
			if randf() < 0.55:
				player_blood += 7
				_log("[color=#88ff44]It pays off. +7 Blood.[/color]")
			else:
				var d := mini(2, player_hp - 1) if player_hp > 1 else 1
				player_hp = maxi(player_hp - d, 1)
				_log("[color=#ff4444]It goes wrong (-" + str(d) + " HP).[/color]")


func _grant_random_instinct() -> void:
	var pool : Array = []
	for id in GameData.instincts.keys():
		if not has(id) and cat_count(GameData.instincts[id]["cat"]) < CAT_CAP:
			pool.append(id)
	if pool.is_empty():
		player_blood += 5
		_log("[color=#888888]Nothing new to learn — Blood returned.[/color]")
		return
	_grant_instinct(pool.pick_random())


func _give_item(id: String) -> void:
	inventory.append(id)
	_log("[color=#ffd089]Item: " + str(GameData.items[id]["name"]) + " — " + str(GameData.items[id]["desc"]) + "[/color]")


# ══════════════════════════════════════════════════════════════════════════════
#  POUCH / INSTINCT MENU
# ══════════════════════════════════════════════════════════════════════════════
func _toggle_pouch() -> void:
	pouch_overlay.visible = not pouch_overlay.visible
	if pouch_overlay.visible:
		bestiary_overlay.visible = false
		_rebuild_pouch()


func _toggle_bestiary() -> void:
	bestiary_overlay.visible = not bestiary_overlay.visible
	if bestiary_overlay.visible:
		pouch_overlay.visible = false


func _rebuild_pouch() -> void:
	for c in pouch_list.get_children():
		c.queue_free()
	pouch_title.text = "POUCH    ·    Blood %d" % player_blood

	_pouch_header("INSTINCTS")
	for cat in ["obs", "atk", "def", "sur"]:
		var ids : Array = owned_instincts.filter(func(id): return GameData.instincts[id]["cat"] == cat)
		_pouch_subheader(str(GameData.cat_names[cat]) + "   (" + str(ids.size()) + "/" + str(CAT_CAP) + ")")
		if ids.is_empty():
			_pouch_note("—")
		for id in ids:
			var can_remove := not battle_over and ui_mode != "choice"
			_pouch_row(str(GameData.instincts[id]["name"]) + " — " + str(GameData.instincts[id]["desc"]),
				"REMOVE", _remove_instinct.bind(id), can_remove)

	_pouch_header("ITEMS  (single use)")
	if inventory.is_empty():
		_pouch_note("—  no items")
	else:
		var usable := player_turn and not battle_over and ui_mode == "combat"
		for i in inventory.size():
			var id : String = inventory[i]
			_pouch_row(str(GameData.items[id]["name"]) + " — " + str(GameData.items[id]["desc"]),
				"USE", _use_item.bind(i), usable)


func _pouch_header(text: String) -> void:
	var l := Label.new()
	l.text = "\n" + text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	pouch_list.add_child(l)


func _pouch_subheader(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.75, 1))
	pouch_list.add_child(l)


func _pouch_note(text: String) -> void:
	var l := Label.new()
	l.text = "   " + text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	pouch_list.add_child(l)


func _pouch_row(text: String, btn_text: String, cb: Callable, enabled: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	var b := Button.new()
	b.text = btn_text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(90, 0)
	b.pressed.connect(cb)
	row.add_child(l)
	row.add_child(b)
	pouch_list.add_child(row)


func _remove_instinct(id: String) -> void:
	owned_instincts.erase(id)
	if id == "thick_hide":
		player_hp = mini(player_hp, max_hp())
	if id == "deep_lungs" or id == "endurance":
		player_breath = mini(player_breath, max_breath())
	_log("[color=#cc8888]Released instinct: " + str(GameData.instincts[id]["name"]) + ".[/color]")
	_refresh_ui()
	_rebuild_pouch()


func _use_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var id : String = inventory[index]
	inventory.remove_at(index)
	match id:
		"crow_feather":  player_breath = mini(player_breath + 1, max_breath())
		"dried_meat":    player_breath = mini(player_breath + 2, max_breath())
		"sharp_stone":   turn_attack_bonus += 2
		"pelt":          turn_shield += 2
		"spider_egg":    enemy_breath = maxi(enemy_breath - 1, 0)
		"owl_eye":       _reveal_tell(true)
		"ancient_acorn": player_hp = max_hp()
		"bear_claw":     next_attack_bonus += 3
		"wolf_fang":     next_ignores_defense = true
		"stag_heart":
			reveal_battle = true
			_reveal_tell(true)
		"bloodroot":
			enemy_hp -= 1
			if enemy_hp <= 0:
				_log("[color=#ffd089]Bloodroot finishes it![/color]")
				_refresh_ui()
				_finish_kill()
				return
	_log("[color=#ffd089]Used " + str(GameData.items[id]["name"]) + ".[/color]")
	_refresh_ui()
	_rebuild_pouch()


# ══════════════════════════════════════════════════════════════════════════════
#  CHOICE UI
# ══════════════════════════════════════════════════════════════════════════════
func _show_choices(title: String, choices: Array) -> void:
	ui_mode = "choice"
	pending_choices = choices
	phase_label.text = title
	_hide_wheel()
	hint_label.visible = false
	button_hbox.visible = true
	var btns := [observe_btn, claw_btn, guard_btn]
	for j in 3:
		btns[j].modulate = Color(1, 1, 1)
		if j < choices.size():
			btns[j].visible  = true
			btns[j].text     = choices[j]["text"]
			btns[j].disabled = choices[j]["cost"] > 0 and player_blood < choices[j]["cost"]
		else:
			btns[j].visible  = false


func _restore_combat_buttons() -> void:
	ui_mode = "combat"
	button_hbox.visible = false      # the 3-button row is only for events / instincts
	hint_label.visible = true
	_hide_wheel()


func _rebuild_wheel() -> void:
	for c in wheel_list.get_children():
		c.queue_free()
	for i in equipped_moves.size():
		var id : String = equipped_moves[i]
		var md : Dictionary = GameData.player_moves.get(id, {})
		var b := Button.new()
		b.text = ("▶  " if i == selected_move else "     ") + str(md.get("name", id)) + "\n      " + str(md.get("desc", ""))
		b.custom_minimum_size = Vector2(0, 54)
		b.disabled = player_breath < int(md.get("cost", 0)) or not player_turn or battle_over
		b.modulate = Color(1, 1, 1) if i == selected_move else Color(0.66, 0.66, 0.7)
		b.pressed.connect(_execute_turn.bind(id))
		b.mouse_entered.connect(_on_wheel_hover.bind(i))
		wheel_list.add_child(b)


func _on_wheel_hover(i: int) -> void:
	if selected_move != i:
		selected_move = i
		_rebuild_wheel()


func _show_wheel(from_scroll: bool) -> void:
	if not _combat_input_ready():
		return
	wheel_open = true
	wheel_from_scroll = from_scroll
	wheel_timer = WHEEL_HIDE_DELAY
	move_wheel.visible = true
	_rebuild_wheel()


func _hide_wheel() -> void:
	wheel_open = false
	wheel_from_scroll = false
	move_wheel.visible = false


func _cycle_move(dir: int) -> void:
	if equipped_moves.is_empty():
		return
	selected_move = wrapi(selected_move + dir, 0, equipped_moves.size())
	_rebuild_wheel()


func _confirm_move() -> void:
	if equipped_moves.is_empty() or selected_move >= equipped_moves.size():
		return
	var id : String = equipped_moves[selected_move]
	if player_breath < int(GameData.player_moves.get(id, {}).get("cost", 0)):
		return
	_execute_turn(id)


func _process(delta: float) -> void:
	# A wheel raised by scrolling fades out once you stop scrolling.
	if wheel_open and wheel_from_scroll:
		wheel_timer -= delta
		if wheel_timer <= 0.0:
			_hide_wheel()


func _on_creature_clicked() -> void:
	if ui_mode == "combat" and player_turn and not battle_over:
		_execute_turn("observe")


func _resolve_choice(i: int) -> void:
	if i >= pending_choices.size():
		return
	var c : Dictionary = pending_choices[i]
	if c["cost"] > 0:
		if player_blood < c["cost"]:
			return
		player_blood -= c["cost"]
	pending_followup = ""
	ui_mode = "resolving"
	_buttons_enabled(false)
	if c.get("outcome") is Callable:
		c["outcome"].call()
	_refresh_ui()
	if player_hp <= 0:
		_game_over("Your wounds catch up with you.")
		return
	if pending_followup == "instinct":
		pending_followup = ""
		_offer_instinct()
		return
	if pending_followup == "raccoon":
		pending_followup = ""
		_offer_raccoon()
		return
	_next_step()


# ══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _on_button(i: int) -> void:
	if ui_mode == "combat":
		match i:
			0: _execute_turn("observe")
			1: _execute_turn("claw")
			2: _execute_turn("guard")
	elif ui_mode == "choice":
		_resolve_choice(i)


func _set_player_turn(value: bool) -> void:
	player_turn = value
	if value:
		if has("last_stand") and player_hp <= max_hp() / 2:
			player_breath = mini(player_breath + 1, max_breath())
		phase_label.text   = ""
		_buttons_enabled(true)
		if wheel_open:
			_rebuild_wheel()
	else:
		phase_label.text = "RESOLVING..."
		_buttons_enabled(false)


func _buttons_enabled(on: bool) -> void:
	observe_btn.disabled = not on
	claw_btn.disabled    = not on
	guard_btn.disabled   = not on


func _dom_signed(v: int) -> String:
	return ("+" + str(v)) if v > 0 else str(v)


func _dom_status() -> String:
	if dominance >= 4:
		return "COMMANDING   dmg " + _dom_signed(dom_attack_bonus()) + " · block +1"
	elif dominance > 0:
		return "AHEAD   dmg " + _dom_signed(dom_attack_bonus())
	elif dominance == 0:
		return "EVEN"
	elif dominance <= -5:
		return "BROKEN   dmg -1 · +1 taken"
	elif dominance <= -3:
		return "CORNERED   dmg -1"
	return "SLIPPING"


func _refresh_ui() -> void:
	player_hp_bar.max_value = max_hp()
	player_hp_bar.value     = player_hp
	player_hp_label.text    = "HP  %d / %d" % [player_hp, max_hp()]
	breath_label.text       = "Breath  %d / %d" % [player_breath, max_breath()]
	status_label.text       = _dom_status()
	blood_label.text        = "Blood  %d    Frag A%d D%d S%d" % [
		player_blood, int(player_fragments.get("atk", 0)), int(player_fragments.get("def", 0)), int(player_fragments.get("spc", 0))]

	dom_bar.value  = dominance
	dom_bar.modulate = Color(0.45, 0.85, 0.45) if dominance >= 0 else Color(0.9, 0.4, 0.4)
	dom_label.text = "DOMINANCE  " + _dom_signed(dominance)

	enemy_hp_bar.max_value = enemy_max_hp
	enemy_hp_bar.value     = enemy_hp
	enemy_hp_label.text    = "HP  %d / %d" % [enemy_hp, enemy_max_hp]
	enemy_name_label.text  = "%s   ·   %d/%d" % [enemy_name.to_upper(), battle_num, run_encounters.size()]


func _log(text: String) -> void:
	combat_log.append_text(text + "\n")


func _fade_in() -> void:
	overlay.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.0, 0.8)


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	if not battle_over:
		_save_now()   # capture live progress so the run resumes here
	get_tree().change_scene_to_file("res://Scenes/save_select.tscn")


func _on_cave_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/cave.tscn")


# ══════════════════════════════════════════════════════════════════════════════
#  DEBUG OVERLAY  (press ` to toggle)
# ══════════════════════════════════════════════════════════════════════════════
func _combat_input_ready() -> bool:
	return ui_mode == "combat" and player_turn and not battle_over and not debug_open \
		and not pouch_overlay.visible and not bestiary_overlay.visible


func _click_is_protected(pos: Vector2) -> bool:
	# Areas that keep their own click behaviour even while the wheel is open.
	for c in [creature, menu_btn, bestiary_btn, exit_btn]:
		if c.visible and c.get_global_rect().has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	# Scroll raises the wheel and cycles it; middle-click commits the highlighted move.
	if event is InputEventMouseButton and event.pressed and _combat_input_ready():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if not wheel_open:
				_show_wheel(true)
			else:
				_cycle_move(dir)
			wheel_timer = WHEEL_HIDE_DELAY
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE and wheel_open:
			_confirm_move()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and wheel_open and not _click_is_protected(event.position):
			_confirm_move()
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k : int = event.keycode
	if k == KEY_QUOTELEFT:
		debug_open = not debug_open
		debug_panel.visible = debug_open
		debug_cat = ""
		debug_buffer = ""
		if debug_open:
			_debug_render()
		get_viewport().set_input_as_handled()
		return
	if not debug_open:
		if k == KEY_SPACE and _combat_input_ready():
			if wheel_open:
				_hide_wheel()
			else:
				_show_wheel(false)      # raised by SPACE → stays up until SPACE again
			get_viewport().set_input_as_handled()
		elif (k == KEY_ENTER or k == KEY_KP_ENTER) and wheel_open and _combat_input_ready():
			_confirm_move()
			get_viewport().set_input_as_handled()
		return

	if k == KEY_ESCAPE:
		if debug_cat == "":
			debug_open = false
			debug_panel.visible = false
		else:
			debug_cat = ""
			debug_buffer = ""
		_debug_render()
		get_viewport().set_input_as_handled()
		return

	if debug_cat == "":
		match k:
			KEY_S: debug_cat = "stats"
			KEY_I: debug_cat = "items"
			KEY_N: debug_cat = "instincts"
			KEY_E: debug_cat = "encounter"
			KEY_V: debug_cat = "event"
			KEY_M: debug_cat = "modifiers"
		debug_buffer = ""
		_debug_render()
		get_viewport().set_input_as_handled()
		return

	if k >= KEY_0 and k <= KEY_9:
		debug_buffer += str(k - KEY_0)
	elif k >= KEY_KP_0 and k <= KEY_KP_9:
		debug_buffer += str(k - KEY_KP_0)
	elif k == KEY_BACKSPACE:
		debug_buffer = debug_buffer.substr(0, maxi(debug_buffer.length() - 1, 0))
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_debug_apply()
		debug_buffer = ""
	_debug_render()
	get_viewport().set_input_as_handled()


func _debug_apply() -> void:
	if debug_buffer == "":
		return
	var n := int(debug_buffer)
	match debug_cat:
		"stats":     _debug_stat(n)
		"items":
			var keys : Array = GameData.items.keys()
			if n >= 1 and n <= keys.size():
				_give_item(keys[n - 1])
		"instincts":
			var keys : Array = GameData.instincts.keys()
			if n >= 1 and n <= keys.size():
				_debug_grant_instinct(keys[n - 1])
		"encounter": _debug_jump_encounter(n)
		"event":
			var keys : Array = GameData.events.keys()
			if n >= 1 and n <= keys.size():
				debug_open = false
				debug_panel.visible = false
				_offer_event(keys[n - 1])
		"modifiers":
			var keys : Array = GameData.modifiers.keys()
			if n >= 1 and n <= keys.size():
				_apply_modifier(keys[n - 1])
				_log("[color=#ff9966][DEBUG] Applied " + str(GameData.modifiers[keys[n - 1]]["name"]) + ".[/color]")
	_refresh_ui()


func _debug_stat(n: int) -> void:
	match n:
		1: player_hp = mini(player_hp + 1, max_hp())
		2: player_hp = maxi(player_hp - 1, 0)
		3: player_breath = mini(player_breath + 1, max_breath())
		4: player_breath = maxi(player_breath - 1, 0)
		5: dominance = clampi(dominance + 1, DOM_MIN, DOM_MAX)
		6: dominance = clampi(dominance - 1, DOM_MIN, DOM_MAX)
		7: player_blood += 5
		8: player_blood = maxi(player_blood - 5, 0)
		9:
			player_hp = max_hp()
			player_breath = max_breath()


func _debug_grant_instinct(id: String) -> void:
	if has(id):
		return
	owned_instincts.append(id)
	_apply_instinct_stats(id)
	_log("[color=#ffcc66][DEBUG] Granted " + str(GameData.instincts[id]["name"]) + ".[/color]")


func _debug_jump_encounter(n: int) -> void:
	n = clampi(n, 1, run_encounters.size())
	var idx := -1
	var count := 0
	for i in steps.size():
		if steps[i]["type"] == "battle":
			count += 1
			if count == n:
				idx = i
				break
	if idx >= 0:
		step_ptr = idx
	battle_num = n - 1
	battle_over = false
	debug_open = false
	debug_panel.visible = false
	start_battle(run_encounters[n - 1])


func _debug_render() -> void:
	var s := "[b][color=#ffcc66]DEBUG[/color][/b]   [color=#888888]` close[/color]\n"
	s += "[color=#8faab5]HP " + str(player_hp) + "/" + str(max_hp()) + "  Breath " + str(player_breath) + "/" + str(max_breath()) + "  Dom " + _dom_signed(dominance) + "  Blood " + str(player_blood) + "[/color]\n\n"
	if debug_cat == "":
		s += "[b]Pick a category:[/b]\n"
		s += "  [color=#ffdd88]S[/color]  Stats\n"
		s += "  [color=#ffdd88]I[/color]  Items\n"
		s += "  [color=#ffdd88]N[/color]  Instincts\n"
		s += "  [color=#ffdd88]E[/color]  Encounter\n"
		s += "  [color=#ffdd88]V[/color]  Event\n"
		s += "  [color=#ffdd88]M[/color]  Modifiers\n"
		s += "\n[color=#888888]Esc closes.[/color]"
	else:
		s += "[b]" + debug_cat.to_upper() + "[/b]   [color=#888888]type a number, Enter · Esc back[/color]\n"
		s += "[color=#88ff88]> " + debug_buffer + "[/color]\n\n"
		match debug_cat:
			"stats":
				s += "1 HP+1   2 HP-1\n3 Breath+1   4 Breath-1\n5 Dom+1   6 Dom-1\n7 Blood+5   8 Blood-5\n9 Full HP+Breath\n"
			"items":
				var i := 1
				for id in GameData.items.keys():
					s += str(i) + "  " + str(GameData.items[id]["name"]) + "  [color=#666666][" + str(GameData.items[id].get("rarity", "common")) + "][/color]\n"
					i += 1
			"instincts":
				var i := 1
				for id in GameData.instincts.keys():
					var owned : String = "  [color=#66ff66](owned)[/color]" if has(id) else ""
					s += str(i) + "  " + str(GameData.instincts[id]["name"]) + owned + "\n"
					i += 1
			"encounter":
				var i := 1
				for e in run_encounters:
					s += str(i) + "  " + str(GameData.animals[e["sp"]]["name"]) + "  [color=#666666]hp " + str(e["hp"]) + "[/color]\n"
					i += 1
			"event":
				var i := 1
				for id in GameData.events.keys():
					s += str(i) + "  " + str(GameData.events[id]["title"]) + "\n"
					i += 1
			"modifiers":
				var i := 1
				for id in GameData.modifiers.keys():
					s += str(i) + "  " + str(GameData.modifiers[id]["name"]) + "\n"
					i += 1
	debug_text.text = s
