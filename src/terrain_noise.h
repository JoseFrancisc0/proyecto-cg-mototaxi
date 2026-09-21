#ifndef TERRAIN_NOISE_H
#define TERRAIN_NOISE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>

namespace godot {

class TerrainNoise : public RefCounted {
    GDCLASS(TerrainNoise, RefCounted)

public:
    enum Channel { CH_DETAIL = 0, CH_ELEVATION = 1, CH_MOISTURE = 2, CH_COUNT = 3 };

private:
    int perm[CH_COUNT][512];
    int _seed = 1337;

    struct BiomeParams { double base_height, amplitude, frequency; int octaves; };

    void _build_permutation(int *table, int seed);
    double _grad(int hash, double x, double y) const;
    double _perlin(int channel, double x, double y) const;
    BiomeParams _biome_params(double e, double h) const;

protected:
    static void _bind_methods();

public:
    TerrainNoise();

    void set_seed(int seed);
    int get_seed() const { return _seed; }

    double get_height(double x, double z) const;
    double get_elevation(double x, double z) const;
    double get_moisture(double x, double z) const;
    double get_biome_blend(double x, double z) const;
    Color get_biome_color(double x, double z, double base_h) const;
};

}

#endif // TERRAIN_NOISE_H