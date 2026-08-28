extends Node
# ──────────────────────────────────────────────────────────────────────────────
#  Save — autoload.  Three slots persisted as JSON under user://.
#  A slot holds { name, stage, run:{...} }.  battle.gd builds/reads the run blob.
# ──────────────────────────────────────────────────────────────────────────────

const SLOTS := 3

# Set by the save screen before changing to the battle scene.
var active_slot : int  = 0
var resume      : bool = false


func _file(i: int) -> String:
	return "user://save_%d.json" % i


func read_slot(i: int) -> Dictionary:
	var p := _file(i)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	return d if typeof(d) == TYPE_DICTIONARY else {}


func write_slot(i: int, data: Dictionary) -> void:
	var f := FileAccess.open(_file(i), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func reset_slot(i: int) -> void:
	var d := DirAccess.open("user://")
	var fname := "save_%d.json" % i
	if d != null and d.file_exists(fname):
		d.remove(fname)


func slot_exists(i: int) -> bool:
	return not read_slot(i).is_empty()


func slot_has_run(i: int) -> bool:
	var s := read_slot(i)
	return s.has("run") and typeof(s["run"]) == TYPE_DICTIONARY and not (s["run"] as Dictionary).is_empty()


func slot_name(i: int) -> String:
	return str(read_slot(i).get("name", ""))
