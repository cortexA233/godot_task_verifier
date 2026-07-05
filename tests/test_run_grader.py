import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import run_grader


def find_godot() -> Path | None:
    candidates = [
        os.environ.get("GODOT_PATH"),
        r"C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe",
        r"C:\Godot_v4.6-stable_mono_win64\Godot_v4.6-stable_mono_win64_console.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return Path(candidate)
    return None


class RunGraderTests(unittest.TestCase):
    def test_runner_records_structured_score_details(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_score_detail(", runner_source)
        self.assertIn('"Projectile spawned"', runner_source)
        self.assertIn('"Nearby target damage across angles"', runner_source)
        self.assertIn('"Detonation effects across angles"', runner_source)

    def test_explosion_gameplay_uses_multiple_out_of_range_safety_targets(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("EXPLOSION_TRIAL_SEEDS", runner_source)
        self.assertIn("_explosion_trial_variants", runner_source)
        self.assertIn("_run_explosion_trial", runner_source)
        self.assertIn('"seed"', runner_source)
        self.assertIn('"FarTarget"', runner_source)
        self.assertIn('"LeftSideTarget"', runner_source)
        self.assertIn('"RightSideTarget"', runner_source)
        self.assertIn('"RearTarget"', runner_source)
        self.assertIn("out-of-range safety targets were damaged", runner_source)
        self.assertIn("all explosion safety trials protected out-of-range targets", runner_source)
        self.assertIn("damage_detonation_observed", runner_source)
        self.assertIn("_add_nearby_damage_targets(arena, target_group, nearby_radii)", runner_source)
        self.assertGreaterEqual(runner_source.count("_add_safety_target(arena,"), 4)

    def test_explosion_gameplay_uses_fixed_seed_parameterized_trials(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("EXPLOSION_TRIAL_SEEDS := [", runner_source)
        self.assertIn("EXPLOSION_TRIAL_BASE_HEADING_DEGREES", runner_source)
        self.assertIn("RandomNumberGenerator.new()", runner_source)
        self.assertIn("rng.seed = seed_value", runner_source)
        self.assertIn("_seeded_nearby_damage_radii", runner_source)
        self.assertIn('"nearby_radii"', runner_source)
        self.assertIn('"safety_radius"', runner_source)
        self.assertIn('"heading_y"', runner_source)
        self.assertIn("_run_explosion_trial(trial, calibration)", runner_source)
        self.assertNotIn("EXPLOSION_TRIALS := [", runner_source)

    def test_explosion_gameplay_uses_radial_nearby_damage_target_rings(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("TARGET_FIELD_RADIUS := 30.0", runner_source)
        self.assertIn("NEARBY_TARGET_GROUP_DEGREES := 20", runner_source)
        self.assertIn("NEARBY_TARGET_GROUP_COUNT := 18", runner_source)
        self.assertIn("NEARBY_DAMAGE_TARGET_RADII := [6.0, 8.0, 10.0, 12.0]", runner_source)
        self.assertIn("_nearby_damage_target_groups", runner_source)
        self.assertIn("_nearby_target_group_name", runner_source)
        self.assertIn("_target_group_for_heading", runner_source)
        self.assertIn("for index in range(NEARBY_TARGET_GROUP_COUNT)", runner_source)
        self.assertIn("var degrees := index * NEARBY_TARGET_GROUP_DEGREES", runner_source)
        self.assertIn("_add_nearby_damage_targets", runner_source)
        self.assertIn("for group_data in _nearby_damage_target_groups()", runner_source)
        self.assertIn('var group := String(group_data["target_group"])', runner_source)
        self.assertIn("_polar_target_position(float(group_data[\"heading_y\"]), radius)", runner_source)
        self.assertIn("_nearby_hit_score", runner_source)
        self.assertIn('target.name = "NearbyTarget_%s_%02d"', runner_source)
        self.assertIn("_nearby_hit_score(expected_nearby_hits, nearby_hits, damaged_safety_targets.size(), global_sweep)", runner_source)
        self.assertIn("expected_nearby_hits > 0", runner_source)
        self.assertIn("nearby_hits > 0", runner_source)

    def test_runner_prefers_project_weapon_switch_action_when_available(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_weapon_switch_action", runner_source)
        self.assertIn('"weapon_switch"', runner_source)

    def test_weapon_controls_scores_behavior_not_action_names(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('"Weapon switch input responds"', runner_source)
        self.assertIn('"Controller weapon-switch binding"', runner_source)
        self.assertIn("_switch_route_has_joypad_binding", runner_source)
        self.assertIn("_action_is_weapon_switch_route", runner_source)
        self.assertIn("InputEventJoypadButton", runner_source)
        self.assertIn("KEY_TAB", runner_source)
        # The old name-based detail must not award points for the
        # swap_weapons action name existing.
        self.assertNotIn('"Weapon switch input action"', runner_source)

    def test_runner_routes_all_weapon_switch_taps_through_helper(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertNotIn('input.tap("swap_weapons")', runner_source)
        self.assertNotIn('input.can_drive("swap_weapons")', runner_source)
        self.assertIn("await _tap_weapon_switch()", runner_source)

    def test_score_board_enforces_category_floors_and_suspect_flag(self):
        board_source = (ROOT / "verifier_godot" / "__verifier__" / "score_board.gd").read_text(encoding="utf-8")

        self.assertIn("PASS_THRESHOLD := 85", board_source)
        self.assertIn('"trajectory_preview": 15', board_source)
        self.assertIn('"projectile_physics": 8', board_source)
        self.assertIn('"explosion_gameplay": 10', board_source)
        self.assertIn('"visual_audio_polish": 4', board_source)
        self.assertIn("failed_category_floors", board_source)
        self.assertIn("floor_failures.is_empty()", board_source)
        self.assertIn('"category_floor_failures": floor_failures', board_source)
        self.assertIn("func flag_suspect", board_source)
        self.assertIn('"suspect": not _suspect_reasons.is_empty()', board_source)
        self.assertIn('"suspect_reasons": _suspect_reasons', board_source)

    def test_score_board_keeps_visual_polish_inside_formal_logic_score(self):
        board_source = (ROOT / "verifier_godot" / "__verifier__" / "score_board.gd").read_text(encoding="utf-8")

        self.assertIn('"visual_audio_polish"', board_source)
        self.assertIn('"score_sections": sections', board_source)
        self.assertIn('"logic_score": score_total', board_source)
        self.assertIn('"logic_max_score": max_total', board_source)
        self.assertIn('_score_section("logic", "Logic Score"', board_source)
        self.assertNotIn("VISUAL_SCORE_CATEGORIES", board_source)
        self.assertNotIn('_score_section("visual", "Visual Score"', board_source)
        self.assertNotIn('"visual_score":', board_source)
        self.assertIn("func score_sections() -> Array[Dictionary]", board_source)

    def test_screenshot_probe_declares_auxiliary_visual_score_not_used_for_score(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")

        self.assertIn('"auxiliary_score_sections"', runner_source)
        self.assertIn('"name": "screenshot_visual"', runner_source)
        self.assertIn('"used_for_score": false', runner_source)
        self.assertIn("_screenshot_visual_score", runner_source)

    def test_screenshot_probe_scores_footprint_quality_as_ten_point_auxiliary_score(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")

        self.assertIn('"max": 10', runner_source)
        self.assertIn("DEBUG_FOOTPRINT_PARTIAL_AREA", runner_source)
        self.assertIn("DEBUG_FOOTPRINT_FULL_AREA", runner_source)
        self.assertIn("MAIN_FOOTPRINT_PARTIAL_AREA", runner_source)
        self.assertIn("MAIN_FOOTPRINT_STRONG_AREA", runner_source)
        self.assertIn("MAIN_FOOTPRINT_FULL_AREA", runner_source)
        self.assertIn("_footprint_quality_score", runner_source)
        self.assertIn("projectile footprint too small", runner_source)
        self.assertIn("not counted in 100-point score", runner_source)

    def test_runner_flags_explosion_suspects_for_manual_review(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_flag_explosion_suspects(trial_results, capped_score < raw_score)", runner_source)
        self.assertIn('board.flag_suspect("global damage sweep detected across explosion trials")', runner_source)
        self.assertIn('board.flag_suspect("explosion damaged out-of-range far/side/rear safety targets")', runner_source)
        self.assertIn('board.flag_suspect("player was affected by their own grenade explosion")', runner_source)

    def test_scene_probe_has_calibration_tracking_helpers(self):
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")

        self.assertIn("track_nodes_positions", probe_source)
        self.assertIn("horizontal_distance", probe_source)
        self.assertIn("horizontal_travel_distance", probe_source)
        self.assertIn("path_is_player_safe", probe_source)
        self.assertIn("calibration_path_is_usable", probe_source)

    def test_runner_declares_default_throw_calibration_flow(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("CALIBRATION_FULL_MIN_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_FULL_MAX_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_BORDERLINE_MIN_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_BORDERLINE_MAX_DISTANCE", runner_source)
        self.assertIn("_calibrate_default_throw_distance", runner_source)
        self.assertIn("_calibration_band", runner_source)
        self.assertIn("candidate_records", runner_source)
        self.assertIn("_object_has_property", runner_source)
        self.assertIn("_last_strong_direction", runner_source)
        self.assertIn("_target_forward_distance", runner_source)
        self.assertIn("_polar_target_position", runner_source)
        self.assertIn("calibration[\"status\"]", runner_source)
        self.assertIn("default throw calibration", runner_source)

    def test_runner_uses_adaptive_explosion_target_placement_with_fixed_fallback(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("FALLBACK_THROW_DISTANCE", runner_source)
        self.assertIn("FAR_TARGET_DISTANCE := 25.0", runner_source)
        self.assertIn("var target_forward_distance := _target_forward_distance(calibration)", runner_source)
        self.assertIn("for trial in _explosion_trial_variants(calibration)", runner_source)
        self.assertIn("_run_explosion_trial(trial, calibration)", runner_source)
        self.assertIn("_explosion_details_from_trials(trial_results, calibration)", runner_source)
        self.assertIn("_add_nearby_damage_targets(arena, target_group, nearby_radii)", runner_source)
        self.assertIn('_add_safety_target(arena, "FarTarget", heading_y, safety_radius)', runner_source)

    def test_runner_drives_trajectory_aim_change_through_project_aim_state(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_set_explosion_trial_heading(0.45)", runner_source)
        self.assertIn("first_transforms", runner_source)

    def test_runner_uses_discriminating_score_weights(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('board.add("weapon_controls", _detail_score(details), 15', runner_source)
        self.assertIn('board.add("hud_feedback", _detail_score(details), 10', runner_source)
        self.assertIn('board.add("trajectory_preview", _detail_score(details), 30', runner_source)
        self.assertIn('board.add("projectile_physics", _detail_score(details), 15', runner_source)
        self.assertIn('board.add("explosion_gameplay", capped_score, 20', runner_source)
        self.assertIn("_explosion_gameplay_score_cap", runner_source)
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

    def test_scene_probe_declares_auxiliary_screenshot_pixel_helpers(self):
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("viewport_screenshot_signature", probe_source)
        self.assertIn("frame_signature_delta", probe_source)
        self.assertIn("save_viewport_screenshot", probe_source)
        self.assertIn('DisplayServer.get_name() == "headless"', probe_source)
        self.assertIn('board.add("visual_audio_polish", _detail_score(details), 5', runner_source)

    def test_screenshot_probe_captures_every_ten_frames_until_explosion(self):
        probe_runner = ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd"
        visual_probe = ROOT / "verifier_godot" / "__verifier__" / "screenshot_visual_probe.gd"
        cli_runner = ROOT / "run_screenshot_probe.py"

        self.assertTrue(probe_runner.exists())
        self.assertTrue(visual_probe.exists())
        self.assertTrue(cli_runner.exists())

        probe_source = probe_runner.read_text(encoding="utf-8")
        visual_source = visual_probe.read_text(encoding="utf-8")
        cli_source = cli_runner.read_text(encoding="utf-8")
        combined_source = probe_source + "\n" + visual_source

        self.assertIn("SCREENSHOT_INTERVAL_FRAMES := 10", combined_source)
        self.assertIn("MAX_POST_THROW_FRAMES", combined_source)
        self.assertIn("_explosion_nodes_since", combined_source)
        self.assertIn('"attack_%03d"', combined_source)
        self.assertIn('"explosion_observed"', combined_source)
        self.assertIn("res://__verifier__/screenshot_probe_runner.gd", cli_source)

    def test_screenshot_probe_cli_declares_visual_modes(self):
        cli_source = (ROOT / "run_screenshot_probe.py").read_text(encoding="utf-8")

        self.assertIn('"--mode"', cli_source)
        self.assertIn('choices=["debug-arena", "main-scene", "both", "trajectory-shadow"]', cli_source)
        self.assertIn('default="both"', cli_source)
        self.assertIn('"--probe-mode"', cli_source)
        self.assertIn("copytree", cli_source)

    def test_screenshot_probe_runner_declares_debug_and_main_scene_modes(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")
        visual_source_path = ROOT / "verifier_godot" / "__verifier__" / "screenshot_visual_probe.gd"

        self.assertTrue(visual_source_path.exists())
        visual_source = visual_source_path.read_text(encoding="utf-8")

        self.assertIn("ScreenshotVisualProbe", runner_source)
        self.assertIn("OS.get_cmdline_user_args", runner_source)
        self.assertIn('"debug-arena"', runner_source)
        self.assertIn('"main-scene"', runner_source)
        self.assertIn('"both"', runner_source)
        self.assertIn('"used_for_score": false', runner_source)
        self.assertIn("run_debug_arena", visual_source)
        self.assertIn("run_main_scene", visual_source)
        self.assertIn("res://main.tscn", visual_source)
        self.assertIn('"debug_arena"', visual_source)
        self.assertIn('"main_scene"', visual_source)
        self.assertGreaterEqual(visual_source.count("await input.tap(_weapon_switch_action(), 3, 12)"), 2)

    def test_scene_probe_declares_projectile_footprint_helpers(self):
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")
        visual_source_path = ROOT / "verifier_godot" / "__verifier__" / "screenshot_visual_probe.gd"

        self.assertTrue(visual_source_path.exists())
        visual_source = visual_source_path.read_text(encoding="utf-8")

        self.assertIn("projectile_screen_rect", probe_source)
        self.assertIn("viewport_region_signature", probe_source)
        self.assertIn("viewport_image", probe_source)
        self.assertIn("image_region_signature", probe_source)
        self.assertIn("projectile_footprint", visual_source)
        self.assertIn("used_for_score", visual_source)
        self.assertIn("delta_in_rect", visual_source)

    def test_explosion_gameplay_records_throw_distance_quality(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('"Throw distance calibration quality"', runner_source)
        self.assertIn("_calibration_quality_score", runner_source)
        self.assertIn('calibration_status == "full"', runner_source)
        self.assertIn("borderline default throw distance receives 0/2 calibration-quality credit", runner_source)

    def test_runner_requires_visible_effect_for_detonation_audio_credit(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('visible_effects > 0 and bool(activity.get("saw_audio", false))', runner_source)

    def test_runner_scores_runtime_grenade_projectile_model_visual(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")

        self.assertIn('"Thrown grenade model"', runner_source)
        self.assertIn("grenade_projectile_visual_report", runner_source)
        self.assertIn("PROJECTILE_VISUAL_MIN_EXTENT", runner_source)
        self.assertIn("grenade_projectile_visual_report", probe_source)
        self.assertIn("_mesh_is_placeholder_primitive", probe_source)
        self.assertIn("_mesh_uses_reused_projectile_asset", probe_source)

    def test_runner_declares_main_scene_integration_smoke_check(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_score_main_scene_integration", runner_source)
        self.assertIn("res://main.tscn", runner_source)
        self.assertIn('"Main scene loads"', runner_source)
        self.assertIn('"Main scene default attacks"', runner_source)
        self.assertIn('"Main scene actors and pickups"', runner_source)
        self.assertIn("collect_coin", runner_source)
        self.assertIn("damageables", runner_source)
        self.assertIn("targeteables", runner_source)
        self.assertIn("_stop_audio_players_under", runner_source)
        self.assertIn("AudioStreamPlayer3D", runner_source)

    def test_explosion_gameplay_detects_nearby_damage_when_actual_throw_angle_differs(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            candidate = tmp_path / "candidate"
            player_dir = candidate / "player"
            player_dir.mkdir(parents=True)
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (player_dir / "player.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=2 format=3]

                [ext_resource type="Script" path="res://player/player.gd" id="1_player"]

                [node name="Player" type="CharacterBody3D"]
                script = ExtResource("1_player")
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "fake_grenade.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=2 format=3]

                [ext_resource type="Script" path="res://player/fake_grenade.gd" id="1_grenade"]

                [node name="FakeGrenadeProjectile" type="Node3D"]
                script = ExtResource("1_grenade")
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "player.gd").write_text(textwrap.dedent(
                """
                extends CharacterBody3D

                signal weapon_switched(weapon_name: String)

                const GRENADE_SCENE := preload("res://player/fake_grenade.tscn")

                var _weapon_mode := "DEFAULT"


                func _ready() -> void:
                    _ensure_action("swap_weapons")
                    _ensure_action("weapon_switch")
                    _ensure_action("attack")
                    _ensure_action("aim")
                    weapon_switched.emit(_weapon_mode)


                func _physics_process(_delta: float) -> void:
                    if Input.is_action_just_pressed("swap_weapons") or Input.is_action_just_pressed("weapon_switch"):
                        _weapon_mode = "GRENADE" if _weapon_mode == "DEFAULT" else "DEFAULT"
                        weapon_switched.emit(_weapon_mode)
                    if Input.is_action_just_pressed("attack"):
                        if _weapon_mode == "GRENADE":
                            var grenade := GRENADE_SCENE.instantiate()
                            grenade.shooter = self
                            get_parent().add_child(grenade)
                            grenade.global_position = global_position + Vector3.UP * 1.4
                        else:
                            var default_attack := Node3D.new()
                            default_attack.name = "DefaultAttackNode"
                            get_parent().add_child(default_attack)
                            default_attack.global_position = global_position + Vector3(0, 1.0, -2.0)


                func _ensure_action(action_name: String) -> void:
                    if not InputMap.has_action(action_name):
                        InputMap.add_action(action_name)
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "fake_grenade.gd").write_text(textwrap.dedent(
                """
                extends Node3D

                const DETONATE_FRAME := 70
                const THROW_DISTANCE := 11.0
                const EXPLOSION_RADIUS := 4.5

                var shooter: Node = null
                var _start_position := Vector3.ZERO
                var _frame := 0
                var _detonated := false


                func _ready() -> void:
                    _start_position = global_position


                func _physics_process(_delta: float) -> void:
                    if _detonated:
                        return
                    _frame += 1
                    var t := minf(float(_frame) / float(DETONATE_FRAME), 1.0)
                    global_position = _start_position + Vector3(0.0, sin(t * PI) * 1.5, THROW_DISTANCE * t)
                    if _frame >= DETONATE_FRAME:
                        _detonate()


                func _detonate() -> void:
                    if _detonated:
                        return
                    _detonated = true
                    var effect := MeshInstance3D.new()
                    effect.name = "FakeExplosionEffect"
                    effect.mesh = BoxMesh.new()
                    get_parent().add_child(effect)
                    effect.global_position = global_position
                    for node in get_tree().get_nodes_in_group("damageables"):
                        if node == shooter or not is_instance_valid(node):
                            continue
                        if not (node is Node3D) or not node.has_method("damage"):
                            continue
                        if (node as Node3D).global_position.distance_to(global_position) <= EXPLOSION_RADIUS:
                            node.damage(global_position, Vector3.UP)
                    queue_free()
                """
            ).lstrip(), encoding="utf-8")

            out = tmp_path / "score.json"
            log = tmp_path / "score.log"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_grader.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    str(godot),
                    "--out",
                    str(out),
                    "--log",
                    str(log),
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=120,
            )

            log_text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr + log_text)
            data = json.loads(out.read_text(encoding="utf-8"))
            explosion = next(item for item in data["breakdown"] if item["name"] == "explosion_gameplay")
            self.assertGreaterEqual(explosion["score"], 14, json.dumps(explosion, indent=2))
            self.assertIn("explosion damage stayed localized", explosion["notes"])

    def test_explosion_gameplay_penalizes_global_targetable_damage_sweep(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            candidate = tmp_path / "candidate"
            player_dir = candidate / "player"
            player_dir.mkdir(parents=True)
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (player_dir / "player.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=2 format=3]

                [ext_resource type="Script" path="res://player/player.gd" id="1_player"]

                [node name="Player" type="CharacterBody3D"]
                script = ExtResource("1_player")
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "fake_grenade.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=2 format=3]

                [ext_resource type="Script" path="res://player/fake_grenade.gd" id="1_grenade"]

                [node name="FakeGrenadeProjectile" type="Node3D"]
                script = ExtResource("1_grenade")
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "player.gd").write_text(textwrap.dedent(
                """
                extends CharacterBody3D

                signal weapon_switched(weapon_name: String)

                const GRENADE_SCENE := preload("res://player/fake_grenade.tscn")

                var _weapon_mode := "DEFAULT"


                func _ready() -> void:
                    _ensure_action("swap_weapons")
                    _ensure_action("weapon_switch")
                    _ensure_action("attack")
                    _ensure_action("aim")
                    weapon_switched.emit(_weapon_mode)


                func _physics_process(_delta: float) -> void:
                    if Input.is_action_just_pressed("swap_weapons") or Input.is_action_just_pressed("weapon_switch"):
                        _weapon_mode = "GRENADE" if _weapon_mode == "DEFAULT" else "DEFAULT"
                        weapon_switched.emit(_weapon_mode)
                    if Input.is_action_just_pressed("attack"):
                        if _weapon_mode == "GRENADE":
                            var grenade := GRENADE_SCENE.instantiate()
                            get_parent().add_child(grenade)
                            grenade.global_position = global_position + Vector3.UP * 1.4
                        else:
                            var default_attack := Node3D.new()
                            default_attack.name = "DefaultAttackNode"
                            get_parent().add_child(default_attack)
                            default_attack.global_position = global_position + Vector3(0, 1.0, -2.0)


                func _ensure_action(action_name: String) -> void:
                    if not InputMap.has_action(action_name):
                        InputMap.add_action(action_name)
                """
            ).lstrip(), encoding="utf-8")
            (player_dir / "fake_grenade.gd").write_text(textwrap.dedent(
                """
                extends Node3D

                const DETONATE_FRAME := 70
                const THROW_DISTANCE := 9.0

                var _start_position := Vector3.ZERO
                var _frame := 0
                var _detonated := false


                func _ready() -> void:
                    _start_position = global_position


                func _physics_process(_delta: float) -> void:
                    if _detonated:
                        return
                    _frame += 1
                    var t := minf(float(_frame) / float(DETONATE_FRAME), 1.0)
                    global_position = _start_position + Vector3(0.0, sin(t * PI) * 1.5, THROW_DISTANCE * t)
                    if _frame >= DETONATE_FRAME:
                        _detonate()


                func _detonate() -> void:
                    if _detonated:
                        return
                    _detonated = true
                    var effect := MeshInstance3D.new()
                    effect.name = "FakeExplosionEffect"
                    effect.mesh = BoxMesh.new()
                    get_parent().add_child(effect)
                    effect.global_position = global_position
                    for node in get_tree().get_nodes_in_group("targeteables"):
                        if not is_instance_valid(node):
                            continue
                        if node is Node3D and node.has_method("damage"):
                            node.damage(global_position, Vector3.UP)
                    queue_free()
                """
            ).lstrip(), encoding="utf-8")

            out = tmp_path / "score.json"
            log = tmp_path / "score.log"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_grader.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    str(godot),
                    "--out",
                    str(out),
                    "--log",
                    str(log),
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=120,
            )

            log_text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr + log_text)
            data = json.loads(out.read_text(encoding="utf-8"))
            explosion = next(item for item in data["breakdown"] if item["name"] == "explosion_gameplay")
            self.assertLessEqual(explosion["score"], 6, json.dumps(explosion, indent=2))
            self.assertIn("global damage sweep", explosion["notes"])

    def test_explosion_gameplay_scores_destructibles_and_caps_global_sweeps(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")
        arena_source = (ROOT / "verifier_godot" / "__verifier__" / "arena_builder.gd").read_text(encoding="utf-8")
        target_source = (ROOT / "verifier_godot" / "__verifier__" / "verifier_damage_target.gd").read_text(encoding="utf-8")

        self.assertIn("_add_nearby_destructible_target", runner_source)
        self.assertIn('"Nearby destructible damage across angles"', runner_source)
        self.assertIn('"Blast locality across angles"', runner_source)
        self.assertIn("_global_sweep_detected", runner_source)
        self.assertIn("_explosion_gameplay_score_cap", runner_source)
        self.assertIn("global damage sweep cap applied", runner_source)
        self.assertIn("add_damageable_only_target", arena_source)
        self.assertIn("targetable := true", target_source)

    def test_scene_probe_observes_transient_visual_and_audio_activity(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const SceneProbe = preload("res://__verifier__/scene_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _spawn_transient_activity(arena: Node3D) -> void:
                    await physics_frame
                    var effect := MeshInstance3D.new()
                    effect.name = "TransientEffect"
                    effect.mesh = BoxMesh.new()
                    arena.add_child(effect)

                    var audio := AudioStreamPlayer.new()
                    audio.stream = AudioStreamGenerator.new()
                    arena.add_child(audio)
                    audio.play()

                    await physics_frame
                    await physics_frame
                    effect.queue_free()
                    audio.queue_free()

                func _run() -> void:
                    var arena := Node3D.new()
                    root.add_child(arena)
                    var before := SceneProbe.collect_instance_ids(arena)
                    _spawn_transient_activity(arena)

                    var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, Vector3.ZERO, 5.0, 8)
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(activity))
                    quit(0 if int(activity.get("visible_count", 0)) > 0 and bool(activity.get("saw_audio", false)) else 1)
                """
            ), encoding="utf-8")

            completed = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(tmp_path),
                    "--script",
                    "res://test_runner.gd",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=30,
            )

            self.assertTrue((tmp_path / "result.json").exists(), completed.stdout + completed.stderr)
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertGreater(result["visible_count"], 0, completed.stdout + completed.stderr)
            self.assertTrue(result["saw_audio"], completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_scene_probe_detects_windowed_screenshot_pixel_delta_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const SceneProbe = preload("res://__verifier__/scene_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    root.size = Vector2i(640, 360)
                    for _i in range(6):
                        await process_frame
                    var before := SceneProbe.viewport_screenshot_signature(root, 32)

                    var rect := ColorRect.new()
                    rect.color = Color(1.0, 0.0, 0.0, 1.0)
                    rect.position = Vector2.ZERO
                    rect.size = Vector2(640.0, 360.0)
                    root.add_child(rect)

                    for _i in range(6):
                        await process_frame
                    var after := SceneProbe.viewport_screenshot_signature(root, 32)
                    var saved := SceneProbe.save_viewport_screenshot(root, "res://after.png")
                    var delta := SceneProbe.frame_signature_delta(before, after)
                    before.erase("samples")
                    after.erase("samples")
                    var result := {
                        "before": before,
                        "after": after,
                        "saved": saved,
                        "delta": delta,
                        "display_driver": DisplayServer.get_name(),
                    }
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(result))
                    quit(0)
                """
            ), encoding="utf-8")

            try:
                completed = subprocess.run(
                    [
                        str(godot),
                        "--path",
                        str(tmp_path),
                        "--script",
                        "res://test_runner.gd",
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                    timeout=20,
                )
            except subprocess.TimeoutExpired as exc:
                self.skipTest(f"Windowed Godot screenshot probe timed out: {exc}")

            output = completed.stdout + completed.stderr
            if "Nonexistent function" in output or "Invalid call" in output:
                self.fail(output)
            if not (tmp_path / "result.json").exists():
                self.skipTest("Windowed Godot screenshot probe could not produce a result in this environment")

            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            if not result["before"].get("available") or not result["after"].get("available"):
                self.skipTest(f"Windowed viewport capture unavailable: {result}")
            self.assertEqual(completed.returncode, 0, output)
            self.assertTrue(result["saved"].get("saved"), result)
            self.assertTrue((tmp_path / "after.png").exists(), result)
            self.assertGreater(result["delta"], 0.001, result)

    def test_scene_probe_reports_projectile_screen_rect_and_region_delta_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const SceneProbe = preload("res://__verifier__/scene_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    root.size = Vector2i(640, 360)
                    var world := Node3D.new()
                    root.add_child(world)
                    var camera := Camera3D.new()
                    camera.current = true
                    camera.position = Vector3(0, 1.5, 6)
                    camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
                    world.add_child(camera)
                    var projectile := Node3D.new()
                    projectile.name = "Projectile"
                    world.add_child(projectile)
                    var mesh := MeshInstance3D.new()
                    mesh.mesh = SphereMesh.new()
                    mesh.position = Vector3(0, 1.0, 0)
                    projectile.add_child(mesh)
                    for _i in range(8):
                        await process_frame
                    var rect := SceneProbe.projectile_screen_rect(camera, projectile, root.size)
                    var before := SceneProbe.viewport_region_signature(root, Rect2(rect.get("x", 0), rect.get("y", 0), rect.get("width", 1), rect.get("height", 1)), 4)
                    var material := StandardMaterial3D.new()
                    material.albedo_color = Color(1, 0, 0, 1)
                    mesh.set_surface_override_material(0, material)
                    for _i in range(8):
                        await process_frame
                    var after := SceneProbe.viewport_region_signature(root, Rect2(rect.get("x", 0), rect.get("y", 0), rect.get("width", 1), rect.get("height", 1)), 4)
                    var delta := SceneProbe.frame_signature_delta(before, after)
                    var result := {"rect": rect, "after": after, "delta": delta}
                    result["after"].erase("samples")
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(result))
                    quit(0)
                """
            ), encoding="utf-8")

            completed = subprocess.run(
                [str(godot), "--path", str(tmp_path), "--script", "res://test_runner.gd"],
                text=True,
                capture_output=True,
                check=False,
                timeout=20,
            )
            output = completed.stdout + completed.stderr
            if "Nonexistent function" in output or "Invalid call" in output:
                self.fail(output)
            if not (tmp_path / "result.json").exists():
                self.skipTest("Windowed projectile footprint probe could not produce a result in this environment")
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            if not result["after"].get("available"):
                self.skipTest(f"Windowed viewport capture unavailable: {result}")
            self.assertEqual(completed.returncode, 0, output)
            self.assertTrue(result["rect"].get("visible"), result)
            self.assertGreater(result["rect"].get("area_px", 0), 0, result)
            self.assertGreater(result["delta"], -1.0, result)

    def test_screenshot_probe_debug_arena_mode_writes_nested_artifacts_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        candidate = ROOT / "tmp" / "screenshot-probe-debug-arena-candidate"
        if candidate.exists():
            shutil.rmtree(candidate)
        candidate.mkdir(parents=True)
        (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        out_dir = Path(tempfile.mkdtemp(prefix="screenshot-probe-debug-arena-out-"))
        try:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_screenshot_probe.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    str(godot),
                    "--out-dir",
                    str(out_dir),
                    "--mode",
                    "debug-arena",
                    "--timeout",
                    "60",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=90,
            )
            output = completed.stdout + completed.stderr
            if not (out_dir / "result.json").exists():
                self.skipTest(f"Windowed debug arena screenshot probe unavailable: {output}")
            result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
            self.assertFalse(result.get("used_for_score", True), result)
            self.assertIn("debug_arena", result.get("modes", {}), result)
            self.assertTrue((out_dir / "debug_arena").exists(), result)
        finally:
            shutil.rmtree(candidate, ignore_errors=True)
            shutil.rmtree(out_dir, ignore_errors=True)

    def test_screenshot_probe_main_scene_mode_writes_ready_capture_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as candidate_tmp, tempfile.TemporaryDirectory() as out_tmp:
            candidate = Path(candidate_tmp)
            out_dir = Path(out_tmp)
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (candidate / "player.gd").write_text(
                "extends CharacterBody3D\n\nfunc collect_coin():\n\tpass\n",
                encoding="utf-8",
            )
            (candidate / "main.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=2 format=3]

                [ext_resource type="Script" path="res://player.gd" id="1"]

                [node name="Main" type="Node3D"]

                [node name="Player" type="CharacterBody3D" parent="."]
                script = ExtResource("1")

                [node name="Camera3D" type="Camera3D" parent="Player"]
                transform = Transform3D(1, 0, 0, 0, 0.965926, 0.258819, 0, -0.258819, 0.965926, 0, 2, 6)
                current = true
                """
            ).strip() + "\n", encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_screenshot_probe.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    str(godot),
                    "--out-dir",
                    str(out_dir),
                    "--mode",
                    "main-scene",
                    "--timeout",
                    "60",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=90,
            )
            output = completed.stdout + completed.stderr
            if not (out_dir / "result.json").exists():
                self.skipTest(f"Windowed main scene screenshot probe unavailable: {output}")
            result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
            self.assertFalse(result.get("used_for_score", True), result)
            self.assertIn("main_scene", result.get("modes", {}), result)
            self.assertTrue((out_dir / "main_scene").exists(), result)
            self.assertTrue((out_dir / "main_scene" / "main_ready.png").exists(), result)

    def test_screenshot_probe_main_scene_mode_resumes_demo_overlay_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow is not available to inspect screenshot pixels")

        with tempfile.TemporaryDirectory() as candidate_tmp, tempfile.TemporaryDirectory() as out_tmp:
            candidate = Path(candidate_tmp)
            out_dir = Path(out_tmp)
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (candidate / "player.gd").write_text(
                "extends CharacterBody3D\n\nfunc collect_coin():\n\tpass\n",
                encoding="utf-8",
            )
            (candidate / "demo_overlay.gd").write_text(textwrap.dedent(
                """
                extends Node

                @onready var overlay: ColorRect = $CanvasLayer/Overlay

                var resumed := false
                var frames_after_resume := -1

                func _ready() -> void:
                    get_tree().paused = true
                    overlay.show()

                func _process(_delta: float) -> void:
                    if frames_after_resume < 0:
                        return
                    frames_after_resume += 1
                    if frames_after_resume >= 8:
                        overlay.hide()
                        frames_after_resume = -1

                func resume_demo() -> void:
                    resumed = true
                    get_tree().paused = false
                    frames_after_resume = 0
                """
            ).strip() + "\n", encoding="utf-8")
            (candidate / "main.tscn").write_text(textwrap.dedent(
                """
                [gd_scene load_steps=3 format=3]

                [ext_resource type="Script" path="res://player.gd" id="1"]
                [ext_resource type="Script" path="res://demo_overlay.gd" id="2"]

                [node name="Main" type="Node3D"]

                [node name="Player" type="CharacterBody3D" parent="."]
                script = ExtResource("1")

                [node name="Camera3D" type="Camera3D" parent="Player"]
                transform = Transform3D(1, 0, 0, 0, 0.965926, 0.258819, 0, -0.258819, 0.965926, 0, 2, 6)
                current = true

                [node name="DemoOverlay" type="Node" parent="."]
                script = ExtResource("2")

                [node name="CanvasLayer" type="CanvasLayer" parent="DemoOverlay"]

                [node name="Background" type="ColorRect" parent="DemoOverlay/CanvasLayer"]
                offset_right = 1280.0
                offset_bottom = 720.0
                color = Color(0, 1, 0, 1)

                [node name="Overlay" type="ColorRect" parent="DemoOverlay/CanvasLayer"]
                offset_right = 1280.0
                offset_bottom = 720.0
                color = Color(1, 0, 0, 1)
                """
            ).strip() + "\n", encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_screenshot_probe.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    str(godot),
                    "--out-dir",
                    str(out_dir),
                    "--mode",
                    "main-scene",
                    "--timeout",
                    "60",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=90,
            )
            output = completed.stdout + completed.stderr
            if not (out_dir / "result.json").exists():
                self.skipTest(f"Windowed main scene screenshot probe unavailable: {output}")
            result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
            main_scene = result.get("modes", {}).get("main_scene", {})
            resume = main_scene.get("resume_demo", {})
            self.assertEqual(completed.returncode, 0, output)
            self.assertTrue(resume.get("attempted"), result)
            self.assertEqual(resume.get("method"), "resume_demo", result)
            self.assertFalse(resume.get("paused_after"), result)
            ready_capture = out_dir / "main_scene" / "main_ready.png"
            self.assertTrue(ready_capture.exists(), result)
            with Image.open(ready_capture) as image:
                red, green, _blue, _alpha = image.convert("RGBA").getpixel((image.width // 2, image.height // 2))
            self.assertLess(red, 96, result)
            self.assertGreater(green, 128, result)

    def test_scene_probe_rejects_placeholder_projectile_meshes(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const SceneProbe = preload("res://__verifier__/scene_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _make_array_mesh() -> ArrayMesh:
                    var mesh := ArrayMesh.new()
                    var vertices := PackedVector3Array([
                        Vector3(-0.25, -0.15, -0.35),
                        Vector3(0.25, -0.15, -0.35),
                        Vector3(0.0, 0.2, -0.1),
                        Vector3(0.0, -0.05, 0.35),
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

                func _add_visual(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
                    var visual := MeshInstance3D.new()
                    visual.mesh = mesh
                    parent.add_child(visual)
                    return visual

                func _run() -> void:
                    var bad := Node3D.new()
                    bad.name = "BadProjectile"
                    root.add_child(bad)
                    _add_visual(bad, SphereMesh.new())

                    var good := Node3D.new()
                    good.name = "GoodProjectile"
                    root.add_child(good)
                    _add_visual(good, _make_array_mesh())

                    var tracks := {}
                    tracks[bad.get_instance_id()] = [Vector3.ZERO, Vector3(0.0, 0.2, -1.0)]
                    tracks[good.get_instance_id()] = [Vector3.ZERO, Vector3(0.0, 0.2, -1.0)]

                    var bad_report: Dictionary = SceneProbe.grenade_projectile_visual_report([bad], tracks, 0.5, 0.1, 2.0)
                    var good_report: Dictionary = SceneProbe.grenade_projectile_visual_report([good], tracks, 0.5, 0.1, 2.0)
                    var result := {
                        "bad_has_model": bool(bad_report.get("has_model_visual", false)),
                        "bad_notes": String(bad_report.get("notes", "")),
                        "good_has_model": bool(good_report.get("has_model_visual", false)),
                        "good_notes": String(good_report.get("notes", "")),
                    }
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(result))
                    quit(0 if not result["bad_has_model"] and result["good_has_model"] else 1)
                """
            ), encoding="utf-8")

            completed = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(tmp_path),
                    "--script",
                    "res://test_runner.gd",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=30,
            )

            self.assertTrue((tmp_path / "result.json").exists(), completed.stdout + completed.stderr)
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertFalse(result["bad_has_model"], completed.stdout + completed.stderr)
            self.assertIn("placeholder primitive", result["bad_notes"], completed.stdout + completed.stderr)
            self.assertTrue(result["good_has_model"], completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_copy_candidate_project_excludes_git_and_godot_cache(self):
        with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as dst_dir:
            src = Path(src_dir)
            dst = Path(dst_dir) / "copy"
            (src / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (src / ".git").mkdir()
            (src / ".git" / "HEAD").write_text("secret", encoding="utf-8")
            (src / ".godot").mkdir()
            (src / ".godot" / "cache").write_text("cache", encoding="utf-8")
            (src / "output").mkdir()
            (src / "output" / "report.html").write_text("report", encoding="utf-8")
            (src / "tmp").mkdir()
            (src / "tmp" / "scratch.txt").write_text("scratch", encoding="utf-8")
            (src / "player").mkdir()
            (src / "player" / "player.gd").write_text("extends Node\n", encoding="utf-8")

            run_grader.copy_candidate_project(src, dst)

            self.assertTrue((dst / "project.godot").exists())
            self.assertTrue((dst / "player" / "player.gd").exists())
            self.assertFalse((dst / ".git").exists())
            self.assertFalse((dst / ".godot").exists())
            self.assertFalse((dst / "output").exists())
            self.assertFalse((dst / "tmp").exists())

    def test_inject_verifier_copies_verifier_folder(self):
        with tempfile.TemporaryDirectory() as verifier_dir, tempfile.TemporaryDirectory() as project_dir:
            verifier_root = Path(verifier_dir)
            project = Path(project_dir)
            source = verifier_root / "verifier_godot" / "__verifier__"
            source.mkdir(parents=True)
            (source / "runner.gd").write_text("extends SceneTree\n", encoding="utf-8")

            run_grader.inject_verifier(verifier_root, project)

            self.assertTrue((project / "__verifier__" / "runner.gd").exists())

    def test_cli_runs_fake_godot_and_writes_score_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            candidate = tmp_path / "candidate"
            candidate.mkdir()
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")

            verifier = tmp_path / "verifier"
            (verifier / "verifier_godot" / "__verifier__").mkdir(parents=True)
            (verifier / "verifier_godot" / "__verifier__" / "runner.gd").write_text("extends SceneTree\n", encoding="utf-8")

            fake_godot = tmp_path / "fake_godot.py"
            fake_godot.write_text(textwrap.dedent(
                """
                import json
                import sys
                from pathlib import Path

                args = sys.argv[1:]
                project = Path(args[args.index("--path") + 1])
                result = {
                    "score": 11,
                    "max_score": 100,
                    "logic_score": 11,
                    "logic_max_score": 100,
                    "passed": False,
                    "godot_version": "fake-godot",
                    "score_sections": [
                        {"name": "logic", "label": "Logic Score", "score": 11, "max": 100, "categories": ["weapon_controls", "visual_audio_polish"]}
                    ],
                    "auxiliary_score_sections": [
                        {"name": "screenshot_visual", "label": "Screenshot Visual Analysis", "score": 4, "max": 10, "used_for_score": False}
                    ],
                    "breakdown": [{"name": "weapon_controls", "score": 11, "max": 15, "notes": "fake"}],
                    "artifacts": {"log": "run.log", "screenshots": []}
                }
                (project / "__verifier_result.json").write_text(json.dumps(result), encoding="utf-8")
                print("fake godot executed")
                """
            ), encoding="utf-8")

            out = tmp_path / "score.json"
            log = tmp_path / "run.log"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_grader.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    sys.executable,
                    "--godot-arg",
                    str(fake_godot),
                    "--verifier-root",
                    str(verifier),
                    "--out",
                    str(out),
                    "--log",
                    str(log),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["score"], 11)
            self.assertIn("Logic score: 11/100", completed.stdout)
            self.assertNotIn("Visual score:", completed.stdout)
            self.assertIn("fake godot executed", log.read_text(encoding="utf-8"))

    def test_cli_writes_pdf_report_when_requested(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            candidate = tmp_path / "candidate"
            candidate.mkdir()
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")

            verifier = tmp_path / "verifier"
            (verifier / "verifier_godot" / "__verifier__").mkdir(parents=True)
            (verifier / "verifier_godot" / "__verifier__" / "runner.gd").write_text("extends SceneTree\n", encoding="utf-8")

            fake_godot = tmp_path / "fake_godot.py"
            fake_godot.write_text(textwrap.dedent(
                """
                import json
                import sys
                from pathlib import Path

                args = sys.argv[1:]
                project = Path(args[args.index("--path") + 1])
                result = {
                    "score": 87,
                    "max_score": 100,
                    "passed": True,
                    "godot_version": "fake-godot",
                    "breakdown": [
                        {"name": "weapon_controls", "score": 15, "max": 15, "notes": "ok"},
                        {"name": "trajectory_preview", "score": 13, "max": 20, "notes": "partial"}
                    ],
                    "artifacts": {"log": "run.log", "screenshots": []}
                }
                (project / "__verifier_result.json").write_text(json.dumps(result), encoding="utf-8")
                print("fake godot executed")
                """
            ), encoding="utf-8")

            out = tmp_path / "score.json"
            pdf = tmp_path / "score-report.pdf"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_grader.py"),
                    "--project",
                    str(candidate),
                    "--godot",
                    sys.executable,
                    "--godot-arg",
                    str(fake_godot),
                    "--verifier-root",
                    str(verifier),
                    "--out",
                    str(out),
                    "--pdf-report",
                    str(pdf),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(out.exists())
            self.assertTrue(pdf.exists())
            self.assertEqual(pdf.read_bytes()[:4], b"%PDF")

    def test_input_driver_falls_back_to_tab_key_event_without_swap_action(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "input_driver.gd", verifier_dir / "input_driver.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const InputDriver = preload("res://__verifier__/input_driver.gd")

                class CaptureNode:
                    extends Node
                    var tab_presses := 0

                    func _input(event: InputEvent) -> void:
                        if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
                            tab_presses += 1

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    if InputMap.has_action("swap_weapons"):
                        InputMap.erase_action("swap_weapons")
                    var capture := CaptureNode.new()
                    root.add_child(capture)
                    var driver := InputDriver.new(self)
                    await driver.tap("swap_weapons", 1, 1)
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify({"tab_presses": capture.tab_presses}))
                    quit(0 if capture.tab_presses == 1 else 1)
                """
            ), encoding="utf-8")

            completed = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(tmp_path),
                    "--script",
                    "res://test_runner.gd",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=30,
            )

            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(result["tab_presses"], 1, completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_input_driver_reports_swap_key_fallback_as_drivable(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "input_driver.gd", verifier_dir / "input_driver.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const InputDriver = preload("res://__verifier__/input_driver.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    if InputMap.has_action("swap_weapons"):
                        InputMap.erase_action("swap_weapons")
                    var driver := InputDriver.new(self)
                    var can_drive := driver.has_method("can_drive") and bool(driver.call("can_drive", "swap_weapons"))
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify({"can_drive": can_drive}))
                    quit(0 if can_drive else 1)
                """
            ), encoding="utf-8")

            completed = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(tmp_path),
                    "--script",
                    "res://test_runner.gd",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=30,
            )

            self.assertTrue((tmp_path / "result.json").exists(), completed.stdout + completed.stderr)
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertTrue(result["can_drive"], completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
