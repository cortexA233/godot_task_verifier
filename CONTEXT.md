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
