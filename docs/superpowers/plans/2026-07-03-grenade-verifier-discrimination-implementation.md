# Grenade Verifier Discrimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the RoboBlast grenade verifier more discriminating by raising trajectory-preview weight, adding preview/projectile direction consistency, and recording borderline throw distance as a small explosion-gameplay miss.

**Architecture:** Keep all scoring behavior inside the existing Godot runner and probe helper files. Use `tests/test_run_grader.py` for fast structural coverage before changing GDScript, then run the Python suite and a Godot calibration when the engine is available.

**Tech Stack:** Godot 4.6 GDScript verifier files, Python `unittest`, existing ReportLab PDF renderer, Markdown docs.

---

## File Structure

- Modify `tests/test_run_grader.py`: add structural tests for the new weights, trajectory gates, direction helpers, and throw-distance quality detail.
- Modify `tests/test_report_renderer.py`: update sample score maxima so the PDF path exercises the new rubric.
- Modify `verifier_godot/__verifier__/scene_probe.gd`: add reusable horizontal direction and aiming-aid heuristics.
- Modify `verifier_godot/__verifier__/runner.gd`: update category weights, trajectory detail scoring, trajectory gates, preview/projectile direction comparison, and explosion calibration quality scoring.
- Modify `README.md`: update scoring table and calibration notes.
- Modify `BENCHMARK.md`: update scoring table and validity-probe language.
- Modify `probe_matrix.md`: update expected score bands for trajectory and borderline-distance probes.

## Task 1: Add Failing Rubric Tests

**Files:**
- Modify: `tests/test_run_grader.py`
- Modify: `tests/test_report_renderer.py`

- [ ] **Step 1: Add structural tests for new runner rubric**

In `tests/test_run_grader.py`, add these tests inside `RunGraderTests` after `test_runner_drives_trajectory_aim_change_through_project_aim_state`:

```python
    def test_runner_uses_discriminating_score_weights(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('board.add("weapon_controls", _detail_score(details), 15', runner_source)
        self.assertIn('board.add("hud_feedback", _detail_score(details), 10', runner_source)
        self.assertIn('board.add("trajectory_preview", _detail_score(details), 30', runner_source)
        self.assertIn('board.add("projectile_physics", _detail_score(details), 15', runner_source)
        self.assertIn('board.add("explosion_gameplay", _detail_score(details), 20', runner_source)
        self.assertIn('board.add("visual_audio_polish", _detail_score(details), 5', runner_source)
        self.assertIn('board.add("stability_repeatability", _detail_score(details), 5', runner_source)

    def test_trajectory_preview_uses_quality_gates_and_consistency_detail(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('"Visible grenade aiming aid"', runner_source)
        self.assertIn('"Communicates arcing throw"', runner_source)
        self.assertIn('"Updates with aim/camera direction"', runner_source)
        self.assertIn('"Preview matches projectile direction"', runner_source)
        self.assertIn('"Visibility lifecycle/cooldown behavior"', runner_source)
        self.assertIn("trajectory details gated because no visible aiming aid was observed", runner_source)
        self.assertIn("consistency not credited because aiming aid did not update", runner_source)
        self.assertIn("SceneProbe.directions_match", runner_source)

    def test_scene_probe_has_trajectory_direction_helpers(self):
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")

        self.assertIn("horizontal_direction", probe_source)
        self.assertIn("track_horizontal_direction", probe_source)
        self.assertIn("average_horizontal_direction", probe_source)
        self.assertIn("directions_match", probe_source)
        self.assertIn("visible_nodes_suggest_arc_or_landing", probe_source)

    def test_explosion_gameplay_records_throw_distance_quality(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('"Throw distance calibration quality"', runner_source)
        self.assertIn("_calibration_quality_score", runner_source)
        self.assertIn('calibration_status == "full"', runner_source)
        self.assertIn("borderline default throw distance receives 0/2 calibration-quality credit", runner_source)
```

- [ ] **Step 2: Update report renderer sample data for the new rubric**

In `tests/test_report_renderer.py`, change `sample_result()` category maxima and the total score to keep a representative failing report:

