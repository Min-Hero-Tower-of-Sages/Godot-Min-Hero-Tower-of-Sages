shader_type canvas_item;

uniform vec3 rgb_multiplier = vec3(1.0);
uniform vec3 rgb_offset = vec3(0.0);
varying vec4 sprite_modulate;

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	// Flash ColorTransform adds the tint offset instead of darkening the bitmap.
	pixel.rgb = clamp(pixel.rgb * rgb_multiplier + rgb_offset, vec3(0.0), vec3(1.0));
	COLOR = pixel * sprite_modulate;
}
