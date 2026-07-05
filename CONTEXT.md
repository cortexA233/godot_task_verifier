# RoboBlast Grenade Verifier

This context defines the benchmark language used by the private external
verifier for the RoboBlast grenade weapon task.

## Language

**Formal grader**:
The deterministic headless verifier path that produces the official 0-100 score
and `passed` flag for a candidate project.
_Avoid_: official screenshot runner, visual grader

**Screenshot probe**:
An auxiliary render-capable verifier run that captures viewport images and
visual metrics as evidence. It can fail, skip, or be unavailable without changing
the formal grader's score.
_Avoid_: formal visual score, screenshot grader

**Debug arena visual run**:
A screenshot probe mode that instantiates the verifier-owned deterministic arena
and drives the grenade workflow under controlled camera, target, and timing
conditions.
_Avoid_: test map screenshot, fake scene score

**Gameplay camera**:
The camera or camera controller that the candidate game uses to decide player
aim, throw direction, target distance, and third-person presentation.
_Avoid_: screenshot camera, verifier camera

**Capture camera**:
A verifier-owned observer camera used only to render screenshots or visual
metrics. It must not change the candidate game's aim, input, throw direction, or
selected gameplay camera.
_Avoid_: gameplay camera, aim camera

**Side-view trajectory visual run**:
A screenshot probe mode that renders grenade preview and throw evidence from a
capture camera placed broadly side-on to the player's throw direction, so arc
height, forward travel, and landing feedback are easier to inspect.
_Avoid_: side-view formal grader, gameplay side camera

**Side-oblique capture view**:
A side-view trajectory visual run composition where the capture camera is offset
broadly perpendicular to the throw direction and elevated enough to keep both
arc height and ground landing feedback inspectable.
_Avoid_: flat side view, top-down view

**Multi-heading trajectory sample**:
A deterministic set of grenade preview and throw observations across more than
one player heading, used to reduce single-angle overfitting in trajectory visual
evidence.
_Avoid_: random camera sweep, one-off side screenshot

**Gameplay-view visual evidence**:
Screenshot evidence captured from the candidate's normal gameplay presentation
or the existing debug-arena view, used to confirm the grenade preview and throw
remain visible in a player-facing composition.
_Avoid_: original camera score, real gameplay score

**Gameplay-view visibility gate**:
A shadow visual evidence check that requires grenade preview guidance to be
visible in a player-facing or existing debug-arena view before side-view
trajectory measurements are treated as healthy evidence.
_Avoid_: side-view-only pass, screenshot beauty gate

**Hybrid trajectory evidence**:
Shadow visual evidence that combines runtime trajectory observations,
gameplay-view visual evidence, and side-view trajectory visual run measurements
to evaluate whether the grenade preview communicates an arc, reacts to aim, and
matches the projectile behavior.
_Avoid_: pure screenshot score, node-shape score

**Baseline-difference trajectory mask**:
A pixel mask derived from differences between a stable baseline screenshot and a
later trajectory-evidence screenshot, used to identify visible preview or throw
changes without relying on runtime preview-node projection.
_Avoid_: node-projected mask, whole-frame diff

**Trajectory analysis region**:
A verifier-defined image region for baseline-difference trajectory masks, chosen
from the capture setup and expected throw corridor rather than from candidate
preview nodes. It excludes unrelated screen areas such as HUD, labels, and
camera-edge noise.
_Avoid_: whole-frame mask, candidate-node crop

**Per-heading clean baseline**:
A baseline screenshot captured separately for each trajectory sample heading
after the player and cameras have settled but before grenade mode shows preview
guidance.
_Avoid_: startup baseline, shared baseline

**Preview phase**:
The period after grenade mode is selected and before the attack input launches a
grenade, when the candidate should show aiming guidance for the next throw.
_Avoid_: aiming setup frame, pre-attack screenshot

**Early-flight phase**:
The initial period after a grenade is launched and before detonation, when the
projectile's visible and runtime movement can be compared with the earlier
preview.
_Avoid_: explosion phase, projectile-only score

**Main scene visual run**:
A screenshot probe mode that loads the candidate project's real playable scene
and captures evidence that the grenade workflow still renders in that context.
_Avoid_: integration score, real-game grader

**Projectile footprint**:
The projectile's screen-space visual presence before detonation, measured by a
projected rectangle and local pixel activity around the moving projectile.
_Avoid_: whole-frame similarity, grenade screenshot

**Auxiliary evidence**:
Artifacts and metrics that help a human inspect a run but do not directly award
or remove formal grader points.
_Avoid_: hidden score, unofficial penalty

**Shadow visual evidence**:
Auxiliary evidence that mirrors a possible future scoring rule by producing
structured measurements, provisional findings, and calibration notes without
changing the formal grader's score, category floors, or `passed` flag.
_Avoid_: provisional official score, hidden penalty

**Trajectory shadow metrics**:
Machine-readable measurements emitted by hybrid trajectory evidence, such as
mask size, preview shape, preview movement, projectile agreement, and per-heading
notes. They are calibration data, not formal score items.
_Avoid_: hidden trajectory score, screenshot-only grade

**Provisional visual verdict**:
A human-readable shadow visual evidence conclusion, such as healthy, suspect, or
missing, derived from trajectory shadow metrics without changing the formal
grader's score, category floors, or `passed` flag.
_Avoid_: visual pass, official verdict
