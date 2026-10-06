shader_type canvas_item;

uniform sampler2D reveal_mask : filter_linear;
uniform vec2 art_origin;
uniform float mask_y = 646.0;
uniform float mask_x = 155.0;
uniform bool inverted = true;

void fragment() {
	vec4 art = texture(TEXTURE, UV) * COLOR;
	vec2 point = UV / TEXTURE_PIXEL_SIZE + art_origin - vec2(mask_x, mask_y);
	if (inverted) point.y = -point.y;
	vec2 mask_size = vec2(textureSize(reveal_mask, 0));
	float alpha = 0.0;
	if (point.x >= 0.0 && point.y >= 0.0 && point.x < mask_size.x && point.y < mask_size.y) {
		alpha = texture(reveal_mask, point / mask_size).a;
	}
	// The Flash mask combines its bitmap with this solid rectangle.
	if (point.x >= 0.0 && point.x <= 399.0 && point.y >= -322.0 && point.y <= 3.0) alpha = 1.0;
	COLOR = vec4(art.rgb, art.a * alpha);
}
