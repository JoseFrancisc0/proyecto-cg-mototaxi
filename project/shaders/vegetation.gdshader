shader_type spatial;
// Vegetacion (S14): misma luz que el terreno (terrain_splat.gdshader) para que los
// arboles no se vean "pegados": Blinn-Phong difusa + ambiente hemisferico + niebla + ACES.
// La sombra del terreno sobre cada planta y su visibilidad del cielo se calculan en C++
// (ray tracing sobre el heightfield) y llegan por INSTANCE_CUSTOM (r = fase del viento,
// g = sol, b = cielo). El color de la instancia trae una variacion de +-12%.
render_mode unshaded, cull_disabled;

group_uniforms Iluminacion;
/** Direccion HACIA el sol, en coordenadas del mundo. La pone chunk_mesh.gd. */
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
/** Cuanto se mueve la copa con el viento (m por cada metro de altura). */
uniform float wind_strength = 0.035;
uniform float wind_speed = 1.3;
/** Brillo translucido de las hojas a contraluz. */
uniform float translucency = 0.25;

varying vec3 world_pos;
varying vec3 world_normal;
varying float sun_vis;
varying float sky_vis;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	// Viento: el desplazamiento crece con la altura al cuadrado (la base no se mueve).
	float h = max(VERTEX.y, 0.0);
	float gust = sin(TIME * wind_speed + phase + origin.x * 0.05) + 0.4 * sin(TIME * wind_speed * 2.3 + phase * 1.7 + origin.z * 0.08);
	VERTEX.x += gust * wind_strength * h * h * 0.15;
	VERTEX.z += gust * wind_strength * h * h * 0.08;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	sun_vis = INSTANCE_CUSTOM.g;
	sky_vis = INSTANCE_CUSTOM.b;
}

vec3 tonemap(vec3 c) {
	c *= exposure;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

void fragment() {
	vec3 N = normalize(world_normal);
	if (!FRONT_FACING) {
		N = -N;
	}
	// sun_direction llega en coordenadas del mundo (MODEL_MATRIX incluye el giro de la planta).
	vec3 L = normalize(sun_direction);
	// COLOR = color del vertice (parte de la planta) x color de la instancia (variacion).
	vec3 albedo = COLOR.rgb;
	float ndl = max(dot(N, L), 0.0);
	float back = max(dot(-N, L), 0.0) * translucency;
	vec3 ambient = mix(ground_color, sky_color, N.y * 0.5 + 0.5) * ambient_intensity * mix(0.35, 1.0, sky_vis);
	vec3 sun = sun_color * sun_intensity * sun_vis;
	vec3 color = albedo * (ambient + sun * (ndl + back));
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	color = mix(color, fog_color, 1.0 - exp(-dist * fog_density));
	ALBEDO = tonemap(color);
}
