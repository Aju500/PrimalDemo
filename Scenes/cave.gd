extends Control
# ──────────────────────────────────────────────────────────────────────────────
#  THE CAVE — the between-runs hub.
#  Live: THE POND (learn/equip moves), THE HOLLOW (permanent Adaptations),
#  BLOOD ALTAR (one-run boon), THE TRADER (buy items for next run's pouch).
#  THE OLD PREDATOR is lore/tips only. Quests are still a future TODO.
# ──────────────────────────────────────────────────────────────────────────────

const TRADER_STOCK_SIZE := 3
const TRADER_MARKUP := 3   # cave prices run higher than the in-run raccoon

@onready var blood_label : Label         = $BloodLabel
@onready var overlay     : Control       = $InfoOverlay
@onready var info_title  : Label         = $InfoOverlay/Panel/InfoTitle
@onready var info_text   : RichTextLabel = $InfoOverlay/Panel/InfoText
@onready var info_panel  : Panel         = $InfoOverlay/Panel

var _rows : VBoxContainer = null


func _ready() -> void:
	$BackBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/save_select.tscn"))
	$EnterBtn.pressed.connect(_on_enter_forest)
	$InfoOverlay/Panel/CloseBtn.pressed.connect(_close)

	$PredatorBtn.pressed.connect(_predator)
	$PondBtn.pressed.connect(_pond)
	$HollowBtn.pressed.connect(_hollow)
	$AltarBtn.pressed.connect(_altar)
	$TraderBtn.pressed.connect(_trader)

	_refresh()


func _slot() -> Dictionary:
	return Save.read_slot(Save.active_slot)


func _save(d: Dictionary) -> void:
	Save.write_slot(Save.active_slot, d)


func _refresh() -> void:
	var d := _slot()
	var f := _frag_dict(d)
	blood_label.text = "%s        Blood  %d        Frag  A%d D%d S%d" % [
		str(d.get("name", "Hunter")), int(d.get("blood_bank", 0)), f["atk"], f["def"], f["spc"]]


func _frag_dict(d: Dictionary) -> Dictionary:
	var raw = d.get("fragments", {})
	var out := { "atk": 0, "def": 0, "spc": 0 }
	if typeof(raw) == TYPE_DICTIONARY:
		for k in out.keys():
			out[k] = int(raw.get(k, 0))
	return out


func _close() -> void:
	overlay.visible = false
	_clear_rows()
	info_text.visible = true


func _clear_rows() -> void:
	if _rows != null:
		var sc = _rows.get_meta("scroll", null)
		if sc != null and is_instance_valid(sc):
			sc.queue_free()
		_rows = null


func _show_text(title: String, body: String) -> void:
	_close()
	info_title.text = title
	info_text.text = body
	overlay.visible = true


func _open_rows_panel(title: String) -> void:
	_close()
	info_title.text = title
	info_text.visible = false
	overlay.visible = true
	_clear_rows()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 52)
	scroll.size = Vector2(560, 264)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.custom_minimum_size = Vector2(548, 0)
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	_rows.set_meta("scroll", scroll)