```python
def sample_result() -> dict:
    return {
        "score": 35,
        "max_score": 100,
        "passed": False,
        "godot_version": "4.6-stable (official)",
        "breakdown": [
            {
                "name": "weapon_controls",
                "score": 10,
                "max": 15,
                "notes": "swap_weapons input exists; attack after weapon switch did not create observable runtime nodes",
            },
            {
                "name": "hud_feedback",
                "score": 10,
                "max": 10,
                "notes": "player has visible UI controls; UI control state changed after weapon switch",
            },
            {
                "name": "trajectory_preview",
                "score": 6,
                "max": 30,
                "notes": "visible aiming aid appeared; aim feedback did not update or match projectile direction",
            },
            {
                "name": "projectile_physics",
                "score": 4,
                "max": 15,
                "notes": "grenade attack spawned a nearby 3D node; no spawned node showed clear arc motion; projectile overlapped player body",
                "details": [
                    {
                        "label": "Projectile spawned",
                        "score": 4,
                        "max": 4,
                        "status": "earned",
                        "notes": "grenade attack spawned a nearby 3D node",
                    },
                    {
                        "label": "Arcing motion",
                        "score": 0,
                        "max": 8,
                        "status": "missed",
                        "notes": "no spawned node showed clear arc motion",
                    },
                    {
                        "label": "Player-safe path",
                        "score": 0,
                        "max": 3,
                        "status": "missed",
                        "notes": "projectile overlapped player body",
                    },
                ],
            },
            {
                "name": "explosion_gameplay",
                "score": 0,
                "max": 20,
                "notes": LONG_EXPLOSION_NOTE,
            },
            {
                "name": "visual_audio_polish",
                "score": 5,
                "max": 5,
                "notes": "visible and audio effects appeared",
            },
        ],
        "artifacts": {"log": "score.log", "screenshots": []},
    }
```

- [ ] **Step 3: Run the new tests and verify they fail**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_runner_uses_discriminating_score_weights tests.test_run_grader.RunGraderTests.test_trajectory_preview_uses_quality_gates_and_consistency_detail tests.test_run_grader.RunGraderTests.test_scene_probe_has_trajectory_direction_helpers tests.test_run_grader.RunGraderTests.test_explosion_gameplay_records_throw_distance_quality tests.test_report_renderer.ReportRendererTests.test_select_key_findings_prioritizes_zero_scores -v
```

Expected: the `test_report_renderer` test still passes, and the new `test_run_grader` tests fail because `runner.gd` and `scene_probe.gd` still use the old rubric and helper set.

- [ ] **Step 4: Commit failing tests**

Run:

```powershell
git add tests/test_run_grader.py tests/test_report_renderer.py
git commit -m "test: cover discriminating grenade rubric"
```

## Task 2: Add Direction Helpers To SceneProbe

**Files:**
- Modify: `verifier_godot/__verifier__/scene_probe.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add horizontal direction helpers**

In `verifier_godot/__verifier__/scene_probe.gd`, insert this code after `horizontal_distance`:

```gdscript
static func horizontal_direction(a: Vector3, b: Vector3) -> Vector2:
	var delta := Vector2(b.x - a.x, b.z - a.z)
	if delta.length() <= 0.001:
		return Vector2.ZERO
	return delta.normalized()


static func track_horizontal_direction(points: Array, minimum_distance: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var start: Vector3 = points[0]
	for index in range(points.size() - 1, 0, -1):
		var point: Vector3 = points[index]
		if horizontal_distance(start, point) >= minimum_distance:
			return horizontal_direction(start, point)
	return Vector2.ZERO


static func average_horizontal_direction(nodes: Array[Node3D], origin: Vector3) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var position_direction := horizontal_direction(origin, node.global_position)
		if not position_direction.is_zero_approx():
			total += position_direction
			count += 1
			continue
		var forward_3d := (node.global_transform.basis * Vector3.FORWARD).normalized()
		var forward_2d := Vector2(forward_3d.x, forward_3d.z)
		if forward_2d.length() > 0.001:
			total += forward_2d.normalized()
			count += 1
	if count <= 0 or total.length() <= 0.001:
		return Vector2.ZERO
	return total.normalized()


static func directions_match(a: Vector2, b: Vector2, minimum_dot: float) -> bool:
	if a.length() <= 0.001 or b.length() <= 0.001:
		return false
	return a.normalized().dot(b.normalized()) >= minimum_dot
```

- [ ] **Step 2: Add static aiming-aid arc-or-landing heuristic**

In `scene_probe.gd`, insert this code after `directions_match`:

