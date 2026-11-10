shader_type canvas_item;
// Full-screen post effects driven by gameplay:
//   blur        — radial motion blur from the centre: smear length as a fraction of the
//                 distance to the centre (mild while running, heavy while dashing)
//   aberration  — RGB split towards the edges (hits, parries)
//   vignette    — red edge pulse (taking damage)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 0.0;
uniform float aberration = 0.0;
uniform float vignette = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.75, 0.04, 0.02, 1.0);
// Edge darkening for focus (charging).
uniform float darken = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	// Keep the middle (where your fighter is) sharp; the smear grows towards the edges.
	float reach = smoothstep(0.1, 0.42, length(dir * vec2(1.0, 0.8)));
	vec3 col = vec3(0.0);
	const int SAMPLES = 16;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		col += texture(screen_tex, uv - dir * t * blur * reach).rgb;
	}
	col /= float(SAMPLES);
	if (aberration > 0.001) {
		vec2 off = dir * aberration * 0.012;
		col.r = mix(col.r, texture(screen_tex, uv + off).r, 0.85);
		col.b = mix(col.b, texture(screen_tex, uv - off).b, 0.85);
	}
	float edge = smoothstep(0.32, 0.8, length(dir * vec2(1.0, 0.85)));
	col = mix(col, vignette_color.rgb, edge * vignette * 0.7);
	col *= 1.0 - edge * darken * 0.65;
	COLOR = vec4(col, 1.0);
}
