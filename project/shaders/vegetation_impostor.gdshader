shader_type spatial;
// Impostor octaédrico de un árbol lejano: 2 triángulos en vez de cientos.
//
// tools/bake_impostors.gd dibujó el modelo real desde frames x frames direcciones del
// hemisferio superior, repartidas con la proyección hemi-octaédrica, y las guardó en dos
// atlas (color, y normal + hojosidad). Aquí, por cada árbol:
//  1. vertex: se calcula la dirección planta -> cámara en el espacio del modelo, se ubica en
//     la grilla hemi-octaédrica y se eligen las 3 vistas horneadas más cercanas (triángulo de
//     la celda) con pesos baricéntricos; el quad se orienta hacia la cámara.
//  2. fragment: el rayo cámara -> píxel se proyecta sobre el plano de cada una de esas 3
//     vistas para saber qué píxel de esa vista le toca; se mezclan las 3 (sin saltos al girar).
//  3. Con la normal mezclada se calcula la misma luz que el terreno y vegetation_textured.
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
/** Vistas por lado del atlas. */
uniform float frames = 8.0;
/** Centro y radio de la esfera que envuelve el modelo (espacio del modelo). */
uniform vec3 center = vec3(0.0, 5.0, 0.0);
uniform float radius = 5.0;
uniform float model_height = 10.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
/** LOD por planta (como vegetation_textured): el impostor se oculta cerca de la cámara. */
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

varying vec3 obj_pos;
varying vec3 obj_cam;
varying vec3 world_pos;
varying vec2 frame0;
varying vec2 frame1;
varying vec2 frame2;
varying vec3 weights;
varying float sun_vis;
varying float sky_vis;

// Dirección del hemisferio superior para un punto g de la grilla en [-1, 1]^2.
vec3 hemi_oct_decode(vec2 g) {
	float x = (g.x + g.y) * 0.5;
	float z = (g.x - g.y) * 0.5;
	return normalize(vec3(x, 1.0 - abs(x) - abs(z), z));
}

// Inversa de hemi_oct_decode (d.y >= 0).
vec2 hemi_oct_encode(vec3 d) {
	d /= abs(d.x) + abs(d.y) + abs(d.z);
	return vec2(d.x + d.z, d.x - d.z);
}