func _note(t: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.custom_minimum_size = Vector2(540, 0)
	l.text = t
	_rows.add_child(l)


func _row(label_text: String, btn_text: String, enabled: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(540, 34)

	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.custom_minimum_size = Vector2(370, 30)
	l.text = label_text
	row.add_child(l)

	var b := Button.new()
	b.custom_minimum_size = Vector2(140, 30)
	b.text = btn_text
	b.disabled = not enabled
	b.pressed.connect(cb)
	row.add_child(b)
	_rows.add_child(row)


# ── THE OLD PREDATOR (lore / tips) ────────────────────────────────────────────
func _predator() -> void:
	_show_text("THE OLD PREDATOR",
		"[i][color=#9fbfd0]He is older than anything else that still breathes here. One eye. He does not hunt any more; he watches, and he remembers.[/color][/i]\n\n" +
		"[color=#ffdd88]On reading:[/color] Skittish means it defends. Aggressive means it strikes — or lies. Tired means it has nothing left. [i]Calm means it has told you nothing.[/i]\n\n" +
		"[color=#ffdd88]On the Feint:[/color] An Aggressive read that never lands. Watch the weight — a real strike is heavy, a feint is light.\n\n" +
		"[color=#ffdd88]On Breath:[/color] Everything costs. Observe is the only thing that gives. Spend what you have not yet earned and the forest will collect.\n\n" +
		"[color=#ffdd88]On Dominance:[/color] Land a clean strike or turn one aside and it climbs. Bleed and it falls. Fall far enough and the prey stops being prey.\n\n" +
		"[color=#888888]The tutorial voice will speak from this old predator once the systems settle.[/color]")


# ── THE POND — learn moves with Fragments, then set your loadout ─────────────
func _pond() -> void:
	_open_rows_panel("THE POND")
	_build_pond()


func _build_pond() -> void:
	_clear_rows_content()
	var d := _slot()
	var frags := _frag_dict(d)
	var unlocked := _unlocked(d)
	var loadout := _loadout(d)

	_note("[i][color=#9fbfd0]Water so still it looks solid, until it ripples and shows you something you have not done yet.[/color][/i]")
	_note("[color=#cfa0ff]Fragments — Attack %d · Defense %d · Special %d[/color]     [color=#888888]Observe is always yours.[/color]" % [frags["atk"], frags["def"], frags["spc"]])

	for cat in ["atk", "def", "spc"]:
		var cap : int = GameData.LOADOUT_CAP[cat]
		var equipped : Array = loadout.get(cat, [])
		_note("\n[color=#ffdd88][b]%s  (%d/%d equipped)  ·  %d fragments[/b][/color]" % [_cat_name(cat), equipped.size(), cap, frags[cat]])
		for id in GameData.player_moves.keys():
			var md : Dictionary = GameData.player_moves[id]
			if str(md.get("cat", "")) != cat or md.get("always", false):
				continue
			_move_row(id, md, unlocked.has(id), equipped.has(id), equipped.size() >= cap, frags[cat])


func _clear_rows_content() -> void:
	for c in _rows.get_children():
		c.queue_free()


func _cat_name(cat: String) -> String:
	match cat:
		"atk": return "ATTACK"
		"def": return "DEFENSE"
	return "SPECIAL"


func _move_row(id: String, md: Dictionary, is_unlocked: bool, is_equipped: bool, cat_full: bool, frags_in_cat: int) -> void:
	var tint := "#dddddd" if is_unlocked else "#777777"
	var label := "[color=%s][b]%s[/b]  —  %s[/color]" % [tint, str(md.get("name", id)), str(md.get("desc", ""))]
	var cost := int(md.get("fragments", 0))
	if not is_unlocked:
		_row(label, "LEARN  (%d frag)" % cost, frags_in_cat >= cost, _learn.bind(id, cost))
	elif is_equipped:
		_row(label, "UNEQUIP", true, _equip.bind(id, false))
	else:
		_row(label, "SLOTS FULL" if cat_full else "EQUIP", not cat_full, _equip.bind(id, true))


func _unlocked(d: Dictionary) -> Array:
	var u : Array = []
	for m in d.get("unlocked", []):
		u.append(str(m))
	if u.is_empty():
		for id in GameData.player_moves.keys():
			if GameData.player_moves[id].get("start", false) or GameData.player_moves[id].get("always", false):
				u.append(id)
	return u


func _loadout(d: Dictionary) -> Dictionary:
	var lo : Dictionary = d.get("loadout", {})
	var out := { "atk": [], "def": [], "spc": [] }
	for cat in out.keys():
		for m in lo.get(cat, []):
			out[cat].append(str(m))
	if lo.is_empty():
		out["atk"] = ["claw"]
		out["def"] = ["guard"]
	return out


func _learn(id: String, cost: int) -> void:
	var d := _slot()
	var frags := _frag_dict(d)
	var cat := str(GameData.player_moves[id].get("cat", "atk"))
	if frags[cat] < cost:
		return
	frags[cat] -= cost
	var u := _unlocked(d)
	if not u.has(id):
		u.append(id)
	d["fragments"] = frags
	d["unlocked"] = u
	_save(d)
	_refresh()
	_build_pond()


func _equip(id: String, on: bool) -> void:
	var d := _slot()
	var lo := _loadout(d)
	var cat := str(GameData.player_moves[id].get("cat", "atk"))
	var arr : Array = lo[cat]
	if on:
		if arr.size() >= int(GameData.LOADOUT_CAP[cat]) or arr.has(id):
			return
		arr.append(id)
	else:
		arr.erase(id)
	lo[cat] = arr
	d["loadout"] = lo
	_save(d)
	_build_pond()


# ── THE HOLLOW — permanent Adaptations, equip up to 2 ─────────────────────────
const ADAPT_CAP := 2

func _hollow() -> void:
	_open_rows_panel("THE HOLLOW")
	_build_hollow()


func _build_hollow() -> void:
	_clear_rows_content()
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	var best := int(d.get("best_battle", 0))
	var owned : Array = d.get("adaptations_owned", [])
	var equipped : Array = d.get("adaptations_equipped", [])

	_note("[i][color=#9fbfd0]Mushrooms glow at the lip of it. Something died here a long time ago and the forest kept the shape of it.[/color][/i]")
	_note("[color=#888888]Buy an Adaptation once, forever. Equip up to %d for your next hunt.[/color]" % ADAPT_CAP)
	_note("[color=#ffcc66][b]Equipped: %d/%d[/b][/color]" % [equipped.size(), ADAPT_CAP])

	for id in GameData.adaptations.keys():
		var ad : Dictionary = GameData.adaptations[id]
		var req : Dictionary = ad.get("requires", {})
		var locked := req.has("best_battle") and best < int(req["best_battle"])
		var cost := int(ad.get("cost", 0))
		var label := "[b]%s[/b]  —  %s" % [str(ad.get("name", id)), str(ad.get("desc", ""))]
		if locked:
			label = "[color=#666666]%s\n[i]Locked — reach encounter %d to unlock[/i][/color]" % [label, int(req["best_battle"])]
			_row(label, "LOCKED", false, func(): pass)
		elif owned.has(id):
			if equipped.has(id):
				_row(label, "UNEQUIP", true, _unequip_adaptation.bind(id))
			else:
				_row(label, "EQUIP" if equipped.size() < ADAPT_CAP else "SLOTS FULL", equipped.size() < ADAPT_CAP, _equip_adaptation.bind(id))
		else:
			_row(label, "BUY  (%d blood)" % cost, blood >= cost, _buy_adaptation.bind(id, cost))


func _buy_adaptation(id: String, cost: int) -> void:
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	if blood < cost:
		return
	d["blood_bank"] = blood - cost
	var owned : Array = d.get("adaptations_owned", [])
	if not owned.has(id):
		owned.append(id)
	d["adaptations_owned"] = owned
	_save(d)
	_refresh()
	_build_hollow()


func _equip_adaptation(id: String) -> void:
	var d := _slot()
	var equipped : Array = d.get("adaptations_equipped", [])
	if equipped.size() >= ADAPT_CAP or equipped.has(id):
		return
	equipped.append(id)
	d["adaptations_equipped"] = equipped
	_save(d)
	_build_hollow()


func _unequip_adaptation(id: String) -> void:
	var d := _slot()
	var equipped : Array = d.get("adaptations_equipped", [])
	equipped.erase(id)
	d["adaptations_equipped"] = equipped
	_save(d)
	_build_hollow()


# ── BLOOD ALTAR — one-run boon, single choice ─────────────────────────────────
func _altar() -> void:
	_open_rows_panel("BLOOD ALTAR")
	_build_altar()


func _build_altar() -> void:
	_clear_rows_content()
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	var pending := str(d.get("pending_boon", ""))

	_note("[i][color=#9fbfd0]A slab worn smooth by older animals than you, dark in the cracks.[/color][/i]")
	_note("[color=#888888]One boon, spent the moment you enter the forest. Choosing a new one replaces the last.[/color]")
	if pending != "" and GameData.altar_boons.has(pending):
		_note("[color=#ffb3b3][b]Awaiting your next hunt:[/b] %s[/color]" % str(GameData.altar_boons[pending]["name"]))

	for id in GameData.altar_boons.keys():
		var b : Dictionary = GameData.altar_boons[id]
		var cost := int(b.get("cost", 0))
		var label := "[b]%s[/b]  —  %s" % [str(b.get("name", id)), str(b.get("desc", ""))]
		if pending == id:
			_row(label, "CHOSEN", false, func(): pass)
		else:
			_row(label, "CHOOSE  (%d blood)" % cost, blood >= cost, _buy_boon.bind(id, cost))


func _buy_boon(id: String, cost: int) -> void:
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	if blood < cost:
		return
	d["blood_bank"] = blood - cost
	d["pending_boon"] = id
	_save(d)
	_refresh()
	_build_altar()


# ── THE TRADER — buy items for next run's starting pouch ─────────────────────
func _trader() -> void:
	_open_rows_panel("THE TRADER")
	_build_trader()


func _build_trader() -> void:
	_clear_rows_content()
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	var pending : Array = d.get("pending_items", [])
	var stock : Array = d.get("trader_stock", [])
	if stock.is_empty():
		stock = _roll_trader_stock()
		d["trader_stock"] = stock
		_save(d)

	_note("[i][color=#9fbfd0]A ring-eyed raccoon spreads its wares on a flat stone and grins. It has never explained where any of it comes from.[/color][/i]")
	_note("[color=#888888]Pricier than the dark. What you buy waits in your pouch for your next hunt.[/color]")
	if not pending.is_empty():
		var names : Array = []
		for it in pending:
			names.append(str(GameData.items.get(str(it), {}).get("name", it)))
		_note("[color=#ffd089][b]Waiting in your pouch:[/b] %s[/color]" % ", ".join(names))
	_note("[color=#666666]A new stock waits each visit once you've spent what's here. [i]Quests: coming soon.[/i][/color]")

	for id in stock:
		var it : Dictionary = GameData.items.get(str(id), {})
		var cost := _trader_price(str(id))
		var label := "[b]%s[/b]  —  %s" % [str(it.get("name", id)), str(it.get("desc", ""))]
		_row(label, "BUY  (%d blood)" % cost, blood >= cost, _buy_trader_item.bind(str(id), cost))


func _roll_trader_stock() -> Array:
	var pool : Array = []
	for id in GameData.items.keys():
		var r := str(GameData.items[id].get("rarity", "common"))
		if r == "common" or r == "uncommon" or r == "rare":
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(TRADER_STOCK_SIZE, pool.size()))


func _trader_price(id: String) -> int:
	var base := 3
	match str(GameData.items[id].get("rarity", "common")):
		"rare":     base = 6
		"uncommon": base = 4
	return base + TRADER_MARKUP


func _buy_trader_item(id: String, cost: int) -> void:
	var d := _slot()
	var blood := int(d.get("blood_bank", 0))
	if blood < cost:
		return
	d["blood_bank"] = blood - cost
	var pending : Array = d.get("pending_items", [])
	pending.append(id)
	d["pending_items"] = pending
	var stock : Array = d.get("trader_stock", [])
	stock.erase(id)
	d["trader_stock"] = stock
	_save(d)
	_refresh()
	_build_trader()


# ── Enter the forest ───────────────────────────────────────────────────────────
func _on_enter_forest() -> void:
	var data := _slot()
	data["stage"] = "run"
	_save(data)
	Save.resume = false          # a fresh run
	get_tree().change_scene_to_file("res://Scenes/battle.tscn")
