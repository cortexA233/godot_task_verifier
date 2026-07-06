# Emphasize Presentation Fidelity In Grenade Rubric

The formal grenade rubric will increase `visual_audio_polish` to 15 points with
a conservative `5/15` pass floor. Placeholder grenade models and placeholder
explosion VFX should be penalized in the score, but they should not automatically
block `passed` when the gameplay logic is otherwise strong. The extra
presentation weight comes mostly from `trajectory_preview` and a small amount
from `hud_feedback`, while trajectory preview correctness remains gameplay
communication rather than asset polish. `explosion_gameplay` will stop awarding
visual-effect points and will instead put that weight into blast locality,
keeping explosion range correctness separate from presentation fidelity.

The top-level rubric will use `weapon_controls` 15, `hud_feedback` 8,
`trajectory_preview` 22, `projectile_physics` 15, `explosion_gameplay` 20,
`visual_audio_polish` 15, and `stability_repeatability` 5. Inside
`visual_audio_polish`, projectile model asset quality and explosion VFX asset
quality are each worth 4 points, while detonation timing/location, detonation
audio, cleanup, and cross-trial consistency carry the remaining 7 points.

This favors a stronger visual benchmark without turning placeholder assets into
a hard failure when the grenade behavior itself works: projectile model quality
and explosion VFX asset quality carry most of the presentation points, while
audio, cleanup, timing/location, and cross-trial consistency remain supporting
checks. The current
wrong-projectile-model probe will be removed instead of replaced with new visual
asset probes; runtime helper tests and existing calibration runs will protect
the detector behavior and benchmark pass/fail boundaries.
