shader_type spatial;

uniform sampler2D portrait : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 skin_tone : source_color = vec4(0.8, 0.6, 0.46, 1.0);

void fragment() {
	vec2 oval = (UV - vec2(0.5, 0.5)) * vec2(2.15, 2.0);
	float blend = (1.0 - smoothstep(0.76, 1.0, length(oval))) * COLOR.a;
	ALBEDO = mix(skin_tone.rgb, texture(portrait, UV).rgb, blend);
	ROUGHNESS = 0.86;
	SPECULAR = 0.2;
}