```gdscript
static func visible_nodes_suggest_arc_or_landing(nodes: Array[Node3D], origin: Vector3) -> bool:
	if nodes.is_empty():
		return false
	var min_distance := INF
	var max_distance := 0.0
	var min_y := INF
	var max_y := -INF
	var far_ground_marker := false
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var distance := horizontal_distance(origin, node.global_position)
		min_distance = minf(min_distance, distance)
		max_distance = maxf(max_distance, distance)
		min_y = minf(min_y, node.global_position.y)
		max_y = maxf(max_y, node.global_position.y)
		if distance >= 4.0 and absf(node.global_position.y - origin.y) <= 1.0:
			far_ground_marker = true
	var horizontal_span := max_distance - min_distance
	var vertical_span := max_y - min_y
	return far_ground_marker or (horizontal_span >= 2.0 and vertical_span >= 0.2)
```

- [ ] **Step 3: Run helper test and verify it passes**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_scene_probe_has_trajectory_direction_helpers -v
```

Expected: PASS.

- [ ] **Step 4: Commit helper changes**

Run:

```powershell
git add verifier_godot/__verifier__/scene_probe.gd
git commit -m "feat: add trajectory direction probe helpers"
```

## Task 3: Update Runner Weights And Trajectory Scoring

**Files:**
- Modify: `verifier_godot/__verifier__/runner.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add trajectory constants**

In `runner.gd`, add these constants after `PROJECTILE_PLAYER_MIN_DISTANCE`:

```gdscript
const TRAJECTORY_AID_RADIUS := 25.0
const TRAJECTORY_AIM_CHANGE_HEADING := 0.45
const TRAJECTORY_DIRECTION_MIN_DOT := 0.5
const TRAJECTORY_PROJECTILE_TRACK_FRAMES := 35
```

- [ ] **Step 2: Add runner-local helper functions**

In `runner.gd`, insert these helpers before `_score_trajectory_preview`:

```gdscript
func _count_visible_nodes(nodes: Array[Node3D]) -> int:
	var count := 0
	for node in nodes:
		if is_instance_valid(node) and node.visible:
			count += 1
	return count


func _nodes_moved_or_rotated(nodes: Array[Node3D], first_transforms: Array[Transform3D], origin_threshold: float, angle_threshold: float) -> bool:
	for index in range(nodes.size()):
		var node := nodes[index]
		if not is_instance_valid(node) or index >= first_transforms.size():
			continue
		var first_transform := first_transforms[index]
		var origin_moved := node.global_transform.origin.distance_to(first_transform.origin) > origin_threshold
		var basis_moved := node.global_transform.basis.get_euler().distance_to(first_transform.basis.get_euler()) > angle_threshold
		if origin_moved or basis_moved:
			return true
	return false


func _projectile_direction_after_attack(before_attack: Dictionary) -> Vector2:
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before_attack), player.global_position, CALIBRATION_SPAWN_RADIUS)
	if spawned.is_empty():
		return Vector2.ZERO
	var tracks: Dictionary = await SceneProbe.track_nodes_positions(self, spawned, TRAJECTORY_PROJECTILE_TRACK_FRAMES)
	for candidate in spawned:
		if not is_instance_valid(candidate):
			continue
		var points: Array = tracks.get(candidate.get_instance_id(), [])
		var direction := SceneProbe.track_horizontal_direction(points, CALIBRATION_MIN_TRAVEL_DISTANCE)
		if not direction.is_zero_approx():
			return direction
	return Vector2.ZERO
```

- [ ] **Step 3: Lower HUD max from 15 to 10**

In `_score_hud_feedback`, replace the max scores with this distribution:

```gdscript
details.append(_score_detail(
	"Visible UI controls",
	3,
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
await input.hold("aim", 8)
var aiming_snapshot := SceneProbe.control_snapshot(arena)
await input.release("aim")
details.append(_score_detail(
	"Aiming UI feedback",
	3,
	SceneProbe.count_changed_controls(after, aiming_snapshot) > 0,
	"aiming changes UI feedback",
	"aiming did not change UI feedback"
))
board.add("hud_feedback", _detail_score(details), 10, _detail_notes(details), details)
```

Also change the player-null path in `_score_hud_feedback` to:

```gdscript
var details: Array[Dictionary] = [_detail("Player availability", 0, 10, "missed", "No player available.")]
board.add("hud_feedback", 0, 10, _detail_notes(details), details)
```

- [ ] **Step 4: Replace trajectory scoring function**

Replace `_score_trajectory_preview` with:

