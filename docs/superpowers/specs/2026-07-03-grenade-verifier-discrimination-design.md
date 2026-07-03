# Grenade Verifier Discrimination Design

## Context

The RoboBlast grenade verifier currently distinguishes the ablated task from a
complete reference implementation, but a strong partial Sonnet run scored
`89/100`. Inspection showed that the candidate had real projectile, explosion,
visual, audio, and repeatability behavior, but its grenade trajectory preview
was clearly wrong and its default throw distance calibrated outside the preferred
range.

The assignment source of truth in `game_take_home.html` requires calibrated
difficulty: strong agents should land in a partial-credit zone when meaningful
behavior is missing. The verifier should therefore give high partial credit for
real grenade systems while making incorrect aiming prediction a major defect.

## Goals

- Make trajectory preview correctness more discriminating without assuming one
  implementation shape.
- Keep scoring behavioral and out of 100.
- Preserve high scores for a correct reference implementation and low scores for
  the ablated task.
- Recalibrate the known Sonnet-2 partial candidate from `89/100` into roughly
  the `60-70` or low-`70` range.
- Record throw-distance quality as a small explosion-gameplay signal instead of
  allowing borderline default throw distance to receive full explosion credit.
- Update docs and tests alongside verifier behavior.

## Non-Goals

- Do not cap total score with a hard global rule.
- Do not require exact node names, script names, paths, signals, or historical
  implementation details.
- Do not require frame-perfect predicted trajectory matching.
- Do not make explosion damage depend on trajectory-preview success.
- Do not commit generated score JSON, logs, screenshots, PDFs, temporary
  candidate copies, or debug arena exports.

## Score Weights

The category weights remain a 100-point total:

```text
weapon_controls          15
hud_feedback             10
trajectory_preview       30
projectile_physics       15
explosion_gameplay       20
visual_audio_polish       5
stability_repeatability   5
```

Compared to the current rubric, `trajectory_preview` gains 10 points because it
is a core player-facing requirement in the task prompt. `hud_feedback` loses 5
points and `visual_audio_polish` loses 5 points because those are important
supporting signals, but they should not offset a visibly wrong grenade aiming
aid.

Expected score shape for the known Sonnet-2 partial candidate:

```text
weapon_controls          11/15
hud_feedback             10/10
trajectory_preview        5-9/30
projectile_physics       15/15
explosion_gameplay       18/20
visual_audio_polish       5/5
stability_repeatability   5/5
total                    69-73/100
```

The exact trajectory score depends on how much basic visible aiming-aid behavior
the verifier observes. The important outcome is that clearly wrong trajectory
prediction no longer passes as a near-complete implementation.

## Trajectory Preview Scoring

`trajectory_preview` becomes a 30-point category with these detail items:

```text
Visible grenade aiming aid                    5
Communicates arcing throw, not bullet line    6
Updates with aim/camera direction             8
Preview matches projectile direction          7
Visibility lifecycle/cooldown behavior        4
```

The category should use behavioral gates:

```text
If no visible aiming aid is observed:
  The remaining trajectory detail items cannot score.

If the aiming aid does not update with aim/camera direction:
  Preview-to-projectile direction consistency cannot score.

If no actual grenade projectile is observed:
  Preview-to-projectile direction consistency cannot score, but visible,
  update, arc-expression, and lifecycle behavior may still receive credit when
  observed.
```

`Preview matches projectile direction` means the aiming aid's indicated
horizontal direction should agree with the actual grenade projectile's initial
to mid-flight horizontal motion direction within a generous direction sector.
It does not require exact ballistic prediction or frame-by-frame curve overlap.

Reasonable aiming aids include trajectory meshes, dotted arc previews, landing
markers, reticles, projected decals, or equivalent in-world visual guidance.
The verifier should continue to avoid checking for exact node names or asset
paths.

## Explosion Gameplay Calibration

`explosion_gameplay` remains a 20-point category, but includes explicit
throw-distance calibration quality:

```text
Nearby target damage across angles      8
Out-of-range safety across angles       4
Player safety across angles             3
Detonation effects across angles        3
Throw distance calibration quality      2
```

The throw-distance quality item scores:

```text
full 6-12 units:          2/2
borderline 4-14 units:    0/2
failed/outside:           0/2
```

This is intentionally a small penalty. A candidate with real localized damage,
safe explosions, and detonation effects should keep most explosion-gameplay
credit even if the default throw lands outside the preferred 6-12 unit envelope.

## Runner Behavior

The runner should continue to build deterministic arenas, set known player
headings, drive input through existing input actions and fallbacks, and observe
runtime behavior. The design adds two behavioral observations:

- Better trajectory preview state capture across at least two aim/camera
  headings.
- A direction-comparison path between observed preview orientation/position and
  observed grenade projectile travel.

When the verifier cannot confidently infer preview direction, it should fail
only the consistency detail rather than the entire trajectory category. This
keeps the rubric tolerant of alternate correct implementations while still
penalizing previews that are static or directionally wrong.

## Documentation Updates

Update the following files with the new scoring model and calibration language:

- `README.md`: category weights, trajectory-preview explanation, calibration
  notes, latest local calibration summary.
- `BENCHMARK.md`: score categories, score interpretation, validity-probe
  expectations.
- `probe_matrix.md`: expected ranges for fixed/wrong trajectory,
  visual-only/trajectory-only, and borderline throw-distance probes.

## Testing And Calibration

Run the Python test suite after implementation:

```powershell
python -m unittest discover -s tests
```

When Godot 4.6 is available, run the real headless calibration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Calibration targets:

```text
ablated task:              still low, around 10-20
reference implementation:  still high, ideally 95-100
Sonnet-2 partial:          reduced from 89 to roughly 60-70 or low 70s
```

Tests should cover:

- New category weights still total 100.
- `trajectory_preview` detail labels and gates are present.
- Missing visible aiming aid prevents later trajectory detail scores.
- Missing aim/camera update prevents direction-consistency credit.
- Borderline throw-distance calibration records `0/2` for calibration quality.
- Report rendering can display the updated category maxima and detail items.

Generated runtime artifacts from calibration runs must remain uncommitted.

## Acceptance Criteria

- The verifier remains behavioral and implementation-agnostic.
- The total maximum score remains 100.
- Correct reference behavior remains high-scoring.
- Ablated behavior remains low-scoring.
- The known strong partial Sonnet-2 shape no longer receives a pass-level score
  when trajectory prediction is visibly wrong.
- Documentation and tests reflect the new rubric.
