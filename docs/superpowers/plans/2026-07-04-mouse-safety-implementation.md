# Verifier Mouse Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make verifier-owned Godot windows release the cursor by default while preserving temporary mouse capture for manual aiming.

**Architecture:** Add one focused Godot helper, `mouse_safety.gd`, that owns cursor visibility, Escape release, and F8 capture toggling. Install it from both the manual debug arena and the verifier runner so current debug exports and future windowed automation share the same safety behavior. Keep grenade input action-driven so headless scoring and throw tests are unchanged.

**Tech Stack:** Godot 4.6 GDScript, Python `unittest`, existing verifier scene/export structure.

---

### Task 1: Add Mouse Safety Tests

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\tests\test_mouse_safety.py`
- Later create: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\mouse_safety.gd`
- Later modify: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\debug_arena.gd`
- Later modify: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\runner.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_mouse_safety.py` with this exact content:

```python
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
            self.assertEqual(result["after_ready"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_guard"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_f8"], result["captured"], completed.stdout + completed.stderr)
            self.assertEqual(result["after_escape"], result["visible"], completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```powershell
python -m unittest tests.test_mouse_safety -v
```

Expected: FAIL because `mouse_safety.gd` does not exist and `debug_arena.gd`/`runner.gd` do not preload it.

### Task 2: Implement The Mouse Safety Helper

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\mouse_safety.gd`
- Test: `C:\recent_project\roboblast-grenade-verifier\tests\test_mouse_safety.py`

- [ ] **Step 1: Create `mouse_safety.gd`**

Create `verifier_godot/__verifier__/mouse_safety.gd` with this exact content:

```gdscript
extends Node

const STARTUP_VISIBLE_FRAMES := 12

var _startup_guard_frames := 0


func _ready() -> void:
	name = "VerifierMouseSafety"
	process_mode = Node.PROCESS_MODE_ALWAYS
	force_visible_for_startup()


func force_visible_for_startup() -> void:
	_startup_guard_frames = STARTUP_VISIBLE_FRAMES
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _process(_delta: float) -> void:
	if _startup_guard_frames <= 0:
		set_process(false)
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_startup_guard_frames -= 1


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var keycode := key_event.physical_keycode
	if keycode == 0:
		keycode = key_event.keycode
	if keycode == KEY_ESCAPE:
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif keycode == KEY_F8:
		_toggle_capture()
		get_viewport().set_input_as_handled()


func _release_mouse() -> void:
	_startup_guard_frames = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(false)


func _toggle_capture() -> void:
	_startup_guard_frames = 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(false)
```

- [ ] **Step 2: Run the focused test and confirm remaining failures are integration failures**

Run:

```powershell
python -m unittest tests.test_mouse_safety -v
```

Expected: the helper source and Godot behavior checks pass, while the debug arena and runner installation checks still fail.

### Task 3: Install Mouse Safety In Verifier-Owned Scenes

**Files:**
- Modify: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\debug_arena.gd`
- Modify: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\runner.gd`
- Test: `C:\recent_project\roboblast-grenade-verifier\tests\test_mouse_safety.py`

- [ ] **Step 1: Update `debug_arena.gd` preloads and state**

At the top of `debug_arena.gd`, add the `MouseSafety` preload after the existing verifier preloads, and add a `mouse_safety` variable near the other state:

```gdscript
const MouseSafety = preload("res://__verifier__/mouse_safety.gd")

var mouse_safety: Node
```

- [ ] **Step 2: Install mouse safety from debug arena startup**

Replace the start of `_ready()` with:

```gdscript
func _ready() -> void:
	name = "VerifierDebugArena"
	_install_mouse_safety()
	call_deferred("_setup_debug_arena")
```

Add this helper near `_ready()`:

```gdscript
func _install_mouse_safety() -> void:
	if mouse_safety != null and is_instance_valid(mouse_safety):
		if mouse_safety.has_method("force_visible_for_startup"):
			mouse_safety.call("force_visible_for_startup")
		return
	mouse_safety = MouseSafety.new()
	mouse_safety.name = "VerifierMouseSafety"
	add_child(mouse_safety)
```

- [ ] **Step 3: Preserve the helper when debug children are cleared**

Update `_clear_debug_children()` to skip the mouse safety child:

