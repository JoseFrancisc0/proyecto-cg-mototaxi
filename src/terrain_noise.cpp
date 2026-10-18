#include "terrain_noise.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

static const double LACUNARITY = 2.0;
static const double PERSISTENCE = 0.5;
static const int OCTAVES = 3; // antes 6
static const double CONTROL_FREQUENCY = 0.004; // antes 0.012
static const double SIERRA_THRESHOLD = 0.40; // antes 0.55
static const double BIOME_BAND = 0.25; // antes 0.10
static const double SIERRA_BASE = 35.0, SIERRA_AMP = 55.0, SIERRA_FREQ = 0.006; // antes 0.028
static const double SELVA_BASE = -10.0, SELVA_AMP = 15.0, SELVA_FREQ = 0.005; // antes 7.0 y 0.020

void TerrainNoise::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure_regions", "config"), &TerrainNoise::configure_regions);
	ClassDB::bind_method(D_METHOD("get_biome_weights", "x", "z"), &TerrainNoise::get_biome_weights);
	ClassDB::bind_method(D_METHOD("get_hardness", "x", "z"), &TerrainNoise::get_hardness);
	ClassDB::bind_method(D_METHOD("get_critical_slope", "x", "z"), &TerrainNoise::get_critical_slope);
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &TerrainNoise::set_seed);
	ClassDB::bind_method(D_METHOD("get_seed"), &TerrainNoise::get_seed);
	ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &TerrainNoise::get_height);
	ClassDB::bind_method(D_METHOD("get_elevation", "x", "z"), &TerrainNoise::get_elevation);
	ClassDB::bind_method(D_METHOD("get_moisture", "x", "z"), &TerrainNoise::get_moisture);
	ClassDB::bind_method(D_METHOD("get_biome_blend", "x", "z"), &TerrainNoise::get_biome_blend);
	ClassDB::bind_method(D_METHOD("get_biome_color", "x", "z", "base_h"), &TerrainNoise::get_biome_color);
}

TerrainNoise::TerrainNoise() { set_seed(1337); }

static inline double fade(double t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }
static inline double lerp_d(double a, double b, double t) { return a + t * (b - a); }
static inline double smoothstep_d(double a, double b, double x) {
	if (a == b)
		return x < a ? 0.0 : 1.0;
	double t = (x - a) / (b - a);
	if (t < 0.0)
		t = 0.0;
	if (t > 1.0)
		t = 1.0;
	return t * t * (3.0 - 2.0 * t);
}

double TerrainNoise::_grad(int hash, double x, double y) const {
	switch (hash & 7) {
		case 0:
			return x + y;
		case 1:
			return -x + y;
		case 2:
			return x - y;
		case 3:
			return -x - y;
		case 4:
			return x;
		case 5:
			return -x;
		case 6:
			return y;
		default:
			return -y;
	}
}

double TerrainNoise::_perlin(int channel, double x, double y) const {
	const int *p = perm[channel];
	int xi = (int)std::floor(x) & 255;
	int yi = (int)std::floor(y) & 255;
	double xf = x - std::floor(x), yf = y - std::floor(y);
	double u = fade(xf), v = fade(yf);
	int aa = p[p[xi] + yi];
	int ab = p[p[xi] + yi + 1];
	int ba = p[p[xi + 1] + yi];
	int bb = p[p[xi + 1] + yi + 1];
	double x1 = lerp_d(_grad(aa, xf, yf), _grad(ba, xf - 1.0, yf), u);
	double x2 = lerp_d(_grad(ab, xf, yf - 1.0), _grad(bb, xf - 1.0, yf - 1.0), u);
	return lerp_d(x1, x2, v);
}

void TerrainNoise::_build_permutation(int *table, int seed) {
	int base[256];
	for (int i = 0; i < 256; i++)
		base[i] = i;
	unsigned int state = (unsigned int)seed;
	for (int i = 255; i > 0; i--) {
		state = state * 1664525u + 1013904223u;
		int j = (int)(state % (unsigned int)(i + 1));
		int t = base[i];
		base[i] = base[j];
		base[j] = t;
	}
	for (int i = 0; i < 512; i++)
		table[i] = base[i & 255];
}

void TerrainNoise::set_seed(int seed) {
	_seed = seed;
	_build_permutation(perm[CH_DETAIL], seed);
	_build_permutation(perm[CH_ELEVATION], int(unsigned(seed) + 7919u));
	_build_permutation(perm[CH_MOISTURE], int(unsigned(seed) + 104729u));
	_build_regions();
}

