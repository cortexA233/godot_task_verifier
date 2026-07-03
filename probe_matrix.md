# Anti-Cheat Probe Matrix

Run each probe as a separate candidate project with:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\probe-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\probe-name-score.json
```

| Probe | Expected Score Band | Required Failure Evidence |
| --- | ---: | --- |
| HUD-only weapon switch, no projectile | 10-30 | `projectile_physics`, calibration, `explosion_gameplay`, and `stability_repeatability` stay low. |
| Attack directly damages all targets | 15-40 | `projectile_physics` low and far/side/rear target penalty appears. |
| Visual explosion with no damage | 10-35 | `visual_audio_polish` may score, `explosion_gameplay` remains low. |
| Damage with no trajectory feedback | 30-60 | `trajectory_preview` remains low even if adaptive explosion placement gives some damage credit. |
| Single-use grenade | 40-75 | `stability_repeatability` loses repeated-use points. |
| Grenade damages player | 30-70 | `explosion_gameplay` notes player impact or unsafe path. |
| Fixed or wrong trajectory that ignores aim | 30-70 | `trajectory_preview` loses aim-change and preview/projectile consistency points; `explosion_gameplay` may still credit localized damage when the blast is otherwise real, nearby, and safe. |
| Explosion affects distant targets | 35-75 | `explosion_gameplay` notes far, side, rear, or player safety target damage. |
| Very short or very long default throw | 25-68 | Calibration notes failed or borderline distance; throw-distance quality records `0/2` and fixed fallback or safety targets prevent full explosion credit. |
| Grenade mode breaks default shooting | 35-75 | `stability_repeatability` loses default-weapon regression points. |
