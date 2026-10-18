shader_type spatial;
render_mode diffuse_burley;

// Texture mapping del terreno (S10, capa de texturas; sin POM ni ray tracing aun).
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

// Capas, mismo orden que TerrainTextures.MATERIALS:
// 0 Ground054 arena (costa plano)      1 Rocks021 piedras (costa ladera)
// 2 Rocks007 roca+pasto (sierra plano)  3 Rocks011 lajas (sierra ladera)
// 4 Snow015 nieve (sierra cumbre)       5 Ground037 musgo (selva plano)
// 6 Rock059 roca verde (selva ladera)
uniform sampler2DArray albedo_maps : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_maps : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray roughness_maps : filter_linear_mipmap, repeat_enable;

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

group_uniforms Depuracion;
/** 0 = texturas, 1 = color por material, 2 = pesos de region, 3 = ajedrez de UV. */
uniform int debug_view : hint_range(0, 3) = 0;

varying vec3 world_pos;
// Posicion en el espacio del terreno: si se mueve el nodo, la nieve y las
// texturas se quedan pegadas al terreno en vez de deslizarse.
varying vec3 local_pos;
varying vec3 world_normal;
varying vec4 regions;

const int LAYERS = 7;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	regions = CUSTOM0;
}

// Normal del mapa (formato OpenGL, verde = +v) en [-1, 1].
vec3 unpack_normal(vec4 texel) {
	vec3 t = texel.rgb * 2.0 - 1.0;
	t.xy *= normal_strength;
	return t;
}

// Mapeo planar con la UV de la malla (parametrizacion de la clase).
void sample_planar(float layer, vec2 uv, float tile, vec3 N, out vec3 albedo, out vec3 normal, out float rough) {
	vec3 p = vec3(uv / tile, layer);
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
				sample_planar(float(i), UV, tiles[k], N, a, n, r);
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

	if (debug_view == 1) {
		vec3 palette[7] = vec3[](vec3(0.95, 0.85, 0.45), vec3(0.75, 0.55, 0.30), vec3(0.55, 0.65, 0.30),
				vec3(0.50, 0.45, 0.40), vec3(1.0), vec3(0.15, 0.60, 0.20), vec3(0.20, 0.35, 0.30));
		albedo = vec3(0.0);
		for (int i = 0; i < LAYERS; i++) {
			albedo += palette[i] * w[i];
		}
	} else if (debug_view == 2) {
		albedo = vec3(R.x, R.z, R.y);
	} else if (debug_view == 3) {
		albedo = checker(UV);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
}