```gdscript
func _score_trajectory_preview() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 30, "missed", "No player available.")]
		board.add("trajectory_preview", 0, 30, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await _tap_weapon_switch(3, 10)
	await input.wait_physics_frames(8)
	var aiming_aid_nodes := SceneProbe.newly_visible_3d_nodes(arena, before_visible, player.global_position, TRAJECTORY_AID_RADIUS)
	var visible_aid := aiming_aid_nodes.size() > 0
	details.append(_score_detail(
		"Visible grenade aiming aid",
		5,
		visible_aid,
		"visible grenade aiming aid appears in grenade mode",
		"no visible grenade trajectory, landing marker, or equivalent aiming aid detected"
	))
	if not visible_aid:
		details.append(_detail("Communicates arcing throw", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Updates with aim/camera direction", 0, 8, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Visibility lifecycle/cooldown behavior", 0, 4, "missed", "trajectory details gated because no visible aiming aid was observed"))
		board.add("trajectory_preview", _detail_score(details), 30, _detail_notes(details), details)
		return

	var first_transforms: Array[Transform3D] = []
	for node in aiming_aid_nodes:
		first_transforms.append(node.global_transform)
	var first_direction := SceneProbe.average_horizontal_direction(aiming_aid_nodes, player.global_position)
	var communicates_arc := SceneProbe.visible_nodes_suggest_arc_or_landing(aiming_aid_nodes, player.global_position)
	details.append(_score_detail(
		"Communicates arcing throw",
		6,
		communicates_arc,
		"aiming aid communicates an arcing throw or landing area",
		"aiming aid does not clearly communicate an arcing grenade throw"
	))

	_set_explosion_trial_heading(TRAJECTORY_AIM_CHANGE_HEADING)
	await input.wait_physics_frames(12)
	var second_direction := SceneProbe.average_horizontal_direction(aiming_aid_nodes, player.global_position)
	var moved_feedback := _nodes_moved_or_rotated(aiming_aid_nodes, first_transforms, 0.2, 0.05)
	var changed_direction := (not first_direction.is_zero_approx() and not second_direction.is_zero_approx() and first_direction.dot(second_direction) < 0.95)
	var updates_with_aim := moved_feedback or changed_direction
	details.append(_score_detail(
		"Updates with aim/camera direction",
		8,
		updates_with_aim,
		"aiming aid updates after aim or camera direction changes",
		"aiming aid did not update after aim or camera direction changed"
	))

	var before_attack := SceneProbe.collect_instance_ids(arena)
	var projectile_direction := await _projectile_direction_after_attack(before_attack)
	var consistency := updates_with_aim and SceneProbe.directions_match(second_direction, projectile_direction, TRAJECTORY_DIRECTION_MIN_DOT)
	if consistency:
		details.append(_detail("Preview matches projectile direction", 7, 7, "earned", "aiming aid direction matches the thrown grenade direction"))
	elif not updates_with_aim:
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "consistency not credited because aiming aid did not update"))
	elif projectile_direction.is_zero_approx():
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "consistency not credited because no measurable grenade projectile direction was observed"))
	else:
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "aiming aid direction did not match the thrown grenade direction"))

	await input.wait_physics_frames(12)
	var visible_during_cooldown := _count_visible_nodes(aiming_aid_nodes) > 0
	await _tap_weapon_switch(3, 8)
	await input.wait_physics_frames(8)
	var visible_after_switch := _count_visible_nodes(aiming_aid_nodes)
	var lifecycle_ok := visible_during_cooldown and visible_after_switch < aiming_aid_nodes.size()
	details.append(_score_detail(
		"Visibility lifecycle/cooldown behavior",
		4,
		lifecycle_ok,
		"aiming aid remains available in grenade mode and hides after leaving grenade mode",
		"aiming aid did not show the expected grenade-mode lifecycle"
	))
	board.add("trajectory_preview", _detail_score(details), 30, _detail_notes(details), details)
```

- [ ] **Step 5: Lower visual/audio max from 10 to 5**

In `_score_visual_audio_polish`, use this scoring:

```gdscript
if player == null:
	var details: Array[Dictionary] = [_detail("Player availability", 0, 5, "missed", "No player available.")]
	board.add("visual_audio_polish", 0, 5, _detail_notes(details), details)
	return
```

Then set the three detail values to `2`, `2`, and `1`:

