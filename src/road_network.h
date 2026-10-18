#ifndef ROAD_NETWORK_H
#define ROAD_NETWORK_H

#include "terrain_noise.h"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>

namespace godot {

struct RoadSegment {
	std::vector<Vector3> pts;
	std::vector<double> h;
	std::vector<unsigned char> elevated;
	int kind = 0; // 0 camino anterior, 1 carretera, 2 avenida, 3 calle.
	double half_width = -1.0; // Negativo: usar el ancho global anterior.
};

class RoadNetwork : public RefCounted {
	GDCLASS(RoadNetwork, RefCounted)

private:
	std::vector<RoadSegment> _roads;
	PackedVector3Array _town_centers;
	std::vector<double> surface;
	std::vector<unsigned char> water;
	int surface_n = 0;
	double surface_cell = 1;
	double sample_height(Ref<TerrainNoise> terrain, double x, double z) const;
	double sample_water(double x, double z) const;
	void _generate_hierarchy(Ref<TerrainNoise> terrain, double area_half, Dictionary config);

protected:
	static void _bind_methods();

public:
	RoadNetwork();
	void set_surface(const std::vector<double> &h, const std::vector<unsigned char> &mask, int n, double cell);
	void clear_surface();

	PackedVector3Array find_path(Ref<TerrainNoise> terrain, Vector2 start, Vector2 goal, double area_half) const;
	void generate_roads(Ref<TerrainNoise> terrain, int grid_size, double cell_size, Dictionary road_cfg);

	std::vector<RoadSegment> &get_roads_mutable() { return _roads; }
	const std::vector<RoadSegment> &get_roads_internal() const { return _roads; }
	int get_road_count() const { return (int)_roads.size(); }
	Array get_road_paths() const;
	Array get_road_metadata() const;
	PackedVector3Array get_town_centers() const { return _town_centers; }
};

} //namespace godot

#endif // ROAD_NETWORK_H
