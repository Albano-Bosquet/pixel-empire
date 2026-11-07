// Flat silhouette of a unit hidden behind a tree or rock (OcclusionXray).
// Same look as xray.gdshader, but the prop's own pixels clip it right here: the
// clip_children used for buildings costs a render pass per object, too much for
// a forest full of woodcutters on a phone.
// Budget: two texture samples, no branches; any 2D renderer.
shader_type canvas_item;

// The props atlas and where the prop sits in it (x, y, width, height in texels).
uniform sampler2D mask_tex : filter_nearest;
uniform vec4 mask_rect;
// From this sprite's local pixels to the prop's top-left corner.
uniform vec2 shift;

// Opaque-pixel threshold of the pixel-art sheets (their alpha is 0 or 1).
const float SOLID_ALPHA = 0.5;

varying vec4 tint;
varying vec2 prop_px;

void vertex() {
	tint = COLOR;
	prop_px = VERTEX + shift;
}

void fragment() {
	vec2 inside = step(vec2(0.0), prop_px) * step(prop_px, mask_rect.zw);
	vec2 uv = (mask_rect.xy + prop_px) / vec2(textureSize(mask_tex, 0));
	float covered = step(SOLID_ALPHA, texture(mask_tex, uv).a) * inside.x * inside.y;
	COLOR = vec4(tint.rgb, step(SOLID_ALPHA, texture(TEXTURE, UV).a) * covered * tint.a);
}
