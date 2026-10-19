#ifndef TERRAIN_NOISE_H
#define TERRAIN_NOISE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>

namespace godot {

class TerrainNoise : public RefCounted {
	GDCLASS(TerrainNoise, RefCounted)

public:
	enum Channel { CH_DETAIL = 0,
		CH_ELEVATION = 1,
		CH_MOISTURE = 2,
		CH_COUNT = 3 };

private:
	int perm[CH_COUNT][512];
	int _seed = 1337;
	bool regions_enabled = false;
	double region_extent = 768.0, transition_width = 0.16, border_warp = 0.16;
	struct RegionSite {
		double x, z, bias;
		int biome;
	};
	int region_patches = 16;
	std::vector<RegionSite> region_sites;
	void _build_regions();

	struct BiomeParams {
		double base_height, amplitude, frequency;
		int octaves;
	};
	BiomeParams coast_params = { 4.0, 4.0, 0.003, 3 };
	BiomeParams mountain_params = { 130.0, 85.0, 0.008, 3 };
	BiomeParams jungle_params = { 28.0, 14.0, 0.004, 3 };
	Vector3 hardness_values = Vector3(0.10, 0.65, 0.35);
	Vector3 talus_values = Vector3(0.25, 1.15, 0.60);

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
	void configure_regions(Dictionary config);
	Vector3 get_biome_weights(double x, double z) const;
	double get_hardness(double x, double z) const;
	double get_critical_slope(double x, double z) const;
};

} //namespace godot

#endif // TERRAIN_NOISE_H