```gdscript
func _clear_debug_children() -> void:
	for child in get_children():
		if child == mouse_safety or child.name == "VerifierMouseSafety":
			continue
		child.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 4: Reset the startup guard after the candidate player is added**

At the end of `_build_base_arena()`, after `ArenaBuilder.add_optional_weapon_ui(arena, player)`, add:

```gdscript
	_install_mouse_safety()
```

- [ ] **Step 5: Update `runner.gd` preloads and state**

At the top of `runner.gd`, add the `MouseSafety` preload after the existing verifier preloads, and add a `mouse_safety` variable near the other state:

```gdscript
const MouseSafety = preload("res://__verifier__/mouse_safety.gd")

var mouse_safety: Node
```

- [ ] **Step 6: Install mouse safety from runner startup and arena rebuilds**

In `_run()`, after `input = InputDriver.new(self)`, add:

```gdscript
	_install_mouse_safety()
```

Add this helper near `_cleanup_before_quit()`:

```gdscript
func _install_mouse_safety() -> void:
	if mouse_safety != null and is_instance_valid(mouse_safety):
		if mouse_safety.has_method("force_visible_for_startup"):
			mouse_safety.call("force_visible_for_startup")
		return
	mouse_safety = MouseSafety.new()
	mouse_safety.name = "VerifierMouseSafety"
	root.add_child(mouse_safety)
```

In `_build_arena()`, after `weapon_ui = ArenaBuilder.add_optional_weapon_ui(arena, player)`, add:

```gdscript
	_install_mouse_safety()
```

- [ ] **Step 7: Run the focused test to verify the implementation passes**

Run:

```powershell
python -m unittest tests.test_mouse_safety -v
```

Expected: PASS.

- [ ] **Step 8: Commit the implementation**

Run:

```powershell
git add tests/test_mouse_safety.py verifier_godot/__verifier__/mouse_safety.gd verifier_godot/__verifier__/debug_arena.gd verifier_godot/__verifier__/runner.gd
git commit -m "fix: add verifier mouse safety"
```

Expected: commit succeeds with only mouse-safety implementation files staged.

### Task 4: Document Controls And Verify The Suite

**Files:**
- Modify: `C:\recent_project\roboblast-grenade-verifier\README.md`
- Test: `C:\recent_project\roboblast-grenade-verifier\tests\test_mouse_safety.py`

- [ ] **Step 1: Add a failing README structural assertion**

Append this test to `tests/test_mouse_safety.py` inside `MouseSafetyTests`:

```python
    def test_readme_documents_debug_arena_mouse_safety_controls(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")

        self.assertIn("Mouse safety is enabled", readme)
        self.assertIn("F8", readme)
        self.assertIn("Esc", readme)
        self.assertIn("cursor visible", readme)
```

- [ ] **Step 2: Run the focused test to verify the README assertion fails**

Run:

```powershell
python -m unittest tests.test_mouse_safety -v
```

Expected: FAIL because `README.md` does not yet document the mouse-safety controls.

- [ ] **Step 3: Update README debug arena controls**

In `README.md`, under `## Debug Arena Export`, after the paragraph that starts `The debug scene uses`, add:

```markdown

Mouse safety is enabled in verifier-owned scenes. The debug arena starts with
the cursor visible, `F8` toggles temporary mouse capture for manual aiming, and
`Esc` releases the cursor. Automated grenade throws continue to use Godot input
actions and do not require cursor capture.
```

- [ ] **Step 4: Run the focused test**

Run:

```powershell
python -m unittest tests.test_mouse_safety -v
```

Expected: PASS.

- [ ] **Step 5: Run the full Python test suite**

Run:

```powershell
python -m unittest discover -s tests -v
```

Expected: PASS, with Godot-backed tests skipped only if the Godot executable is unavailable in this environment.

- [ ] **Step 6: Run a real headless verifier smoke check when Godot is available**

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\recent_project\godot-4-3d-third-person-controller `
  --godot C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\mouse-safety-score.json
```

Expected: command completes and writes a score JSON. Do not commit the generated score JSON or log.

- [ ] **Step 7: Commit docs and tests**

Run:

```powershell
git add README.md tests/test_mouse_safety.py
git commit -m "docs: document verifier mouse safety controls"
```

Expected: commit succeeds with only README and the focused test update staged.
