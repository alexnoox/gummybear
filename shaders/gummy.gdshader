shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

instance uniform vec4 gummy_color : source_color = vec4(0.9, 0.08, 0.15, 0.8);
uniform float rim_strength = 0.35;
uniform float contact_fade_dist = 0.08;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;


void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = gummy_color.rgb;
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
	EMISSION = gummy_color.rgb * fres * rim_strength; // candy rim glow
	float alpha = clamp(gummy_color.a + fres * 0.25, 0.0, 1.0); // denser-looking edges
	// soft-contact depth fade against scene behind
	float depth_raw = texture(depth_texture, SCREEN_UV).x;
	vec4 view_p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_depth = -view_p.z / view_p.w;
	float frag_depth = -VERTEX.z; // view space here
	alpha *= clamp((scene_depth - frag_depth) / contact_fade_dist, 0.0, 1.0);
	ALPHA = alpha;
}
