#include "road_network.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <queue>
#include <limits>
#include <algorithm>
#include <set>
#include <random>

using namespace godot;

static const double PATH_SPACING = 2.0;
static const double SLOPE_WEIGHT = 2.0;

void RoadNetwork::_bind_methods() {
    ClassDB::bind_method(D_METHOD("find_path", "terrain", "start", "goal", "area_half"), &RoadNetwork::find_path);
    ClassDB::bind_method(D_METHOD("generate_roads", "terrain", "grid_size", "cell_size", "road_cfg"), &RoadNetwork::generate_roads);
    ClassDB::bind_method(D_METHOD("get_road_count"), &RoadNetwork::get_road_count);
    ClassDB::bind_method(D_METHOD("get_poi_points"), &RoadNetwork::get_poi_points);
}

RoadNetwork::RoadNetwork() {}

PackedVector2Array RoadNetwork::get_poi_points() const {
    PackedVector2Array out;
    for (const Vector2 &p : _pois) out.push_back(p);
    return out;
}

PackedVector3Array RoadNetwork::find_path(Ref<TerrainNoise> terrain, Vector2 start, Vector2 goal, double area_half) const {
    PackedVector3Array path;
    if (terrain.is_null()) return path;

    const int W = (int)std::round((2.0 * area_half) / PATH_SPACING) + 1;
    const int count = W * W;
    auto nx = [&](int ix) { return -area_half + ix * PATH_SPACING; };
    auto nz = [&](int iz) { return -area_half + iz * PATH_SPACING; };
    auto cl = [&](int v) { return v < 0 ? 0 : (v >= W ? W - 1 : v); };

    int sx = cl((int)std::round((start.x + area_half) / PATH_SPACING));
    int sz = cl((int)std::round((start.y + area_half) / PATH_SPACING));
    int gx = cl((int)std::round((goal.x  + area_half) / PATH_SPACING));
    int gz = cl((int)std::round((goal.y  + area_half) / PATH_SPACING));
    int start_i = sz * W + sx, goal_i = gz * W + gx;

    std::vector<double> height(count);
    for (int iz = 0; iz < W; iz++)
        for (int ix = 0; ix < W; ix++)
            height[iz * W + ix] = terrain->get_height(nx(ix), nz(iz));

    std::vector<double> g(count, std::numeric_limits<double>::infinity());
    std::vector<int> came(count, -1);
    std::vector<bool> closed(count, false);
    auto heur = [&](int i) {
        double dx = nx(i % W) - nx(gx), dz = nz(i / W) - nz(gz);
        return std::sqrt(dx * dx + dz * dz);
    };
    using Item = std::pair<double, int>;
    std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
    g[start_i] = 0.0; open.push({heur(start_i), start_i});
    const int dxs[8] = {1,-1,0,0,1,1,-1,-1};
    const int dzs[8] = {0,0,1,-1,1,-1,1,-1};

    while (!open.empty()) {
        int cur = open.top().second; open.pop();
        if (closed[cur]) continue;
        if (cur == goal_i) break;
        closed[cur] = true;
        int cix = cur % W, ciz = cur / W;
        for (int d = 0; d < 8; d++) {
            int nix = cix + dxs[d], niz = ciz + dzs[d];
            if (nix < 0 || nix >= W || niz < 0 || niz >= W) continue;
            int ni = niz * W + nix;
            if (closed[ni]) continue;
            double horiz = (dxs[d] && dzs[d]) ? PATH_SPACING * 1.41421356 : PATH_SPACING;
            double dh = std::fabs(height[ni] - height[cur]);
            double tent = g[cur] + horiz + SLOPE_WEIGHT * dh;
            if (tent < g[ni]) { g[ni] = tent; came[ni] = cur; open.push({tent + heur(ni), ni}); }
        }
    }

    if (goal_i != start_i && came[goal_i] == -1) return path;
    std::vector<int> rev;
    for (int c = goal_i; c != -1; c = came[c]) rev.push_back(c);
    for (int k = (int)rev.size() - 1; k >= 0; k--) {
        int i = rev[k];
        path.push_back(Vector3(nx(i % W), height[i], nz(i / W)));
    }
    return path;
}

void RoadNetwork::generate_roads(Ref<TerrainNoise> terrain, int grid_size, double cell_size, Dictionary road_cfg) {
    _roads.clear();
    _pois.clear();
    if (terrain.is_null()) return;

    auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
    int    num_points = (int)cfg_d("num_points", 6.0);
    double min_dist   = cfg_d("min_point_dist", 25.0);
    int    k_neigh    = (int)cfg_d("k_neighbors", 2.0);
    int    road_smth  = (int)cfg_d("road_smooth", 3.0);

    const double area_half = grid_size * cell_size * 0.5;

    std::mt19937 rng((unsigned int)terrain->get_seed());
    double r_min = -area_half + 12.0;
    double r_max = area_half - 12.0;
    if (r_min >= r_max) {
        r_min = 0.0;
        r_max = 0.1;
    }
    std::uniform_real_distribution<double> ud(r_min, r_max);
    std::vector<Vector2> pts;
    int attempts = 0;
    while ((int)pts.size() < num_points && attempts < num_points * 300) {
        attempts++;
        double x = ud(rng), z = ud(rng);
        if (terrain->get_biome_blend(x, z) > 0.45) continue;
        bool ok = true;
        for (const Vector2 &p : pts) {
            double dx = x - p.x, dz = z - p.y;
            if (std::sqrt(dx * dx + dz * dz) < min_dist) { ok = false; break; }
        }
        if (ok) pts.push_back(Vector2(x, z));
    }
    _pois = pts;

    std::set<std::pair<int,int>> seen;
    std::vector<std::pair<int,int>> edges;
    for (int i = 0; i < (int)pts.size(); i++) {
        std::vector<std::pair<double,int>> ds;
        for (int j = 0; j < (int)pts.size(); j++)
            if (j != i) ds.push_back({pts[i].distance_to(pts[j]), j});
        std::sort(ds.begin(), ds.end());
        for (int nn = 0; nn < k_neigh && nn < (int)ds.size(); nn++) {
            int j = ds[nn].second;
            auto key = std::make_pair(std::min(i, j), std::max(i, j));
            if (!seen.count(key)) { seen.insert(key); edges.push_back({i, j}); }
        }
    }

    for (const auto &e : edges) {
        PackedVector3Array pp = find_path(terrain, pts[e.first], pts[e.second], area_half);
        int n = pp.size();
        if (n < 2) continue;
        RoadSegment r;
        r.pts.resize(n);
        for (int i = 0; i < n; i++) r.pts[i] = pp[i];
        r.h.resize(n);
        for (int i = 0; i < n; i++) {
            double acc = 0.0; int cnt = 0;
            for (int j = std::max(0, i - road_smth); j < std::min(n, i + road_smth + 1); j++) {
                acc += r.pts[j].y; cnt++;
            }
            r.h[i] = acc / cnt;
        }
        _roads.push_back(r);
        
    }
}