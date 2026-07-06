# Formal Render-Backed Polish Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold screenshot-derived projectile and explosion footprint evidence into the formal `visual_audio_polish` score while preserving a 100-point rubric and a diagnostic headless path.

**Architecture:** Keep `run_grader.py` as the public entry point and `score_board.gd` as the formal score authority. Move the render-backed footprint checks into the formal `runner.gd` visual/audio category by reusing existing viewport capture and footprint ideas, while keeping `run_screenshot_probe.py` as a standalone auxiliary/debug tool. Full formal scoring requires render-capable capture; no-screenshot headless runs are explicitly diagnostic and incomplete.

**Tech Stack:** Python `argparse`/`subprocess`/`unittest`; Godot 4.6 GDScript verifier modules; existing `SceneProbe`, `ScreenshotVisualProbe`, report renderer, and PowerShell calibration scripts.

---

## File Structure

- Modify `verifier_godot/__verifier__/score_board.gd`: remove `visual_audio_polish` pass floor, lower the trajectory floor to 9, rename the score section to `Formal Score`, delete `logic_score/logic_max_score`, and mark diagnostic incomplete results when screenshot scoring is skipped.
- Modify `verifier_godot/__verifier__/runner.gd`: lower `trajectory_preview` to 17, raise `visual_audio_polish` to 20, add render-backed projectile/explosion footprint details, distinguish renderer failure from candidate main-scene failure, and support a verifier argument to skip screenshot scoring for diagnostic runs.
- Modify `run_grader.py`: add `--render-mode {windowed,headless}` and `--skip-screenshot-scoring`; default full formal runs to render-capable mode and pass a verifier argument to Godot when screenshot scoring is intentionally skipped.
- Modify `report_renderer.py`: stop assuming `logic_score` exists and label score sections using the new `Formal Score` contract.
- Modify `tests/test_run_grader.py` and `tests/test_report_renderer.py`: lock the new score contract, rubric weights, diagnostic flagging, and no-stale-doc expectations covered by the existing repository consistency tests.
- Modify `README.md`, `BENCHMARK.md`, and `probe_matrix.md`: document unattended render-capable formal scoring, the new 100-point table, deleted visual floor, diagnostic headless mode, and recalibration expectations.

## Task 1: Lock Score Contract And Rubric Tests

- [x] Add source-level tests asserting that `score_board.gd` emits `Formal Score`, does not emit `logic_score` or `logic_max_score`, uses `trajectory_preview >= 9`, and has no `visual_audio_polish` pass floor.
- [x] Add source-level tests asserting `runner.gd` uses `trajectory_preview` max 17 and `visual_audio_polish` max 20.
- [x] Add source-level tests asserting `visual_audio_polish` contains exactly the agreed detail names and weights: rendered projectile footprint 5, rendered explosion footprint 5, thrown grenade asset 3, explosion VFX asset 3, detonation audio 2, temporary visual cleanup 1, runtime presentation consistency 1.
- [x] Add source-level tests asserting render-backed footprint scoring uses debug-arena and main-scene weights of 3 and 2.
- [x] Run the targeted tests and verify they fail before implementation:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_score_board_uses_formal_score_contract tests.test_run_grader.RunGraderTests.test_runner_uses_render_backed_visual_polish_weights -v
```

## Task 2: Update Score Board And Existing Formal Weights

- [x] Update `score_board.gd` floors and score section names.
- [x] Remove `logic_score/logic_max_score` from normal score output.
- [x] Add stable diagnostic metadata fields and mark them incomplete when screenshot scoring is skipped.
- [x] Reweight `runner.gd` trajectory details from 22 to 17 while preserving the same behavioral gates.
- [x] Rework `visual_audio_polish` detail weights to total 20.
- [x] Run the targeted score contract and rubric tests until they pass.

## Task 3: Add Render-Backed Footprint Scoring To Formal Runner

- [x] Add a small formal render probe path in `runner.gd` that captures controlled debug-arena projectile and explosion frames using viewport images.
- [x] Add a main-scene capture path that scores candidate absence separately from renderer/capture failure.
- [x] Implement footprint scoring bands with strict lower bounds and tolerant sustained-oversize rules.
- [x] Feed the resulting scores into the rendered projectile and explosion footprint details.
- [x] Keep asset-quality details focused on placeholder/reused-asset quality and not mere visibility.
- [x] Run focused Godot-backed tests when Godot 4.6 is available; otherwise rely on source-level tests and document the skip.

## Task 4: Add Render Mode And Diagnostic Skip Controls

- [x] Add `--render-mode windowed|headless` to `run_grader.py`; full formal scoring defaults to `windowed`.
- [x] Remove `--headless` from Godot invocations only in `windowed` mode; keep it for diagnostic headless mode.
- [x] Add `--skip-screenshot-scoring`, pass `--skip-screenshot-scoring` through to `runner.gd`, and mark score JSON with `diagnostic_only: true`, `formal_score_complete: false`, and omitted screenshot components.
- [x] Ensure screenshot capture unavailable during full scoring becomes a verifier infrastructure failure rather than a candidate zero.
- [x] Run CLI/fake-Godot tests for both default and diagnostic modes.

## Task 5: Update Reports And Docs

- [x] Update report rendering tests so reports display `Formal Score` and no longer look for `Logic score`.
- [x] Update README, BENCHMARK, and probe matrix wording from headless-only auxiliary screenshot scoring to unattended render-capable formal scoring with diagnostic headless support.
- [x] Keep `run_screenshot_probe.py` documented as auxiliary/debug evidence.
- [x] Update calibration instructions to re-run reference, ablated, seven active probes, and any retained report rows; do not re-run deleted Codex runs.
- [x] Run stale-text searches for `logic_score`, `Logic Score`, `visual_audio_polish >= 5`, and `not counted in the 100-point benchmark score`.

## Task 6: Verification And Commit

- [x] Run targeted tests after each task.
- [x] Run `python -m unittest discover -s tests` before claiming completion.
- [x] If Godot 4.6 is available, run one full render-capable verifier smoke against the reference candidate and one diagnostic headless run.
- [x] Commit only scoped files in this verifier repository.

## Self-Review

- Spec coverage: The plan covers the confirmed top-level rubric, deleted visual floor, formal screenshot integration, diagnostic headless mode, score JSON rename/removal, main-scene classification, docs, and calibration scope.
- Placeholder scan: No task relies on unspecified files or unknown commands; implementation details that need code discovery are constrained to the listed files and existing helper APIs.
- Type consistency: The plan consistently uses `visual_audio_polish`, `Formal Score`, `diagnostic_only`, `formal_score_complete`, `omitted_formal_components`, `Rendered projectile footprint`, and `Rendered explosion footprint`.
