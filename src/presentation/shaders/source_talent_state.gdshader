shader_type canvas_item;

// TalentTreeNode.as uses TweenMax ColorMatrixFilter: saturation .1,
// brightness .5 while locked, and 1/1 when active. Preserve alpha.
uniform float saturation = 1.0;
uniform float brightness = 1.0;

void fragment() {
	// CanvasItem fragment COLOR already includes the sampled texture. Sampling
	// it again would square its RGB/alpha and darken even fully active nodes.
	vec4 sample_color = COLOR;
	float luminance = dot(sample_color.rgb, vec3(0.212671, 0.715160, 0.072169));
	// ColorMatrixFilterPlugin.setBrightness translates channels by
	// 100 * brightness - 100, rather than multiplying their intensity.
	sample_color.rgb = clamp(mix(vec3(luminance), sample_color.rgb, saturation) + vec3((brightness - 1.0) * 100.0 / 255.0), vec3(0.0), vec3(1.0));
	COLOR = sample_color;
}
