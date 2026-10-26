// TerrainMesh: lo que el juego necesita sobre la superficie final.
//   - Mapa de rios para el shader (S13 CG-B / S14 agua).
//   - Vegetacion repartida por region, pendiente, altura y humedad (S14, MultiMesh).
//   - Landmarks por tipo: picos, confluencias y costa (S13 CG-B).
//   - Chunks de 128 x 128 con LOD y faldones (S12 CG-B).
#include "terrain_internal.h"
#include "terrain_mesh.h"
#include <algorithm>
#include <cmath>
#include <deque>
#include <godot_cpp/classes/mesh.hpp>

using namespace godot;

namespace {

// Hash entero -> [0, 1). Repetible: misma semilla, mismas plantas.
inline uint32_t hash_u32(uint32_t x) {
	x ^= x >> 16;
	x *= 0x7feb352dU;
	x ^= x >> 15;
	x *= 0x846ca68bU;
	x ^= x >> 16;
	return x;
}
inline double hash01(int a, int b, int c, int salt) {
	uint32_t h = hash_u32(uint32_t(a) * 0x9E3779B1U ^ hash_u32(uint32_t(b) * 0x85EBCA77U ^ hash_u32(uint32_t(c) * 0xC2B2AE3DU ^ uint32_t(salt))));
	return (h >> 8) * (1.0 / 16777216.0);
}

// Ruido de valor 2D suave (para que las plantas formen manchas, no una lluvia uniforme).
double value_noise(double x, double z, int seed) {
	int ix = (int)std::floor(x), iz = (int)std::floor(z);
	double fx = x - ix, fz = z - iz;
	double ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz);
	double a = hash01(ix, iz, seed, 11), b = hash01(ix + 1, iz, seed, 11);
	double c = hash01(ix, iz + 1, seed, 11), d = hash01(ix + 1, iz + 1, seed, 11);
	return (a * (1 - ux) + b * ux) * (1 - uz) + (c * (1 - ux) + d * ux) * uz;
}

inline double smooth01(double a, double b, double x) {
	if (a == b)
		return x < a ? 0.0 : 1.0;
	double t = std::clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3 - 2 * t);
}

// Maximo (o minimo) en una ventana cuadrada de radio r, separable, O(n^2) con deque.
std::vector<double> window_extreme(const std::vector<double> &h, int n, int r, bool maximum) {
	auto better = [maximum](double a, double b) { return maximum ? a >= b : a <= b; };
	std::vector<double> tmp(h.size()), out(h.size());
	for (int pass = 0; pass < 2; pass++) {
		const std::vector<double> &src = pass == 0 ? h : tmp;
		std::vector<double> &dst = pass == 0 ? tmp : out;
		for (int line = 0; line < n; line++) {
			std::deque<int> q;
			auto at = [&](int k) { return pass == 0 ? src[size_t(line) * n + k] : src[size_t(k) * n + line]; };
			auto put = [&](int k, double v) {
				if (pass == 0)
					dst[size_t(line) * n + k] = v;
				else
					dst[size_t(k) * n + line] = v;
			};
			int right = 0;
			for (int k = 0; k < n; k++) {
				while (right < n && right <= k + r) {
					while (!q.empty() && better(at(right), at(q.back())))
						q.pop_back();
					q.push_back(right);
					right++;
				}
				while (!q.empty() && q.front() < k - r)
					q.pop_front();
				put(k, at(q.front()));
			}
		}
	}
	return out;
}

} // namespace

