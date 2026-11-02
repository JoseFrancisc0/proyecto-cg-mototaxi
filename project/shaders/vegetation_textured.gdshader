shader_type spatial;
// Vegetacion con modelos reales (texturas de corteza y hojas). Misma luz que el terreno
// (terrain_splat.gdshader) y que vegetation.gdshader: Blinn-Phong difusa + ambiente
// hemisferico + niebla + ACES, con la sombra del relieve y la visibilidad del cielo que
// calcula C++ por planta (INSTANCE_CUSTOM: r = fase del viento, g = sol, b = cielo).
// Las hojas se recortan con alpha (sin transparencia: no se ven "fantasmas").
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_map = false;
/** Tinte multiplicado a la textura (las mascaras blancas de hojas se tiñen por especie). */
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
/** 1 = hojas (viento y luz a contraluz), 0 = tronco. */
uniform float leafiness : hint_range(0.0, 1.0) = 0.0;
/** Altura del modelo (m, a escala 1): el viento y el oscurecimiento interior la usan. */
uniform float model_height = 10.0;
/** LOD por planta: se oculta si está más cerca que hide_inside o más lejos que hide_outside
 * de la cámara (versión lejana / cercana del mismo árbol). */
uniform float hide_inside = 0.0;
uniform float hide_outside = 1.0e9;

group_uniforms Iluminacion;
uniform vec3 sun_direction = vec3(0.5, 0.6, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float sun_intensity = 2.0;
uniform vec3 sky_color : source_color = vec3(0.52, 0.66, 0.90);
uniform vec3 ground_color : source_color = vec3(0.36, 0.31, 0.25);
uniform float ambient_intensity = 0.45;
uniform float exposure = 1.0;
group_uniforms Atmosfera;
uniform vec3 fog_color : source_color = vec3(0.62, 0.72, 0.86);
uniform float fog_density = 0.00008;
group_uniforms Viento;
uniform float wind_strength = 0.035;
uniform float wind_speed = 1.3;
uniform float translucency = 0.3;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_tangent;
varying vec3 world_binormal;
varying float sun_vis;
varying float sky_vis;
varying float height01;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_d = distance(origin.xz, CAMERA_POSITION_WORLD.xz);
	if (cam_d < hide_inside || cam_d > hide_outside) {
		VERTEX = vec3(0.0); // triángulos degenerados: esta planta la dibuja la otra versión
	}
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	height01 = clamp(VERTEX.y / max(model_height, 0.1), 0.0, 1.0);
	// Viento: crece con la altura al cuadrado; las hojas ademas tiemblan un poco.
	float h = max(VERTEX.y, 0.0) / max(model_height, 0.1) * 6.0;
	float gust = sin(TIME * wind_speed + phase + origin.x * 0.05) + 0.4 * sin(TIME * wind_speed * 2.3 + phase * 1.7 + origin.z * 0.08);
	float flutter = sin(TIME * 6.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + phase) * 0.04 * leafiness;
	VERTEX.x += gust * wind_strength * h * h * 0.15 + flutter;
	VERTEX.z += gust * wind_strength * h * h * 0.08 + flutter * 0.6;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_tangent = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	world_binormal = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	sun_vis = INSTANCE_CUSTOM.g;
	sky_vis = INSTANCE_CUSTOM.b;
}

vec3 tonemap(vec3 c) {
	c *= exposure;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < alpha_cut) {
		discard;
	}
	vec3 N = normalize(world_normal);
	if (use_normal_map) {
		vec3 nm = texture(normal_tex, UV).xyz * 2.0 - 1.0;
		N = normalize(world_tangent * nm.x + world_binormal * nm.y + N * nm.z);
	}
	if (!FRONT_FACING) {
		N = -N;
	}
	vec3 L = normalize(sun_direction);
	// COLOR = color de la instancia (variacion +-12%, la pone C++).
	vec3 albedo = tex.rgb * tint.rgb * COLOR.rgb;
	// Las hojas de adentro y de abajo reciben menos luz (oclusion aproximada de la copa).
	float inner = mix(1.0, mix(0.55, 1.0, height01), leafiness);
	float ndl = max(dot(N, L), 0.0);
	float back = max(dot(-N, L), 0.0) * translucency * leafiness;
	// En las hojas la normal del modelo es poco fiable: se mezcla con una luz mas pareja.
	float diffuse = mix(ndl, 0.35 + 0.65 * ndl, leafiness * 0.6);
	vec3 ambient = mix(ground_color, sky_color, N.y * 0.5 + 0.5) * ambient_intensity * mix(0.35, 1.0, sky_vis);
	vec3 sun = sun_color * sun_intensity * sun_vis;
	vec3 color = albedo * inner * (ambient + sun * (diffuse + back));
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	color = mix(color, fog_color, 1.0 - exp(-dist * fog_density));
	ALBEDO = tonemap(color);
}
