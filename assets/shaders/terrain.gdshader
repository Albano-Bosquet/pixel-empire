// Terrain renderer: one quad covering the map. Each fragment converts its
// world pixel to grid space, jitters the lookup with noise (organic, dithered
// borders between terrain types) and samples a 64x64 tiling pixel-art texture
// from the terrain atlas. Water is animated and gets shoreline foam.
shader_type canvas_item;

uniform sampler2D atlas : filter_nearest;
uniform sampler2D terrain_map : filter_nearest;
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform vec2 map_size = vec2(96.0, 96.0);
uniform float border_jitter = 0.42;
uniform vec4 void_color : source_color = vec4(0.05, 0.06, 0.08, 1.0);

const float TILE_PX = 64.0;
const int WATER_MAX_ID = 1; // ids 0 (deep) and 1 (shallow) are water

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

vec2 to_grid(vec2 w) {
	return vec2((w.x / 32.0 + w.y / 16.0) * 0.5, (w.y / 16.0 - w.x / 32.0) * 0.5);
}

int terrain_at(vec2 g) {
	ivec2 t = clamp(ivec2(floor(g)), ivec2(0), ivec2(map_size) - 1);
	return int(texelFetch(terrain_map, t, 0).r * 255.0 + 0.5);
}

vec4 sample_terrain(int id, vec2 p) {
	ivec2 q = ivec2(mod(p, TILE_PX));
	return texelFetch(atlas, ivec2(id * int(TILE_PX) + q.x, q.y), 0);
}

void fragment() {
	vec2 wp = floor(world_pos);
	vec2 g = to_grid(wp + 0.5);
	if (g.x < 0.0 || g.y < 0.0 || g.x >= map_size.x || g.y >= map_size.y) {
		COLOR = void_color;
	} else {
		vec4 nz = texture(noise_tex, wp / 128.0);
		vec2 gj = g + (nz.rg - 0.5) * 2.0 * border_jitter;
		int id = terrain_at(gj);
		vec2 p = wp;
		bool water = id <= WATER_MAX_ID;
		if (water) {
			float step_t = floor(TIME * 6.0) / 6.0;
			p.x += floor(sin(wp.y * 0.21 + step_t * 2.0) * 1.6 + step_t * 3.0);
			p.y += floor(step_t * 1.5);
		}
		vec4 col = sample_terrain(id, p);
		if (water) {
			// Shoreline foam: land within ~0.3 tiles of this water pixel.
			float land = 0.0;
			land += float(terrain_at(gj + vec2(0.3, 0.0)) > WATER_MAX_ID);
			land += float(terrain_at(gj - vec2(0.3, 0.0)) > WATER_MAX_ID);
			land += float(terrain_at(gj + vec2(0.0, 0.3)) > WATER_MAX_ID);
			land += float(terrain_at(gj - vec2(0.0, 0.3)) > WATER_MAX_ID);
			if (land > 0.0) {
				float wave = step(0.5, fract(nz.b * 3.0 + TIME * 0.35));
				col.rgb = mix(col.rgb, vec3(0.80, 0.93, 0.96), 0.30 + 0.35 * wave);
			}
		} else if (id == 2) {
			// Wet sand right next to water.
			float wet = float(terrain_at(gj + vec2(0.25, 0.25)) <= WATER_MAX_ID) + float(terrain_at(gj - vec2(0.25, 0.25)) <= WATER_MAX_ID);
			col.rgb *= 1.0 - 0.12 * min(wet, 1.0);
		}
		// Low-frequency, posterised brightness variation breaks up repetition.
		float macro = texture(noise_tex, wp / 900.0).b;
		col.rgb *= 1.0 + (floor(macro * 4.0) / 3.0 - 0.5) * 0.10;
		// Darken the outermost tiles so the map edge reads as a border.
		float edge = min(min(g.x, g.y), min(map_size.x - g.x, map_size.y - g.y));
		if (edge < 1.2) {
			col.rgb *= mix(0.45, 1.0, floor(edge / 1.2 * 3.0) / 3.0);
		}
		COLOR = col;
	}
}