// ---------------------------------------------------------------------------
// Rios en el shader
// ---------------------------------------------------------------------------
// Para cada texel se guarda la distancia con signo a la orilla del rio mas cercano
// (s = distancia al eje - semiancho; s < 0 = dentro del agua), el semiancho y la
// direccion de la corriente. Es un campo de distancia (como las fuentes SDF): al
// interpolarlo en la GPU la orilla queda suave aunque el rio sea angosto.
// Ancho: geometria hidraulica (Leopold y Maddock 1953), w ~ Q^0.5, con el area de
// drenaje como sustituto del caudal Q.
void TerrainMesh::build_river_map(int n, double cell, double threshold, const Dictionary &cfg) {
	auto cfg_d = [&](const char *k, double def) { Variant v = cfg.get(k, def); return (double)v; };
	const int ss = std::clamp((int)cfg_d("river_supersample", n <= 1100 ? 2.0 : 1.0), 1, 4);
	const int size = (n - 1) * ss + 1;
	const double texel = cell / ss;
	const double S = 8.0, W = 8.0; // rangos de codificacion (m)
	const double width_scale = cfg_d("river_width", 1.4);
	const double min_half = std::max(cfg_d("river_min_half_width", 1.0), texel * 0.8);
	const double max_half = std::min(cfg_d("river_max_half_width", 7.0), W);
	const double band = cfg_d("river_band", 6.0);
	const double offset = (n - 1) * cell * 0.5;
	std::vector<float> sdist(size_t(size) * size, (float)S), half(size_t(size) * size, 0.0f), dx(size_t(size) * size, 0.0f), dz(size_t(size) * size, 0.0f);
	// Nivel del agua del segmento mas cercano (para no pintar agua en las paredes de un cauce hondo).
	std::vector<float> wlevel(size_t(size) * size, -1e9f);
	auto half_width = [&](int i) { return std::clamp(width_scale * std::sqrt(std::max(0.0, drainage.accumulation[i]) / threshold), min_half, max_half); };
	for (int i = 0; i < n * n; i++) {
		if (!drainage.channel[i])
			continue;
		int j = drainage.receiver[i];
		if (j < 0)
			continue;
		double ax = (i % n) * cell - offset, az = (i / n) * cell - offset;
		double bx = (j % n) * cell - offset, bz = (j / n) * cell - offset;
		double wa = half_width(i), wb = std::max(wa, half_width(j));
		double vx = bx - ax, vz = bz - az, len2 = vx * vx + vz * vz;
		if (len2 <= 0.0)
			continue;
		double inv = 1.0 / std::sqrt(len2);
		double reach = std::max(wa, wb) + band;
		int x0 = std::clamp((int)std::floor((std::min(ax, bx) - reach + offset) / texel), 0, size - 1);
		int x1 = std::clamp((int)std::ceil((std::max(ax, bx) + reach + offset) / texel), 0, size - 1);
		int z0 = std::clamp((int)std::floor((std::min(az, bz) - reach + offset) / texel), 0, size - 1);
		int z1 = std::clamp((int)std::ceil((std::max(az, bz) + reach + offset) / texel), 0, size - 1);
		for (int z = z0; z <= z1; z++)
			for (int x = x0; x <= x1; x++) {
				double px = x * texel - offset, pz = z * texel - offset;
				double t = std::clamp(((px - ax) * vx + (pz - az) * vz) / len2, 0.0, 1.0);
				double d = std::hypot(px - ax - t * vx, pz - az - t * vz);
				double w = wa + (wb - wa) * t;
				double s = d - w;
				size_t k = size_t(z) * size + x;
				if (s < sdist[k]) {
					sdist[k] = (float)s;
					half[k] = (float)w;
					wlevel[k] = (float)(drainage.level[i] + (drainage.level[j] - drainage.level[i]) * t);
					dx[k] = (float)(vx * inv);
					dz[k] = (float)(vz * inv);
				}
			}
	}
	river_size = size;
	river_texel = texel;
	river_rgba.resize(size_t(size) * size * 4);
	auto byte = [](double v) { return (uint8_t)std::lround(std::clamp(v, 0.0, 1.0) * 255.0); };
	for (size_t k = 0; k < size_t(size) * size; k++) {
		river_rgba[k * 4] = byte(0.5 + sdist[k] / (2.0 * S));
		river_rgba[k * 4 + 1] = byte(half[k] / W);
		river_rgba[k * 4 + 2] = byte(dx[k] * 0.5 + 0.5);
		river_rgba[k * 4 + 3] = byte(dz[k] * 0.5 + 0.5);
	}
	river_bank.assign(size_t(n) * n, (float)S);
	river_level.assign(size_t(n) * n, 0.0f);
	for (int z = 0; z < n; z++)
		for (int x = 0; x < n; x++) {
			size_t k = size_t(z) * ss * size + size_t(x) * ss;
			river_bank[size_t(z) * n + x] = sdist[k];
			// Lejos de los rios se usa la altura del terreno: asi la interpolacion no salta.
			river_level[size_t(z) * n + x] = wlevel[k] > -1e8f ? wlevel[k] : (float)drainage.level[size_t(z) * n + x];
		}
}