```gdscript
details.append(_score_detail(
	"Visible effect nodes",
	2,
	visible_effects > 0,
	"visible grenade or explosion nodes appeared",
	"no visible grenade or explosion nodes appeared"
))
details.append(_score_detail(
	"Detonation audio",
	2,
	visible_effects > 0 and bool(activity.get("saw_audio", false)),
	"audio player was active during detonation window",
	"detonation audio not observed during visible detonation window"
))
details.append(_score_detail(
	"Temporary node cleanup",
	1,
	visible_effects > 0 and int(activity.get("remaining_visible_count", 0)) < visible_effects,
	"some temporary nodes cleaned up",
	"temporary visual nodes did not visibly clean up"
))
board.add("visual_audio_polish", _detail_score(details), 5, _detail_notes(details), details)
```

- [ ] **Step 6: Run runner rubric tests**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_runner_uses_discriminating_score_weights tests.test_run_grader.RunGraderTests.test_trajectory_preview_uses_quality_gates_and_consistency_detail tests.test_run_grader.RunGraderTests.test_runner_drives_trajectory_aim_change_through_project_aim_state -v
```

Expected: PASS.

- [ ] **Step 7: Commit trajectory scoring update**

Run:

```powershell
git add verifier_godot/__verifier__/runner.gd
git commit -m "feat: strengthen trajectory preview scoring"
```

## Task 4: Add Throw-Distance Quality To Explosion Scoring

**Files:**
- Modify: `verifier_godot/__verifier__/runner.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add calibration-quality helper**

In `runner.gd`, insert this helper before `_explosion_details_from_trials`:

```gdscript
func _calibration_quality_score(calibration_status: String) -> int:
	if calibration_status == "full":
		return 2
	return 0
```

- [ ] **Step 2: Update explosion detail weights**

In `_explosion_details_from_trials`, change nearby target scaling from 10 max to 8 max:

```gdscript
var nearby_score := _scaled_average_score(total_near_score, trial_results.size(), 10, 8)
details.append(_detail(
	"Nearby target damage across angles",
	nearby_score,
	8,
	_score_status(nearby_score, 8),
	calibration_prefix + "; nearby target damage averaged across explosion trials: " + "; ".join(near_notes)
))
```

At the end of `_explosion_details_from_trials`, before `return details`, append the calibration-quality detail:

```gdscript
var calibration_quality_score := _calibration_quality_score(calibration_status)
var calibration_quality_status := _score_status(calibration_quality_score, 2)
var calibration_quality_notes := "default throw calibration is full quality inside the 6-12 unit envelope"
if calibration_status == "borderline":
	calibration_quality_notes = "borderline default throw distance receives 0/2 calibration-quality credit"
elif calibration_status != "full":
	calibration_quality_notes = "default throw calibration failed or landed outside the accepted envelope"
details.append(_detail(
	"Throw distance calibration quality",
	calibration_quality_score,
	2,
	calibration_quality_status,
	calibration_quality_notes
))
return details
```

- [ ] **Step 3: Update near-note denominator**

In the loop over `trial_results`, keep `near_score` as a per-trial value out of 10, but make the final detail notes explicit:

```gdscript
near_notes.append("%s raw nearby hit score %d/10" % [label, near_score])
```

- [ ] **Step 4: Run explosion scoring tests**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_explosion_gameplay_records_throw_distance_quality tests.test_run_grader.RunGraderTests.test_runner_declares_default_throw_calibration_flow tests.test_run_grader.RunGraderTests.test_runner_uses_adaptive_explosion_target_placement_with_fixed_fallback -v
```

Expected: PASS.

- [ ] **Step 5: Commit explosion calibration update**

Run:

```powershell
git add verifier_godot/__verifier__/runner.gd
git commit -m "feat: score throw distance calibration quality"
```

## Task 5: Update Public Docs And Probe Matrix

**Files:**
- Modify: `README.md`
- Modify: `BENCHMARK.md`
- Modify: `probe_matrix.md`

- [ ] **Step 1: Update README score categories**

In `README.md`, replace the score category bullets with:

```markdown
- `weapon_controls`: 15 points
- `hud_feedback`: 10 points
- `trajectory_preview`: 30 points
- `projectile_physics`: 15 points
- `explosion_gameplay`: 20 points
- `visual_audio_polish`: 5 points
- `stability_repeatability`: 5 points
```

- [ ] **Step 2: Update README calibration paragraph**

In `README.md`, replace the calibration paragraph under `## Calibration` with:

