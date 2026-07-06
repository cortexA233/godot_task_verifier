# Anti-Cheat Probe Matrix

The `passed` report flag is a convenience meaning `score >= 85` plus the
category floors below. Most anti-cheat probes must stay clearly below the
numeric pass line, and a low-score probe that reaches the pass line is a
verifier validity failure that must be fixed before scores are trusted. The
active representative probe set contains seven observed fake candidates. The
previous wrong-projectile-model run is retained only as historical evidence
from the pre-reweighting visual-floor calibration point; it is not an active
probe and should not be rerun unless a future rubric explicitly restores it.
Record every active probe run in the Observed column and keep its score JSON as
curated evidence under `evaluation/evidence/`.

Two extra tripwires back the score bands: core-category pass floors
(`trajectory_preview >= 11`, `projectile_physics >= 8`,
`explosion_gameplay >= 10`, `visual_audio_polish >= 5`) hard-block `passed`
regardless of total score, and the soft `suspect` flag records global damage
sweeps, damaged safety targets, and player self-damage for manual review.

Run each probe as a separate candidate project with:

```powershell
$Verifier = "<path-to-this-repo>"
$Godot = "<path-to-godot-4.6-console-executable>"
$ProbeProject = "<path-to-probe-project>"

python "$Verifier\run_grader.py" `
  --project "$ProbeProject" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\probe-name-score.json"
```

| Probe | Expected Score Band | Observed | Required Failure Evidence |
| --- | ---: | --- | --- |
| HUD-only weapon switch, no projectile | 10-30 | `19/100` on 2026-07-03, `passed: false`, all core category floors fail (`evaluation/evidence/calibration-20260703-probe-hud-only-score.json`) | `projectile_physics`, calibration, `explosion_gameplay`, and `stability_repeatability` stay low. |
| Attack directly damages all targets | 15-40 | deferred; covered by the stronger global targetable damage sweep probe below | `projectile_physics` low and far/side/rear target penalty appears. |
| Visual explosion with no damage | 10-35 | `34/100` on 2026-07-03, `passed: false`, `visual_audio_polish` gets credit while `explosion_gameplay` stays `0/20` (`evaluation/evidence/calibration-20260703-probe-visual-no-damage-score.json`) | `visual_audio_polish` may score, `explosion_gameplay` remains low. |
| Damage with no trajectory feedback | 30-60 | `54/100` on 2026-07-03, `passed: false`, `trajectory_preview` stays at zero, `suspect: true` for sweep/safety-target damage (`evaluation/evidence/calibration-20260703-probe-damage-no-preview-score.json`) | `trajectory_preview` remains low even if adaptive explosion placement gives some damage credit. |
| Single-use grenade | 40-75 | `75/100` on 2026-07-03, `passed: false`, `stability_repeatability` loses repeated-use credit, `explosion_gameplay` remains below the pass floor, `suspect: true` for sweep/safety-target damage (`evaluation/evidence/calibration-20260703-probe-single-use-score.json`) | `stability_repeatability` loses repeated-use points. |
| Grenade damages player | 30-70 | deferred; player-safety scoring and suspect flag remain implemented, but no separate fake candidate was run in the fast probe pass | `explosion_gameplay` notes player impact or unsafe path. |
| Fixed or wrong trajectory that ignores aim | 30-70 | `65/100` on 2026-07-03, `passed: false`, trajectory and projectile behavior are partial while `explosion_gameplay` stays below the pass floor (`evaluation/evidence/calibration-20260703-probe-fixed-trajectory-score.json`) | `trajectory_preview` loses aim-change and preview/projectile consistency points; `explosion_gameplay` may still credit localized damage when the blast is otherwise real, nearby, and safe. |
| Hard-coded one-angle or one-distance blast | 25-65 | deferred; partially covered by the fixed-trajectory probe and the adaptive multi-heading explosion trials | Fixed-seed explosion variants include multiple deterministic headings, nearby radii, and safety placements; expected-direction hits receive full nearby credit, while off-seed localized hits are capped at partial credit. |
| Global targetable damage sweep | 35-79 | `78/100` on 2026-07-03, `passed: false`, `explosion_gameplay` capped to `4/20`, `suspect: true` (sweep + safety-target damage), fails the `explosion_gameplay` floor (`evaluation/evidence/calibration-20260703-probe-global-damage-score.json`) | `explosion_gameplay` notes global damage sweep detection and applies the category cap even though nearby target damage is observed. |
| Explosion affects distant targets | 35-75 | deferred; covered by the global sweep probe's damaged far/side/rear safety-target evidence | `explosion_gameplay` notes far, side, rear, or player safety target damage; repeated broad sweeps are capped as global damage. |
| Very short or very long default throw | 25-68 | `50/100` on 2026-07-03, `passed: false`, calibration fails at a measured 2.74-unit throw and `explosion_gameplay` stays `0/20` (`evaluation/evidence/calibration-20260703-probe-bad-distance-score.json`) | Calibration notes failed or borderline distance; throw-distance quality records `0/2` and fixed fallback or safety targets prevent full explosion credit. |
| Grenade mode breaks default shooting | 35-75 | deferred; the real `res://main.tscn` smoke check remains in `stability_repeatability`, but no separate fake candidate was run in the fast probe pass | `stability_repeatability` loses default-weapon regression points. |

The active fast probe pass has seven observed fake candidates with committed
score JSON evidence, and all seven remain below the numeric `score >= 85` pass
line. Deferred rows are intentionally documented as overlapping validity work
rather than silent passes; run them later if the verifier scoring changes or if
the final reviewer asks for exhaustive per-row evidence. The historical
wrong-projectile-model score JSON remains in `evaluation/evidence/` as
pre-reweighting evidence, but it is no longer counted in the active probe set.
The observed global-sweep score sits 7 points below the 85 pass line, so re-run
that probe first whenever explosion scoring changes; re-run the visual-only and
damage/trajectory probes plus the asset-quality helper tests whenever visual
scoring changes.
