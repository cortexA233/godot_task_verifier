# Anti-Cheat Probe Fixtures

This folder stores the fake-candidate test cases used by the anti-cheat probe
matrix. The repository keeps compact overlays instead of six full Godot project
copies. This avoids committing hundreds of megabytes of repeated assets while
still keeping the probe definitions versioned with the verifier.

## Cases

- `hud-only`: weapon switching and UI signal behavior without a projectile.
- `visual-no-damage`: visible explosion feedback without damage.
- `damage-no-preview`: damage behavior with no visible trajectory aid.
- `single-use`: one grenade can be thrown, repeat use fails.
- `fixed-trajectory`: grenade behavior ignores aim direction.
- `bad-distance`: default throw distance is far outside the accepted envelope.

The observed score JSONs for these cases are committed under
`evaluation/evidence/`.

## Materialize Runnable Projects

Use a full candidate project as the base and generate runnable probe projects:

```powershell
python C:\recent_project\roboblast-grenade-verifier\evaluation\probes\materialize_probe_cases.py `
  --base-project C:\recent_project\godot-4-3d-third-person-controller-grenade-global `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\probe-candidates `
  --force
```

Then grade a generated case with the normal verifier command:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\recent_project\roboblast-grenade-verifier\artifacts\probe-candidates\hud-only `
  --godot C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\probe-hud-only-score.json
```