```markdown
Explosion scoring calibrates default throw distance behaviorally. The runner measures a target-free throw, accepts only a nearby player-safe travel path, gives full throw-distance quality credit to a 6-12 unit default landing distance, and treats 4-14 units as borderline usable but worth `0/2` calibration-quality points. Formal explosion trials are generated from fixed seed constants: each seed deterministically picks a heading, nearby target radii around the canonical 6, 8, 10, and 12 unit rings plus the measured landing distance, and a far/side/rear safety radius inside the 30-unit target field. Every run of the same verifier version uses the same seeded variants. Detonation effects are observed inside the same 30-unit target field, but explosion gameplay still requires real damage evidence before effect or safety credit is awarded. Safety targets remain far enough to catch over-large explosions without moving inward with explosion radius. Trajectory preview scoring now emphasizes visible aiming aid behavior, arcing or landing-area communication, aim/camera reactivity, and broad direction consistency with the actual thrown grenade.
```

- [ ] **Step 3: Update BENCHMARK score categories**

In `BENCHMARK.md`, replace the score category bullets with:

```markdown
- `weapon_controls`: 15
- `hud_feedback`: 10
- `trajectory_preview`: 30
- `projectile_physics`: 15
- `explosion_gameplay`: 20
- `visual_audio_polish`: 5
- `stability_repeatability`: 5
```

- [ ] **Step 4: Update BENCHMARK validity-probe language**

In `BENCHMARK.md`, replace the validity-probe bullet that mentions fixed trajectory with:

```markdown
- HUD-only, direct-damage, visual-only, fixed or wrong trajectory, broad-damage,
  borderline throw-distance, and single-use implementations do not receive high
  scores
```

- [ ] **Step 5: Update probe matrix ranges**

In `probe_matrix.md`, replace the affected rows with:

```markdown
| Damage with no trajectory feedback | 30-60 | `trajectory_preview` remains low even if adaptive explosion placement gives some damage credit. |
| Fixed or wrong trajectory that ignores aim | 30-70 | `trajectory_preview` loses aim-change and preview/projectile consistency points; `explosion_gameplay` may still credit localized damage when the blast is otherwise real, nearby, and safe. |
| Very short or very long default throw | 25-68 | Calibration notes failed or borderline distance; throw-distance quality records `0/2` and fixed fallback or safety targets prevent full explosion credit. |
```

- [ ] **Step 6: Commit docs**

Run:

```powershell
git add README.md BENCHMARK.md probe_matrix.md
git commit -m "docs: update grenade rubric calibration"
```

## Task 6: Run Full Verification

**Files:**
- No source edits in this task unless verification reveals a concrete failing change from earlier tasks.

- [ ] **Step 1: Run Python unit tests**

Run:

```powershell
python -m unittest discover -s tests -v
```

Expected: all tests pass. Godot-backed tests may skip only when no Godot executable is available.

- [ ] **Step 2: Run headless calibration when Godot 4.6 is available**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Expected:

```text
Godot executable: C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe
Godot version: 4.6.stable.official.89cea1439
ablated task: still low, around 10-20
reference implementation: still high, ideally 95-100 when the reference path exists
Sonnet-2 partial candidate: around 60-70 or low 70s when the candidate path exists
```

- [ ] **Step 3: Record local calibration notes without committing generated artifacts**

If calibration produced new JSON/log files under `artifacts/`, leave them unstaged. Update `README.md` only with a concise latest-local-calibration summary and the exact Godot executable/version observed.

Use this Markdown shape:

```markdown
Latest local calibration:

- Godot executable: `C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe`
- Godot version: `4.6.stable.official.89cea1439`
- Ablated task branch: `<score>/100`; grenade behavior remains absent.
- Reference branch: `<score>/100` if available locally.
- Sonnet-2 partial candidate: `<score>/100` if available locally; trajectory preview defects now keep it below pass-level.
```

- [ ] **Step 4: Commit calibration-note adjustment if README changed**

Run only if `README.md` changed in Step 3:

```powershell
git add README.md
git commit -m "docs: record verifier recalibration"
```

- [ ] **Step 5: Confirm generated artifacts are unstaged**

Run:

```powershell
git status --short
```

Expected: source/doc changes are committed. Generated runtime files under `artifacts/` are unstaged or ignored, and unrelated pre-existing untracked files are still not staged.
