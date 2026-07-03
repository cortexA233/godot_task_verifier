# RoboBlast Grenade Feature Task

You are working on an ablated copy of a Godot third-person shooter demo. The game currently has movement, aiming, shooting, melee attacks, enemies, breakable crates, coins, jump pads, HUD elements, sounds, and visual assets. Your task is to implement a complete grenade weapon feature from scratch.

Treat this as a player-facing gameplay task, not a code-shape task. You may inspect and modify the project as needed, but do not look at git history, other branches, external verifier files, previous solutions, or online copies of this feature. Use only the current project and this specification.

## Goal

Add a second weapon mode: grenades. The player should be able to switch between the existing/default weapon behavior and a grenade mode. In grenade mode, attacking should throw an arcing grenade whether or not the aim button is held. The grenade should land or collide in the world, detonate, damage nearby enemies or breakable objects, and give clear visual/audio feedback.

The feature should feel integrated with the existing third-person shooter controls and presentation. Preserve all existing non-grenade behavior unless this task explicitly changes it.

## Controls And Weapon Switching

- The player starts in the default weapon mode.
- Pressing the weapon-switch control should toggle between default weapon mode and grenade mode.
- Keyboard players should be able to use `Tab` for weapon switching.
- Controller players should also have a reasonable weapon-switch input if the project already supports controller play.
- When default mode is selected:
  - Existing aim, shoot, and melee behavior should continue to work.
  - The player should not throw grenades.
- When grenade mode is selected:
  - Pressing attack should throw a grenade instead of firing the default projectile.
  - Pressing attack without holding aim should still throw a grenade.
  - Melee behavior should not trigger while grenade mode is selected; the player should switch back to the default weapon mode for default melee behavior.
  - Pressing attack during grenade cooldown should not fall back to melee or default shooting.
  - Grenade throwing should have a cooldown or rate limit so holding or spamming attack cannot create an uncontrolled stream of grenades.
- Switching modes should be reliable before and after throwing grenades.

## HUD And Player Feedback

- The HUD should clearly show that the player has two weapon choices: default weapon and grenades.
- The currently selected weapon should be visibly distinguishable.
- The selected weapon indicator should update immediately when the player switches modes.
- Existing aiming reticle/camera behavior should remain coherent.
- Grenade mode should be understandable without requiring debug text or editor-only indicators.
- The UI should not overlap, flicker, or permanently hide existing HUD information such as coins.

## Aiming Feedback

When grenade mode is selected:

- Show a visible trajectory preview, landing marker, or equivalent aiming aid before the grenade is thrown, even when the player is not holding the aim button.
- The aiming aid should communicate that the grenade will travel in an arc rather than in a straight bullet path.
- Without holding the aim button, grenade mode should use a stable default medium-range forward arc. Normal mouse or camera movement should not be required to fine-tune throw distance in this default throw state.
- While holding the aim button, moving the mouse or adjusting the camera aim should let the player control both the grenade's throw direction and throw distance by changing the predicted arc and landing area.
- The preview should update as the player changes aim direction or camera direction.
- The predicted landing/impact feedback should appear near the intended target area when possible.
- The aiming aid should remain visible during grenade cooldown so the player can keep lining up the next throw. It may show cooldown state, but it should not be deleted or hidden solely because the next grenade is not ready yet.
- The aiming aid should be hidden when:
  - The player switches back to the default weapon.
- The aiming aid should be visible in normal gameplay, not only in debug overlays.

## Grenade Throw And Flight

When the player throws a grenade:

- A visible grenade-like object should appear near the player and move into the world.
- It should travel as a physical arcing projectile influenced by gravity or an equivalent believable ballistic simulation.
- It should not instantly teleport to the target or apply damage with no flight phase.
- It should not immediately collide with or damage the player at spawn.
- It should interact plausibly with the environment:
  - It may bounce, roll, or settle after impact.
  - It should not pass through normal level geometry in common cases.
  - It should not fly forever.
- The throw direction should correspond to the player's current aim.
- Throws should remain deterministic and stable enough that repeated attempts behave consistently.

## Detonation

- A grenade should detonate after impact, after a short fuse, or after a combination of impact and fuse timing.
- The delay should be short enough to feel responsive in combat.
- Detonation should happen near the grenade's final flight/impact position.
- Each thrown grenade should detonate once.
- After detonation, temporary grenade and explosion objects should clean themselves up.
- Repeated throws should continue to work after earlier grenades have detonated.

## Explosion Gameplay Effect

The explosion should affect nearby damageable game objects.

- Nearby enemies should be damaged or defeated in a way consistent with the existing game. Knockback or other visible reactions are welcome as additional feedback, but should not replace a real damage or defeat effect.
- Nearby breakable crates or equivalent destructible targets should be damaged or broken.
- Multiple nearby targets should be affected by the same explosion.
- Distant enemies and distant destructible targets should not be affected.
- The player should not be damaged by their own grenade explosion.
- The explosion should not globally damage every target in the scene.
- Damage should be spatially based around the detonation point.

## Gameplay Tuning Expectations

The grenade should have sensible default tuning for normal third-person combat.

- A default forward throw should be useful at ordinary combat range, not only at point-blank range and not only at very long range.
- On flat ground, when the player faces a target area and attacks in grenade mode without holding aim, the grenade should land in a medium-distance area in front of the player, roughly 6-12 Godot units away.
- The explosion should affect targets within a few units of the detonation point.
- Targets clearly separated from the detonation point, such as targets well over ten units away, far to the side, behind the player, or the player themselves, should remain safe.
- Cooldown and fuse timing should allow repeated throws to be observed during normal play without producing an uncontrolled stream of grenades.
- Implementations may expose tuning values for throw range, explosion radius, cooldown, fuse, or gravity, but a specific configuration API is not required.

## Visual And Audio Feedback

- The thrown grenade should have a visible in-world representation.
- Detonation should produce a visible explosion effect at or very near the detonation point.
- The explosion should be noticeable from the normal gameplay camera.
- Detonation should play an appropriate explosion sound.
- Effects should not persist forever after they are finished.
- Visual and audio feedback should work for more than one throw.

## Stability And Integration

- The game should run without script errors.
- The main scene should still load and play normally.
- Existing movement, jumping, aiming, default shooting, default-mode melee attacks, enemies, crates, coins, and jump pads should not be broken by the grenade work.
- The implementation should tolerate repeated weapon switches and repeated grenade throws.
- Avoid test-only shortcuts, debug-only visuals, hard-coded one-off target damage, or behavior that only works in a single prearranged scene setup.
- Prefer using existing project style and Godot conventions where they are apparent.

## Suggested Manual Smoke Test

After implementing, manually verify this flow in the playable game:

1. Start the main game scene.
2. Confirm the default weapon mode is active and normal shooting/melee still works.
3. Press `Tab` and confirm the HUD indicates grenade mode.
4. Confirm a visible arcing trajectory or landing indicator appears in grenade mode before holding the aim button.
5. Move the camera or aim direction and confirm the trajectory/landing indicator updates.
6. Press attack without holding aim and confirm a grenade is thrown instead of a melee attack.
7. Confirm the trajectory/landing indicator remains visible during the grenade cooldown.
8. Confirm the grenade detonates near where it lands or collides.
9. Confirm nearby enemies or breakable objects are affected while distant targets are not.
10. Confirm the player is not harmed by their own explosion.
11. Throw a second grenade after the cooldown and confirm it also works.
12. Switch back to the default weapon and confirm normal shooting and melee still work.

## Deliverable

Implement the grenade weapon feature in the project. Leave the project in a runnable state and summarize what you changed, how to test it, and any limitations you are aware of.
