#include "terrain_mesh.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <cmath>
#include <vector>
#include <limits>
#include <algorithm>

using namespace godot;

static inline double lerp_d(double a, double b, double t) { return a + t * (b - a); }
static inline double smoothstep_d(double a, double b, double x) {
    if (a == b) return x < a ? 0.0 : 1.0;
    double t = (x - a) / (b - a);
    if (t < 0.0) t = 0.0; if (t > 1.0) t = 1.0;
    return t * t * (3.0 - 2.0 * t);
}

void TerrainMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_heightmap", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::generate_heightmap);
    ClassDB::bind_method(D_METHOD("build_mesh", "heights", "colors", "grid_size", "cell_size"), &TerrainMesh::build_mesh);
    ClassDB::bind_method(D_METHOD("generate_mesh", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::generate_mesh);
}

TerrainMesh::TerrainMesh() {}

Dictionary TerrainMesh::generate_heightmap(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
    Dictionary out;
    if (terrain.is_null() || grid_size < 1) return out;

    auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
    double road_width = cfg_d("road_width", 4.0);
    double road_fade  = cfg_d("road_fade", 3.0);
    const double reach = road_width + road_fade;

    const double area_half = grid_size * cell_size * 0.5;
    const int n = grid_size + 1;
    PackedFloat32Array H; H.resize((int64_t)n * n);
    PackedColorArray  Cv; Cv.resize((int64_t)n * n);

    const std::vector<RoadSegment> *roads_ptr = roads.is_valid() ? &roads->get_roads_internal() : nullptr;

    // Caja envolvente de cada camino (ampliada por su zona de influencia) para descartar caminos lejanos.
    struct Box { double x0, z0, x1, z1; };
    std::vector<Box> boxes;
    if (roads_ptr) {
        for (const RoadSegment &r : *roads_ptr) {
            Box b{ std::numeric_limits<double>::infinity(), std::numeric_limits<double>::infinity(),
                  -std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity() };
            for (const Vector3 &p : r.pts) {
                b.x0 = std::min(b.x0, (double)p.x); b.x1 = std::max(b.x1, (double)p.x);
                b.z0 = std::min(b.z0, (double)p.z); b.z1 = std::max(b.z1, (double)p.z);
            }
            b.x0 -= reach; b.z0 -= reach; b.x1 += reach; b.z1 += reach;
            boxes.push_back(b);
        }
    }

    for (int iz = 0; iz < n; iz++) {
        for (int ix = 0; ix < n; ix++) {
            double x = ix * cell_size - area_half;
            double z = iz * cell_size - area_half;
            double base_h = terrain->get_height(x, z);
            Color col = terrain->get_biome_color(x, z, base_h);

            if (roads_ptr) {
                double best_d = std::numeric_limits<double>::infinity();
                double best_h = 0.0;

                for (size_t ri = 0; ri < roads_ptr->size(); ri++) {
                    const Box &b = boxes[ri];
                    if (x < b.x0 || x > b.x1 || z < b.z0 || z > b.z1) continue;
                    const RoadSegment &r = (*roads_ptr)[ri];
                    for (int i = 0; i + 1 < (int)r.pts.size(); i++) {
                        const Vector3 &a = r.pts[i];
                        const Vector3 &c = r.pts[i + 1];
                        double abx = c.x - a.x, abz = c.z - a.z;
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

                double w = 1.0 - smoothstep_d(road_width, reach, best_d);
                if (w > 0.0) {
                    base_h = lerp_d(base_h, best_h, w);
                    col = col.lerp(Color(0.40, 0.28, 0.16), w);
                }
            }

            H.set((int64_t)iz * n + ix, (float)base_h);
            Cv.set((int64_t)iz * n + ix, col);
        }
    }

    out["heights"] = H;
    out["colors"] = Cv;
    return out;
}

Ref<ArrayMesh> TerrainMesh::build_mesh(PackedFloat32Array heights, PackedColorArray colors, int grid_size, double cell_size) {
    const int n = grid_size + 1;
    if (grid_size < 1 || heights.size() != (int64_t)n * n) return Ref<ArrayMesh>();
    const bool has_colors = colors.size() == heights.size();
    const double offset = grid_size * cell_size * 0.5;
    const float *H = heights.ptr();

    auto Hv = [&](int ix, int iz) {
        if (ix < 0) ix = 0; if (ix >= n) ix = n - 1;
        if (iz < 0) iz = 0; if (iz >= n) iz = n - 1;
        return (double)H[(size_t)iz * n + ix];
    };

    PackedVector3Array verts; PackedVector3Array norms; PackedColorArray cols;
    verts.resize((int64_t)n * n); norms.resize((int64_t)n * n);
    if (has_colors) cols = colors;
    for (int iz = 0; iz < n; iz++) {
        for (int ix = 0; ix < n; ix++) {
            int64_t i = (int64_t)iz * n + ix;
            verts.set(i, Vector3(ix * cell_size - offset, H[i], iz * cell_size - offset));
            double dhdx = (Hv(ix + 1, iz) - Hv(ix - 1, iz)) / (2.0 * cell_size);
            double dhdz = (Hv(ix, iz + 1) - Hv(ix, iz - 1)) / (2.0 * cell_size);
            norms.set(i, Vector3(-dhdx, 1.0, -dhdz).normalized());
        }
    }

    PackedInt32Array idx;
    idx.resize((int64_t)grid_size * grid_size * 6);
    int64_t k = 0;
    for (int iz = 0; iz < grid_size; iz++) {
        for (int ix = 0; ix < grid_size; ix++) {
            int i00 = iz * n + ix, i10 = iz * n + ix + 1;
            int i01 = (iz + 1) * n + ix, i11 = (iz + 1) * n + ix + 1;
            idx.set(k++, i00); idx.set(k++, i11); idx.set(k++, i01);
            idx.set(k++, i00); idx.set(k++, i10); idx.set(k++, i11);
        }
    }

    Array arrays; arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_NORMAL] = norms;
    if (has_colors) arrays[Mesh::ARRAY_COLOR] = cols;
    arrays[Mesh::ARRAY_INDEX]  = idx;

    Ref<ArrayMesh> am; am.instantiate();
    am->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return am;
}

Ref<ArrayMesh> TerrainMesh::generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
    Dictionary hm = generate_heightmap(terrain, roads, grid_size, cell_size, road_cfg);
    if (hm.is_empty()) return Ref<ArrayMesh>();
    return build_mesh(hm["heights"], hm["colors"], grid_size, cell_size);
}
