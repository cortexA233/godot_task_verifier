# Screenshot Visual Analysis Research

Date: 2026-07-04

## Local Context

The current branch, `codex/experimental-screenshot-visual-probe`, adds
experimental viewport screenshot helpers in `verifier_godot/__verifier__/scene_probe.gd`:

- `viewport_screenshot_signature(viewport, sample_step)`
- `frame_signature_delta(before, after)`
- `save_viewport_screenshot(viewport, output_path)`

The branch does not yet wire the screenshot signal into `runner.gd` scoring. The
existing verifier still scores `visual_audio_polish` through structural runtime
signals: moving projectile model checks, visible node creation, audio activity,
and cleanup.

Godot supports saving a viewport image through
`Viewport.get_texture().get_image().save_png(...)`, but the official docs warn
that the texture can be black or stale if captured too early and recommend
waiting for `RenderingServer.frame_post_draw` before saving. Godot's command
line docs also state that `--headless` enables `--display-driver headless` and a
dummy audio driver. This matters because the current verifier runs headlessly by
default, so any screenshot-based scoring needs a calibrated rendered display
path rather than assuming the headless run exposes useful pixels.

Sources:

- Godot Viewport `get_texture()` docs: https://docs.godotengine.org/en/stable/classes/class_viewport.html
- Godot command line `--headless` docs: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html

## Similar Approaches

### 1. Visual regression testing

Tools such as Playwright screenshot assertions, Applitools Eyes, Percy, and
Chromatic all use a similar loop:

1. Drive the application to a deterministic state.
2. Wait until rendering is stable.
3. Capture one or more screenshots, often at fixed viewport sizes.
4. Compare the new screenshots against approved baselines.
5. Apply thresholds, masks, ignore regions, match levels, or layout-focused
   comparison to avoid false positives.
6. Require human review when the visual difference may be intentional.

Playwright generates reference screenshots on first run and compares later runs,
with configurable pixel-difference tolerances. It explicitly warns that
rendering can vary across OS, hardware, browser, headless mode, fonts, and other
environment details, so baselines should be produced in the same environment
where tests run.

Applitools describes visual testing as checkpoints compared against stored
baselines, with review/accept/reject workflow. Its newer Visual AI settings let
tests choose match strictness, screenshot type, and ignored shifts.

Percy and Chromatic add hosted review workflows, cross-browser or multi-viewport
snapshotting, baseline management, and visual diffs. Chromatic documents waiting
for render completion, cropping screenshots, diffing against previous baselines,
and pausing CSS animations/videos to reduce false positives.

Sources:

- Playwright visual comparisons: https://playwright.dev/docs/test-snapshots
- Applitools visual UI testing overview: https://applitools.com/docs/eyes/getting-started/overview
- Applitools Visual AI options: https://applitools.com/docs/autonomous/authoring-a-test/custom-flow-test/visual-ai-options
- Percy visual testing basics: https://www.browserstack.com/docs/percy/overview/visual-testing-basics
- Chromatic snapshots: https://www.chromatic.com/docs/snapshots/

### 2. Pixel-diff libraries

Libraries such as `pixelmatch` compare two equal-sized images and return a count
of mismatched pixels, optionally writing a diff image. Its options include a
threshold from 0 to 1 and anti-aliasing handling. This is the low-level version
of what many screenshot regression tools use internally.

This is closest to the current branch's `frame_signature_delta`, but the
production pattern usually compares fixed regions or baselines, not a sparse
whole-frame average. Whole-frame averages can hide small but important effects,
while camera jitter, lighting, UI animation, or particles can dominate the
signal.

Source:

- pixelmatch README: https://github.com/mapbox/pixelmatch

### 3. Image-recognition UI and game automation

SikuliX and Airtest are closer to "game screenshot analysis" than web UI visual
regression.

SikuliX automates visual workflows by capturing small screen images and finding
them on the current screen. Its docs say it uses OpenCV `matchTemplate()` and
recommend constraining the search region when multiple similar visual elements
exist. SikuliX also requires a real screen or equivalent virtual solution.

Airtest targets games and apps. Its docs describe cross-platform automation that
uses image recognition to locate UI elements without injecting code. Tests can
use `touch(Template(...))`, `swipe(Template(...), Template(...))`, and
`assert_exists(Template(...))`, plus screenshot-rich HTML reports.

The pattern here is template/feature presence, not full-scene scoring: search
for expected visual elements in constrained regions and time windows, with
confidence thresholds and debug artifacts.

Sources:

- SikuliX introduction and image matching: https://sikulix.github.io/docs/
- Airtest documentation: https://airtest.readthedocs.io/en/latest/README_MORE.html

### 4. Screenshot-based multimodal agent benchmarks

VisualWebArena, WebVoyager, and OSWorld show the current AI benchmark pattern:
screenshots are used as observations for agents, often paired with text,
accessibility trees, DOM/element metadata, or execution state. Evaluation is
usually not a simple pixel diff. It is either execution-based, based on custom
task checks, or sometimes assisted by a multimodal model for open-ended web
tasks.

For this verifier, the key lesson is to avoid treating a vision model or broad
visual similarity score as the sole oracle. Screenshot interpretation can help
with evidence and qualitative review, but a reproducible benchmark should keep
hard pass/fail grounded in controlled task state where possible.

Sources:

- VisualWebArena paper: https://arxiv.org/abs/2401.13649
- WebVoyager paper: https://arxiv.org/abs/2401.13919
- OSWorld project: https://os-world.github.io/

### 5. Game benchmarks using pixels as observations

The Arcade Learning Environment exposes Atari observations as RGB image frames,
grayscale frames, or RAM. It also documents reward dynamics, stochasticity
controls, frame skipping, sticky actions, and rendering modes. This is useful
context because it separates "pixels as observation" from "pixels as score":
agents may act from pixels, but the final reward usually comes from the emulator
environment, not a screenshot judge.

Source:

- Arcade Learning Environment docs: https://ale.farama.org/environments/

## Implications For This Verifier

The current branch is a good exploratory step, but the screenshot signal should
not be promoted directly into scoring yet.

Recommended path:

1. Keep screenshot helpers behind an auxiliary/evidence layer until there is a
   deterministic rendered run mode. A Godot `--headless` run should remain the
   default scoring path unless a real or virtual display path is calibrated.
2. Replace sparse whole-frame averages with task-specific visual probes:
   projectile silhouette/size/visibility in a camera-aligned region, explosion
   flash/particle presence near the expected screen-space detonation point, and
   cleanup across a fixed time window.
3. Capture multiple frames around known verifier events rather than one before
   and one after image. Effects are transient, so the verifier should look for
   peak signal across a deterministic window.
4. Save screenshots and, eventually, diff overlays as report evidence first.
   This is valuable even before pixels affect score.
5. If pixels affect score, make them a small corroborating signal inside
   `visual_audio_polish`, not a replacement for physics, damage, projectile
   tracking, and scene-probe checks.
6. Calibrate against the reference, the existing rollout attempts, and the
   anti-cheat probes. Add a dedicated visual-only false-positive probe and a
   no-visible-effect-but-correct-logic probe before changing pass thresholds.
7. Document the rendering environment, viewport size, camera pose, sample
   regions, thresholds, and failure artifacts in `README.md`, `BENCHMARK.md`,
   and `probe_matrix.md` if screenshot scoring graduates from experiment.

