#include "terrain_noise.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>

using namespace godot;

static const double LACUNARITY  = 2.0;
static const double PERSISTENCE = 0.5;
static const int    OCTAVES     = 6;
static const double CONTROL_FREQUENCY = 0.012;
static const double SIERRA_THRESHOLD = 0.55;
static const double BIOME_BAND       = 0.10;
static const double SIERRA_BASE = 35.0, SIERRA_AMP = 55.0, SIERRA_FREQ = 0.028;
static const double SELVA_BASE  = -10.0, SELVA_AMP  = 7.0,  SELVA_FREQ  = 0.020;

void TerrainNoise::_bind_methods() {
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
    if (a == b) return x < a ? 0.0 : 1.0;
    double t = (x - a) / (b - a);
    if (t < 0.0) t = 0.0; if (t > 1.0) t = 1.0;
    return t * t * (3.0 - 2.0 * t);
}

double TerrainNoise::_grad(int hash, double x, double y) const {
    switch (hash & 7) {
        case 0: return x + y;  case 1: return -x + y;
        case 2: return x - y;  case 3: return -x - y;
        case 4: return x;      case 5: return -x;
        case 6: return y;      default: return -y;
    }
}

double TerrainNoise::_perlin(int channel, double x, double y) const {
    const int *p = perm[channel];
    int xi = (int)std::floor(x) & 255;
    int yi = (int)std::floor(y) & 255;
    double xf = x - std::floor(x), yf = y - std::floor(y);
    double u = fade(xf), v = fade(yf);
    int aa = p[p[xi]     + yi];
    int ab = p[p[xi]     + yi + 1];
    int ba = p[p[xi + 1] + yi];
    int bb = p[p[xi + 1] + yi + 1];
    double x1 = lerp_d(_grad(aa, xf, yf),       _grad(ba, xf - 1.0, yf),       u);
    double x2 = lerp_d(_grad(ab, xf, yf - 1.0), _grad(bb, xf - 1.0, yf - 1.0), u);
    return lerp_d(x1, x2, v);
}

void TerrainNoise::_build_permutation(int *table, int seed) {
    int base[256];
    for (int i = 0; i < 256; i++) base[i] = i;
    unsigned int state = (unsigned int)seed;
    for (int i = 255; i > 0; i--) {
        state = state * 1664525u + 1013904223u;
        int j = (int)(state % (unsigned int)(i + 1));
        int t = base[i]; base[i] = base[j]; base[j] = t;
    }
    for (int i = 0; i < 512; i++) table[i] = base[i & 255];
}

void TerrainNoise::set_seed(int seed) {
    _seed = seed;
    _build_permutation(perm[CH_DETAIL],    seed);
    _build_permutation(perm[CH_ELEVATION], seed + 7919);
    _build_permutation(perm[CH_MOISTURE],  seed + 104729);
}

TerrainNoise::BiomeParams TerrainNoise::_biome_params(double e, double h) const {
    double t = smoothstep_d(SIERRA_THRESHOLD - BIOME_BAND, SIERRA_THRESHOLD + BIOME_BAND, e);
    BiomeParams p;
    p.base_height = lerp_d(SELVA_BASE, SIERRA_BASE, t);
    p.amplitude   = lerp_d(SELVA_AMP,  SIERRA_AMP,  t);
    p.frequency   = lerp_d(SELVA_FREQ, SIERRA_FREQ, t);
    p.octaves     = OCTAVES;
    return p;
}

double TerrainNoise::get_height(double x, double z) const {
    double e = get_elevation(x, z);
    double h = get_moisture(x, z);
    BiomeParams bp = _biome_params(e, h);
    double total = 0.0, freq = bp.frequency, amp = 1.0, maxv = 0.0;
    for (int i = 0; i < bp.octaves; i++) {
        total += _perlin(CH_DETAIL, x * freq, z * freq) * amp;
        maxv += amp; amp *= PERSISTENCE; freq *= LACUNARITY;
    }
    return bp.base_height + (total / maxv) * bp.amplitude;
}

double TerrainNoise::get_elevation(double x, double z) const {
    double v = _perlin(CH_ELEVATION, x * CONTROL_FREQUENCY, z * CONTROL_FREQUENCY);
    v = (v + 1.0) * 0.5; if (v < 0.0) v = 0.0; if (v > 1.0) v = 1.0; return v;
}

double TerrainNoise::get_moisture(double x, double z) const {
    double v = _perlin(CH_MOISTURE, x * CONTROL_FREQUENCY, z * CONTROL_FREQUENCY);
    v = (v + 1.0) * 0.5; if (v < 0.0) v = 0.0; if (v > 1.0) v = 1.0; return v;
}

double TerrainNoise::get_biome_blend(double x, double z) const {
    double e = get_elevation(x, z);
    return smoothstep_d(SIERRA_THRESHOLD - BIOME_BAND, SIERRA_THRESHOLD + BIOME_BAND, e);
}

Color TerrainNoise::get_biome_color(double x, double z, double base_h) const {
    double t = get_biome_blend(x, z);
    Color col = Color(0.20, 0.45, 0.15).lerp(Color(0.45, 0.38, 0.28), t);
    if (base_h > 60.0) {
        double g = (base_h - 60.0) / 30.0; if (g < 0) g = 0; if (g > 1) g = 1;
        col = col.lerp(Color(0.55, 0.55, 0.55), g);
    }
    return col;
}