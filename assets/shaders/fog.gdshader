// Fog of war overlay drawn above all world sprites. fog_map holds one texel per
// tile: 0 = unexplored, ~0.5 = explored, 1 = visible. The lookup is jittered with
// the terrain noise and posterised with ordered dithering so edges stay pixel-art.
shader_type canvas_item;

uniform sampler2D fog_map : filter_linear;
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform vec2 map_size = vec2(96.0, 96.0);
uniform vec4 unexplored_color : source_color = vec4(0.03, 0.035, 0.05, 1.0);
uniform float explored_alpha = 0.48;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int idx = q.y * 4 + q.x;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

void fragment() {
	vec2 wp = floor(world_pos);
	vec2 g = vec2((wp.x / 32.0 + wp.y / 16.0) * 0.5, (wp.y / 16.0 - wp.x / 32.0) * 0.5);
	vec2 nz = texture(noise_tex, wp / 128.0).rg - 0.5;
	vec2 uv = (g + nz * 0.6) / map_size;
	float v = texture(fog_map, uv).r;
	if (g.x < 0.0 || g.y < 0.0 || g.x >= map_size.x || g.y >= map_size.y) {
		v = 0.0;
	}
	float d = bayer4(wp) - 0.5;
	// Two posterised steps: unexplored (black) and explored (dimmed).
	float explored = step(0.25, v + d * 0.18);
	float visible = step(0.75, v + d * 0.18);
	vec4 col = unexplored_color;
	col.a = 1.0 - explored * (1.0 - explored_alpha) - visible * explored_alpha;
	COLOR = col;
}
