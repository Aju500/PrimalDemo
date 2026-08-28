extends Control
# Save-select screen: three named, resettable slots.  New slot → straight into a
# run; a slot with a run in progress → CONTINUE where it left off.

@onready var slots_box : VBoxContainer = $Slots


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	for i in Save.SLOTS:
		slots_box.add_child(_make_row(i))


func _make_row(i: int) -> Control:
	var has_save := Save.slot_exists(i)
	var has_run  := Save.slot_has_run(i)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 64)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(230, 40)
	name_edit.placeholder_text = "Name your predator"
	name_edit.text = Save.slot_name(i) if has_save else ""
	name_edit.editable = not has_save   # a name is set once, at creation
	row.add_child(name_edit)

	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.custom_minimum_size = Vector2(230, 0)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if has_run:
		var r : Dictionary = Save.read_slot(i).get("run", {})
		var total : int = (r.get("encounters", []) as Array).size()
		status.text = "In the hunt  ·  encounter %d/%d" % [int(r.get("battle_num", 1)), total]
		status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))
	elif has_save:
		status.text = "Resting at the cave mouth"
		status.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	else:
		status.text = "Empty — new territory"
		status.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(status)

	var play := Button.new()
	play.custom_minimum_size = Vector2(150, 40)
	if has_run:
		play.text = "CONTINUE"
	elif has_save:
		play.text = "TO THE CAVE"
	else:
		play.text = "BEGIN HUNT"
	play.pressed.connect(_on_play.bind(i, name_edit))
	row.add_child(play)

	var reset := Button.new()
	reset.custom_minimum_size = Vector2(90, 40)
	reset.text = "RESET"
	reset.disabled = not has_save
	reset.pressed.connect(_on_reset.bind(i))
	row.add_child(reset)

	return panel


func _on_play(i: int, name_edit: LineEdit) -> void:
	var existed := Save.slot_exists(i)
	var has_run := Save.slot_has_run(i)
	var data := Save.read_slot(i)
	if not existed:
		var nm := name_edit.text.strip_edges()
		if nm == "":
			nm = "Hunter %d" % (i + 1)
		data["name"] = nm   # name is fixed at creation — not editable afterward

	Save.active_slot = i
	Save.resume = has_run
	if has_run:
		Save.write_slot(i, data)                       # resume the run in progress
		get_tree().change_scene_to_file("res://Scenes/battle.tscn")
	elif existed and str(data.get("stage", "")) == "hub":
		Save.write_slot(i, data)                       # resting between runs → the cave
		get_tree().change_scene_to_file("res://Scenes/cave.tscn")
	else:
		data["stage"] = "run"                          # brand new save → straight into a run
		Save.write_slot(i, data)
		get_tree().change_scene_to_file("res://Scenes/battle.tscn")


func _on_reset(i: int) -> void:
	Save.reset_slot(i)
	_rebuild()