Dictionary TerrainMesh::get_river_map() const {
	Dictionary d;
	d["size"] = river_size;
	d["texel"] = river_texel;
	d["extent"] = river_size > 1 ? (river_size - 1) * river_texel : 0.0;
	d["threshold"] = river_threshold_used;
	d["distance_range"] = 8.0;
	d["width_range"] = 8.0;
	PackedByteArray bytes;
	bytes.resize((int64_t)river_rgba.size());
	if (!river_rgba.empty())
		memcpy(bytes.ptrw(), river_rgba.data(), river_rgba.size());
	d["rgba"] = bytes;
	PackedFloat32Array level;
	level.resize((int64_t)river_level.size());
	if (!river_level.empty())
		memcpy(level.ptrw(), river_level.data(), river_level.size() * sizeof(float));
	d["level"] = level;
	d["level_size"] = river_level.empty() ? 0 : (int)std::lround(std::sqrt((double)river_level.size()));
	return d;
}

// ---------------------------------------------------------------------------
// Vegetacion (S14)
// ---------------------------------------------------------------------------
Dictionary TerrainMesh::scatter_vegetation(Ref<TerrainNoise> terrain, Array species, Dictionary options) {
	Dictionary result;
	const int n = final_n;
	if (n < 2 || final_height.size() != size_t(n) * n)
		return result;
	const double cell = final_cell;
	const double extent = (n - 1) * cell, half = extent * 0.5;
	const std::vector<float> &biome = biome_weights(terrain, n, cell);
	auto opt = [&](const char *k, double def) { Variant v = options.get(k, def); return (double)v; };
	const int chunk_cells = std::max(8, (int)opt("chunk_cells", 128.0));
	const double chunk_m = chunk_cells * cell;
	const int chunks_side = std::max(1, (int)std::ceil((n - 1) / double(chunk_cells)));
	const double density_scale = std::max(0.0, opt("density_scale", 1.0));
	const int seed = (int)opt("seed", 1);
	const double snow_height = opt("snow_height", 1e30);
	// Luz de cada instancia (el shader de la vegetacion usa la misma luz que el terreno):
	// sombra del terreno hacia el sol (ray tracing sobre el heightfield, como el shader)
	// y visibilidad del cielo (AO de la superficie).
	Vector3 to_sun = options.get("sun_direction", Vector3(0.5, 0.6, 0.4));
	to_sun = to_sun.normalized();
	const double softness = opt("shadow_softness", 10.0);
	const double shadow_reach = opt("shadow_max_distance", 2500.0);
	auto ao_layer = layers.find("ao");
	const std::vector<float> *ao_map = ao_layer != layers.end() && ao_layer->second.size() == size_t(n) * n ? &ao_layer->second : nullptr;
	double lo = 1e300, hi = -1e300;
	for (double v : final_height) {
		lo = std::min(lo, v);
		hi = std::max(hi, v);
	}
	const double range = std::max(1e-3, hi - lo);
	std::vector<float> canopy(size_t(n) * n, 0.0f);

	// Altura en (x, z) sobre los mismos triangulos que la malla y la colision (diagonal 10-01).
	auto surface = [&](double x, double z) {
		double fx = std::clamp((x + half) / cell, 0.0, double(n - 1)), fz = std::clamp((z + half) / cell, 0.0, double(n - 1));
		int ix = std::min(int(fx), n - 2), iz = std::min(int(fz), n - 2);
		double tx = fx - ix, tz = fz - iz;
		double h00 = final_height[size_t(iz) * n + ix], h10 = final_height[size_t(iz) * n + ix + 1];
		double h01 = final_height[size_t(iz + 1) * n + ix], h11 = final_height[size_t(iz + 1) * n + ix + 1];
		if (tx + tz <= 1.0)
			return h00 + tx * (h10 - h00) + tz * (h01 - h00);
		return h11 + (1 - tx) * (h01 - h11) + (1 - tz) * (h10 - h11);
	};
	auto sun_visibility = [&](double x, double y, double z) {
		if (to_sun.y <= 0.0)
			return 0.0;
		double top = hi + 5.0;
		double t = cell, result = 1.0;
		for (int k = 0; k < 96; k++) {
			double qx = x + to_sun.x * t, qy = y + to_sun.y * t, qz = z + to_sun.z * t;
			if (qy > top || std::fabs(qx) > half || std::fabs(qz) > half || t > shadow_reach)
				break;
			double d = qy - surface(qx, qz);
			if (d < 0.0)
				return 0.0;
			result = std::min(result, softness * d / t);
			t *= 1.08;
		}
		return std::clamp(result, 0.0, 1.0);
	};
	auto sample_index = [&](double x, double z) {
		int ix = std::clamp((int)std::lround((x + half) / cell), 0, n - 1), iz = std::clamp((int)std::lround((z + half) / cell), 0, n - 1);
		return size_t(iz) * n + ix;
	};

	Dictionary all;
	int total = 0;
	for (int s = 0; s < species.size(); s++) {
		Dictionary sp = species[s];
		auto get = [&](const char *k, double def) { Variant v = sp.get(k, def); return (double)v; };
		String name = sp.get("name", String("planta_") + String::num_int64(s));
		const double density = get("density", 1.0) * density_scale; // por 100 m2
		if (density <= 0.0)
			continue;
		Vector3 pref = sp.get("biome", Vector3(1, 1, 1));
		const double slope_max = get("slope_max", 0.3), slope_min = get("slope_min", 0.0);
		const double alt_min = get("alt_min", 0.0), alt_max = get("alt_max", 1.0);
		const bool below_snow = (bool)sp.get("below_snow", true);
		const double river_min = get("river_min", 1.0);
		const double river_reach = std::max(0.1, get("river_reach", 30.0));
		const double wet_boost = std::max(0.0, get("wet_boost", 1.0));
		const bool wet_only = (bool)sp.get("wet_only", false);
		const double road_max = get("road_max", 0.05);
		const double scale_min = get("scale_min", 0.8), scale_max = get("scale_max", 1.2);
		const double tilt = std::clamp(get("tilt", 0.0), 0.0, 1.0);
		const double sink = get("sink", 0.05);
		const double clump = std::clamp(get("clump", 0.5), 0.0, 1.0);
		const double clump_scale = std::max(1.0, get("clump_scale", 40.0));
		const double canopy_radius = get("canopy_radius", 0.0);
		const double canopy_strength = get("canopy_strength", 0.5);
		const double max_mult = std::max(1.0, wet_boost);
		const double spacing = std::sqrt(100.0 / (density * max_mult));
		const int cells_side = std::max(1, (int)std::floor(extent / spacing));
		const double step = extent / cells_side;
		std::map<int, std::vector<float>> chunks;
		int count = 0;
		for (int gz = 0; gz < cells_side; gz++)
			for (int gx = 0; gx < cells_side; gx++) {
				// Muestreo con jitter: un candidato al azar dentro de cada celda.
				double x = -half + (gx + hash01(gx, gz, seed + s * 7919, 1)) * step;
				double z = -half + (gz + hash01(gx, gz, seed + s * 7919, 2)) * step;
				size_t i = sample_index(x, z);
				double q = biome[i * 3] * pref.x + biome[i * 3 + 1] * pref.y + biome[i * 3 + 2] * pref.z;
				if (q <= 0.0)
					continue;
				double h = surface(x, z);
				double alt = (h - lo) / range;
				if (alt < alt_min || alt > alt_max)
					continue;
				if (below_snow && h > snow_height)
					continue;
				if (!road_weight.empty() && road_weight[i] > road_max)
					continue;
				// Pendiente = 1 - N.y, con la normal de diferencias centrales.
				double hx = (surface(x + cell, z) - surface(x - cell, z)) / (2 * cell);
				double hz = (surface(x, z + cell) - surface(x, z - cell)) / (2 * cell);
				double ny = 1.0 / std::sqrt(hx * hx + 1.0 + hz * hz);
				double slope = 1.0 - ny;
				if (slope > slope_max || slope < slope_min)
					continue;
				q *= 1.0 - smooth01(slope_max * 0.6, slope_max, slope);
				// Rios: nunca dentro del agua; mas plantas cerca de la orilla (oasis en la costa).
				double bank = river_bank.empty() ? 1e9 : (double)river_bank[i];
				if (bank < river_min)
					continue;
				double wet = bank < 1e8 ? std::exp(-std::max(0.0, bank) / river_reach) : 0.0;
				if (wet_only && wet < 0.05)
					continue;
				q *= 1.0 + (wet_boost - 1.0) * wet;
				if (clump > 0.0) {
					double v = value_noise(x / clump_scale, z / clump_scale, seed + s * 31);
					q *= (1.0 - clump) + clump * smooth01(0.25, 0.75, v) * 2.0;
				}
				if (hash01(gx, gz, seed + s * 7919, 3) * max_mult >= q)
					continue;
				// Transformacion de la instancia: giro, escala y (para pastos) inclinacion.
				double yaw = hash01(gx, gz, seed + s * 7919, 4) * 6.283185307179586;
				double sc = scale_min + (scale_max - scale_min) * hash01(gx, gz, seed + s * 7919, 5);
				Vector3 N(-hx * ny, ny, -hz * ny);
				Vector3 up = Vector3(0, 1, 0).lerp(N, tilt).normalized();
				Vector3 fwd(std::sin(yaw), 0, std::cos(yaw));
				Vector3 right = up.cross(fwd).normalized();
				Vector3 back = right.cross(up).normalized();
				Vector3 bx = right * sc, by = up * sc, bz = back * sc;
				double y = h - sink * sc;
				int cx = std::clamp((int)std::floor((x + half) / chunk_m), 0, chunks_side - 1);
				int cz = std::clamp((int)std::floor((z + half) / chunk_m), 0, chunks_side - 1);
				std::vector<float> &buf = chunks[cz * chunks_side + cx];
				// MultiMesh.buffer (TRANSFORM_3D + colores + datos propios): fila por fila de la
				// matriz 3x4 [X Y Z | origen], luego el color de la instancia y INSTANCE_CUSTOM.
				// (En el renderer Compatibility hace falta use_colors: sin el, COLOR llega en negro.)
				float v = (float)(hash01(gx, gz, seed + s * 7919, 6) - 0.5) * 0.24f; // +-12% de variacion
				float warm = (float)(hash01(gx, gz, seed + s * 7919, 8) - 0.5) * 0.10f;
				const float row[20] = {
					(float)bx.x, (float)by.x, (float)bz.x, (float)x,
					(float)bx.y, (float)by.y, (float)bz.y, (float)y,
					(float)bx.z, (float)by.z, (float)bz.z, (float)z,
					1.0f + v + warm, 1.0f + v, 1.0f + v - warm, 1.0f,
					// INSTANCE_CUSTOM: fase del viento, sol (sombra del terreno), cielo (AO), libre.
					(float)hash01(gx, gz, seed + s * 7919, 7), (float)sun_visibility(x, h + 1.0 * sc, z), ao_map ? (*ao_map)[i] : 1.0f, 0.0f
				};
				buf.insert(buf.end(), row, row + 20);
				count++;
				if (canopy_radius > 0.0) {
					double R = canopy_radius * sc;
					int r = (int)std::ceil(R / cell);
					int ix = (int)std::lround((x + half) / cell), iz = (int)std::lround((z + half) / cell);
					for (int dz2 = -r; dz2 <= r; dz2++)
						for (int dx2 = -r; dx2 <= r; dx2++) {
							int qx = ix + dx2, qz = iz + dz2;
							if (qx < 0 || qz < 0 || qx >= n || qz >= n)
								continue;
							double d = std::hypot(qx * cell - half - x, qz * cell - half - z) / R;
							if (d >= 1.0)
								continue;
							float v = (float)(canopy_strength * (1.0 - d * d));
							float &c = canopy[size_t(qz) * n + qx];
							c = 1.0f - (1.0f - c) * (1.0f - v); // sombras que se suman sin pasar de 1
						}
				}
			}
		Dictionary chunk_dict;
		for (auto &entry : chunks) {
			PackedFloat32Array arr;
			arr.resize((int64_t)entry.second.size());
			memcpy(arr.ptrw(), entry.second.data(), entry.second.size() * sizeof(float));
			chunk_dict[entry.first] = arr;
		}
		Dictionary info;
		info["chunks"] = chunk_dict;
		info["count"] = count;
		all[name] = info;
		total += count;
	}
	PackedByteArray canopy_bytes;
	canopy_bytes.resize((int64_t)canopy.size());
	for (size_t i = 0; i < canopy.size(); i++)
		canopy_bytes.set((int64_t)i, (uint8_t)std::lround(std::clamp((double)canopy[i], 0.0, 1.0) * 255.0));
	layers["vegetacion"] = canopy;
	result["species"] = all;
	result["total"] = total;
	result["chunk_size_m"] = chunk_m;
	result["chunks_per_side"] = chunks_side;
	result["canopy"] = canopy_bytes;
	result["canopy_size"] = n;
	return result;
}

