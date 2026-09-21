#ifndef TERRAIN_MESH_H
#define TERRAIN_MESH_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/ref.hpp>
#include "terrain_noise.h"
#include "road_network.h"

namespace godot {

class TerrainMesh : public RefCounted {
    GDCLASS(TerrainMesh, RefCounted)

protected:
    static void _bind_methods();

public:
    TerrainMesh();

    Ref<ArrayMesh> generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
};

}

#endif // TERRAIN_MESH_H