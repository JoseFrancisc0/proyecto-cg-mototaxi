#ifndef TERRAIN_FIELD_H
#define TERRAIN_FIELD_H
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>
namespace godot {
// Shared immutable-after-generation numerical terrain. No scene nodes on the worker.
class TerrainField : public RefCounted {
	GDCLASS(TerrainField, RefCounted)
	int cells = 0, side = 0;
	double spacing = 1.0;
	std::vector<double> heights, initial;
	std::vector<float> drainage, road_mask;
	std::vector<float> regional_hardness, regional_talus;
	std::vector<Vector3> biomes;
	Array landmarks;
	Dictionary timings;
	void compute_drainage();
	void retarget(int iterations);
	Vector3 position(int x, int z) const;
	double sample(const std::vector<double> &data, double x, double z) const;

protected:
	static void _bind_methods();

public:
	bool generate(int seed, int grid_cells, double cell_size, Dictionary config);
	PackedFloat32Array erode_input(PackedFloat32Array input, int samples, double cell_size, Dictionary config) const;
	double get_height(double x, double z) const;
	Vector3 get_normal(double x, double z) const;
	Vector3 get_biome(double x, double z) const;
	double get_drainage(double x, double z) const;
	PackedFloat32Array get_heights() const;
	PackedFloat32Array get_initial_heights() const;
	PackedFloat32Array get_drainage_map() const;
	PackedFloat32Array get_surface_map() const;
	Array get_landmarks() const { return landmarks; }
	Dictionary get_timings() const { return timings; }
	Dictionary get_regional_maps() const;
	PackedVector3Array find_route(Vector3 start, Vector3 goal) const;
	Ref<ArrayMesh> build_chunk(int origin_x, int origin_z, int chunk_cells) const;
	PackedFloat32Array get_chunk_heights(int origin_x, int origin_z, int chunk_cells) const;
};
} //namespace godot
#endif