// ---------------------------------------------------------------------------
// Landmarks por tipo
// ---------------------------------------------------------------------------
Array TerrainMesh::find_landmark_features(Ref<TerrainNoise> terrain, Dictionary options) {
	Array out;
	const int n = final_n;
	if (n < 8 || final_height.size() != size_t(n) * n)
		return out;
	const double cell = final_cell, half = (n - 1) * cell * 0.5;
	auto opt = [&](const char *k, double def) { Variant v = options.get(k, def); return (double)v; };
	const std::vector<float> &biome = biome_weights(terrain, n, cell);
	const double spacing = opt("min_spacing", 150.0);
	struct Feature {
		std::string type;
		int i;
		double score;
		double value;
	};
	std::vector<Feature> chosen;
	auto far_enough = [&](int i) {
		for (const Feature &f : chosen) {
			double d = std::hypot((f.i % n - i % n) * cell, (f.i / n - i / n) * cell);
			if (d < spacing)
				return false;
		}
		return true;
	};
	auto take = [&](std::vector<Feature> &cands, int max_count) {
		std::sort(cands.begin(), cands.end(), [](const Feature &a, const Feature &b) { return a.score > b.score; });
		int taken = 0;
		for (const Feature &f : cands) {
			if (taken >= max_count)
				break;
			if (!far_enough(f.i))
				continue;
			chosen.push_back(f);
			taken++;
		}
	};
	auto edge_ok = [&](int i, int margin) {
		int x = i % n, z = i / n;
		return x >= margin && z >= margin && x < n - margin && z < n - margin;
	};
	const int margin = std::max(2, (int)std::ceil(opt("edge_margin", 40.0) / cell));

	// Picos: maximo local en un radio y prominencia aproximada (altura - minimo del entorno).
	{
		int r = std::max(2, (int)std::lround(opt("peak_radius", 120.0) / cell));
		std::vector<double> maxf = window_extreme(final_height, n, r, true);
		std::vector<double> minf = window_extreme(final_height, n, r * 2, false);
		std::vector<Feature> cands;
		double prominence = opt("peak_prominence", 20.0);
		for (int i = 0; i < n * n; i++) {
			if (!edge_ok(i, margin) || final_height[i] < maxf[i])
				continue;
			double prom = final_height[i] - minf[i];
			if (prom < prominence)
				continue;
			cands.push_back({ "pico", i, final_height[i] + prom * 0.5, prom });
		}
		take(cands, (int)opt("max_peaks", 6.0));
	}
	// Confluencias: celda de cauce a la que llegan dos cauces con area suficiente.
	if (!drainage.channel.empty() && river_threshold_used > 0.0) {
		std::vector<Feature> cands;
		const double min_area = opt("confluence_min_fraction", 0.35) * river_threshold_used;
		std::vector<std::vector<double>> donors(size_t(n) * n);
		for (int j = 0; j < n * n; j++) {
			int i = drainage.receiver[j];
			if (i >= 0 && drainage.channel[j] && drainage.channel[i] && drainage.accumulation[j] >= min_area)
				donors[i].push_back(drainage.accumulation[j]);
		}
		for (int i = 0; i < n * n; i++) {
			if (donors[i].size() < 2 || !edge_ok(i, margin))
				continue;
			std::sort(donors[i].begin(), donors[i].end(), std::greater<double>());
			cands.push_back({ "confluencia", i, donors[i][1], drainage.accumulation[i] });
		}
		take(cands, (int)opt("max_confluences", 6.0));
	}
	// Costa: llano en la region costera; mejor si hay un rio cerca (desembocadura, caleta).
	{
		std::vector<Feature> cands;
		int stride = std::max(1, (int)std::lround(opt("coast_stride", 12.0) / cell));
		double min_weight = opt("coast_min_weight", 0.7);
		for (int z = margin; z < n - margin; z += stride)
			for (int x = margin; x < n - margin; x += stride) {
				int i = z * n + x;
				double w = biome[size_t(i) * 3];
				if (w < min_weight)
					continue;
				double hx = (final_height[i + 1] - final_height[i - 1]) / (2 * cell);
				double hz = (final_height[i + n] - final_height[i - n]) / (2 * cell);
				double slope = std::sqrt(hx * hx + hz * hz);
				if (slope > opt("coast_max_slope", 0.08))
					continue;
				double bank = river_bank.empty() ? 1e9 : (double)river_bank[i];
				if (bank < 2.0)
					continue;
				double river_bonus = bank < 1e8 ? std::exp(-bank / 60.0) : 0.0;
				double score = w + 0.6 * river_bonus - slope * 3.0 + 0.1 * hash01(x, z, 3, 9);
				cands.push_back({ "costa", i, score, w });
			}
		take(cands, (int)opt("max_coast", 6.0));
	}

	int counters[3] = { 0, 0, 0 };
	for (const Feature &f : chosen) {
		Dictionary d;
		double x = (f.i % n) * cell - half, z = (f.i / n) * cell - half;
		d["type"] = String(f.type.c_str());
		d["position"] = Vector3(x, final_height[f.i], z);
		d["score"] = f.score;
		String label;
		if (f.type == "pico") {
			label = String("Mirador del pico ") + String::num_int64(++counters[0]) + " (" + String::num_int64((int64_t)std::lround(final_height[f.i])) + " m)";
			d["prominence"] = f.value;
		} else if (f.type == "confluencia") {
			label = String("Confluencia ") + String::num_int64(++counters[1]);
			d["drainage_area"] = f.value;
		} else {
			label = String("Caleta ") + String::num_int64(++counters[2]);
			d["coast_weight"] = f.value;
		}
		d["label"] = label;
		out.push_back(d);
	}
	return out;
}

