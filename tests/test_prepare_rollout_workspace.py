import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import prepare_rollout_workspace


class PrepareRolloutWorkspaceTests(unittest.TestCase):
    def test_prepare_rollout_workspace_keeps_agent_task_files_and_excludes_private_artifacts(self):
        with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as tmp_dir:
            source = Path(src_dir)
            output = Path(tmp_dir) / "rollout"

            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (source / "TASK_PROMPT.md").write_text("agent task", encoding="utf-8")
            (source / "TASK_PROMPT.zh.md").write_text("agent task zh", encoding="utf-8")
            (source / "README.md").write_text("public readme", encoding="utf-8")
            (source / "player").mkdir()
            (source / "player" / "player.gd").write_text("extends Node\n", encoding="utf-8")
            (source / "AGENTS.md").write_text("verifier instructions", encoding="utf-8")
            (source / "CLAUDE.md").write_text("hidden hints", encoding="utf-8")
            (source / "game_take_home.html").write_text("assignment source", encoding="utf-8")
            (source / "BENCHMARK.md").write_text("benchmark notes", encoding="utf-8")
            (source / "probe_matrix.md").write_text("probe notes", encoding="utf-8")
            (source / "run_grader.py").write_text("verifier entrypoint", encoding="utf-8")
            (source / "run_calibration.ps1").write_text("calibration", encoding="utf-8")
            (source / "export_debug_arena.py").write_text("debug export", encoding="utf-8")
            (source / ".git").mkdir()
            (source / ".git" / "HEAD").write_text("secret", encoding="utf-8")
            (source / ".godot").mkdir()
            (source / ".godot" / "cache").write_text("cache", encoding="utf-8")
            (source / ".codex").mkdir()
            (source / ".codex" / "config.toml").write_text("mcp config", encoding="utf-8")
            (source / ".claude").mkdir()
            (source / ".claude" / "settings.json").write_text("settings", encoding="utf-8")
            (source / "__verifier__").mkdir()
            (source / "__verifier__" / "runner.gd").write_text("secret", encoding="utf-8")
            (source / "verifier_godot" / "__verifier__").mkdir(parents=True)
            (source / "verifier_godot" / "__verifier__" / "runner.gd").write_text("secret", encoding="utf-8")
            (source / "docs" / "superpowers" / "specs").mkdir(parents=True)
            (source / "docs" / "superpowers" / "specs" / "verifier-design.md").write_text("secret", encoding="utf-8")
            (source / "docs" / "notes.md").write_text("ordinary docs", encoding="utf-8")
            (source / "artifacts").mkdir()
            (source / "artifacts" / "score.json").write_text("score", encoding="utf-8")
            (source / "output").mkdir()
            (source / "output" / "debug").write_text("debug export", encoding="utf-8")
            (source / "tmp").mkdir()
            (source / "tmp" / "scratch.txt").write_text("scratch", encoding="utf-8")

            prepare_rollout_workspace.prepare_rollout_workspace(source, output)

            self.assertTrue((output / "project.godot").exists())
            self.assertTrue((output / "TASK_PROMPT.md").exists())
            self.assertFalse((output / "TASK_PROMPT.zh.md").exists())
            self.assertTrue((output / "README.md").exists())
            self.assertTrue((output / "player" / "player.gd").exists())
            self.assertTrue((output / "docs" / "notes.md").exists())
            self.assertFalse((output / "AGENTS.md").exists())
            self.assertFalse((output / "CLAUDE.md").exists())
            self.assertFalse((output / "game_take_home.html").exists())
            self.assertFalse((output / "BENCHMARK.md").exists())
            self.assertFalse((output / "probe_matrix.md").exists())
            self.assertFalse((output / "run_grader.py").exists())
            self.assertFalse((output / "run_calibration.ps1").exists())
            self.assertFalse((output / "export_debug_arena.py").exists())
            self.assertFalse((output / ".git").exists())
            self.assertFalse((output / ".godot").exists())
            self.assertFalse((output / ".codex").exists())
            self.assertFalse((output / ".claude").exists())
            self.assertFalse((output / "__verifier__").exists())
            self.assertFalse((output / "verifier_godot").exists())
            self.assertFalse((output / "docs" / "superpowers").exists())
            self.assertFalse((output / "artifacts").exists())
            self.assertFalse((output / "output").exists())
            self.assertFalse((output / "tmp").exists())

    def test_prepare_rollout_workspace_requires_force_for_existing_destination(self):
        with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as tmp_dir:
            source = Path(src_dir)
            output = Path(tmp_dir) / "rollout"
            output.mkdir()
            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")

            with self.assertRaises(FileExistsError):
                prepare_rollout_workspace.prepare_rollout_workspace(source, output)

            prepare_rollout_workspace.prepare_rollout_workspace(source, output, force=True)

            self.assertTrue((output / "project.godot").exists())

    def test_cli_prepares_workspace(self):
        with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as tmp_dir:
            source = Path(src_dir)
            output = Path(tmp_dir) / "rollout"
            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (source / "TASK_PROMPT.md").write_text("agent task", encoding="utf-8")

            exit_code = prepare_rollout_workspace.main([
                "--project",
                str(source),
                "--out",
                str(output),
            ])

            self.assertEqual(exit_code, 0)
            self.assertTrue((output / "project.godot").exists())
            self.assertTrue((output / "TASK_PROMPT.md").exists())


if __name__ == "__main__":
    unittest.main()
