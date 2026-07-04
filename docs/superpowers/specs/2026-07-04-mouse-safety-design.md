# Verifier Mouse Safety Design

## Context

The exported verifier debug arena instantiates the candidate project's real
`res://player/player.tscn`. The RoboBlast player sets `Input.mouse_mode` to
`Input.MOUSE_MODE_CAPTURED` during startup, so running the debug arena in a
normal Godot window can trap the user's cursor inside the game window. This is a
manual-inspection hazard today and will also matter for future verifier checks
that run with a visible render-capable window instead of the default headless
driver.

The verifier should preserve real gameplay input behavior for scoring while
making any verifier-owned window safe to open. Throwing a grenade can still be
driven through Godot input actions, so cursor capture is only needed when a
human wants mouse-look aiming during manual inspection.

## Approaches

Recommended: add a reusable verifier mouse-safety helper. Verifier-owned scenes
install the helper, which defaults the mouse to visible, restores visibility
after candidate startup code captures it, lets F8 toggle temporary capture for
manual aiming, and makes Escape always release the mouse. Debug arena and future
windowed automation scenes can use the same helper, keeping the behavior
consistent.

Alternative: patch only `debug_arena.gd`. This fixes the immediate exported
scene, but future windowed verifier scenes could repeat the same trap unless
they remember to copy the behavior.

Alternative: run all manual and automated verifier scenes headless only. This
avoids cursor capture but removes the manual visual-inspection workflow and
blocks future rendered-window automation.

## Design

Add `verifier_godot/__verifier__/mouse_safety.gd` as a small `Node` helper:

- On ready, set `Input.mouse_mode` to `Input.MOUSE_MODE_VISIBLE`.
- During a finite startup guard window, keep restoring visible mode so candidate
  `_ready()` logic cannot immediately recapture the cursor.
- In `_unhandled_input`, release the cursor on Escape.
- In `_unhandled_input`, toggle between visible and captured mode on F8.
- Consume only the Escape and F8 events it handles.

Install the helper in verifier-owned scenes through a single helper function or
direct child node:

- `debug_arena.gd` installs mouse safety before and after it creates the real
  player, so the exported debug scene opens safely.
- `runner.gd` installs the same helper for verifier-owned runs so future
  windowed automation inherits the same safety behavior. Existing headless
  behavior remains deterministic and does not require cursor capture.

Manual input behavior:

- The debug arena starts with the cursor visible.
- Press F8 to temporarily capture the mouse for mouse-look aiming.
- Press Escape to release the mouse.
- Grenade throws continue to work through action-driven input and existing
  attack bindings.

## Testing

Add tests before implementation:

- Structural tests that `mouse_safety.gd` exists and contains the Escape
  release and F8 toggle behavior.
- Structural tests that `debug_arena.gd` installs the mouse-safety helper.
- Structural tests that `runner.gd` installs the mouse-safety helper for
  verifier-owned runs.
- A Godot-backed test, skipped when Godot is unavailable, that starts with
  captured mouse mode, instantiates the helper, waits a frame, and confirms the
  helper restores visible mode. The same script should send F8 and Escape input
  events and confirm capture toggles on and releases afterward.

## Acceptance Criteria

- Exported debug arenas open with a visible cursor even when the candidate
  player captures the mouse during startup.
- Escape reliably releases the cursor in verifier-owned scenes.
- F8 allows temporary mouse capture for manual aiming and can be toggled back.
- Existing headless grader behavior and action-driven grenade tests keep
  working.
- Future windowed verifier automation has a reusable mouse-safety path instead
  of copying debug-arena-specific code.
