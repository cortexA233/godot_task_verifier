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


if __name__ == "__main__":
    unittest.main()
