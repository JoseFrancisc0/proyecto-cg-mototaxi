shader_type spatial;
// La iluminacion la calculamos nosotros (Blinn-Phong + sombras por ray tracing + AO),
// por eso el material es "unshaded": Godot no agrega su propia luz encima.
render_mode unshaded;

// Terreno: texture mapping (S10) + iluminacion local y global (S12).
//
// Tecnicas de la clase:
//   1. Parametrizacion: cada vertice trae (u, v) = (x, z) en metros desde C++.
//      La GPU interpola (u, v) con coordenadas baricentricas dentro de cada triangulo.
//   2. Funciones sobre la malla: CUSTOM0 trae por vertice los pesos de region
//      (costa, sierra, selva) y la humedad; tambien se interpolan baricentricamente.
//   3. Splatting: el color final es la suma ponderada de 7 texturas (pesos que suman 1).
//
// Tecnicas externas que se conservan porque hacen falta:
//   - Triplanar (solo en laderas): la parametrizacion planar se estira en paredes
//     verticales (el problema de "distortions" de la clase). Se proyecta en 3 planos.
//   - Normal map: relieve fino de luz. Se apaga con normal_strength = 0.
//
// Iluminacion (sílabo 6.3.3):
//   4. Modelo local Blinn-Phong: difusa (N.L) + especular (N.H)^s + ambiente del cielo.
//   5. Sombras por ray tracing: desde cada pixel se lanza un rayo hacia el sol que
//      avanza sobre el mapa de alturas (height_map). Si pasa por debajo del terreno,
//      el punto esta en sombra. La distancia minima al terreno da la sombra suave.
//   6. Iluminacion global: visibilidad del cielo por vertice (CUSTOM1), calculada en
//      C++ con rayos sobre el heightfield. Oscurece quebradas y fondos de valle.
//   7. POM: ray marching dentro del mapa Displacement de la textura (relieve de cerca).
//   8. Niebla por distancia (perspectiva aerea) y tone mapping.

// Capas, mismo orden que TerrainTextures.MATERIALS:
// 0 Ground054 arena (costa plano)      1 Rocks021 piedras (costa ladera)
// 2 Rocks007 roca+pasto (sierra plano)  3 Rocks011 lajas (sierra ladera)
// 4 Snow015 nieve (sierra cumbre)       5 Ground037 musgo (selva plano)
// 6 Rock059 roca verde (selva ladera)
uniform sampler2DArray albedo_maps : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_maps : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray roughness_maps : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray height_maps : filter_linear_mipmap, repeat_enable;
/** Alturas de la malla final (1 float por vertice). Lo llena chunk_mesh.gd. */
uniform sampler2D height_map : filter_nearest, repeat_disable;
uniform float map_cells = 2.0;
uniform float map_cell_size = 1.0;
uniform float map_max_height = 1000.0;

group_uniforms Mapeo;
/** Metros que cubre una repeticion de la textura. */
uniform float tile_size : hint_range(1.0, 64.0) = 8.0;
/** Segunda escala de la misma textura: tile_size x macro_scale. Rompe la repeticion. */
uniform float macro_scale : hint_range(1.0, 16.0) = 5.3;
/** Cuanto pesa la escala grande de cerca (0 = nada, 1 = solo la grande). */
uniform float macro_mix : hint_range(0.0, 1.0) = 0.4;
/** Distancia (m) a la camara donde la escala grande empieza y termina de dominar. */
uniform float far_start = 40.0;
uniform float far_end = 300.0;
/** Mayor valor = cambio mas brusco entre los 3 planos del triplanar. */
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms Reglas;
/** Pendiente = 1 - normal.y. 0 = plano, 0.29 = 45 grados, 1 = pared vertical. */
uniform float slope_start : hint_range(0.0, 1.0) = 0.12;
uniform float slope_end : hint_range(0.0, 1.0) = 0.30;
/** Altura (m) donde empieza y se completa la nieve. La calcula chunk_mesh.gd. */
uniform float snow_start = 1000.0;
uniform float snow_end = 1100.0;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.45;

