# Anti-Cheat Probe Fixtures

This folder stores the fake-candidate overlay test cases used by the anti-cheat
probe matrix. The repository keeps compact overlays instead of full Godot
project copies. This avoids committing hundreds of megabytes of repeated assets
while still keeping the probe definitions versioned with the verifier.

## Cases

- `hud-only`: weapon switching and UI signal behavior without a projectile.
- `visual-no-damage`: visible explosion feedback without damage.
- `damage-no-preview`: damage behavior with no visible trajectory aid.
- `single-use`: one grenade can be thrown, repeat use fails.
- `fixed-trajectory`: grenade behavior ignores aim direction.
- `bad-distance`: default throw distance is far outside the accepted envelope.

The global targetable damage sweep probe is maintained as a separate full
candidate project rather than an overlay. The historical wrong-projectile-model
score JSON remains under `evaluation/evidence/`, but that probe overlay has
been retired and is no longer materialized by this folder.

## Materialize Runnable Projects

Use a full candidate project as the base and generate runnable probe projects:

```powershell
$Verifier = "<path-to-this-repo>"
$BaseProject = "<path-to-full-candidate-project>"

python "$Verifier\evaluation\probes\materialize_probe_cases.py" `
  --base-project "$BaseProject" `
  --out "$Verifier\artifacts\probe-candidates" `
  --force
```

Then grade a generated case with the normal verifier command:

```powershell
$Godot = "<path-to-godot-4.6-console-executable>"

python "$Verifier\run_grader.py" `
  --project "$Verifier\artifacts\probe-candidates\hud-only" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\probe-hud-only-score.json"
```
