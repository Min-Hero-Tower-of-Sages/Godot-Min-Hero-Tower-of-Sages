shader_type canvas_item;

// Texture-independent preview shader. A whole evolution line shares these
// settings; source_hue < 0 recolors every chromatic hue for generic models.
uniform float hue_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float saturation_scale : hint_range(0.0, 2.0) = 1.0;
uniform float value_scale : hint_range(0.0, 2.0) = 1.0;
uniform float source_hue : hint_range(-1.0, 1.0) = -1.0;
uniform float hue_width : hint_range(0.0, 0.5) = 0.18;
// Optional unified hue handles lines whose thaw/evolution colors differ.
uniform float target_hue : hint_range(-1.0, 1.0) = -1.0;
uniform float saturation_floor : hint_range(0.0, 1.0) = 0.0;
// Opt-in tint for gray midtones only; bright whites/black outlines stay intact.
uniform float neutral_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float neutral_target_hue : hint_range(-1.0, 1.0) = -1.0;
uniform float neutral_saturation : hint_range(0.0, 1.0) = 0.55;
uniform float neutral_value_scale : hint_range(0.0, 3.0) = 1.0;
uniform float neutral_saturation_max : hint_range(0.14, 1.0) = 0.30;
// Preserve neutral highlights and dark outlines rather than tinting the image.
uniform float minimum_saturation : hint_range(0.0, 1.0) = 0.18;
uniform float minimum_value : hint_range(0.0, 1.0) = 0.10;
// Status ColorTransform comes AFTER recoloring, compatible with battle tinting.
uniform vec3 rgb_multiplier = vec3(1.0);
uniform vec3 rgb_offset = vec3(0.0);
varying vec4 sprite_modulate;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 0.000001)), d / (q.x + 0.000001), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	vec3 hsv = rgb_to_hsv(pixel.rgb);
	float distance = abs(hsv.x - source_hue);
	distance = min(distance, 1.0 - distance);
	float hue_mask = source_hue < 0.0 ? 1.0 : 1.0 - smoothstep(hue_width * 0.75, hue_width, distance);
	float mask = hue_mask * smoothstep(minimum_saturation, minimum_saturation + 0.12, hsv.y)
		* smoothstep(minimum_value, minimum_value + 0.10, hsv.z);
	float selected_hue = target_hue >= 0.0 ? target_hue : fract(hsv.x + hue_shift);
	vec3 adjusted = hsv_to_rgb(vec3(selected_hue, clamp(max(hsv.y * saturation_scale, saturation_floor), 0.0, 1.0), clamp(hsv.z * value_scale, 0.0, 1.0)));
	pixel.rgb = mix(pixel.rgb, adjusted, mask);
	float neutral_mask = (1.0 - smoothstep(neutral_saturation_max - 0.14, neutral_saturation_max, hsv.y))
		* smoothstep(0.15, 0.30, hsv.z) * (1.0 - smoothstep(0.80, 0.96, hsv.z)) * neutral_tint_strength;
	vec3 neutral_color = hsv_to_rgb(vec3(neutral_target_hue >= 0.0 ? neutral_target_hue : selected_hue, max(neutral_saturation, saturation_floor), clamp(hsv.z * neutral_value_scale, 0.0, 1.0)));
	pixel.rgb = mix(pixel.rgb, neutral_color, neutral_mask);
	pixel.rgb = clamp(pixel.rgb * rgb_multiplier + rgb_offset, vec3(0.0), vec3(1.0));
	COLOR = pixel * sprite_modulate;
}
