shader_type spatial;
// First pass of the gummy material: writes the bear's nearest-surface depth
// and no colour, so the translucent colour pass (next_pass) only shades the
// front-most surface instead of blending limbs in triangle order.
// The colour pass's higher render_priority makes it draw after this pass.
render_mode blend_mix, depth_draw_always, cull_back, unshaded, shadows_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
