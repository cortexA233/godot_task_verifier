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
        r"C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
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

        self.assertIn("EXPLOSION_TRIALS", runner_source)
        self.assertIn("_run_explosion_trial", runner_source)
        self.assertIn('"Front throw"', runner_source)
        self.assertIn('"Left-front throw"', runner_source)
        self.assertIn('"Right-front throw"', runner_source)
        self.assertIn('"FarTarget"', runner_source)
        self.assertIn('"LeftSideTarget"', runner_source)
        self.assertIn('"RightSideTarget"', runner_source)
        self.assertIn('"RearTarget"', runner_source)
        self.assertIn("out-of-range safety targets were damaged", runner_source)
        self.assertIn("all explosion safety trials protected out-of-range targets", runner_source)
        self.assertIn("damage_detonation_observed", runner_source)
        self.assertGreaterEqual(runner_source.count("ArenaBuilder.add_damage_target(arena,"), 6)

    def test_runner_prefers_project_weapon_switch_action_when_available(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("_weapon_switch_action", runner_source)
        self.assertIn('"weapon_switch"', runner_source)

    def test_scene_probe_has_calibration_tracking_helpers(self):
        probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")

        self.assertIn("track_nodes_positions", probe_source)
        self.assertIn("horizontal_distance", probe_source)
        self.assertIn("horizontal_travel_distance", probe_source)
        self.assertIn("path_is_player_safe", probe_source)

    def test_runner_declares_default_throw_calibration_flow(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("CALIBRATION_FULL_MIN_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_FULL_MAX_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_BORDERLINE_MIN_DISTANCE", runner_source)
        self.assertIn("CALIBRATION_BORDERLINE_MAX_DISTANCE", runner_source)
        self.assertIn("_calibrate_default_throw_distance", runner_source)
        self.assertIn("_calibration_band", runner_source)
        self.assertIn("_target_forward_distance", runner_source)
        self.assertIn("_far_forward_distance", runner_source)
        self.assertIn("calibration[\"status\"]", runner_source)
        self.assertIn("default throw calibration", runner_source)

    def test_runner_uses_adaptive_explosion_target_placement_with_fixed_fallback(self):
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn("FALLBACK_THROW_DISTANCE", runner_source)
        self.assertIn("FAR_TARGET_MIN_DISTANCE", runner_source)
        self.assertIn("FAR_TARGET_EXTRA_DISTANCE", runner_source)
        self.assertIn("var target_forward_distance := _target_forward_distance(calibration)", runner_source)
        self.assertIn("var far_forward_distance := _far_forward_distance(target_forward_distance)", runner_source)
        self.assertIn("_run_explosion_trial(String(trial[\"label\"]), float(trial[\"heading_y\"]), calibration)", runner_source)
        self.assertIn("_explosion_details_from_trials(trial_results, calibration)", runner_source)
        self.assertIn("_explosion_target_position(forward, right, target_forward_distance, 0.0)", runner_source)
        self.assertIn("_explosion_target_position(forward, right, far_forward_distance, 0.0)", runner_source)

    def test_copy_candidate_project_excludes_git_and_godot_cache(self):
        with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as dst_dir:
            src = Path(src_dir)
            dst = Path(dst_dir) / "copy"
            (src / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (src / ".git").mkdir()
            (src / ".git" / "HEAD").write_text("secret", encoding="utf-8")
            (src / ".godot").mkdir()
            (src / ".godot" / "cache").write_text("cache", encoding="utf-8")
            (src / "player").mkdir()
            (src / "player" / "player.gd").write_text("extends Node\n", encoding="utf-8")

            run_grader.copy_candidate_project(src, dst)

            self.assertTrue((dst / "project.godot").exists())
            self.assertTrue((dst / "player" / "player.gd").exists())
            self.assertFalse((dst / ".git").exists())
            self.assertFalse((dst / ".godot").exists())

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
                    "passed": False,
                    "godot_version": "fake-godot",
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