void TerrainNoise::_build_regions() {
	// Semillas locales reproducibles: no dependen del orden de consultas.
	unsigned state = unsigned(_seed) ^ 0x9e3779b9u;
	auto random01 = [&]() { state = state * 1664525u + 1013904223u; return double(state >> 8) / 16777216.0; };
	int columns = int(std::ceil(std::sqrt(double(region_patches))));
	int rows = (region_patches + columns - 1) / columns;
	std::vector<int> labels(region_patches);
	double probabilities[3] = { 0.2 + random01(), 0.2 + random01(), 0.2 + random01() };
	double total = probabilities[0] + probabilities[1] + probabilities[2];
	for (int i = 0; i < region_patches; i++) {
		double choice = random01() * total;
		labels[i] = i < 3 ? i : (choice < probabilities[0] ? 0 : (choice < probabilities[0] + probabilities[1] ? 1 : 2));
	}
	for (int i = region_patches - 1; i > 0; i--)
		std::swap(labels[i], labels[int(random01() * (i + 1))]);
	region_sites.clear();
	for (int i = 0; i < region_patches; i++) {
		double x = (i % columns + 0.5 + (random01() - 0.5) * 0.64) / columns - 0.5;
		double z = (i / columns + 0.5 + (random01() - 0.5) * 0.64) / rows - 0.5;
		region_sites.push_back({ x, z, (random01() - 0.5) * 0.036, labels[i] });
	}
}

void TerrainNoise::configure_regions(Dictionary config) {
	regions_enabled = bool(config.get("enabled", true));
	auto value = [&](const char *key, double fallback) {
		double v = double(config.get(key, fallback));
		return std::isfinite(v) ? v : fallback;
	};
	region_extent = std::max(1.0, value("extent", 768.0));
	transition_width = std::clamp(value("transition_width", 0.16), 0.02, 0.25);
	border_warp = std::clamp(value("border_warp", 0.16), 0.0, 0.30);
	region_patches = std::clamp(int(value("region_patches", 16)), 6, 32);
	_build_regions();
	coast_params = { value("coast_base", 4), std::max(0.0, value("coast_amplitude", 4)), std::max(0.00001, value("coast_frequency", 0.003)), OCTAVES };
	mountain_params = { value("mountain_base", 130), std::max(0.0, value("mountain_amplitude", 85)), std::max(0.00001, value("mountain_frequency", 0.008)), OCTAVES };
	jungle_params = { value("jungle_base", 28), std::max(0.0, value("jungle_amplitude", 14)), std::max(0.00001, value("jungle_frequency", 0.004)), OCTAVES };
	hardness_values = Vector3(std::clamp(value("coast_hardness", 0.10), 0.0, 1.0), std::clamp(value("mountain_hardness", 0.65), 0.0, 1.0), std::clamp(value("jungle_hardness", 0.35), 0.0, 1.0));
	talus_values = Vector3(std::max(0.01, value("coast_talus", 0.25)), std::max(0.01, value("mountain_talus", 1.15)), std::max(0.01, value("jungle_talus", 0.60)));
}

Vector3 TerrainNoise::get_biome_weights(double x, double z) const {
	if (!regions_enabled) {
		double t = smoothstep_d(SIERRA_THRESHOLD - BIOME_BAND, SIERRA_THRESHOLD + BIOME_BAND, get_elevation(x, z));
		return Vector3(0, t, 1 - t);
	}
	// Regiones del proyecto: Voronoi ponderado y deformado por ruido.
	// Un bioma puede ocupar varias zonas, sin orden obligatorio ni cuotas iguales.
	// La mezcla continua sigue alimentando T0 y los mapas rho/s0 del paper.
	double ux = x / region_extent, uz = z / region_extent;
	ux += border_warp * 0.5 * _perlin(CH_ELEVATION, ux * 3.0 + 13.7, uz * 3.0 - 7.3);
	uz += border_warp * 0.5 * _perlin(CH_MOISTURE, x * 3.0 / region_extent - 5.1, z * 3.0 / region_extent + 11.9);
	double distance[3] = { 1e20, 1e20, 1e20 };
	for (const RegionSite &site : region_sites) {
		double d = std::hypot(ux - site.x, uz - site.z) + site.bias;
		distance[site.biome] = std::min(distance[site.biome], d);
	}
	double closest = std::min(distance[0], std::min(distance[1], distance[2]));
	double band = transition_width * 0.5;
	Vector3 weights;
	for (int biome = 0; biome < 3; biome++)
		weights[biome] = 1.0 - smoothstep_d(0.0, band, distance[biome] - closest);
	return weights / (weights.x + weights.y + weights.z);
}

