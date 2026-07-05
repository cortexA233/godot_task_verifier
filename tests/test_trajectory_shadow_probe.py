from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHADOW_PROBE = ROOT / "verifier_godot" / "__verifier__" / "trajectory_shadow_probe.gd"


def find_godot() -> Path | None:
    configured = Path(r"C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe")
    if configured.exists():
        return configured
    found = shutil.which("godot")
    return Path(found) if found else None


class TrajectoryShadowProbeTests(unittest.TestCase):
    def test_cli_and_runner_expose_explicit_trajectory_shadow_mode(self):
        cli_source = (ROOT / "run_screenshot_probe.py").read_text(encoding="utf-8")
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")

        self.assertIn('choices=["debug-arena", "main-scene", "both", "trajectory-shadow"]', cli_source)
        self.assertIn('"--probe-mode"', cli_source)
        self.assertIn('const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")', runner_source)
        self.assertIn('const VALID_MODES := ["debug-arena", "main-scene", "both", "trajectory-shadow"]', runner_source)
        self.assertIn('if requested_mode == "trajectory-shadow":', runner_source)
        self.assertIn('mode_results["trajectory_shadow"] = await trajectory_probe.run()', runner_source)
        self.assertNotIn('requested_mode == "trajectory-shadow" or requested_mode == "both"', runner_source)
        self.assertNotIn('requested_mode == "both" or requested_mode == "trajectory-shadow"', runner_source)

    def test_shadow_probe_declares_pixel_only_baseline_diff_metrics(self):
        self.assertTrue(SHADOW_PROBE.exists())
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        self.assertIn("func _baseline_diff_metrics", source)
        self.assertIn("PIXEL_DIFF_THRESHOLD", source)
        self.assertIn("GAMEPLAY_ANALYSIS_REGION", source)
        self.assertIn("SIDE_ANALYSIS_REGION", source)
        self.assertIn("changed_pixel_count", source)
        self.assertIn("estimated_area_px", source)
        self.assertIn("suggests_arc", source)
        self.assertNotIn("projectile_screen_rect", source)
        self.assertNotIn("visible_nodes_suggest_arc_or_landing", source)

    def test_shadow_probe_declares_non_scoring_json_contract(self):
        self.assertTrue(SHADOW_PROBE.exists())
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        for token in [
            '"artifact_dir": MODE_NAME',
            '"used_for_score": false',
            '"provisional_verdict"',
            '"heading_results"',
            '"headings_degrees"',
            '"visual_claims"',
            '"preview_matches_projectile_direction"',
            '"updates_with_aim_camera_direction"',
            '"communicates_arcing_throw"',
            '"gameplay_centroid_spread_px"',
            '"runtime_direction_match_count"',
        ]:
            self.assertIn(token, source)
        self.assertNotIn("board.add", source)
        self.assertNotIn('"score"', source)

    def test_baseline_diff_metrics_detect_arc_like_changed_pixels_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(SHADOW_PROBE, verifier_dir / "trajectory_shadow_probe.gd")
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (verifier_dir / "debug_arena.tscn").write_text(textwrap.dedent(
                """
                [gd_scene format=3]

                [node name="DebugArena" type="Node3D"]
                """
            ).strip() + "\n", encoding="utf-8")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    var before_image := Image.create(128, 96, false, Image.FORMAT_RGBA8)
                    before_image.fill(Color(0, 0, 0, 1))
                    var after_image := Image.create(128, 96, false, Image.FORMAT_RGBA8)
                    after_image.fill(Color(0, 0, 0, 1))
                    for x in range(12, 117):
                        var normalized := float(x - 12) / 104.0
                        var y := 70 - int(round(sin(normalized * PI) * 34.0))
                        for dy in range(0, 4):
                            after_image.set_pixel(x, clampi(y + dy, 0, 95), Color(1, 1, 1, 1))
                    var probe := TrajectoryShadowProbe.new(self, null)
                    var metrics: Dictionary = probe._baseline_diff_metrics(before_image, after_image, Rect2i(0, 0, 128, 96), "unit_arc")
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(metrics))
                    quit(0)
                """
            ).strip() + "\n", encoding="utf-8")

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
                timeout=60,
            )
            output = completed.stdout + completed.stderr
            self.assertEqual(completed.returncode, 0, output)
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertTrue(result.get("available"), result)
            self.assertGreater(result.get("changed_pixel_count", 0), 100, result)
            self.assertGreater(result.get("horizontal_span_px", 0), 80, result)
            self.assertGreater(result.get("vertical_span_px", 0), 18, result)
            self.assertTrue(result.get("suggests_arc"), result)

    def test_shadow_probe_uses_fresh_debug_arena_and_two_view_baselines_per_heading(self):
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        self.assertIn("for heading_degrees in TRAJECTORY_SAMPLE_HEADINGS_DEGREES", source)
        self.assertIn("DebugArenaScene.instantiate()", source)
        self.assertIn('"%s/%s" % [OUTPUT_DIR, MODE_NAME]', source)
        self.assertIn('"gameplay_baseline"', source)
        self.assertIn('"side_baseline"', source)
        self.assertIn('"gameplay_preview"', source)
        self.assertIn('"side_preview"', source)
        self.assertIn("_set_side_oblique_camera", source)
        self.assertIn("SIDE_CAMERA_DISTANCE", source)
        self.assertIn("SIDE_CAMERA_HEIGHT", source)
        self.assertIn("SIDE_CAMERA_BACK_OFFSET", source)


if __name__ == "__main__":
    unittest.main()
