// Terrain renderer: one quad covering the map. Each fragment converts its
// world pixel to grid space, jitters the lookup with noise (organic, dithered
// borders between land types) and blends the 64x64 tiling pixel-art textures
// of the four nearest tiles from the terrain atlas, so biomes fade into each
// other over about a tile instead of meeting at a hard edge.
// Water is painted here, not from the atlas: a bilinear "distance to land"
// field (depth_map, built by TerrainRenderer) gives a smooth coastline and
// calm depth bands (turquoise shallows -> deep blue), dithered to pixels.
// Animation is deliberately slow: a foam line that ebbs and flows on the
// shore, a wave line rolling in, faint drifting ripples and rare glints.
// Cliffs are painted here too: the green channel of depth_map outlines raised
// ground, whose camera-facing edges get a rock wall (a pixel is wall when the
// cliff line lies within cliff_height below it) and whose rest is a plateau
// top. The rim under the walls is impassable MOUNTAIN; PLATEAU behind it is
// walkable, and the blue channel marks RAMP cuts where no wall is painted.
// Target: gl_compatibility on PC and Android; cliff sampling only runs on and
// right below mountain tiles.
shader_type canvas_item;

uniform sampler2D atlas : filter_nearest;
uniform sampler2D terrain_map : filter_nearest;
uniform sampler2D depth_map : filter_linear;
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform sampler2D noise_smooth : filter_linear, repeat_enable;
uniform vec2 map_size = vec2(96.0, 96.0);
uniform float depth_scale = 8.0; // tiles encoded by depth_map value 1.0
uniform float border_jitter = 0.34;
uniform float coast_wobble = 0.16;
uniform vec3 wet_sand = vec3(0.84, 0.80, 0.76); // tint of sand the waves reached
uniform float cliff_height = 42.0; // wall height in world pixels
uniform float cliff_jag = 18.0; // slow variation of that height along the cliff
uniform float cliff_chip = 4.0; // block-by-block notches on the wall's top edge
uniform float cliff_rim = 11.0; // rock crest along the plateau's far edge, in pixels
uniform float cliff_wobble = 0.30; // how far the cliff line wanders off the tile edges
uniform float cliff_shadow = 0.72; // brightness of the ground at the wall's foot
uniform vec3 grass_dry = vec3(1.07, 1.03, 0.86); // sun-dried grass tint
uniform vec3 grass_lush = vec3(0.93, 1.03, 0.94); // lush grass tint
uniform vec4 void_color : source_color = vec4(0.05, 0.06, 0.08, 1.0);
uniform vec3 water_0 : source_color = vec3(0.392, 0.761, 0.831); // shallows
uniform vec3 water_1 : source_color = vec3(0.243, 0.627, 0.835);
uniform vec3 water_2 : source_color = vec3(0.169, 0.522, 0.796);
uniform vec3 water_3 : source_color = vec3(0.149, 0.455, 0.776);
uniform vec3 water_4 : source_color = vec3(0.125, 0.396, 0.718); // open sea
uniform vec3 foam_color : source_color = vec3(0.90, 0.96, 0.97);

const float TILE_PX = 64.0;
const int WATER_MAX_ID = 1; // ids 0 (deep) and 1 (shallow) are water
const int SAND_ID = 2;
const int ROCKY_ID = 8;
const int MOUNTAIN_ID = 9;
const int DESERT_ID = 10;
const int PLATEAU_ID = 11;
const float RAMP_REACH = 0.02; // ramp field value where cliff painting gives way to blended ground
const int CLIFF_ID = 13; // atlas entry only: the wall texture
const int GRASS_FIRST_ID = 3; // grass, meadow and forest floor take the lush tint
const int GRASS_LAST_ID = 5;
const float LIT_FACE = 1.05; // south-west walls face the light...
const float SHADE_FACE = 0.84; // ...south-east walls do not
const float WALL_LOW = 0.86; // the foot of a wall is darker than its top
const float WALL_MID = 0.94;
const float MACRO_STEPS = 6.0; // brightness levels of the broad ground variation
const float MACRO_AMOUNT = 0.07; // its total range
const float CLIFF_BLOCK = 13.0; // width of the notches on a wall's top edge
const float BAYER[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};

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

