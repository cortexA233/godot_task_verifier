extends RefCounted

var _items: Array[Dictionary] = []


func add(name: String, score: int, max_score: int, notes: String, details: Array[Dictionary] = []) -> void:
	var clamped_score: int = clampi(score, 0, max_score)
	var item := {
		"name": name,
		"score": clamped_score,
		"max": max_score,
		"notes": notes,
	}
	if not details.is_empty():
		item["details"] = details
	_items.append(item)


func total_score() -> int:
	var total := 0
	for item in _items:
		total += int(item["score"])
	return total


func max_score() -> int:
	var total := 0
	for item in _items:
		total += int(item["max"])
	return total


func to_dictionary(godot_version: String) -> Dictionary:
	var max_total := max_score()
	var score_total := total_score()
	return {
		"score": score_total,
		"max_score": max_total,
		"passed": score_total >= 85,
		"godot_version": godot_version,
		"breakdown": _items,
		"artifacts": {
			"log": "",
			"screenshots": [],
		},
	}
