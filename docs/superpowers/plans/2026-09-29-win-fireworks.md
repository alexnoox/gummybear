# Cycle 2b (part): Win Fireworks and Restart

Date: 2026-09-29. Asked for in chat after the 2a playtest: "once all the
bears are down, show a fireworks and then show a restart button". This
replaces the confetti and the automatic reset after 5 s from the 2a grilling.

**Goal:** knocking down the last green bear feels like a win, and the round
can be replayed without touching the keyboard.

## Decisions

- **Win** = every green bear knocked down (`scripts/round.gd` polls them).
- **Fireworks** (`scripts/fireworks.gd`): 0.8 s after the win the camera
  tilts gently up. Then rockets rise with a trail and burst into coloured
  sparks with a flash of light, 2–6 m either side of straight ahead (the
  bear would hide them otherwise). One every 0.4 s until restart.
- **Restart button** (`scripts/restart_button.gd`): 4 s after the win. It's
  a big yellow disc with a drawn circular arrow and no words; it pops in and
  pulses. It takes focus and frees the mouse, so A, Enter, Space or a click
  press it. There's no automatic restart.
- **Restart** reloads the stage, so every bear stands back where it started.
  The ragdoll blend-back (tween the simulator's influence to 0) isn't needed.
- **Not here:** the icon HUD of bears left, the victory hop, sound.

## Verify

- `--shots`: the harness knocks the remaining bears down itself and asserts
  the win within 0.2 s, at least one rocket, the button showing and focused,
  and the mouse freed. `fireworks.png` and `restart.png` are the shots to
  eyeball. The harness now swallows real mouse input, which kept orbiting
  the camera while someone used the machine.
- Manual: the fireworks read as a win, and A on the pad restarts.