group_uniforms Iluminacion;
/** Direccion HACIA el sol, en el espacio del terreno. La pone chunk_mesh.gd. */
uniform vec3 sun_direction = vec3(0.5, 0.6, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float sun_intensity : hint_range(0.0, 8.0) = 2.0;
uniform vec3 sky_color : source_color = vec3(0.52, 0.66, 0.90);
uniform vec3 ground_color : source_color = vec3(0.36, 0.31, 0.25);
uniform float ambient_intensity : hint_range(0.0, 4.0) = 0.45;
/** Brillo especular maximo (Blinn-Phong). La rugosidad de la textura lo reduce. */
uniform float specular_strength : hint_range(0.0, 2.0) = 0.35;
uniform float exposure : hint_range(0.1, 4.0) = 1.0;

group_uniforms Sombras;
uniform bool shadows_enabled = true;
/** Distancia maxima (m) que recorre el rayo hacia el sol. */
uniform float shadow_max_distance = 2500.0;
/** Mayor valor = sombra mas dura. */
uniform float shadow_softness : hint_range(1.0, 64.0) = 10.0;
/** Cuanto crece cada paso del rayo (1.08 = 8% mas largo que el anterior). */
uniform float shadow_step_growth : hint_range(1.01, 1.3) = 1.08;
/** Fuerza de la oclusion ambiental (visibilidad del cielo). */
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
/** Exponente del AO: mayor valor = quebradas mas oscuras. */
uniform float ao_contrast : hint_range(1.0, 8.0) = 3.0;

group_uniforms Relieve_POM;
uniform bool pom_enabled = true;
/** Profundidad del relieve en unidades de textura (0.03 = 3% de tile_size). */
uniform float pom_depth : hint_range(0.0, 0.1) = 0.04;
/** Solo se calcula cerca de la camara (m). */
uniform float pom_distance = 40.0;

group_uniforms Atmosfera;
uniform vec3 fog_color : source_color = vec3(0.62, 0.72, 0.86);
uniform float fog_density : hint_range(0.0, 0.005, 0.00001) = 0.00008;

group_uniforms Depuracion;
/** 0 = final, 1 = color por material, 2 = regiones, 3 = ajedrez de UV,
    4 = solo sombras del sol, 5 = solo oclusion ambiental, 6 = texturas sin luz. */
uniform int debug_view : hint_range(0, 6) = 0;

varying vec3 world_pos;
// Posicion en el espacio del terreno: si se mueve el nodo, la nieve y las
// texturas se quedan pegadas al terreno en vez de deslizarse.
varying vec3 local_pos;
varying vec3 world_normal;
varying vec4 regions;
varying float sky_visibility;

const int LAYERS = 7;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	regions = CUSTOM0;
	sky_visibility = CUSTOM1.r;
}

// Normal del mapa (formato OpenGL, verde = +v) en [-1, 1].
vec3 unpack_normal(vec4 texel) {
	vec3 t = texel.rgb * 2.0 - 1.0;
	t.xy *= normal_strength;
	return t;
}

// POM: el rayo de vista entra en la textura como si tuviera profundidad. Se avanza
// en pasos hasta que el rayo queda por debajo del mapa Displacement y se usa la UV
// de ese punto. V va del punto hacia la camara, en el espacio del terreno.
vec2 parallax_uv(float layer, vec2 uv, vec3 V, float depth) {
	if (depth <= 0.0) {
		return uv;
	}
	float steps = mix(16.0, 6.0, clamp(V.y, 0.0, 1.0));
	float delta = 1.0 / steps;
	vec2 shift = V.xz / max(V.y, 0.25) * depth * delta;
	float ray_depth = 0.0;
	vec2 cur = uv;
	float map_depth = 1.0 - textureLod(height_maps, vec3(cur, layer), 0.0).r;
	for (int s = 0; s < 16; s++) {
		if (ray_depth >= map_depth || float(s) >= steps) {
			break;
		}
		cur -= shift;
		map_depth = 1.0 - textureLod(height_maps, vec3(cur, layer), 0.0).r;
		ray_depth += delta;
	}
	// Interpolacion entre el ultimo paso por encima y el primero por debajo.
	vec2 prev = cur + shift;
	float after = map_depth - ray_depth;
	float before = (1.0 - textureLod(height_maps, vec3(prev, layer), 0.0).r) - ray_depth + delta;
	float t = after / min(after - before, -1e-5);
	return mix(cur, prev, clamp(t, 0.0, 1.0));
}

// Mapeo planar con la UV de la malla (parametrizacion de la clase).
void sample_planar(float layer, vec2 uv, float tile, vec3 N, vec3 V, float pom, out vec3 albedo, out vec3 normal, out float rough) {
	vec3 p = vec3(parallax_uv(layer, uv / tile, V, pom), layer);
	albedo = texture(albedo_maps, p).rgb;
	rough = texture(roughness_maps, p).r;
	vec3 t = unpack_normal(texture(normal_maps, p));
	// u sigue a +x y v sigue a +z: se inclina la normal del terreno.
	normal = normalize(vec3(N.x + t.x, N.y * t.z, N.z + t.y));
}

