# Debug Arena Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone debug arena export command so a user can open and manually run the same verifier arena in Godot.

**Architecture:** Reuse the existing project copy and verifier injection logic from `run_grader.py`. Add a static Godot debug scene under `verifier_godot/__verifier__` that builds the same arena at runtime, plus a Python exporter that creates a self-contained debug project copy.

**Tech Stack:** Python stdlib, Godot GDScript, unittest, Godot headless smoke check.

---

### Task 1: Add Debug Export Tests

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\tests\test_debug_scene_exporter.py`
- Create later: `C:\recent_project\roboblast-grenade-verifier\debug_scene_exporter.py`

- [ ] **Step 1: Write failing tests**

Tests should verify that `export_debug_project(source, output, verifier_root)` copies a project, injects `__verifier__`, and leaves `__verifier__/debug_arena.tscn` in the exported project.

- [ ] **Step 2: Run tests**

Run:

```powershell
python -m unittest tests.test_debug_scene_exporter -v
```

Expected: FAIL because `debug_scene_exporter.py` does not exist yet.

### Task 2: Add Godot Debug Scene Assets

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\debug_arena.tscn`
- Create: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\debug_arena.gd`
- Create: `C:\recent_project\roboblast-grenade-verifier\verifier_godot\__verifier__\debug_arena_smoke.gd`

- [ ] **Step 1: Implement debug scene**

The scene root should run `debug_arena.gd`, call `ArenaBuilder.create_arena()`, add the real player, optional weapon UI, near/far damage targets at the same coordinates used by scoring, plus a camera, light, visible floor, and labels.

- [ ] **Step 2: Implement smoke script**

The smoke script should instantiate `debug_arena.tscn`, wait a few frames, confirm `VerifierPlayer`, `NearTargetA`, `NearTargetB`, and `FarTarget` exist, print a success line, and quit nonzero on failure.

### Task 3: Add Python Exporter and CLI

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\debug_scene_exporter.py`
- Create: `C:\recent_project\roboblast-grenade-verifier\export_debug_arena.py`

- [ ] **Step 1: Implement exporter**

`export_debug_project(source_project, output_project, verifier_root)` should reuse `run_grader.copy_candidate_project` and `run_grader.inject_verifier`, then verify `project.godot` and `__verifier__/debug_arena.tscn` exist in the output.

- [ ] **Step 2: Implement CLI**

`export_debug_arena.py --project SOURCE --out OUTPUT` should call the exporter and print the scene path to open: `res://__verifier__/debug_arena.tscn`.

- [ ] **Step 3: Run tests**

Run:

```powershell
python -m unittest tests.test_debug_scene_exporter -v
```

Expected: PASS.

### Task 4: Document Usage and Verify With Godot

**Files:**
- Modify: `C:\recent_project\roboblast-grenade-verifier\README.md`
- Output: `C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena-cc-opus`

- [ ] **Step 1: Document export command**

Add README instructions for exporting and opening the debug project.

- [ ] **Step 2: Run all Python tests**

Run:

```powershell
python -m unittest discover -s tests -v
```

Expected: PASS.

- [ ] **Step 3: Export a real debug project**

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\export_debug_arena.py --project C:\recent_project\godot-4-3d-third-person-controller_cc_opus_no_git --out C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena-cc-opus
```

Expected: exported project exists.

- [ ] **Step 4: Run Godot smoke check**

Run:

```powershell
Godot --headless --path C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena-cc-opus --script res://__verifier__/debug_arena_smoke.gd
```

Expected: prints `Verifier debug arena smoke check passed.`
