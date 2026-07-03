import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "evaluation" / "probes" / "materialize_probe_cases.py"
CASES = ROOT / "evaluation" / "probes" / "cases"


class ProbeMaterializerTests(unittest.TestCase):
    def test_materializes_selected_probe_overlay(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            base = tmp_path / "base"
            base.mkdir()
            (base / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (base / "player").mkdir()
            (base / "player" / "player.gd").write_text("extends Node3D\n", encoding="utf-8")
            (base / ".git").mkdir()
            (base / ".git" / "hidden").write_text("do not copy\n", encoding="utf-8")

            out = tmp_path / "out"
            subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--base-project",
                    str(base),
                    "--out",
                    str(out),
                    "--case",
                    "hud-only",
                ],
                check=True,
            )

            generated = out / "hud-only"
            self.assertTrue((generated / "project.godot").is_file())
            self.assertFalse((generated / ".git").exists())
            self.assertEqual(
                (CASES / "hud-only" / "player" / "player.gd").read_text(encoding="utf-8"),
                (generated / "player" / "player.gd").read_text(encoding="utf-8"),
            )

    def test_requires_force_for_existing_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            base = tmp_path / "base"
            base.mkdir()
            (base / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            out = tmp_path / "out"
            (out / "hud-only").mkdir(parents=True)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--base-project",
                    str(base),
                    "--out",
                    str(out),
                    "--case",
                    "hud-only",
                ],
                text=True,
                stderr=subprocess.PIPE,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Pass --force", result.stderr)


if __name__ == "__main__":
    unittest.main()
