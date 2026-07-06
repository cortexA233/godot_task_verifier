# Presentation Fidelity Rubric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved grenade rubric reweighting that raises `visual_audio_polish` to 15 points, penalizes placeholder grenade and explosion assets without making them hard pass blockers, and keeps explosion range correctness separate from presentation fidelity.

**Architecture:** Keep the existing formal Godot runner as the scoring authority. Extend `SceneProbe` with reusable presentation-asset reports, then have `runner.gd` aggregate those reports into the new 15-point `visual_audio_polish` category while shrinking HUD and trajectory weights and strengthening blast locality. Update tests, benchmark docs, and calibration notes in the same change.

**Tech Stack:** Godot 4.6 GDScript verifier code, Python `unittest`, PowerShell calibration scripts, Markdown/HTML docs.

---

## File Structure

- Modify `verifier_godot/__verifier__/score_board.gd`: category pass floors.
- Modify `verifier_godot/__verifier__/runner.gd`: HUD, trajectory, explosion, and visual/audio score weights and aggregation.
- Modify `verifier_godot/__verifier__/scene_probe.gd`: reusable projectile and explosion visual asset quality helpers.
- Modify `tests/test_run_grader.py`: source-level and Godot-facing tests for the new rubric and helper behavior.
- Modify `README.md`: public command interface scoring table, floors, calibration notes, and historical probe wording.
- Modify `BENCHMARK.md`: benchmark score definition and calibration expectations.
- Modify `probe_matrix.md`: active probe set, pass floors, and removal of wrong-projectile-model as an active probe.
- Modify `evaluation/writeup.html` only after calibration reruns if the retained score table or visual-analysis prose still reflects the old 5-point visual category.

No new fake candidate probe should be added. Existing wrong-projectile-model evidence may remain in `evaluation/evidence/` as historical probe evidence, but it must not be listed as an active probe row.

---

### Task 1: Lock The New Rubric In Tests

**Files:**
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Update category floor assertions**

In `test_score_board_enforces_category_floors_and_suspect_flag`, change the floor assertions to:

```python
self.assertIn('"trajectory_preview": 11', board_source)
self.assertIn('"projectile_physics": 8', board_source)
self.assertIn('"explosion_gameplay": 10', board_source)
self.assertIn('"visual_audio_polish": 5', board_source)
```

- [ ] **Step 2: Update top-level score weight assertions**

In `test_runner_uses_discriminating_score_weights`, assert the approved top-level table:

```python
self.assertIn('board.add("weapon_controls", _detail_score(details), 15', runner_source)
self.assertIn('board.add("hud_feedback", _detail_score(details), 8', runner_source)
self.assertIn('board.add("trajectory_preview", _detail_score(details), 22', runner_source)
self.assertIn('board.add("projectile_physics", _detail_score(details), 15', runner_source)
self.assertIn('board.add("explosion_gameplay", capped_score, 20', runner_source)
self.assertIn("_explosion_gameplay_score_cap", runner_source)
self.assertIn('board.add("visual_audio_polish", _detail_score(details), 15', runner_source)
self.assertIn('board.add("stability_repeatability", _detail_score(details), 5', runner_source)
```

- [ ] **Step 3: Add HUD detail weight assertions**

Add this test near `test_runner_uses_discriminating_score_weights`:

```python
def test_hud_feedback_uses_reweighted_supporting_details(self):
    runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

    self.assertIn('"Visible UI controls",\n\t\t2,', runner_source)
    self.assertIn('_detail("Weapon-switch UI state", 4, 4', runner_source)
    self.assertIn('"Aiming UI feedback",\n\t\t2,', runner_source)
```

- [ ] **Step 4: Add trajectory detail weight assertions**

Extend `test_trajectory_preview_uses_quality_gates_and_consistency_detail` with the new weights:

```python
self.assertIn('"Visible grenade aiming aid",\n\t\t4,', runner_source)
self.assertIn('_detail("Communicates arcing throw", 0, 4', runner_source)
self.assertIn('"Communicates arcing throw",\n\t\t4,', runner_source)
self.assertIn('"Updates with aim/camera direction",\n\t\t6,', runner_source)
self.assertIn('_detail("Preview matches projectile direction", 6, 6', runner_source)
self.assertIn('_detail("Visibility lifecycle/cooldown behavior", 0, 2', runner_source)
self.assertIn('"Visibility lifecycle/cooldown behavior",\n\t\t2,', runner_source)
```

- [ ] **Step 5: Add explosion detail weight assertions**

Replace the old `"Detonation effects across angles"` expectation with this test:

