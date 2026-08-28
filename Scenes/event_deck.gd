extends RefCounted
class_name EventDeck

# Weighted random "bag" with anti-clumping over GameData.events.
# Event data + choice effects live in res://Data/events.json; battle.gd applies them.

var _recent : Array = []


func next_event() -> String:
	var pool : Array = []
	var weights : Array = []
	var cooldown : int = GameData.events_cooldown
	for id in GameData.events.keys():
		if _recent.has(id):
			continue
		pool.append(id)
		weights.append(int(GameData.events[id]["weight"]))
	if pool.is_empty():
		for id in GameData.events.keys():
			pool.append(id)
			weights.append(int(GameData.events[id]["weight"]))

	var total := 0
	for w in weights:
		total += w
	var roll := randi() % maxi(total, 1)
	var picked : String = pool[0]
	for i in pool.size():
		roll -= weights[i]
		if roll < 0:
			picked = pool[i]
			break

	_recent.append(picked)
	while _recent.size() > cooldown:
		_recent.pop_front()
	return picked
