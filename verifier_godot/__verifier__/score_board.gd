extends RefCounted

const PASS_THRESHOLD := 85
const CATEGORY_PASS_FLOORS := {
	"trajectory_preview": 15,
	"projectile_physics": 8,
	"explosion_gameplay": 10,
	"visual_audio_polish": 4,
}

var _items: Array[Dictionary] = []
var _suspect_reasons: Array[String] = []


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


func flag_suspect(reason: String) -> void:
	if not _suspect_reasons.has(reason):
		_suspect_reasons.append(reason)


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


func category_score(category_name: String) -> int:
	for item in _items:
		if String(item["name"]) == category_name:
			return int(item["score"])
	return 0


func failed_category_floors() -> Array[String]:
	var failures: Array[String] = []
	for category_name in CATEGORY_PASS_FLOORS:
		var floor_score := int(CATEGORY_PASS_FLOORS[category_name])
		if category_score(String(category_name)) < floor_score:
			failures.append("%s below pass floor %d" % [category_name, floor_score])
	return failures


func to_dictionary(godot_version: String) -> Dictionary:
	var max_total := max_score()
	var score_total := total_score()
	var floor_failures := failed_category_floors()
	return {
		"score": score_total,
		"max_score": max_total,
		"passed": score_total >= PASS_THRESHOLD and floor_failures.is_empty(),
		"pass_threshold": PASS_THRESHOLD,
		"category_floor_failures": floor_failures,
		"suspect": not _suspect_reasons.is_empty(),
		"suspect_reasons": _suspect_reasons,
		"godot_version": godot_version,
		"breakdown": _items,
		"artifacts": {
			"log": "",
			"screenshots": [],
		},
	}