// The ground a land pixel blends from: water tiles count as beach, and the
// cliff rim as rocky ground.
int ground_id(vec2 g) {
	int id = terrain_at(g);
	if (id <= WATER_MAX_ID) {
		return SAND_ID;
	}
	return id == MOUNTAIN_ID ? ROCKY_ID : id;
}

float is_grass(int id) {
	return (id >= GRASS_FIRST_ID && id <= GRASS_LAST_ID) ? 1.0 : 0.0;
}

float is_sand(int id) {
	return (id == SAND_ID || id == DESERT_ID) ? 1.0 : 0.0;
}

vec4 sample_terrain(int id, vec2 p) {
	ivec2 q = ivec2(mod(p, TILE_PX));
	return texelFetch(atlas, ivec2(id * int(TILE_PX) + q.x, q.y), 0);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	return (BAYER[q.x + q.y * 4] + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 water_band(int k) {
	if (k <= 0) return water_0;
	if (k == 1) return water_1;
	if (k == 2) return water_2;
	if (k == 3) return water_3;
	return water_4;
}

// Above 0 on the plateau, below 0 off it; the 0 contour is the cliff line.
float plateau_at(vec2 w) {
	float wob = (texture(noise_smooth, w / 90.0).g - 0.5) * 2.0 * cliff_wobble;
	return texture(depth_map, to_grid(w) / map_size).g * depth_scale + wob - 0.5;
}

// A mountain pixel: rock wall if the cliff line is just below it, else plateau.
vec4 paint_mountain(vec2 wp) {
	float h = cliff_height + (texture(noise_smooth, vec2(wp.x / 80.0, 0.31)).r - 0.5) * cliff_jag
		+ (hash(vec2(floor(wp.x / CLIFF_BLOCK), 5.0)) - 0.5) * cliff_chip;
	// No wall above a ramp: the ground climbs straight onto the plateau.
	float ramp_ahead = max(texture(depth_map, to_grid(wp + vec2(0.0, h * 0.5)) / map_size).b,
		texture(depth_map, to_grid(wp + vec2(0.0, h)) / map_size).b);
	if (ramp_ahead > 0.5) {
		return sample_terrain(PLATEAU_ID, wp);
	}
	float low = plateau_at(wp + vec2(0.0, h * 0.34));
	float mid = plateau_at(wp + vec2(0.0, h * 0.67));
	float high = plateau_at(wp + vec2(0.0, h));
	if (min(low, min(mid, high)) >= 0.0) {
		// Far edge: a low crest of the same rock closes the plateau.
		float rim = cliff_rim + (hash(vec2(floor(wp.x / CLIFF_BLOCK), 9.0)) - 0.5) * cliff_chip;
		if (plateau_at(wp - vec2(0.0, rim)) < 0.0) {
			return sample_terrain(CLIFF_ID, wp);
		}
		vec4 top = sample_terrain(PLATEAU_ID, wp);
		// Sunlit lip along the wall's top edge.
		if (plateau_at(wp + vec2(0.0, h + 3.0)) < 0.0) {
			top.rgb *= 1.16;
		}
		return top;
	}
	// Which way the wall faces, from the field's slope; its strata run along
	// the cliff line, so the texture is sheared to the iso edge it follows.
	float side = plateau_at(wp + vec2(8.0, 0.0)) >= plateau_at(wp - vec2(8.0, 0.0)) ? 1.0 : -1.0;
	vec4 wall = sample_terrain(CLIFF_ID, floor(vec2(wp.x, wp.y - side * 0.5 * wp.x)));
	wall.rgb *= side > 0.0 ? LIT_FACE : SHADE_FACE;
	wall.rgb *= low < 0.0 ? WALL_LOW : (mid < 0.0 ? WALL_MID : 1.0);
	return wall;
}

// Short horizontal glints that fade in and out now and then (open water only).
float glint(vec2 wp) {
	vec2 cell_size = vec2(30.0, 15.0);
	vec2 cell = floor(wp / cell_size);
	float h = hash(cell);
	if (h > 0.24) {
		return 0.0;
	}
	vec2 local = wp - cell * cell_size;
	float gx = 4.0 + floor(hash(cell + 7.1) * 18.0);
	float gy = 3.0 + floor(hash(cell + 3.7) * 9.0);
	float len = 3.0 + floor(hash(cell + 1.3) * 3.0);
	float pulse = sin(floor(TIME * 8.0) / 8.0 * 0.9 + h * 61.0);
	if (pulse < 0.72) {
		return 0.0;
	}
	float strength = (pulse - 0.72) / 0.28;
	if (local.y == gy && local.x >= gx && local.x < gx + len) {
		return 0.35 + 0.45 * strength;
	}
	if (local.y == gy + 1.0 && local.x >= gx + 1.0 && local.x < gx + len - 1.0) {
		return 0.20 * strength;
	}
	return 0.0;
}

// Short light wave strokes with curled ends, scattered over the water.
float strokes(vec2 wp) {
	vec2 p = wp + floor(vec2(TIME * 2.0, TIME * 0.7));
	vec2 cell_size = vec2(22.0, 9.0);
	vec2 cell = floor(p / cell_size);
	float h = hash(cell + 19.0);
	if (h > 0.55) {
		return 0.0;
	}
	float fade = clamp(sin(TIME * 0.5 + h * 40.0) * 2.0, 0.0, 1.0);
	vec2 local = p - cell * cell_size;
	float sx = 1.0 + floor(hash(cell + 5.3) * 13.0);
	float sy = floor(hash(cell + 2.9) * 7.0);
	float len = 3.0 + floor(hash(cell + 8.1) * 5.0);
	if (local.y == sy && local.x >= sx && local.x < sx + len) {
		return fade;
	}
	if (local.y == sy + 1.0 && (local.x == sx - 1.0 || local.x == sx + len)) {
		return 0.6 * fade;
	}
	return 0.0;
}

void fragment() {
	vec2 wp = floor(world_pos);
	vec2 g = to_grid(wp + 0.5);
	if (g.x < 0.0 || g.y < 0.0 || g.x >= map_size.x || g.y >= map_size.y) {
		COLOR = void_color;
	} else {
		vec4 nz = texture(noise_tex, wp / 128.0);
		vec2 gj = g + (nz.rg - 0.5) * 2.0 * border_jitter;
		// Smooth coast: the bilinear depth field, lightly wobbled.
		float wob = (texture(noise_smooth, wp / 110.0).r - 0.5) * 2.0 * coast_wobble;
		vec3 field = texture(depth_map, g / map_size).rgb;
		float depth = field.r * depth_scale + wob;
		float shore = depth - 0.5; // 0 on the coastline, > 0 out at sea
		float ebb = 0.5 + 0.5 * sin(TIME * 0.9 + texture(noise_smooth, wp / 300.0).b * 12.0);
		vec4 col;
		if (shore > 0.0) {
			// Depth bands, nudged by a slow drifting swell, ordered-dithered.
			float swell = texture(noise_smooth, wp / 260.0 + vec2(TIME * 0.010, TIME * 0.004)).b
				+ texture(noise_smooth, wp / 190.0 - vec2(TIME * 0.007, -TIME * 0.009)).g - 1.0;
			float t = clamp(shore / 3.6 + swell * 0.16, 0.0, 1.0);
			int k = int(floor(t * 4.0 + 0.5 + (bayer4(wp) - 0.5) * 0.85));
			col = vec4(water_band(clamp(k, 0, 4)), 1.0);
			// Faint wave strokes drifting a pixel at a time, fading in and out.
			col.rgb = mix(col.rgb, foam_color, 0.16 * strokes(wp));
			if (shore > 0.9) {
				col.rgb = mix(col.rgb, foam_color, glint(wp));
			}
			// Shore foam that ebbs and flows, and a wave line rolling in.
			float foam_w = 0.06 + 0.10 * ebb;
			if (shore < foam_w) {
				col.rgb = mix(col.rgb, foam_color, 0.80);
			} else if (shore < foam_w + 0.07) {
				col.rgb = mix(col.rgb, foam_color, 0.35);
			}
			float roll = fract(TIME * 0.12 + texture(noise_smooth, wp / 240.0).r * 0.5);
			float wave_at = 0.10 + (1.0 - roll) * 0.75;
			if (abs(shore - wave_at) < 0.03 + 0.02 * roll) {
				col.rgb = mix(col.rgb, foam_color, 0.42 * roll);
			}
		} else if (field.g > 0.0 && field.b < RAMP_REACH && plateau_at(wp) > 0.0) {
			col = paint_mountain(wp);
		} else {
			// Land: the four nearest tiles, weighted by how close this pixel is
			// to each, so one biome fades into the next. Next to the sea the
			// water tiles count as sand, which makes the beach fade in too.
			vec2 q = gj - 0.5;
			vec2 cell = floor(q) + 0.5;
			vec2 f = smoothstep(0.0, 1.0, fract(q));
			int a = ground_id(cell);
			int b = ground_id(cell + vec2(1.0, 0.0));
			int c = ground_id(cell + vec2(0.0, 1.0));
			int d = ground_id(cell + vec2(1.0, 1.0));
			vec4 w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
			col = sample_terrain(a, wp);
			if (a != b || a != c || a != d) {
				col = col * w.x + sample_terrain(b, wp) * w.y + sample_terrain(c, wp) * w.z + sample_terrain(d, wp) * w.w;
			}
			float green = dot(w, vec4(is_grass(a), is_grass(b), is_grass(c), is_grass(d)));
			float sandy = dot(w, vec4(is_sand(a), is_sand(b), is_sand(c), is_sand(d)));
			// Broad, non-repeating dry and lush areas, stepped by dither.
			float lush = texture(noise_smooth, wp / 520.0).g * 0.6 + texture(noise_smooth, wp / 210.0).r * 0.4;
			float step_t = floor(clamp((lush - 0.3) * 2.5, 0.0, 1.0) * 4.0 + bayer4(wp)) / 4.0;
			col.rgb *= mix(vec3(1.0), mix(grass_dry, grass_lush, step_t), green);
			// The wall's shadow on the ground at its foot.
			if (field.b < RAMP_REACH && texture(depth_map, to_grid(wp - vec2(4.0, 6.0)) / map_size).g > 0.0
					&& (plateau_at(wp - vec2(0.0, 7.0)) > 0.0 || plateau_at(wp - vec2(9.0, 5.0)) > 0.0)) {
				col.rgb *= cliff_shadow;
			}
			// Wet sand where the last wave reached.
			if (shore > -(0.07 + 0.10 * ebb)) {
				col.rgb *= mix(vec3(1.0), wet_sand, sandy);
			}
			// Low-frequency brightness variation breaks up repetition; dithered
			// steps, so flat ground shows no hard-edged blobs.
			float macro = texture(noise_smooth, wp / 900.0).b;
			col.rgb *= 1.0 + (floor(macro * MACRO_STEPS + bayer4(wp)) / MACRO_STEPS - 0.5) * MACRO_AMOUNT;
		}
		// Darken the outermost tiles so the map edge reads as a border.
		float edge = min(min(g.x, g.y), min(map_size.x - g.x, map_size.y - g.y));
		if (edge < 1.2) {
			col.rgb *= mix(0.45, 1.0, floor(edge / 1.2 * 3.0) / 3.0);
		}
		COLOR = col;
	}
}
