# Rendered Visual Probe Design

## Context

`game_take_home.html` explicitly encourages verifier checks that look at rendered
frames, screenshots, pixels, or regions instead of relying only on internal game
state. The current verifier already observes visible nodes, audio players, and
runtime activity, but `visual_audio_polish` does not inspect viewport pixels.

Godot 4.6's `--headless` mode uses the headless display driver and dummy
rendering driver. A local probe confirmed that direct viewport texture capture is
unavailable in that mode, while the same script can capture pixels when Godot
runs with the normal Windows display driver. The verifier must therefore keep
the deterministic headless path stable and add rendered-frame evidence without
making correct candidates lose points just because the default grader command is
headless.

## Approaches

Recommended: add an opportunistic viewport pixel-change probe to
`visual_audio_polish`. The runner captures a small viewport signature before and
during the grenade visual window. When a render texture is available, a
meaningful pixel delta earns the rendered-frame visual detail. When the texture
is unavailable, the detail falls back to the existing runtime-visible evidence
and records that the rendered pixel path was unavailable under the active driver.
This gives a real rendered check in render-capable runs while preserving the
current headless verifier contract.

Alternative: switch the default grader run from `--headless` to a hidden
render-capable window. This would make pixel checks first-class by default, but
it conflicts with the repository's headless-execution rule and is riskier for
CI-like environments.

Alternative: add only screen-space geometry checks through a verifier camera.
This is fully headless-compatible and catches effects that spawn outside the
visible play area, but it is not a rendered-frame or pixel check.

## Design

Add a small rendered-frame helper in `SceneProbe`:

- `viewport_frame_signature(viewport, sample_step)` returns a structured
  signature with `available`, image size, sampled pixel count, and average RGB
  values. If `viewport.get_texture()` is unavailable, it returns
  `available: false`.
- `frame_signature_delta(before, after)` returns a normalized color delta when
  both signatures are available.

Update `visual_audio_polish` from three details to four details while keeping
the category at 5 points:

```text
Visible runtime effect nodes      1
Rendered frame pixel activity     1
Detonation audio                  2
Temporary node cleanup            1
```

The rendered-frame detail should score from pixel delta when rendering is
available. If rendering is unavailable, it may score only when visible runtime
effect nodes were observed, and its notes must say that the pixel path was
unavailable under the active display/rendering driver. This prevents default
headless runs from losing a point for infrastructure reasons while making
render-capable runs stricter.

The helper should be generic enough for future screenshot artifacts. This scoped
change will not add artifact file output; the score JSON's existing
`artifacts.screenshots` field remains empty until the render-pass policy is
settled in a separate task.

## Testing

Add tests before implementation:

- Structural tests that `SceneProbe` exposes viewport signature and delta
  helpers.
- Structural tests that `visual_audio_polish` contains the rendered-frame detail
  and keeps the 5-point category max.
- A Godot-backed test, skipped when Godot is unavailable, that runs a temporary
  render-capable project without `--headless`, draws a `ColorRect`, captures two
  viewport signatures, and verifies that the helper reports a positive pixel
  delta.
- Existing headless tests continue to pass.

## Acceptance Criteria

- The default verifier command remains headless.
- Total score remains 100.
- `visual_audio_polish` still awards at most 5 points.
- Render-capable runs can detect real viewport pixel changes.
- Headless dummy-renderer runs do not fail or lose score solely because viewport
  texture capture is unavailable.
- README and benchmark docs mention that rendered-frame checks are opportunistic
  under Godot 4.6 headless constraints.