// Triplanar: tres mapeos planares (planos YZ, XZ, XY) mezclados segun la normal.
void sample_triplanar(float layer, vec3 pos, float tile, vec3 N, out vec3 albedo, out vec3 normal, out float rough) {
	vec3 b = pow(abs(N), vec3(triplanar_sharpness));
	b /= max(b.x + b.y + b.z, 1e-5);
	vec3 q = pos / tile;
	vec3 px = vec3(q.zy, layer), py = vec3(q.xz, layer), pz = vec3(q.xy, layer);
	albedo = texture(albedo_maps, px).rgb * b.x + texture(albedo_maps, py).rgb * b.y + texture(albedo_maps, pz).rgb * b.z;
	rough = texture(roughness_maps, px).r * b.x + texture(roughness_maps, py).r * b.y + texture(roughness_maps, pz).r * b.z;
	vec3 tx = unpack_normal(texture(normal_maps, px));
	vec3 ty = unpack_normal(texture(normal_maps, py));
	vec3 tz = unpack_normal(texture(normal_maps, pz));
	// Mezcla "whiteout": se suma el relieve del mapa a la normal en cada plano.
	vec3 nx = vec3(N.x * tx.z, N.y + tx.y, N.z + tx.x);
	vec3 ny = vec3(N.x + ty.x, N.y * ty.z, N.z + ty.y);
	vec3 nz = vec3(N.x + tz.x, N.y + tz.y, N.z * tz.z);
	normal = normalize(nx * b.x + ny * b.y + nz * b.z);
}

