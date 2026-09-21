#ifndef ROAD_NETWORK_H
#define ROAD_NETWORK_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/ref.hpp>
#include "terrain_noise.h"
#include <vector>

namespace godot {

struct RoadSegment {
    std::vector<Vector3> pts;
    std::vector<double> h;
};

class RoadNetwork : public RefCounted {
    GDCLASS(RoadNetwork, RefCounted)

private:
    std::vector<RoadSegment> _roads;

protected:
    static void _bind_methods();

public:
    RoadNetwork();

    PackedVector3Array find_path(Ref<TerrainNoise> terrain, Vector2 start, Vector2 goal, double area_half) const;
    void generate_roads(Ref<TerrainNoise> terrain, int grid_size, double cell_size, Dictionary road_cfg);

    const std::vector<RoadSegment>& get_roads_internal() const { return _roads; }
    int get_road_count() const { return (int)_roads.size(); }
};

}

#endif // ROAD_NETWORK_H