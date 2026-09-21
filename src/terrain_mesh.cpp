#include "terrain_mesh.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <cmath>
#include <vector>
#include <limits>

using namespace godot;

static inline double lerp_d(double a, double b, double t) { return a + t * (b - a); }
static inline double smoothstep_d(double a, double b, double x) {
    if (a == b) return x < a ? 0.0 : 1.0;
    double t = (x - a) / (b - a);
    if (t < 0.0) t = 0.0; if (t > 1.0) t = 1.0;
    return t * t * (3.0 - 2.0 * t);
}

void TerrainMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_mesh", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::generate_mesh);
}

TerrainMesh::TerrainMesh() {}

Ref<ArrayMesh> TerrainMesh::generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
    if (terrain.is_null()) return Ref<ArrayMesh>();

    auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
    double road_width = cfg_d("road_width", 4.0);
    double road_fade  = cfg_d("road_fade", 3.0);

    const double area_half = grid_size * cell_size * 0.5;
    const int n = grid_size + 1;
    const double offset = area_half;
    std::vector<double> H((size_t)n * n);
    std::vector<Color>  Cv((size_t)n * n);

    const std::vector<RoadSegment> *roads_ptr = roads.is_valid() ? &roads->get_roads_internal() : nullptr;

    for (int iz = 0; iz < n; iz++) {
        for (int ix = 0; ix < n; ix++) {
            double x = ix * cell_size - offset;
            double z = iz * cell_size - offset;
            double base_h = terrain->get_height(x, z);
            Color col = terrain->get_biome_color(x, z, base_h);

            if (roads_ptr && !roads_ptr->empty()) {
                double best_d = std::numeric_limits<double>::infinity();
                double best_h = 0.0;

                for (const RoadSegment &r : *roads_ptr) {
                    for (int i = 0; i + 1 < (int)r.pts.size(); i++) {
                        const Vector3 &a = r.pts[i];
                        const Vector3 &b = r.pts[i + 1];
                        double abx = b.x - a.x, abz = b.z - a.z;
                        double len2 = abx * abx + abz * abz;
                        double t = 0.0;
                        if (len2 > 0.0) {
                            t = ((x - a.x) * abx + (z - a.z) * abz) / len2;
                            if (t < 0.0) t = 0.0; if (t > 1.0) t = 1.0;
                        }
                        double cx = a.x + t * abx, cz = a.z + t * abz;
                        double dx = x - cx, dz = z - cz;
                        double dd = std::sqrt(dx * dx + dz * dz);
                        if (dd < best_d) { best_d = dd; best_h = lerp_d(r.h[i], r.h[i + 1], t); }
                    }
                }

                double w = 1.0 - smoothstep_d(road_width, road_width + road_fade, best_d);
                if (w > 0.0) {
                    base_h = lerp_d(base_h, best_h, w);
                    col = col.lerp(Color(0.40, 0.28, 0.16), w);
                }
            }

            H[(size_t)iz * n + ix] = base_h;
            Cv[(size_t)iz * n + ix] = col;
        }
    }

    PackedVector3Array verts; PackedColorArray cols; PackedVector3Array norms;
    auto Hv = [&](int ix, int iz) {
        if (ix < 0) ix = 0; if (ix >= n) ix = n - 1;
        if (iz < 0) iz = 0; if (iz >= n) iz = n - 1;
        return H[(size_t)iz * n + ix];
    };
    for (int iz = 0; iz < n; iz++) {
        for (int ix = 0; ix < n; ix++) {
            double x = ix * cell_size - offset;
            double z = iz * cell_size - offset;
            verts.push_back(Vector3(x, H[(size_t)iz * n + ix], z));
            cols.push_back(Cv[(size_t)iz * n + ix]);
            double dhdx = (Hv(ix + 1, iz) - Hv(ix - 1, iz)) / (2.0 * cell_size);
            double dhdz = (Hv(ix, iz + 1) - Hv(ix, iz - 1)) / (2.0 * cell_size);
            norms.push_back(Vector3(-dhdx, 1.0, -dhdz).normalized());
        }
    }

    PackedInt32Array idx;
    for (int iz = 0; iz < grid_size; iz++) {
        for (int ix = 0; ix < grid_size; ix++) {
            int i00 = iz * n + ix, i10 = iz * n + ix + 1;
            int i01 = (iz + 1) * n + ix, i11 = (iz + 1) * n + ix + 1;
            idx.push_back(i00); idx.push_back(i11); idx.push_back(i01);
            idx.push_back(i00); idx.push_back(i10); idx.push_back(i11);
        }
    }

    Array arrays; arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = norms;
    arrays[Mesh::ARRAY_COLOR]  = cols;
    arrays[Mesh::ARRAY_INDEX]  = idx;

    Ref<ArrayMesh> am; am.instantiate();
    am->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return am;
}