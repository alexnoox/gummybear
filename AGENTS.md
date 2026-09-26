# gummy-bear

Godot 4 third-person character project. The bear's mesh, rig and idle action
are hand-maintained in Blender (`gummy-bear.blend`); `blender/walk_actions.py`
authors the walk loops and `blender/export_bear.py` exports `assets/bear.glb`.
Gameplay lives in `scripts/gummy_bear.gd` and `scripts/orbit_camera.gd`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `alexnoox/gummybear` (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root (created lazily by `/domain-modeling`). See `docs/agents/domain.md`.