// ---------------------------------------------------------------------------
// Chunks con LOD
// ---------------------------------------------------------------------------
void TerrainMesh::release_arrays() {
	kept_vertices = PackedVector3Array();
	kept_normals = PackedVector3Array();
	kept_colors = PackedColorArray();
	kept_uvs = PackedVector2Array();
	kept_regions = PackedFloat32Array();
	kept_ao = PackedFloat32Array();
}

// Cada chunk es una malla con sus propios vertices (bordes compartidos con el vecino),
// LOD por diezmado de la grilla (paso 2^k) y un "faldon": una tira vertical en el borde
// que tapa las grietas cuando dos chunks vecinos usan LOD distintos.
Array TerrainMesh::build_chunks(int chunk_cells, int lod_levels, double skirt_depth) {
	Array out;
	const int n = final_n;
	if (n < 3 || kept_vertices.size() != (int64_t)n * n || chunk_cells < 2)
		return out;
	const int grid = n - 1;
	const int per_side = (grid + chunk_cells - 1) / chunk_cells;
	lod_levels = std::clamp(lod_levels, 0, 4);
	const Vector3 *V = kept_vertices.ptr();
	const Vector3 *Nr = kept_normals.ptr();
	const Color *C = kept_colors.ptr();
	const Vector2 *UV = kept_uvs.ptr();
	const float *R = kept_regions.ptr();
	const float *AO = kept_ao.ptr();
	for (int cz = 0; cz < per_side; cz++)
		for (int cx = 0; cx < per_side; cx++) {
			const int x0 = cx * chunk_cells, z0 = cz * chunk_cells;
			const int x1 = std::min(grid, x0 + chunk_cells), z1 = std::min(grid, z0 + chunk_cells);
			const int w = x1 - x0 + 1, h = z1 - z0 + 1;
			PackedVector3Array verts, norms;
			PackedColorArray cols;
			PackedVector2Array uvs;
			PackedFloat32Array regions, ao;
			auto add_vertex = [&](int gx, int gz, double drop) {
				size_t src = size_t(gz) * n + gx;
				Vector3 p = V[src];
				p.y -= drop;
				verts.push_back(p);
				norms.push_back(Nr[src]);
				cols.push_back(C[src]);
				uvs.push_back(UV[src]);
				for (int k = 0; k < 4; k++)
					regions.push_back(R[src * 4 + k]);
				ao.push_back(AO[src]);
			};
			for (int z = z0; z <= z1; z++)
				for (int x = x0; x <= x1; x++)
					add_vertex(x, z, 0.0);
			// Faldon: copia de los vertices del borde, hundida skirt_depth metros.
			std::vector<int> ring; // indice local del vertice de borde, en orden
			for (int x = 0; x < w; x++)
				ring.push_back(x);
			for (int z = 1; z < h; z++)
				ring.push_back(z * w + (w - 1));
			for (int x = w - 2; x >= 0; x--)
				ring.push_back((h - 1) * w + x);
			for (int z = h - 2; z >= 1; z--)
				ring.push_back(z * w);
			const int skirt_base = verts.size();
			for (int local : ring)
				add_vertex(x0 + local % w, z0 + local / w, skirt_depth);
			std::vector<int> skirt_of(size_t(w) * h, -1);
			for (size_t k = 0; k < ring.size(); k++)
				skirt_of[ring[k]] = skirt_base + (int)k;

			auto grid_indices = [&](int stride) {
				PackedInt32Array idx;
				for (int z = 0; z < h - 1; z += stride) {
					int zb = std::min(z + stride, h - 1);
					for (int x = 0; x < w - 1; x += stride) {
						int xb = std::min(x + stride, w - 1);
						int i00 = z * w + x, i10 = z * w + xb, i01 = zb * w + x, i11 = zb * w + xb;
						idx.push_back(i00);
						idx.push_back(i10);
						idx.push_back(i01);
						idx.push_back(i10);
						idx.push_back(i11);
						idx.push_back(i01);
					}
				}
				// Faldon de este LOD: quads entre vertices de borde consecutivos (con paso stride).
				auto skirt_edge = [&](int a, int b) {
					int sa = skirt_of[a], sb = skirt_of[b];
					if (sa < 0 || sb < 0)
						return;
					// Las dos caras: se ve desde cualquier lado de la grieta.
					const int tri[12] = { a, b, sa, b, sb, sa, a, sa, b, b, sa, sb };
					for (int t : tri)
						idx.push_back(t);
				};
				for (int x = 0; x < w - 1; x += stride) {
					int xb = std::min(x + stride, w - 1);
					skirt_edge(x, xb);
					skirt_edge((h - 1) * w + x, (h - 1) * w + xb);
				}
				for (int z = 0; z < h - 1; z += stride) {
					int zb = std::min(z + stride, h - 1);
					skirt_edge(z * w, zb * w);
					skirt_edge(z * w + w - 1, zb * w + w - 1);
				}
				return idx;
			};
			// Error geometrico de cada LOD: diferencia vertical entre la grilla fina y la gruesa
			// (percentil 99, para que un solo corte angosto no impida usar el LOD en todo el chunk).
			auto lod_error = [&](int stride) {
				std::vector<double> errors;
				errors.reserve(size_t(w) * h);
				for (int z = 0; z < h; z++)
					for (int x = 0; x < w; x++) {
						int xa = (x / stride) * stride, za = (z / stride) * stride;
						int xb = std::min(xa + stride, w - 1), zb = std::min(za + stride, h - 1);
						double tx = xb > xa ? double(x - xa) / (xb - xa) : 0.0, tz = zb > za ? double(z - za) / (zb - za) : 0.0;
						auto Y = [&](int gx, int gz) { return (double)V[size_t(z0 + gz) * n + x0 + gx].y; };
						double coarse = tx + tz <= 1.0 ? Y(xa, za) + tx * (Y(xb, za) - Y(xa, za)) + tz * (Y(xa, zb) - Y(xa, za))
														: Y(xb, zb) + (1 - tx) * (Y(xa, zb) - Y(xb, zb)) + (1 - tz) * (Y(xb, za) - Y(xb, zb));
						errors.push_back(std::fabs(Y(x, z) - coarse));
					}
				size_t k = std::min(errors.size() - 1, size_t(errors.size() * 0.99));
				std::nth_element(errors.begin(), errors.begin() + k, errors.end());
				return errors[k];
			};
			Array arrays;
			arrays.resize(Mesh::ARRAY_MAX);
			arrays[Mesh::ARRAY_VERTEX] = verts;
			arrays[Mesh::ARRAY_NORMAL] = norms;
			arrays[Mesh::ARRAY_COLOR] = cols;
			arrays[Mesh::ARRAY_TEX_UV] = uvs;
			arrays[Mesh::ARRAY_CUSTOM0] = regions;
			arrays[Mesh::ARRAY_CUSTOM1] = ao;
			arrays[Mesh::ARRAY_INDEX] = grid_indices(1);
			Dictionary lods;
			double previous = 0.0;
			Array lod_info;
			for (int k = 1; k <= lod_levels; k++) {
				int stride = 1 << k;
				if (stride >= std::min(w, h))
					break;
				double e = std::max(lod_error(stride), previous + 0.01);
				previous = e;
				lods[e] = grid_indices(stride);
				lod_info.push_back(e);
			}
			Ref<ArrayMesh> mesh;
			mesh.instantiate();
			int64_t custom_format = (int64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT) |
					(int64_t(Mesh::ARRAY_CUSTOM_R_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM1_SHIFT);
			mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), lods, (BitField<Mesh::ArrayFormat>)custom_format);
			PackedFloat32Array heights;
			heights.resize((int64_t)w * h);
			for (int z = 0; z < h; z++)
				for (int x = 0; x < w; x++)
					heights.set((int64_t)z * w + x, (float)final_height[size_t(z0 + z) * n + x0 + x]);
			Dictionary chunk;
			chunk["mesh"] = mesh;
			chunk["origin"] = Vector2i(x0, z0);
			chunk["samples"] = Vector2i(w, h);
			chunk["heights"] = heights;
			const double half = grid * final_cell * 0.5;
			chunk["center"] = Vector3((x0 + (w - 1) * 0.5) * final_cell - half, 0.0, (z0 + (h - 1) * 0.5) * final_cell - half);
			chunk["lod_errors"] = lod_info;
			out.push_back(chunk);
		}
	return out;
}
