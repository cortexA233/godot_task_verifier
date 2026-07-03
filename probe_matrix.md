# Anti-Cheat Probe Matrix

The `passed` report flag is a convenience meaning `score >= 85`. Anti-cheat
probes must stay clearly below that line: every expected band deliberately
tops out at 79 or lower, and a probe that reaches the pass line is a verifier
validity failure that must be fixed before scores are trusted. Record every
probe run in the Observed column and keep its score JSON as curated evidence
under `evaluation/evidence/`.

Run each probe as a separate candidate project with:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\probe-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\probe-name-score.json
```

| Probe | Expected Score Band | Observed | Required Failure Evidence |
| --- | ---: | --- | --- |
| HUD-only weapon switch, no projectile | 10-30 | not yet run | `projectile_physics`, calibration, `explosion_gameplay`, and `stability_repeatability` stay low. |
| Attack directly damages all targets | 15-40 | not yet run | `projectile_physics` low and far/side/rear target penalty appears. |
| Visual explosion with no damage | 10-35 | not yet run | `visual_audio_polish` may score, `explosion_gameplay` remains low. |
| Damage with no trajectory feedback | 30-60 | not yet run | `trajectory_preview` remains low even if adaptive explosion placement gives some damage credit. |
| Single-use grenade | 40-75 | not yet run | `stability_repeatability` loses repeated-use points. |
| Grenade damages player | 30-70 | not yet run | `explosion_gameplay` notes player impact or unsafe path. |
| Fixed or wrong trajectory that ignores aim | 30-70 | not yet run | `trajectory_preview` loses aim-change and preview/projectile consistency points; `explosion_gameplay` may still credit localized damage when the blast is otherwise real, nearby, and safe. |
| Hard-coded one-angle or one-distance blast | 25-65 | not yet run | Fixed-seed explosion variants include multiple deterministic headings, nearby radii, and safety placements; expected-direction hits receive full nearby credit, while off-seed localized hits are capped at partial credit. |
| Global targetable damage sweep | 35-79 | `78/100` on 2026-07-03, `passed: false`, `explosion_gameplay` capped to `4/20` (`evaluation/evidence/calibration-20260703-probe-global-damage-score.json`) | `explosion_gameplay` notes global damage sweep detection and applies the category cap even though nearby target damage is observed. |
| Explosion affects distant targets | 35-75 | not yet run | `explosion_gameplay` notes far, side, rear, or player safety target damage; repeated broad sweeps are capped as global damage. |
| Very short or very long default throw | 25-68 | not yet run | Calibration notes failed or borderline distance; throw-distance quality records `0/2` and fixed fallback or safety targets prevent full explosion credit. |
| Grenade mode breaks default shooting | 35-75 | not yet run | `stability_repeatability` loses default-weapon regression points. |

Probes marked "not yet run" still need a fake candidate project built and
graded; treat them as open validity work, not as passing evidence. The
observed global-sweep score sits 7 points below the 85 pass line, so re-run
that probe first whenever scoring or calibration changes.