```python
def test_explosion_gameplay_moves_visual_effect_weight_to_blast_locality(self):
    runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

    self.assertNotIn('"Detonation effects across angles"', runner_source)
    self.assertIn('"Nearby target damage across angles",\n\t\tnearby_score,\n\t\t5,', runner_source)
    self.assertIn('"Nearby destructible damage across angles",\n\t\tdestructible_score,\n\t\t3,', runner_source)
    self.assertIn('"Blast locality across angles",\n\t\tlocality_score,\n\t\t8,', runner_source)
    self.assertIn('"Player safety across angles",\n\t\tplayer_score,\n\t\t2,', runner_source)
    self.assertIn('"Throw distance calibration quality",\n\t\tcalibration_quality_score,\n\t\t2,', runner_source)
```

Also update `test_runner_records_structured_score_details` to remove the old assertion:

```python
self.assertNotIn('"Detonation effects across angles"', runner_source)
```

- [ ] **Step 6: Add visual/audio detail assertions**

Add this test near `test_runner_scores_runtime_grenade_projectile_model_visual`:

```python
def test_visual_audio_polish_scores_asset_quality_without_hard_blocking_placeholders(self):
    runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")
    probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")

    self.assertIn('"Thrown grenade model asset quality"', runner_source)
    self.assertIn('"Explosion VFX asset quality"', runner_source)
    self.assertIn('"Detonation visual timing/location"', runner_source)
    self.assertIn('"Detonation audio"', runner_source)
    self.assertIn('"Temporary visual cleanup"', runner_source)
    self.assertIn('"Presentation consistency across trials"', runner_source)
    self.assertIn("projectile_asset_quality_score", probe_source)
    self.assertIn("explosion_vfx_asset_quality_score", probe_source)
    self.assertIn("_presentation_asset_quality_score", probe_source)
```

- [ ] **Step 7: Run the targeted source tests and verify they fail**

Run:

```powershell
python -m unittest tests.test_run_grader.TestRunGrader.test_score_board_enforces_category_floors_and_suspect_flag tests.test_run_grader.TestRunGrader.test_runner_uses_discriminating_score_weights tests.test_run_grader.TestRunGrader.test_hud_feedback_uses_reweighted_supporting_details tests.test_run_grader.TestRunGrader.test_trajectory_preview_uses_quality_gates_and_consistency_detail tests.test_run_grader.TestRunGrader.test_explosion_gameplay_moves_visual_effect_weight_to_blast_locality tests.test_run_grader.TestRunGrader.test_visual_audio_polish_scores_asset_quality_without_hard_blocking_placeholders
```

Expected: FAIL, because the implementation still uses the old 5-point visual polish rubric and old category weights.

- [ ] **Step 8: Commit the failing tests**

```powershell
git add tests/test_run_grader.py
git commit -m "test: specify presentation fidelity rubric weights"
```

---

### Task 2: Implement Category Weights And Floors

**Files:**
- Modify: `verifier_godot/__verifier__/score_board.gd`
- Modify: `verifier_godot/__verifier__/runner.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Update pass floors**

In `score_board.gd`, set:

```gdscript
const CATEGORY_PASS_FLOORS := {
	"trajectory_preview": 11,
	"projectile_physics": 8,
	"explosion_gameplay": 10,
	"visual_audio_polish": 5,
}
```

- [ ] **Step 2: Reweight HUD details**

In `_score_hud_feedback()`, change the no-player max and details to 8 total:

```gdscript
if player == null:
	var details: Array[Dictionary] = [_detail("Player availability", 0, 8, "missed", "No player available.")]
	board.add("hud_feedback", 0, 8, _detail_notes(details), details)
	return
```

Use these detail weights:

```gdscript
details.append(_score_detail(
	"Visible UI controls",
	2,
	before.size() >= 2,
	"player has visible UI controls",
	"player has little or no visible UI control tree"
))
if can_switch_weapons and changed > 0:
	details.append(_detail("Weapon-switch UI state", 4, 4, "earned", "UI control state changed after weapon switch"))
elif not can_switch_weapons:
	details.append(_detail("Weapon-switch UI state", 0, 4, "missed", "weapon-switch UI change not credited because weapon-switch input is missing"))
else:
	details.append(_detail("Weapon-switch UI state", 0, 4, "missed", "UI did not visibly change after weapon switch"))