// Ejes derecha / arriba de la cámara que mira desde d (igual que VegetationImpostors.frame_basis).
void frame_axes(vec3 d, out vec3 right, out vec3 up) {
	vec3 up_ref = abs(d.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	right = normalize(cross(up_ref, d));
	up = cross(d, right);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_d = distance(origin.xz, CAMERA_POSITION_WORLD.xz);
	float hidden = (cam_d < hide_inside || cam_d > hide_outside) ? 1.0 : 0.0;

	mat3 to_obj = inverse(mat3(MODEL_MATRIX));
	obj_cam = to_obj * (CAMERA_POSITION_WORLD - origin);
	vec3 view = obj_cam - center;
	vec3 view_n = length(view) > 1e-4 ? normalize(view) : vec3(0.0, 1.0, 0.0);

	// Quad hacia la cámara, un poco más grande que la esfera (la perspectiva la agranda).
	vec3 right;
	vec3 up;
	frame_axes(view_n, right, up);
	vec2 corner = UV * vec2(2.0, -2.0) + vec2(-1.0, 1.0);
	vec3 p = center + (right * corner.x + up * corner.y) * radius * 1.15;

	// Las 3 vistas horneadas más cercanas a la dirección de la cámara (bajo el horizonte se usa
	// la del horizonte: solo se hornea la mitad de arriba).
	vec3 sel = normalize(vec3(view_n.x, max(view_n.y, 0.0), view_n.z) + vec3(0.0, 1e-4, 0.0));
	vec2 grid = (hemi_oct_encode(sel) * 0.5 + 0.5) * (frames - 1.0);
	vec2 base = clamp(floor(grid), vec2(0.0), vec2(frames - 2.0));
	vec2 f = clamp(grid - base, 0.0, 1.0);
	frame0 = base;
	frame2 = base + vec2(1.0);
	if (f.x >= f.y) {
		frame1 = base + vec2(1.0, 0.0);
		weights = vec3(1.0 - f.x, f.x - f.y, f.y);
	} else {
		frame1 = base + vec2(0.0, 1.0);
		weights = vec3(1.0 - f.y, f.y - f.x, f.x);
	}

	// Viento: el quad entero se mece un poco (la copa más que la base).
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float gust = sin(TIME * wind_speed + phase + origin.x * 0.05) + 0.4 * sin(TIME * wind_speed * 2.3 + phase * 1.7 + origin.z * 0.08);
	float h = max(p.y, 0.0) / max(model_height, 0.1) * 6.0;
	p.x += gust * wind_strength * h * h * 0.15;
	p.z += gust * wind_strength * h * h * 0.08;

	obj_pos = p;
	VERTEX = p * (1.0 - hidden);
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	sun_vis = INSTANCE_CUSTOM.g;
	sky_vis = INSTANCE_CUSTOM.b;
}

vec3 tonemap(vec3 c) {
	c *= exposure;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

// Muestra una vista: color (rgb premultiplicado, a), y normal en espacio del modelo + hojosidad (n).
void sample_frame(vec2 frame, float w, vec3 ray, inout vec4 color, inout vec4 n) {
	vec3 d = hemi_oct_decode(frame / (frames - 1.0) * 2.0 - 1.0);
	vec3 right;
	vec3 up;
	frame_axes(d, right, up);
	// Rayo cámara -> píxel contra el plano de esta vista (pasa por el centro, normal d).
	float t = dot(center - obj_cam, d) / min(dot(ray, d), -1e-4);
	vec3 hit = obj_cam + ray * t - center;
	vec2 uv = vec2(dot(hit, right), -dot(hit, up)) / (2.0 * radius) + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	uv = (frame + clamp(uv, 0.002, 0.998)) / frames;
	vec4 c = texture(albedo_atlas, uv);
	vec4 nt = texture(normal_atlas, uv);
	float k = w * inside;
	color += vec4(c.rgb * c.a, c.a) * k; // premultiplicado: el borde no oscurece
	vec2 nxy = nt.xy * 2.0 - 1.0;
	vec3 nv = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	n += vec4(right * nv.x + up * nv.y + d * nv.z, nt.z) * k * c.a;
}

void fragment() {
	vec3 ray = obj_pos - obj_cam;
	vec4 color = vec4(0.0);
	vec4 n = vec4(0.0);
	sample_frame(frame0, weights.x, ray, color, n);
	sample_frame(frame1, weights.y, ray, color, n);
	sample_frame(frame2, weights.z, ray, color, n);
	if (color.a < alpha_cut) {
		discard;
	}
	vec3 albedo = color.rgb / color.a * COLOR.rgb;
	float leafiness = n.w / max(color.a, 1e-3);
	vec3 N = normalize(mat3(MODEL_MATRIX) * n.xyz + vec3(0.0, 1e-4, 0.0));
	vec3 L = normalize(sun_direction);
	float ndl = max(dot(N, L), 0.0);
	float back = max(dot(-N, L), 0.0) * translucency * leafiness;
	float diffuse = mix(ndl, 0.35 + 0.65 * ndl, leafiness * 0.6);
	vec3 ambient = mix(ground_color, sky_color, N.y * 0.5 + 0.5) * ambient_intensity * mix(0.35, 1.0, sky_vis);
	vec3 sun = sun_color * sun_intensity * sun_vis;
	vec3 c = albedo * (ambient + sun * (diffuse + back));
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	c = mix(c, fog_color, 1.0 - exp(-dist * fog_density));
	ALBEDO = tonemap(c);
}
