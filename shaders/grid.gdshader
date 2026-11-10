shader_type spatial;
// World-space grid so speed and distance are easy to read.

uniform vec4 base_color : source_color = vec4(0.09, 0.11, 0.14, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.7, 0.95, 1.0);
uniform float cell_size = 2.0;
uniform float line_width = 0.04;
uniform float major_every = 5.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float cell, float width) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	float d = min(g.x, g.y);
	float aa = fwidth(d) * 1.5;
	return 1.0 - smoothstep(width, width + aa, d);
}

void fragment() {
	float minor = grid_line(world_pos.xz, cell_size, line_width);
	float major = grid_line(world_pos.xz, cell_size * major_every, line_width * 2.0);
	float line = max(minor * 0.35, major * 0.8);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line * 0.6);
	EMISSION = line_color.rgb * line * 0.3;
	ROUGHNESS = 0.8;
	METALLIC = 0.2;
}