details.append(_score_detail(
	"Aiming UI feedback",
	2,
	SceneProbe.count_changed_controls(after, aiming_snapshot) > 0,
	"aiming changes UI feedback",
	"aiming did not change UI feedback"
))
board.add("hud_feedback", _detail_score(details), 8, _detail_notes(details), details)
```

- [ ] **Step 3: Reweight trajectory details**

In `_score_trajectory_preview()`, change the no-player max and board max to 22, and use these detail weights:

```gdscript
details.append(_score_detail(
	"Visible grenade aiming aid",
	4,
	visible_aid,
	"visible grenade aiming aid appears in grenade mode",
	"no visible grenade trajectory, landing marker, or equivalent aiming aid detected"
))
if not visible_aid:
	details.append(_detail("Communicates arcing throw", 0, 4, "missed", "trajectory details gated because no visible aiming aid was observed"))
	details.append(_detail("Updates with aim/camera direction", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
	details.append(_detail("Preview matches projectile direction", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
	details.append(_detail("Visibility lifecycle/cooldown behavior", 0, 2, "missed", "trajectory details gated because no visible aiming aid was observed"))
	board.add("trajectory_preview", _detail_score(details), 22, _detail_notes(details), details)
	return
```

Then change the later earned/missed detail maximums to 4, 6, 6, and 2 respectively:

```gdscript
"Communicates arcing throw", 4
"Updates with aim/camera direction", 6
_detail("Preview matches projectile direction", 6, 6, ...)
_detail("Preview matches projectile direction", 0, 6, ...)
"Visibility lifecycle/cooldown behavior", 2
board.add("trajectory_preview", _detail_score(details), 22, _detail_notes(details), details)
```

- [ ] **Step 4: Move explosion visual-effect weight into blast locality**

In `_explosion_details_from_trials()`, remove `effects_count`, `effect_notes`, and the `Detonation effects across angles` detail. Keep `effects_observed` in trial dictionaries only if another caller still needs it; it must not contribute to `explosion_gameplay`.

Use this 20-point table:

```gdscript
var nearby_score := _scaled_average_score(total_near_score, trial_results.size(), 10, 5)
var destructible_score := _scaled_average_score(destructible_hit_count, trial_results.size(), 1, 3)
var locality_score := _scaled_average_score(localized_count, trial_results.size(), 1, 8)
var player_score := _scaled_average_score(player_safe_count, trial_results.size(), 1, 2)
var calibration_quality_score := _calibration_quality_score(calibration_status)
```

The `_detail(...)` calls must use max values 5, 3, 8, 2, and 2.

- [ ] **Step 5: Run targeted tests and verify the weight/floor tests pass**

Run:

```powershell
python -m unittest tests.test_run_grader.TestRunGrader.test_score_board_enforces_category_floors_and_suspect_flag tests.test_run_grader.TestRunGrader.test_runner_uses_discriminating_score_weights tests.test_run_grader.TestRunGrader.test_hud_feedback_uses_reweighted_supporting_details tests.test_run_grader.TestRunGrader.test_trajectory_preview_uses_quality_gates_and_consistency_detail tests.test_run_grader.TestRunGrader.test_explosion_gameplay_moves_visual_effect_weight_to_blast_locality
```

Expected: PASS for the tests listed in this command. The visual asset helper test from Task 1 may still fail until Task 3.

- [ ] **Step 6: Commit category weight implementation**

```powershell
git add verifier_godot/__verifier__/score_board.gd verifier_godot/__verifier__/runner.gd tests/test_run_grader.py
git commit -m "feat: reweight formal grenade rubric"
```

---

### Task 3: Add Presentation Asset Quality Helpers

**Files:**
- Modify: `verifier_godot/__verifier__/scene_probe.gd`
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Add Godot-facing helper tests**

Replace `test_scene_probe_rejects_placeholder_projectile_meshes` with a broader test named:

```python
def test_scene_probe_scores_projectile_and_explosion_asset_quality(self):
```

Use the same temporary Godot project pattern, but write this GDScript runner body:

```gdscript
extends SceneTree

const SceneProbe = preload("res://__verifier__/scene_probe.gd")

func _init() -> void:
	call_deferred("_run")

func _make_array_mesh(extent: float = 0.5) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var h := extent * 0.5
	var vertices := PackedVector3Array([
		Vector3(-h, -h, -h),
		Vector3(h, -h, -h),
		Vector3(0.0, h, -h * 0.5),
		Vector3(0.0, 0.0, h),
	])
	var indices := PackedInt32Array([
		0, 1, 2,
		0, 2, 3,
		1, 3, 2,
		0, 3, 1,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_mesh(parent: Node3D, mesh: Mesh, scale_value: float = 1.0) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3.ONE * scale_value
	parent.add_child(visual)
	return visual

func _run() -> void:
	var bad_projectile := Node3D.new()
	bad_projectile.name = "BadProjectile"
	root.add_child(bad_projectile)
	_add_mesh(bad_projectile, SphereMesh.new())

	var good_projectile := Node3D.new()
	good_projectile.name = "GoodProjectile"
	root.add_child(good_projectile)
	_add_mesh(good_projectile, _make_array_mesh(0.5))

	var tiny_explosion := Node3D.new()
	tiny_explosion.name = "TinyExplosionVFX"
	root.add_child(tiny_explosion)
	_add_mesh(tiny_explosion, _make_array_mesh(0.02))

	var primitive_explosion := Node3D.new()
	primitive_explosion.name = "PrimitiveExplosionVFX"
	root.add_child(primitive_explosion)
	_add_mesh(primitive_explosion, SphereMesh.new(), 3.0)

	var good_explosion := Node3D.new()
	good_explosion.name = "GoodExplosionVFX"
	root.add_child(good_explosion)
	_add_mesh(good_explosion, _make_array_mesh(2.0))

	var tracks := {}
	tracks[bad_projectile.get_instance_id()] = [Vector3.ZERO, Vector3(0.0, 0.2, -1.0)]
	tracks[good_projectile.get_instance_id()] = [Vector3.ZERO, Vector3(0.0, 0.2, -1.0)]

	var bad_projectile_report: Dictionary = SceneProbe.grenade_projectile_visual_report([bad_projectile], tracks, 0.5, 0.1, 2.0)
	var good_projectile_report: Dictionary = SceneProbe.grenade_projectile_visual_report([good_projectile], tracks, 0.5, 0.1, 2.0)
	var tiny_explosion_report: Dictionary = SceneProbe.explosion_vfx_asset_quality_report([tiny_explosion], Vector3.ZERO, 0.5, 8.0)
	var primitive_explosion_report: Dictionary = SceneProbe.explosion_vfx_asset_quality_report([primitive_explosion], Vector3.ZERO, 0.5, 8.0)
	var good_explosion_report: Dictionary = SceneProbe.explosion_vfx_asset_quality_report([good_explosion], Vector3.ZERO, 0.5, 8.0)

	var result := {
		"bad_projectile_score": int(bad_projectile_report.get("projectile_asset_quality_score", -1)),
		"bad_projectile_notes": String(bad_projectile_report.get("notes", "")),
		"good_projectile_score": int(good_projectile_report.get("projectile_asset_quality_score", -1)),
		"tiny_explosion_score": int(tiny_explosion_report.get("explosion_vfx_asset_quality_score", -1)),
		"primitive_explosion_score": int(primitive_explosion_report.get("explosion_vfx_asset_quality_score", -1)),
		"primitive_explosion_notes": String(primitive_explosion_report.get("notes", "")),
		"good_explosion_score": int(good_explosion_report.get("explosion_vfx_asset_quality_score", -1)),
	}
	var file := FileAccess.open("res://result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	var ok := (
		result["bad_projectile_score"] == 2
		and result["bad_projectile_notes"].find("placeholder primitive") >= 0
		and result["good_projectile_score"] == 4
		and result["tiny_explosion_score"] == 3
		and result["primitive_explosion_score"] == 2
		and result["primitive_explosion_notes"].find("placeholder primitive") >= 0
		and result["good_explosion_score"] == 4
	)
	quit(0 if ok else 1)
```

In the Python assertions, verify the JSON values match the `ok` expression.

- [ ] **Step 2: Run helper test and verify it fails**

Run:

```powershell
python -m unittest tests.test_run_grader.TestRunGrader.test_scene_probe_scores_projectile_and_explosion_asset_quality
```

Expected: FAIL because `explosion_vfx_asset_quality_report`, `projectile_asset_quality_score`, and `_presentation_asset_quality_score` do not exist yet.

- [ ] **Step 3: Extend projectile visual reports**

In `scene_probe.gd`, add this scorer near the existing mesh helper methods:

```gdscript
static func _presentation_asset_quality_score(has_visible: bool, has_non_placeholder_asset: bool, has_plausible_footprint: bool) -> int:
	var score := 0
	if has_visible:
		score += 1
	if has_non_placeholder_asset:
		score += 2
	if has_plausible_footprint:
		score += 1
	return score
```

Modify `grenade_projectile_visual_report(...)` so it tracks:

```gdscript
var has_visible_model := mesh_count > 0
var has_non_placeholder_asset := accepted_count > 0 or (mesh_count > 0 and placeholder_count <= 0 and reused_asset_count <= 0)
var has_plausible_scale := accepted_count > 0 or (mesh_count > 0 and bad_size_count <= 0)
var quality_score := _presentation_asset_quality_score(has_visible_model, has_non_placeholder_asset, has_plausible_scale)
```

Return these fields in the dictionary:

```gdscript
"has_visible_model": has_visible_model,
"has_non_placeholder_asset": has_non_placeholder_asset,
"has_plausible_scale": has_plausible_scale,
"projectile_asset_quality_score": quality_score,
```

Keep existing fields such as `has_model_visual`, `placeholder_mesh_count`, and `notes` so older report consumers do not break.

- [ ] **Step 4: Add explosion VFX quality report**

In `scene_probe.gd`, add this helper after `grenade_projectile_visual_report(...)`:

```gdscript
static func explosion_vfx_asset_quality_report(
	candidates: Array[Node3D],
	origin: Vector3,
	min_visual_extent: float = 0.5,
	max_visual_extent: float = 8.0
) -> Dictionary:
	var visible_count := 0
	var placeholder_count := 0
	var reused_asset_count := 0
	var plausible_extent_count := 0
	var non_placeholder_count := 0
	var inspected_notes: Array[String] = []
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		if candidate.global_position.distance_to(origin) > max_visual_extent * 2.0:
			continue
		if not candidate.visible:
			continue
		var candidate_extent := _node3d_visual_extent(candidate)
		if candidate_extent >= min_visual_extent and candidate_extent <= max_visual_extent:
			plausible_extent_count += 1
		if _node_is_particle_vfx(candidate):
			visible_count += 1
			non_placeholder_count += 1
			inspected_notes.append("%s uses particle explosion VFX, extent %.2f" % [str(candidate.get_path()), candidate_extent])
		for mesh_instance in visible_mesh_instances_under(candidate):
			visible_count += 1
			var mesh := mesh_instance.mesh
			var mesh_class := mesh.get_class()
			var max_extent := _mesh_max_world_extent(mesh_instance)
			if max_extent >= min_visual_extent and max_extent <= max_visual_extent:
				plausible_extent_count += 1
			if _mesh_is_placeholder_primitive(mesh):
				placeholder_count += 1
				inspected_notes.append("%s uses placeholder primitive %s" % [str(mesh_instance.get_path()), mesh_class])
				continue
			if _mesh_uses_reused_projectile_asset(mesh_instance):
				reused_asset_count += 1
				inspected_notes.append("%s appears to reuse non-explosion asset %s" % [str(mesh_instance.get_path()), _mesh_resource_path(mesh_instance)])
				continue
			non_placeholder_count += 1
			inspected_notes.append("%s has non-placeholder explosion visual %s, extent %.2f" % [str(mesh_instance.get_path()), mesh_class, max_extent])
	var has_visible_vfx := visible_count > 0
	var has_non_placeholder_asset := non_placeholder_count > 0
	var has_plausible_footprint := plausible_extent_count > 0
	var score := _presentation_asset_quality_score(has_visible_vfx, has_non_placeholder_asset, has_plausible_footprint)
	var notes := "explosion VFX asset quality score %d/4" % score
	if not inspected_notes.is_empty():
		notes += ": " + "; ".join(inspected_notes.slice(0, 3))
	return {
		"has_visible_vfx": has_visible_vfx,
		"has_non_placeholder_asset": has_non_placeholder_asset,
		"has_plausible_footprint": has_plausible_footprint,
		"visible_vfx_count": visible_count,
		"placeholder_mesh_count": placeholder_count,
		"reused_asset_count": reused_asset_count,
		"plausible_extent_count": plausible_extent_count,
		"explosion_vfx_asset_quality_score": score,
		"notes": notes,
	}
```

Add these support helpers below `_mesh_max_world_extent(...)`:

```gdscript
static func _node3d_visual_extent(node_3d: Node3D) -> float:
	if node_3d is MeshInstance3D:
		return _mesh_max_world_extent(node_3d as MeshInstance3D)
	var scale := node_3d.global_transform.basis.get_scale()
	return maxf(absf(scale.x), maxf(absf(scale.y), absf(scale.z)))


static func _node_is_particle_vfx(node: Node) -> bool:
	return node is GPUParticles3D or node is CPUParticles3D
```

Extend `observe_runtime_activity(...)` so it records the best explosion VFX report while transient nodes are still alive. Change the signature to keep existing callers valid:

```gdscript
static func observe_runtime_activity(
	tree: SceneTree,
	root: Node,
	before: Dictionary,
	point: Vector3,
	radius: float,
	frame_count: int,
	vfx_min_extent: float = 0.5,
	vfx_max_extent: float = 8.0
) -> Dictionary:
```

Initialize these values near `visible_ids` and `saw_audio`:

```gdscript
var best_explosion_vfx_score := 0
var best_explosion_vfx_notes := ""
```

Inside the existing loop, immediately after a new visible `Node3D` is accepted into `visible_ids`, add:

```gdscript
var vfx_report := explosion_vfx_asset_quality_report([node_3d], point, vfx_min_extent, vfx_max_extent)
var vfx_score := int(vfx_report.get("explosion_vfx_asset_quality_score", 0))
if vfx_score > best_explosion_vfx_score:
	best_explosion_vfx_score = vfx_score
	best_explosion_vfx_notes = String(vfx_report.get("notes", ""))
```

Add these fields to the returned dictionary:

```gdscript
"explosion_vfx_asset_quality_score": best_explosion_vfx_score,
"explosion_vfx_notes": best_explosion_vfx_notes,
```

- [ ] **Step 5: Run helper test and verify it passes**

Run:

```powershell
python -m unittest tests.test_run_grader.TestRunGrader.test_scene_probe_scores_projectile_and_explosion_asset_quality
```

Expected: PASS when Godot 4.6 is available. If Godot is unavailable, the test should skip using the existing `find_godot()` path.

- [ ] **Step 6: Commit helper implementation**

```powershell
git add verifier_godot/__verifier__/scene_probe.gd tests/test_run_grader.py
git commit -m "feat: score presentation asset quality helpers"
```

---

### Task 4: Implement The 15-Point Visual/Audio Category

**Files:**
- Modify: `verifier_godot/__verifier__/runner.gd`
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Add visual presentation constants**

Near the existing projectile visual constants in `runner.gd`, add:

```gdscript
const EXPLOSION_VFX_MIN_EXTENT := 0.5
const EXPLOSION_VFX_MAX_EXTENT := 8.0
const VISUAL_PRESENTATION_HEADINGS := [0.0, 0.45]
```

- [ ] **Step 2: Add a visual presentation trial helper**

Add this helper before `_score_visual_audio_polish()`:

```gdscript
func _run_visual_presentation_trial(heading_y: float) -> Dictionary:
	await _build_arena()
	if player == null:
		return {
			"projectile_quality": 0,
			"projectile_notes": "no player available",
			"vfx_quality": 0,
			"vfx_notes": "no player available",
			"visual_timing_location": false,
			"saw_audio": false,
			"cleanup": false,
		}
	_set_explosion_trial_heading(heading_y)
	await input.wait_physics_frames(4)
	await _tap_weapon_switch(3, 10)
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before), player.global_position, CALIBRATION_SPAWN_RADIUS)
	var projectile_tracks: Dictionary = await SceneProbe.track_nodes_positions(self, spawned, TRAJECTORY_PROJECTILE_TRACK_FRAMES)
	var projectile_visual: Dictionary = SceneProbe.grenade_projectile_visual_report(
		spawned,
		projectile_tracks,
		CALIBRATION_MIN_TRAVEL_DISTANCE,
		PROJECTILE_VISUAL_MIN_EXTENT,
		PROJECTILE_VISUAL_MAX_EXTENT
	)
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(
		self,
		arena,
		before,
		player.global_position,
		TARGET_FIELD_RADIUS,
		220,
		EXPLOSION_VFX_MIN_EXTENT,
		EXPLOSION_VFX_MAX_EXTENT
	)
	var visible_effects := int(activity.get("visible_count", 0))
	var remaining_new := int(activity.get("remaining_visible_count", 0))
	return {
		"projectile_quality": int(projectile_visual.get("projectile_asset_quality_score", 0)),
		"projectile_notes": String(projectile_visual.get("notes", "")),
		"vfx_quality": int(activity.get("explosion_vfx_asset_quality_score", 0)),
		"vfx_notes": String(activity.get("explosion_vfx_notes", "")),
		"visual_timing_location": visible_effects > 0,
		"saw_audio": visible_effects > 0 and bool(activity.get("saw_audio", false)),
		"cleanup": visible_effects > 0 and remaining_new < visible_effects,
	}
```

- [ ] **Step 3: Replace `_score_visual_audio_polish()`**

Use this aggregation:

```gdscript
func _score_visual_audio_polish() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 15, "missed", "No player available.")]
		board.add("visual_audio_polish", 0, 15, _detail_notes(details), details)
		return
	var trial_results: Array[Dictionary] = []
	for heading_y in VISUAL_PRESENTATION_HEADINGS:
		trial_results.append(await _run_visual_presentation_trial(float(heading_y)))
	var best_projectile_score := 0
	var best_projectile_notes := ""
	var best_vfx_score := 0
	var best_vfx_notes := ""
	var timing_count := 0
	var audio_count := 0
	var cleanup_count := 0
	var strong_consistency_count := 0
	var present_consistency_count := 0
	for result in trial_results:
		var projectile_score := int(result.get("projectile_quality", 0))
		if projectile_score > best_projectile_score:
			best_projectile_score = projectile_score
			best_projectile_notes = String(result.get("projectile_notes", ""))
		var vfx_score := int(result.get("vfx_quality", 0))
		if vfx_score > best_vfx_score:
			best_vfx_score = vfx_score
			best_vfx_notes = String(result.get("vfx_notes", ""))
		if bool(result.get("visual_timing_location", false)):
			timing_count += 1
		if bool(result.get("saw_audio", false)):
			audio_count += 1
		if bool(result.get("cleanup", false)):
			cleanup_count += 1
		if projectile_score >= 3 and vfx_score >= 3:
			strong_consistency_count += 1
		if projectile_score > 0 and vfx_score > 0:
			present_consistency_count += 1
	var timing_score := _scaled_average_score(timing_count, trial_results.size(), 1, 2)
	var audio_score := _scaled_average_score(audio_count, trial_results.size(), 1, 2)
	var cleanup_score := 1 if cleanup_count > 0 else 0
	var consistency_score := 0
	if strong_consistency_count == trial_results.size():
		consistency_score = 2
	elif present_consistency_count == trial_results.size():
		consistency_score = 1
	var details: Array[Dictionary] = []
	details.append(_detail("Thrown grenade model asset quality", best_projectile_score, 4, _score_status(best_projectile_score, 4), best_projectile_notes))
	details.append(_detail("Explosion VFX asset quality", best_vfx_score, 4, _score_status(best_vfx_score, 4), best_vfx_notes))
	details.append(_detail("Detonation visual timing/location", timing_score, 2, _score_status(timing_score, 2), "detonation visual appeared in %d/%d presentation trials" % [timing_count, trial_results.size()]))
	details.append(_detail("Detonation audio", audio_score, 2, _score_status(audio_score, 2), "detonation audio appeared with visible effects in %d/%d presentation trials" % [audio_count, trial_results.size()]))
	details.append(_detail("Temporary visual cleanup", cleanup_score, 1, _score_status(cleanup_score, 1), "temporary visual cleanup observed in %d/%d presentation trials" % [cleanup_count, trial_results.size()]))
	details.append(_detail("Presentation consistency across trials", consistency_score, 2, _score_status(consistency_score, 2), "projectile and explosion presentation consistency across %d trials" % trial_results.size()))
	board.add("visual_audio_polish", _detail_score(details), 15, _detail_notes(details), details)
```

- [ ] **Step 4: Run visual/audio source tests**

Run:

```powershell
python -m unittest tests.test_run_grader.TestRunGrader.test_visual_audio_polish_scores_asset_quality_without_hard_blocking_placeholders tests.test_run_grader.TestRunGrader.test_runner_scores_runtime_grenade_projectile_model_visual
```

Expected: PASS.

- [ ] **Step 5: Run full Python unit suite**

Run:

```powershell
python -m unittest discover -s tests
```

Expected: PASS, with Godot-dependent tests skipped only when the local Godot 4.6 executable is unavailable.

- [ ] **Step 6: Commit visual/audio implementation**

```powershell
git add verifier_godot/__verifier__/runner.gd verifier_godot/__verifier__/scene_probe.gd tests/test_run_grader.py
git commit -m "feat: expand visual audio polish scoring"
```

---

### Task 5: Update Public Benchmark Docs

**Files:**
- Modify: `README.md`
- Modify: `BENCHMARK.md`
- Modify: `probe_matrix.md`
- Modify: `evaluation/writeup.html` when its score/rubric prose reflects the old category table.

- [ ] **Step 1: Update README scoring table and floors**

In `README.md`, update the score categories to:

```markdown
| `weapon_controls` | 15 |
| `hud_feedback` | 8 |
| `trajectory_preview` | 22 |
| `projectile_physics` | 15 |
| `explosion_gameplay` | 20 |
| `visual_audio_polish` | 15 |
| `stability_repeatability` | 5 |
```

Update pass floors to:

```markdown
`trajectory_preview >= 11`, `projectile_physics >= 8`, and
`explosion_gameplay >= 10`, plus a conservative visual presentation floor of
`visual_audio_polish >= 5`.
```

Replace the old projectile-only visual wording with:

```markdown
`visual_audio_polish` includes runtime presentation checks for the thrown
grenade model, explosion VFX asset quality, detonation visual timing/location,
detonation audio, temporary cleanup, and presentation consistency across
deterministic visual trials. Placeholder primitive meshes and obvious reused
non-grenade assets lose asset-quality credit, but placeholder presentation is a
score penalty rather than an automatic pass blocker when core gameplay works.
```

- [ ] **Step 2: Update BENCHMARK score definition**

Make the same category table and pass-floor changes in `BENCHMARK.md`. Preserve the distinction between formal score and auxiliary screenshot visual evidence.

Add this sentence near the visual/audio description:

```markdown
Trajectory preview visibility and aim agreement remain gameplay communication
inside `trajectory_preview`; model and VFX asset quality are presentation
fidelity inside `visual_audio_polish`.
```

- [ ] **Step 3: Update probe matrix active probe set**

In `probe_matrix.md`:

1. Remove the opening paragraph that says the wrong-projectile-model probe is an active high-scoring floor-fail probe.
2. Update floor text to:

```markdown
(`trajectory_preview >= 11`, `projectile_physics >= 8`,
`explosion_gameplay >= 10`, `visual_audio_polish >= 5`)
```

3. Delete the table row:

```markdown
| Wrong projectile model on otherwise complete behavior | ... |
```

4. Replace the closing observed-count paragraph with:

```markdown
The active fast probe set has seven representative fake candidates with
committed score JSON evidence. The previous wrong-projectile-model evidence is
retained only as historical probe evidence from an older visual-floor
calibration point and is not part of the active probe set.
```

- [ ] **Step 4: Update writeup only if it contains old active-score claims**

Search:

```powershell
rg -n "visual_audio_polish|Wrong projectile|trajectory_preview|Detonation effects|5/5|4/5|30|10-point" evaluation/writeup.html
```

If the writeup contains the old 5-point visual score, old active wrong-projectile-model row, or old category table, update the visible report so it matches the new rubric and still follows AGENTS writeup rules:

- one consolidated score table only;
- no local absolute paths;
- wrong-projectile-model only as historical evidence, not active success/failure calibration;
- active rollout/probe score rows updated after calibration reruns.

- [ ] **Step 5: Run documentation sanity search**

Run:

```powershell
rg -n "visual_audio_polish.*5|visual_audio_polish >= 4|trajectory_preview >= 15|trajectory_preview`: 30|wrong-projectile-model probe is intentionally|Wrong projectile model on otherwise complete" README.md BENCHMARK.md probe_matrix.md evaluation/writeup.html
```

Expected: no matches for stale active-rubric statements. Matches in historical evidence prose are acceptable only when the same paragraph says the evidence is historical and no longer active.

- [ ] **Step 6: Commit docs**

```powershell
git add README.md BENCHMARK.md probe_matrix.md evaluation/writeup.html
git commit -m "docs: update presentation fidelity rubric"
```

---

### Task 6: Recalibrate Existing Runs

**Files:**
- Modify: `README.md`
- Modify: `BENCHMARK.md`
- Modify: `probe_matrix.md`
- Modify: `evaluation/writeup.html` when retained evidence changes.
- Create or update curated evidence files only if the project already tracks that specific evidence class intentionally.

- [ ] **Step 1: Record Godot version**

Run:

```powershell
$Godot = "<godot-4.6-console-executable>"
& $Godot --version
```

Expected: a Godot 4.6 version string, preferably `4.6.stable.official.89cea1439` if that is the approved executable.

- [ ] **Step 2: Run unit tests before calibration**

Run:

```powershell
python -m unittest discover -s tests
```

Expected: PASS.

- [ ] **Step 3: Run calibration script**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\run_calibration.ps1"
```

Expected: score JSON and logs under `artifacts/` for the configured reference, ablated, and probe candidates. The run must use Godot 4.6.

- [ ] **Step 4: Confirm the minimum rerun set is represented**

Inspect the calibration output and verify there is fresh evidence for:

- reference behavior;
- ablated task;
- global sweep;
- visual-no-damage;
- damage-no-preview;
- fixed trajectory;
- single-use;
- bad-distance;
- HUD-only.

Do not add a new placeholder visual fake candidate.

- [ ] **Step 5: Update calibration notes**

Update `README.md`, `BENCHMARK.md`, and `probe_matrix.md` with the observed scores from the fresh `artifacts/` JSON files. For each updated row, include:

- exact score out of 100;
- `passed` value;
- floor failures when relevant;
- score JSON evidence path using repo-relative paths;
- Godot version recorded in Step 1.

- [ ] **Step 6: Update writeup evidence**

If `evaluation/writeup.html` is part of the current deliverable, update the consolidated score table, screenshot narrative, and representative frames so the report does not contradict fresh calibration evidence. Embed screenshots as data URIs and keep score/PDF evidence columns only in `Calibration And Scores`.

- [ ] **Step 7: Run final verification**

Run:

```powershell
python -m unittest discover -s tests
```

Expected: PASS.

If Godot is available, also run one direct verifier check against the reference candidate used by calibration:

```powershell
python ".\run_grader.py" --project "<reference-candidate-project>" --godot "<godot-4.6-console-executable>" --out ".\artifacts\reference-new-rubric-score.json" --log ".\artifacts\reference-new-rubric.log"
```

Expected: command exits 0, writes `score`, `max_score: 100`, `logic_score`, `logic_max_score`, `breakdown`, and `category_floor_failures`.

- [ ] **Step 8: Commit calibration documentation and curated evidence**

Stage only updated docs and deliberately curated evidence files:

```powershell
git add README.md BENCHMARK.md probe_matrix.md evaluation/writeup.html evaluation/evidence
git commit -m "docs: refresh calibration for presentation rubric"
```

Do not commit scratch logs, temporary candidate copies, raw artifacts, screenshots, or PDFs unless they are intentionally curated evidence under the repository's existing evidence conventions.

---

## Self-Review

- Spec coverage: The plan implements the approved 15/8/22/15/20/15/5 top-level table, `visual_audio_polish >= 5/15`, moved explosion visual effects out of `explosion_gameplay`, strengthened blast locality to 8/20, removed wrong-projectile-model from the active probe set, and adds helper tests instead of a new fake candidate probe.
- Placeholder scan: The plan uses exact file paths, commands, and expected outcomes. Runtime-dependent score numbers are produced by the calibration commands and then written into docs from generated JSON evidence.
- Type consistency: New helper names are `projectile_asset_quality_score`, `explosion_vfx_asset_quality_report`, `explosion_vfx_asset_quality_score`, and `_presentation_asset_quality_score`; the runner and tests refer to those same names.
