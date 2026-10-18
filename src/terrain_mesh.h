#ifndef TERRAIN_MESH_H
#define TERRAIN_MESH_H

#include "drainage.h"
#include "road_network.h"
#include "terrain_noise.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class TerrainMesh : public RefCounted {
	GDCLASS(TerrainMesh, RefCounted)

private:
	DrainageField drainage;
	// Suelo actual: T0 + erosiones aplicadas, ANTES de rios y caminos.
	std::vector<double> ground_height;
	int ground_n = 0;
	double ground_cell = 1;
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

	// T0 desde el ruido (+ erosion si cfg.erosion_enabled) y superficie final.
	Ref<ArrayMesh> generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	// Erosiona el suelo actual (no lo regenera) y reconstruye rios y caminos encima.
	Ref<ArrayMesh> erode_ground(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	// Reconstruye rios, caminos y malla sobre el suelo actual, sin erosionar.
	Ref<ArrayMesh> rebuild_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	PackedFloat32Array get_ground_heights() const;
	bool set_ground_heights(const PackedFloat32Array &heights, int grid_size, double cell_size);

private:
	void erode_heights(std::vector<double> &H, Ref<TerrainNoise> terrain, int n, double cell_size, const Dictionary &road_cfg);
	Ref<ArrayMesh> build_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
};

} //namespace godot

#endif // TERRAIN_MESH_H