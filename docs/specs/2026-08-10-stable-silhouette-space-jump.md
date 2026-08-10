# Stable Silhouette and Space Jump — Design

Date: 2026-08-10. Approved by user: remove both deformation sources; physics-only grounded jump on Space; preserve the five-action animation contract.

## Problem Statement

The gummy bear looks good overall, but its silhouette continuously expands, compresses, and shears during idle and locomotion. Idle animation scales the full rig between approximately 0.74× and 1.28× height, the four walk clips scale it between 0.84× and 1.16×, and acceleration-driven shader displacement can shift the upper silhouette by as much as 0.12 m. The character also cannot jump.

## Solution

Keep the bear's existing skeletal motion and material appearance while removing every source of animated silhouette scale and acceleration shear. Add a grounded physics jump bound to the physical Space bar. Jumping reuses the existing locomotion blend rather than expanding the Blender action set or adding an airborne animation state.

## User Stories

1. As a player, I want the bear to keep a stable overall size while idle, so that it no longer visibly breathes by stretching and squashing.
2. As a player, I want the bear to keep a stable overall size while walking in every direction, so that locomotion reads as a rigged walk rather than blobbing.
3. As a player, I want starts, stops, turns, takeoff, and landing not to shear the bear's upper silhouette, so that acceleration does not deform the character.
4. As a player, I want the bear's head, ears, arms, legs, and body to retain their authored rotational follow-through, so that removing scale deformation does not make the character static.
5. As a player, I want the gummy material, rim lighting, transparency, floor contact fade, and color cycling to remain unchanged, so that the accepted visual style is preserved.
6. As a player, I want Space to make the bear jump when grounded, so that the control is immediate and conventional.
7. As a player, I want an airborne Space press to do nothing, so that the bear cannot double jump.
8. As a player, I want gravity to return the bear to the floor after jumping, so that jumping integrates with the existing grounded controller.
9. As a player, I want WASD control to remain available in the air, so that a physics-only jump does not introduce a second movement model.
10. As a player, I want directional walking and third-person facing to remain unchanged before, during, and after a jump, so that the new control does not regress locomotion.
11. As a maintainer, I want the five existing animation names and export shape to remain exact, so that jump support does not expand the Blender/export/import contract unnecessarily.
12. As a maintainer, I want deformation removed at its authored and shader sources rather than patched after import, so that re-exporting the bear cannot restore the defect.
13. As a maintainer, I want automated evidence of takeoff, airborne state, rejected double jump, landing, and stable silhouette, so that future controller or asset changes can be checked end to end.
14. As a maintainer, I want the root source file and exported asset to preserve the 1 m height/floor contract, so that collision and shader floor behavior remain aligned.

## Implementation Decisions

- Remove acceleration-driven vertex displacement entirely. Retain only the shader's gummy color, rim, transparency, specular, roughness, and soft-contact behavior.
- Remove the controller spring constants, spring state, velocity-history state, update path, and per-instance wobble parameter writes. No dormant compatibility uniform or no-op code remains.
- Re-author idle and all four walk actions without scale channels on the root or head. Preserve rotation channels, leg-shortening translation, solved root height, loop seams, contact phase, and in-place motion.
- The idle action remains active. Each walk action remains stashed in its existing muted NLA track.
- The exact exported action set remains idle plus forward, backward, left, and right walk loops. No jump action is authored or exported.
- The exported character remains 1 m tall with its feet on the floor. Mesh, skin, joint, triangle, camera, and influence contracts remain unchanged.
- Add one input action mapped to physical Space.
- Add one named upward takeoff velocity. A newly pressed jump action applies it only when the character reports grounded.
- Existing gravity, horizontal acceleration, `move_and_slide`, WASD mapping, model yaw, and locomotion blend-position data flow remain the movement architecture.
- Horizontal movement continues to drive the existing locomotion blend while airborne. There is no jump pose, animation state machine, landing animation, coyote time, buffered input, variable jump height, or air-specific acceleration.
- Existing missing-animation behavior remains idle-only fallback with a warning.
- Never use Blender undo in authoring or export scripts. Asset changes are produced from the root Blender source and then exported normally; the GLB is never patched by hand.

## Testing Decisions

- The primary public seam is the running Godot stage under the deterministic harness. It exercises the same input actions, physics process, collision, animation tree, imported GLB, and shader used interactively.
- The harness will press and release the jump action rather than assigning vertical velocity directly. It will attempt a second press while airborne, capture takeoff/apex/landing frames, and record vertical position, vertical velocity, grounded state, and jump count evidence.
- The harness will retain a locomotion interval so a completed run covers both stable idle and stable walking silhouettes.
- Silhouette stability is checked from rendered output across idle and locomotion windows. Camera and scene are fixed, so large bounding-box size changes reveal renewed squash/stretch; pose-driven limb motion is expected and is not treated as a failure.
- The Blender/export seam retains source-action verification: exact action set, active idle action, loop ranges, constant extrapolation, NLA stashing, seam equality, in-place motion, and planted stance feet. Source actions must contain no scale channels. Blender's glTF exporter samples static transform channels, so exported scale samples must stay constant identity within floating-point tolerance.
- The GLB seam verifies the exact five animation names and the existing mesh/skin/joint/height/floor contracts after export.
- Godot import must complete successfully before the runtime harness. Runtime output must contain no new script, shader, animation, or input errors.
- Verification is behavioral: no source-text-only test substitutes for launching the stage and observing the completed jump cycle.

## Out of Scope

- A dedicated takeoff, airborne, apex, or landing animation.
- Any sixth Blender action or change to the exact five-action exporter contract.
- Coyote time, jump buffering, variable-height jumping, wall jumps, double jumps, or air-specific movement tuning.
- Camera movement, character rotation, run/sprint, stride TimeScale, or changes to the accepted 1.0 m/s movement speed.
- Reworking the gummy material beyond removing vertex displacement.
- Fixing the pre-existing iterator-shadow warning.
- Correcting accepted residual foot glide.

## Further Notes

- The diagnosed idle deformation is dominated by full-rig root scale, not shader wobble: a stationary idle capture varied from roughly 224 to 341 pixels in height under the fixed camera.
- Shader wobble is still a distinct locomotion/jump defect because its 0.12 m clamp permits a top-heavy shear of about 12% of exported character height under acceleration spikes.
- Removing both sources is the only considered approach that directly satisfies stable silhouette during both idle and locomotion. Removing only one leaves a confirmed deformation source active.
- Physics-only jump was selected to keep the asset/export contract stable and avoid an animation state expansion that the requested behavior does not require.
