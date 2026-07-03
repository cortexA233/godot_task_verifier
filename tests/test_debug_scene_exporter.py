import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import debug_scene_exporter


class DebugSceneExporterTests(unittest.TestCase):
    def test_export_debug_project_copies_project_and_injects_debug_scene(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "candidate"
            output = tmp_path / "debug-project"
            verifier = tmp_path / "verifier"

            source.mkdir()
            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (source / ".git").mkdir()
            (source / ".git" / "HEAD").write_text("secret", encoding="utf-8")
            verifier_scene = verifier / "verifier_godot" / "__verifier__"
            verifier_scene.mkdir(parents=True)
            (verifier_scene / "runner.gd").write_text("extends SceneTree\n", encoding="utf-8")
            (verifier_scene / "debug_arena.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")

            exported_scene = debug_scene_exporter.export_debug_project(source, output, verifier)

            self.assertEqual(exported_scene, output / "__verifier__" / "debug_arena.tscn")
            self.assertTrue((output / "project.godot").exists())
            self.assertTrue((output / "__verifier__" / "debug_arena.tscn").exists())
            self.assertFalse((output / ".git").exists())

    def test_export_debug_arena_cli_prints_scene_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "candidate"
            output = tmp_path / "debug-project"
            verifier = tmp_path / "verifier"

            source.mkdir()
            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            verifier_scene = verifier / "verifier_godot" / "__verifier__"
            verifier_scene.mkdir(parents=True)
            (verifier_scene / "debug_arena.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "export_debug_arena.py"),
                    "--project",
                    str(source),
                    "--out",
                    str(output),
                    "--verifier-root",
                    str(verifier),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("res://__verifier__/debug_arena.tscn", completed.stdout)
            self.assertTrue((output / "__verifier__" / "debug_arena.tscn").exists())

    def test_debug_arena_label_describes_adaptive_layout(self):
        debug_source = (ROOT / "verifier_godot" / "__verifier__" / "debug_arena.gd").read_text(encoding="utf-8")

        self.assertIn("fixed seed target variants; calibrated throw", debug_source)
        self.assertIn("distance band fallback", debug_source)

    def test_debug_arena_calibrates_or_shows_distance_band(self):
        debug_source = (ROOT / "verifier_godot" / "__verifier__" / "debug_arena.gd").read_text(encoding="utf-8")

        self.assertIn("_calibrate_default_throw_distance", debug_source)
        self.assertIn("_apply_adaptive_target_layout", debug_source)
        self.assertIn("_add_distance_band_targets", debug_source)
        self.assertIn("candidate_records", debug_source)
        self.assertIn("DistanceBandTarget", debug_source)

    def test_debug_arena_uses_fixed_seed_target_variants(self):
        debug_source = (ROOT / "verifier_godot" / "__verifier__" / "debug_arena.gd").read_text(encoding="utf-8")

        self.assertIn("TARGET_FIELD_RADIUS := 30.0", debug_source)
        self.assertIn("FAR_TARGET_DISTANCE := 25.0", debug_source)
        self.assertIn("NEARBY_TARGET_GROUP_DEGREES := 20", debug_source)
        self.assertIn("NEARBY_TARGET_GROUP_COUNT := 18", debug_source)
        self.assertIn("NEARBY_DAMAGE_TARGET_RADII := [6.0, 8.0, 10.0, 12.0]", debug_source)
        self.assertIn("EXPLOSION_TRIAL_SEEDS := [", debug_source)
        self.assertIn("EXPLOSION_TRIAL_BASE_HEADING_DEGREES", debug_source)
        self.assertIn("_explosion_trial_variants", debug_source)
        self.assertIn("_seeded_nearby_damage_radii", debug_source)
        self.assertIn("rng.seed = seed_value", debug_source)
        self.assertIn("_add_seeded_trial_layout", debug_source)
        self.assertIn("_target_group_for_heading", debug_source)
        self.assertIn("_add_debug_safety_target", debug_source)
        self.assertIn("NearbyTarget", debug_source)


if __name__ == "__main__":
    unittest.main()