// Altura del terreno en (x, z) del espacio local: interpolacion bilineal de 4 texels.
float terrain_height(vec2 xz) {
	vec2 g = xz / map_cell_size + vec2((map_cells - 1.0) * 0.5);
	g = clamp(g, vec2(0.0), vec2(map_cells - 1.001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float h00 = texelFetch(height_map, i, 0).r;
	float h10 = texelFetch(height_map, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(height_map, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(height_map, i + ivec2(1, 1), 0).r;
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

// Ray tracing de la sombra: se avanza desde p hacia el sol sobre el heightfield.
// 1 = luz completa, 0 = sombra. min(k * d / t) da penumbra: si el rayo pasa
// muy cerca del terreno (d pequeno) lejos del punto (t grande), la sombra se suaviza.
float sun_visibility(vec3 p, vec3 L) {
	if (L.y <= 0.0) {
		return 0.0;
	}
	float half_size = (map_cells - 1.0) * 0.5 * map_cell_size;
	// Inicio del rayo con un pequeno desfase aleatorio por pixel: cambia las bandas
	// escalonadas de la penumbra por un grano fino que no se nota.
	float jitter = fract(sin(dot(p.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float t = map_cell_size * (1.0 + jitter);
	float result = 1.0;
	vec3 origin = p + vec3(0.0, 0.3, 0.0);
	for (int s = 0; s < 96; s++) {
		vec3 q = origin + L * t;
		if (q.y > map_max_height || abs(q.x) > half_size || abs(q.z) > half_size || t > shadow_max_distance) {
			break;
		}
		float d = q.y - terrain_height(q.xz);
		if (d < 0.0) {
			return 0.0;
		}
		result = min(result, shadow_softness * d / t);
		t *= shadow_step_growth;
	}
	return clamp(result, 0.0, 1.0);
}

// Tone mapping ACES (aproximacion de Narkowicz): comprime los brillos altos sin quemarlos.
vec3 tonemap(vec3 c) {
	c *= exposure;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

vec3 checker(vec2 uv) {
	vec2 c = floor(uv / tile_size);
	return mod(c.x + c.y, 2.0) < 1.0 ? vec3(0.9) : vec3(0.15);
}

void fragment() {
	vec3 N = normalize(world_normal);
	vec3 R = max(regions.xyz, vec3(0.0));
	R /= max(R.x + R.y + R.z, 1e-5);
	float wet = clamp(regions.w, 0.0, 1.0);

	// Reglas de splatting: region x pendiente x altura.
	float steep = smoothstep(slope_start, slope_end, 1.0 - N.y);
	float snow = smoothstep(snow_start, snow_end, local_pos.y) * (1.0 - smoothstep(0.45, 0.70, 1.0 - N.y));
	float w[7];
	w[0] = R.x * (1.0 - steep);
	w[1] = R.x * steep;
	w[2] = R.y * (1.0 - steep) * (1.0 - snow);
	w[3] = R.y * steep * (1.0 - snow);
	w[4] = R.y * snow;
	w[5] = R.z * (1.0 - steep);
	w[6] = R.z * steep;

	// Dos escalas de la misma textura: de cerca domina la fina, de lejos la grande.
	// Como macro_scale no es entero, los dos patrones no se alinean y la repeticion no se nota.
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	float m = mix(macro_mix, 1.0, smoothstep(far_start, far_end, dist));
	float tiles[2] = float[](tile_size, tile_size * macro_scale);
	float scale_w[2] = float[](1.0 - m, m);
	// Vista hacia la camara en el espacio del terreno (para POM) y profundidad segun distancia.
	vec3 V_local = normalize((inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz - local_pos);
	float pom = pom_enabled ? pom_depth * (1.0 - smoothstep(pom_distance * 0.6, pom_distance, dist)) : 0.0;

	vec3 albedo = vec3(0.0);
	vec3 normal = vec3(0.0);
	float rough = 0.0;
	for (int i = 0; i < LAYERS; i++) {
		if (w[i] < 0.002) {
			continue;
		}
		for (int k = 0; k < 2; k++) {
			if (scale_w[k] < 0.002) {
				continue;
			}
			vec3 a;
			vec3 n;
			float r;
			// Laderas (capas 1, 3, 6): triplanar. Zonas planas: UV de la malla.
			if (i == 1 || i == 3 || i == 6) {
				sample_triplanar(float(i), local_pos, tiles[k], N, a, n, r);
			} else {
				// POM solo en la escala fina (la que se ve de cerca).
				sample_planar(float(i), UV, tiles[k], N, V_local, k == 0 ? pom : 0.0, a, n, r);
			}
			float wk = w[i] * scale_w[k];
			albedo += a * wk;
			normal += n * wk;
			rough += r * wk;
		}
	}
	normal = length(normal) > 1e-4 ? normalize(normal) : N;

	// Orillas humedas: mas oscuras y brillantes.
	albedo *= 1.0 - wet_darkening * wet;
	rough = mix(rough, 0.25, wet);

	// Caminos: alfa del color de vertice = mascara del camino.
	float road = COLOR.a;
	albedo = mix(albedo, COLOR.rgb, road);
	rough = mix(rough, 0.9, road);
	normal = normalize(mix(normal, N, road));

	// ---- Iluminacion ----
	vec3 L = normalize((MODEL_MATRIX * vec4(sun_direction, 0.0)).xyz);
	vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
	float shadow = shadows_enabled ? sun_visibility(local_pos, normalize(sun_direction)) : 1.0;
	float ao = mix(1.0, pow(clamp(sky_visibility, 0.0, 1.0), ao_contrast), ao_strength);
	// Blinn-Phong: difusa de Lambert + especular con el vector medio H.
	float ndl = max(dot(normal, L), 0.0);
	vec3 H = normalize(L + V);
	float gloss = 1.0 - clamp(rough, 0.0, 1.0);
	float shininess = mix(4.0, 96.0, gloss * gloss);
	float spec = specular_strength * gloss * pow(max(dot(normal, H), 0.0), shininess) * ndl;
	// Ambiente hemisferico: cielo arriba, rebote del suelo abajo, tapado por el AO.
	vec3 ambient = mix(ground_color, sky_color, normal.y * 0.5 + 0.5) * ambient_intensity * ao;
	vec3 sun = sun_color * sun_intensity * shadow;
	vec3 color = albedo * (ambient + sun * ndl) + sun * spec;
	// Perspectiva aerea: lo lejano se funde con el color del cielo.
	color = mix(color, fog_color, 1.0 - exp(-dist * fog_density));
	color = tonemap(color);

	if (debug_view == 4) {
		color = vec3(shadow);
	} else if (debug_view == 5) {
		color = vec3(ao);
	} else if (debug_view == 6) {
		color = albedo;
	} else if (debug_view == 1) {
		vec3 palette[7] = vec3[](vec3(0.95, 0.85, 0.45), vec3(0.75, 0.55, 0.30), vec3(0.55, 0.65, 0.30),
				vec3(0.50, 0.45, 0.40), vec3(1.0), vec3(0.15, 0.60, 0.20), vec3(0.20, 0.35, 0.30));
		color = vec3(0.0);
		for (int i = 0; i < LAYERS; i++) {
			color += palette[i] * w[i];
		}
		color *= 0.35 + 0.65 * ndl;
	} else if (debug_view == 2) {
		color = vec3(R.x, R.z, R.y) * (0.35 + 0.65 * ndl);
	} else if (debug_view == 3) {
		color = checker(UV);
	}

	ALBEDO = color;
}
