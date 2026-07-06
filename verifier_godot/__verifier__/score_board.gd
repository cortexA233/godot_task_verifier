extends RefCounted

const PASS_THRESHOLD := 85
const CATEGORY_PASS_FLOORS := {
	"trajectory_preview": 9,
	"projectile_physics": 8,
	"explosion_gameplay": 10,
	"stability_repeatability": 5,
}

var _items: Array[Dictionary] = []
var _suspect_reasons: Array[String] = []
var _formal_score_complete := true
var _diagnostic_only := false
var _omitted_formal_components: Array[String] = []


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


func mark_diagnostic_incomplete(omitted_components: Array) -> void:
	_formal_score_complete = false
	_diagnostic_only = true
	for component in omitted_components:
		var component_name := String(component)
		if not _omitted_formal_components.has(component_name):
			_omitted_formal_components.append(component_name)


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


func score_sections() -> Array[Dictionary]:
	var category_names: Array[String] = []
	for item in _items:
		category_names.append(String(item["name"]))
	return [
		_score_section("formal", "Formal Score", category_names),
	]


func _score_section(name: String, label: String, category_names: Array) -> Dictionary:
	var section_score := 0
	var section_max := 0
	var present_categories: Array[String] = []
	for item in _items:
		var category_name := String(item["name"])
		if category_names.has(category_name):
			section_score += int(item["score"])
			section_max += int(item["max"])
			present_categories.append(category_name)
	return {
		"name": name,
		"label": label,
		"score": section_score,
		"max": section_max,
		"categories": present_categories,
	}


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
	var sections := score_sections()
	return {
		"score": score_total,
		"max_score": max_total,
		"passed": score_total >= PASS_THRESHOLD and floor_failures.is_empty() and _formal_score_complete,
		"pass_threshold": PASS_THRESHOLD,
		"category_floor_failures": floor_failures,
		"suspect": not _suspect_reasons.is_empty(),
		"suspect_reasons": _suspect_reasons,
		"formal_score_complete": _formal_score_complete,
		"diagnostic_only": _diagnostic_only,
		"omitted_formal_components": _omitted_formal_components,
		"godot_version": godot_version,
		"score_sections": sections,
		"breakdown": _items,
		"artifacts": {
			"log": "",
			"screenshots": [],
		},
	}
