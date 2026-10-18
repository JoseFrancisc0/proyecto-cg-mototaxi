#ifndef TERRAIN_MESH_H
#define TERRAIN_MESH_H

#include "drainage.h"
#include "road_network.h"
#include "terrain_noise.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class TerrainMesh : public RefCounted {
	GDCLASS(TerrainMesh, RefCounted)

private:
	DrainageField drainage;
	std::vector<double> final_height;
	Ref<ArrayMesh> water_mesh, bridge_mesh;
	int final_n = 0;
	double final_cell = 1;

protected:
	static void _bind_methods();

public:
	TerrainMesh();
	Ref<ArrayMesh> get_water_mesh() const { return water_mesh; }
	Ref<ArrayMesh> get_bridge_mesh() const { return bridge_mesh; }
	double get_height(double x, double z) const;
	double get_drainage(double x, double z) const;
	Dictionary get_hydrology_data() const;

	Ref<ArrayMesh> generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
};

} //namespace godot

#endif // TERRAIN_MESH_H