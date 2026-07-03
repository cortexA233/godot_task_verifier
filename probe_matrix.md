# Anti-Cheat Probe Matrix

Run each probe as a separate candidate project with:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\probe-project `
  --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\probe-name-score.json
```

| Probe | Expected Score Band | Required Failure Evidence |
| --- | ---: | --- |
| HUD-only weapon switch, no projectile | 10-30 | `projectile_physics`, `explosion_gameplay`, and `stability_repeatability` stay low. |
| Attack directly damages all targets | 15-40 | `projectile_physics` low and far target penalty appears. |
| Visual explosion with no damage | 10-35 | `visual_audio_polish` may score, `explosion_gameplay` remains low. |
| Damage with no trajectory feedback | 35-65 | `trajectory_preview` remains low. |
| Single-use grenade | 40-75 | `stability_repeatability` loses repeated-use points. |
| Grenade damages player | 30-70 | `explosion_gameplay` notes player impact. |
| Fixed trajectory that ignores aim | 35-70 | `trajectory_preview` loses aim-change points. |
| Explosion affects distant targets | 35-75 | `explosion_gameplay` notes far target damage. |
| Grenade mode breaks default shooting | 35-75 | `stability_repeatability` loses default-weapon regression points. |
