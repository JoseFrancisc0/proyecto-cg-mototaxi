#ifndef TERRAIN_MESH_H
#define TERRAIN_MESH_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
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

    // Grilla de (grid_size + 1)^2 alturas con los caminos ya aplanados.
    // Devuelve {"heights": PackedFloat32Array, "colors": PackedColorArray}, fila a fila en z.
    Dictionary generate_heightmap(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
    Ref<ArrayMesh> build_mesh(PackedFloat32Array heights, PackedColorArray colors, int grid_size, double cell_size);
    Ref<ArrayMesh> generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
};

}

#endif // TERRAIN_MESH_H