double TerrainNoise::get_hardness(double x, double z) const {
	Vector3 w = get_biome_weights(x, z);
	// Paper, seccion 4.2: k(p) = k * (1-rho(p)); rho=1 resiste erosion.
	// Los coeficientes regionales son parametros del proyecto, a calibrar.
	double fractal = (_perlin(CH_MOISTURE, x * 0.015, z * 0.015) + 0.5 * _perlin(CH_MOISTURE, x * 0.03, z * 0.03)) / 1.5;
	return std::clamp(double(w.dot(hardness_values)) + w.y * 0.08 * fractal, 0.0, 1.0);
}

double TerrainNoise::get_critical_slope(double x, double z) const {
	// Paper, seccion 4.3: s0(p)=tan(gamma0(p)); es pendiente, no grados.
	Vector3 w = get_biome_weights(x, z);
	double variation = 1 + 0.08 * w.y * _perlin(CH_MOISTURE, x * 0.015, z * 0.015);
	return std::max(0.01, double(w.dot(talus_values)) * variation);
}

TerrainNoise::BiomeParams TerrainNoise::_biome_params(double e, double h) const {
	double t = smoothstep_d(SIERRA_THRESHOLD - BIOME_BAND, SIERRA_THRESHOLD + BIOME_BAND, e);
	BiomeParams p;
	p.base_height = lerp_d(SELVA_BASE, SIERRA_BASE, t);
	p.amplitude = lerp_d(SELVA_AMP, SIERRA_AMP, t);
	p.frequency = lerp_d(SELVA_FREQ, SIERRA_FREQ, t);
	p.octaves = OCTAVES;
	return p;
}

double TerrainNoise::get_height(double x, double z) const {
 auto sample=[&](const BiomeParams &p) {
  double total=0,freq=p.frequency,amp=1,maxv=0;
  for(int i=0;i<p.octaves;i++) {
   total+=_perlin(CH_DETAIL,x*freq,z*freq)*amp;
   maxv+=amp;amp*=PERSISTENCE;freq*=LACUNARITY;
  }
  return p.base_height+(total/maxv)*p.amplitude;
 };
 if(regions_enabled) {
  Vector3 w=get_biome_weights(x,z);
  // Preserve the team's Perlin/fBm for each regional parameter set.
  // Blend heights, not frequencies: a varying frequency shifts noise phase
  // across borders and can introduce spurious ridges in coast/jungle areas.
  return (w.x>0?w.x*sample(coast_params):0)+(w.y>0?w.y*sample(mountain_params):0)+(w.z>0?w.z*sample(jungle_params):0);
 }
 return sample(_biome_params(get_elevation(x,z),get_moisture(x,z)));
}

double TerrainNoise::get_elevation(double x, double z) const {
	double v = _perlin(CH_ELEVATION, x * CONTROL_FREQUENCY, z * CONTROL_FREQUENCY);
	v = (v + 1.0) * 0.5;
	if (v < 0.0)
		v = 0.0;
	if (v > 1.0)
		v = 1.0;
	return v;
}

double TerrainNoise::get_moisture(double x, double z) const {
	double v = _perlin(CH_MOISTURE, x * CONTROL_FREQUENCY, z * CONTROL_FREQUENCY);
	v = (v + 1.0) * 0.5;
	if (v < 0.0)
		v = 0.0;
	if (v > 1.0)
		v = 1.0;
	return v;
}

double TerrainNoise::get_biome_blend(double x, double z) const {
	if (regions_enabled)
		return get_biome_weights(x, z).y;
	double e = get_elevation(x, z);
	return smoothstep_d(SIERRA_THRESHOLD - BIOME_BAND, SIERRA_THRESHOLD + BIOME_BAND, e);
}

Color TerrainNoise::get_biome_color(double x, double z, double base_h) const {
	double t = get_biome_blend(x, z);
	Color col = Color(0.20, 0.45, 0.15).lerp(Color(0.45, 0.38, 0.28), t);
	if (regions_enabled) {
		Vector3 w = get_biome_weights(x, z);
		col = Color(0.65, 0.56, 0.36) * w.x + Color(0.45, 0.38, 0.28) * w.y + Color(0.20, 0.45, 0.15) * w.z;
	}
	if (base_h > 60.0) {
		double g = (base_h - 60.0) / 30.0;
		if (g < 0)
			g = 0;
		if (g > 1)
			g = 1;
		col = col.lerp(Color(0.55, 0.55, 0.55), g);
	}
	return col;
}
