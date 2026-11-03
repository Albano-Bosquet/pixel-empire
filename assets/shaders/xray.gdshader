// Flat silhouette of a unit hidden behind a building (OcclusionXray).
// The draw colour (sprite modulate) is the tint; only the sprite's alpha is
// kept. The parent building sprite clips it, so it shows only where the
// building actually covers the unit.
// Budget: one texture sample, no branches; any 2D renderer.
shader_type canvas_item;

// Opaque-pixel threshold of the pixel-art sheets (their alpha is 0 or 1).
const float SOLID_ALPHA = 0.5;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float a = step(SOLID_ALPHA,texture(TEXTURE, UV).a);
	COLOR = vec4(tint.rgb, a * tint.a);
}
