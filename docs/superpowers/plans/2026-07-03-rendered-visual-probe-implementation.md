# Rendered Visual Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small rendered-frame pixel-change probe to the RoboBlast grenade verifier without breaking the default headless grading path.

**Architecture:** Extend `SceneProbe` with viewport frame-signature helpers, then pass an optional viewport baseline through runtime activity observation. `runner.gd` uses the rendered delta inside `visual_audio_polish` when available and falls back to visible runtime effects when Godot runs with the headless dummy renderer.

**Tech Stack:** Godot 4.6 GDScript verifier files, Python `unittest`, Markdown docs.

---

## File Structure

- Modify `tests/test_run_grader.py`: add structural tests for the rendered probe and a Godot-backed render-capable viewport delta test.
- Modify `verifier_godot/__verifier__/scene_probe.gd`: add viewport signature, signature delta, and optional rendered-frame sampling inside `observe_runtime_activity`.
- Modify `verifier_godot/__verifier__/runner.gd`: update `visual_audio_polish` details to include rendered-frame pixel activity while keeping the category at 5 points.
- Modify `README.md`: mention opportunistic rendered-frame checks under Godot 4.6 headless constraints.
- Modify `BENCHMARK.md`: clarify that visual/audio polish now includes rendered-frame evidence when a render-capable driver is available.

## Task 1: Add Failing Tests

**Files:**
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Add structural tests**

Add tests asserting that `scene_probe.gd` contains `viewport_frame_signature`,
`frame_signature_delta`, `rendered_pixel_delta`, and that `runner.gd` contains
`"Rendered frame pixel activity"` while keeping `visual_audio_polish` at 5.

- [ ] **Step 2: Add render-capable Godot test**

Add a skipped-when-Godot-missing test that runs a temporary project without
`--headless`, captures a viewport signature, draws a `ColorRect`, captures a
second signature, and writes a positive delta to `result.json`.

- [ ] **Step 3: Run the new tests and verify RED**

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_scene_probe_declares_rendered_frame_helpers tests.test_run_grader.RunGraderTests.test_runner_scores_rendered_frame_visual_activity tests.test_run_grader.RunGraderTests.test_scene_probe_detects_render_capable_pixel_delta -v
```

Expected: the new tests fail because the helpers and runner detail do not exist.

## Task 2: Implement SceneProbe Render Helpers

**Files:**
- Modify: `verifier_godot/__verifier__/scene_probe.gd`

- [ ] **Step 1: Add viewport signature helpers**

Implement `viewport_frame_signature(viewport, sample_step)` and
`frame_signature_delta(before, after)`. Store sampled colors in the signature and
return the maximum normalized RGB delta across matching sample positions.

- [ ] **Step 2: Extend runtime activity observation**

Add optional parameters to `observe_runtime_activity`:
`viewport`, `before_frame_signature`, `render_sample_step`, and
`render_sample_interval`. Existing callers continue to work. When signatures are
available, record `render_available` and the largest `rendered_pixel_delta`.

- [ ] **Step 3: Run SceneProbe tests and verify GREEN**

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_scene_probe_declares_rendered_frame_helpers tests.test_run_grader.RunGraderTests.test_scene_probe_detects_render_capable_pixel_delta -v
```

Expected: PASS.

## Task 3: Connect Runner Scoring

**Files:**
- Modify: `verifier_godot/__verifier__/runner.gd`

- [ ] **Step 1: Add rendered visual constants**

Add constants for sample step, sample interval, and minimum pixel delta near the
other verifier constants.

- [ ] **Step 2: Update `visual_audio_polish`**

Capture `before_frame_signature` before firing. Pass it and `root` into
`SceneProbe.observe_runtime_activity`. Score four details:

```text
Visible runtime effect nodes      1
Rendered frame pixel activity     1
Detonation audio                  2
Temporary node cleanup            1
```

When rendering is unavailable, the rendered-frame detail falls back to visible
runtime evidence and explains the fallback in notes.

- [ ] **Step 3: Run runner test and verify GREEN**

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_runner_scores_rendered_frame_visual_activity -v
```

Expected: PASS.

## Task 4: Update Docs

**Files:**
- Modify: `README.md`
- Modify: `BENCHMARK.md`

- [ ] **Step 1: Document the rendered-frame behavior**

Add concise notes that `visual_audio_polish` includes rendered-frame pixel
activity when a render-capable display driver is available and falls back under
Godot 4.6 `--headless` because that mode uses a dummy renderer.

- [ ] **Step 2: Run docs-related structural tests**

```powershell
python -m unittest tests.test_repository_consistency -v
```

Expected: PASS.

## Task 5: Verify And Commit

**Files:**
- No new source edits unless verification finds a concrete failure.

- [ ] **Step 1: Run focused tests**

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_scene_probe_declares_rendered_frame_helpers tests.test_run_grader.RunGraderTests.test_runner_scores_rendered_frame_visual_activity tests.test_run_grader.RunGraderTests.test_scene_probe_detects_render_capable_pixel_delta -v
```

Expected: PASS.

- [ ] **Step 2: Run the full test suite**

```powershell
python -m unittest discover -s tests -v
```

Expected: PASS, with Godot-backed tests skipped only if the Godot executable is
not available.

- [ ] **Step 3: Commit scoped files**

```powershell
git add tests/test_run_grader.py verifier_godot/__verifier__/scene_probe.gd verifier_godot/__verifier__/runner.gd README.md BENCHMARK.md docs/superpowers/plans/2026-07-03-rendered-visual-probe-implementation.md
git commit -m "feat: add rendered visual probe"
```
