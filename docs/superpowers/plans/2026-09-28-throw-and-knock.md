# Cycle 2a: Throw and Knock

Date: 2026-09-28. Agreed in chat (grilling session). The first half of cycle 2
(throwing and tag). Cycle 2b ("win the round": HUD, win screen, confetti,
stand-up reset) gets its own grilling after this one is playtested.

**Goal:** the red bear throws yellow dodgeballs, and a hit knocks a green bear
into a cartoon ragdoll flop that stays down.

## Decisions

- **Throw.** A new `throw` action: right trigger (axis 5) or left click. The
  click throws only while the mouse is captured; otherwise it still just
  recaptures (and the recapture click is released so it doesn't throw).
  Throwing is unlimited with a 0.3 s cooldown and no throw clip. The ball
  leaves the chest along the camera direction.
- **An idle bear turns to face a throw** (quickly, feet slide briefly).
  This amends ADR 0001's 2026-09-26 amendment.
- **Strong aim assist.** The throw bends toward the standing green bear best
  aligned with the camera, within ±30° and 10 m, leading its velocity. A
  bouncing yellow down-arrow **marker** floats over the next target. Downed
  bears are never targeted.
- **Ball.** Yellow dodgeball, 0.3 m across, bouncy, passes through the player.
  Any touch is a hit, even after a bounce. Hitting a bear counts as a bounce;
  it pops with a small burst after 3 bounces.
- **Green bears.** 5 of them, same mesh, lime `Color(0.15, 0.8, 0.25, 0.8)`,
  never recoloured. They wander slowly, and flee at 1.5 m/s when the player
  is within 4 m. A low candy fence keeps them on the 20×20 m ground.
- **Knock.** Hit = shove along the ball's path plus a small upward pop, then a
  ragdoll (`PhysicalBoneSimulator3D`, built in code). The bear stays down
  until the round resets (2b). Balls still knock downed bears around.
- **Not in 2a:** sound, HUD, win screen, confetti, victory hop, stand-up
  reset, the player nudging downed bears.

## Tasks

1. **Split the bear** (`scripts/gummy_bear.gd` becomes the shared body):
   colour, locomotion tree, gravity, `move_and_slide`, yaw toward a wished
   yaw, and `knock()` / `is_down()` with the code-built ragdoll. Subclasses
   `scripts/player_bear.gd` (input, camera, throw, aim assist, marker) and
   `scripts/green_bear.gd` (wander/flee, faces its velocity). Scenes
   `player_bear.tscn` and `green_bear.tscn` inherit `gummy_bear.tscn`;
   `CameraRig` moves to the player scene.
2. **Ragdoll** (from the headless probe): 11 bone shapes offset in metres,
   pairwise collision exceptions (Jolt doesn't disable joined bones), bones
   on layer/mask 0 until the knock, capsule disabled on knock, a
   `ScaleFix` modifier for the 0.333 rig scale, and skeleton physics
   interpolation off on knock only.
3. **Physics layers** (named in `project.godot`): 1 world, 2 bears,
   3 ragdolls, 4 balls.
4. **Ball** (`scripts/ball.gd`, `RigidBody3D`, contact monitor + CCD): hits
   via body contacts, knock direction from its pre-step velocity, bounce
   count, `CPUParticles3D` pop.
5. **Stage** (`scenes/test_stage.tscn`): player node renamed `Player`,
   5 seeded green bears, candy fence (no red or pink: the harness keys on
   red).
6. **Harness** (`scripts/test_stage.gd`), test-first: teleport one green
   bear ~3 m ahead along the camera, press `throw`, assert it's down within
   1.2 s, its ragdoll stayed on the stage, the player didn't drift, and the
   idle player turned toward the throw. `throw.png` and `knock.png` shots.
7. **Docs:** README controls and "How it works", `CONTEXT.md` terms (green
   bear, knocked down, aim assist, marker, candy fence), ADR 0001 amendment.

## Verify

- `$GODOT --path . -- --shots; echo "exit=$?"` → `exit=0`, cycle 1 numbers
  unchanged (rise ≈ 0.42, drive ≈ 2.46), plus the new throw/knock checks.
- Manual (you and your son, with the Xbox pad): the aim assist feels strong
  enough, the flop is funny, the marker reads, the green bears are
  catchable.
