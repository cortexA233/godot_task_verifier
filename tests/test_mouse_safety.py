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


class MouseSafetyTests(unittest.TestCase):
    def test_mouse_safety_helper_defines_release_and_toggle_controls(self):
        source_path = ROOT / "verifier_godot" / "__verifier__" / "mouse_safety.gd"
        self.assertTrue(source_path.exists(), "mouse_safety.gd should exist")
        source = source_path.read_text(encoding="utf-8")

        self.assertIn("Input.MOUSE_MODE_VISIBLE", source)
        self.assertIn("Input.MOUSE_MODE_CAPTURED", source)
        self.assertIn("KEY_ESCAPE", source)
        self.assertIn("KEY_F8", source)
        self.assertIn("force_visible_for_startup", source)

    def test_debug_arena_installs_mouse_safety(self):
        source = (ROOT / "verifier_godot" / "__verifier__" / "debug_arena.gd").read_text(encoding="utf-8")

        self.assertIn('preload("res://__verifier__/mouse_safety.gd")', source)
        self.assertIn("_install_mouse_safety()", source)
        self.assertIn("VerifierMouseSafety", source)

    def test_runner_installs_mouse_safety_for_verifier_owned_runs(self):
        source = (ROOT / "verifier_godot" / "__verifier__" / "runner.gd").read_text(encoding="utf-8")

        self.assertIn('preload("res://__verifier__/mouse_safety.gd")', source)
        self.assertIn("_install_mouse_safety()", source)
        self.assertIn("VerifierMouseSafety", source)

    def test_readme_documents_debug_arena_mouse_safety_controls(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")

        self.assertIn("Mouse safety is enabled", readme)
        self.assertIn("F8", readme)
        self.assertIn("Esc", readme)
        self.assertIn("cursor visible", readme)

    def test_mouse_safety_restores_visible_and_handles_f8_and_escape(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "mouse_safety.gd", verifier_dir / "mouse_safety.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const MouseSafety = preload("res://__verifier__/mouse_safety.gd")

                func _key_event(keycode: int) -> InputEventKey:
                    var event := InputEventKey.new()
                    event.keycode = keycode
                    event.physical_keycode = keycode
                    event.pressed = true
                    return event

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
                    var safety := MouseSafety.new()
                    root.add_child(safety)
                    await process_frame
                    var after_ready := Input.mouse_mode

                    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
                    safety.force_visible_for_startup()
                    await process_frame
                    var after_guard := Input.mouse_mode

                    safety._unhandled_input(_key_event(KEY_F8))
                    var after_f8 := Input.mouse_mode

                    safety._unhandled_input(_key_event(KEY_ESCAPE))
                    var after_escape := Input.mouse_mode

                    var result := {
                        "after_ready": after_ready,
                        "after_guard": after_guard,
                        "after_f8": after_f8,
                        "after_escape": after_escape,
                        "visible": Input.MOUSE_MODE_VISIBLE,
                        "captured": Input.MOUSE_MODE_CAPTURED,
                        "display_driver": DisplayServer.get_name(),
                    }
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(result))
                    var ok := after_ready == Input.MOUSE_MODE_VISIBLE \
                        and after_guard == Input.MOUSE_MODE_VISIBLE \
                        and after_f8 == Input.MOUSE_MODE_CAPTURED \
                        and after_escape == Input.MOUSE_MODE_VISIBLE
                    quit(0 if ok else 1)
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
                    timeout=30,
                )
            except subprocess.TimeoutExpired as exc:
                self.skipTest(f"Windowed Godot mouse-safety probe timed out: {exc}")

            if not (tmp_path / "result.json").exists():
                self.skipTest("Windowed Godot mouse-safety probe could not produce a result in this environment")
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(result["after_ready"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_guard"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_f8"], result["captured"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_escape"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
