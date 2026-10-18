#include "road_network.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/core/class_db.hpp>
#include <limits>
#include <queue>
#include <random>
#include <set>

using namespace godot;

static const double PATH_SPACING = 2.0;
static const double SLOPE_WEIGHT = 2.0;

void RoadNetwork::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_road_metadata"), &RoadNetwork::get_road_metadata);
	ClassDB::bind_method(D_METHOD("get_town_centers"), &RoadNetwork::get_town_centers);
	ClassDB::bind_method(D_METHOD("find_path", "terrain", "start", "goal", "area_half"), &RoadNetwork::find_path);
	ClassDB::bind_method(D_METHOD("generate_roads", "terrain", "grid_size", "cell_size", "road_cfg"), &RoadNetwork::generate_roads);
	ClassDB::bind_method(D_METHOD("get_road_count"), &RoadNetwork::get_road_count);
	ClassDB::bind_method(D_METHOD("get_road_paths"), &RoadNetwork::get_road_paths);
}

RoadNetwork::RoadNetwork() {}
void RoadNetwork::set_surface(const std::vector<double> &h, const std::vector<unsigned char> &mask, int n, double cell) {
	surface = h;
	water = mask;
	surface_n = n;
	surface_cell = cell;
}
void RoadNetwork::clear_surface() {
	surface.clear();
	water.clear();
	surface_n = 0;
}
double RoadNetwork::sample_height(Ref<TerrainNoise> terrain, double x, double z) const {
	if (surface_n < 2)
		return terrain->get_height(x, z);
	double gx = std::clamp(x / surface_cell + (surface_n - 1) * .5, 0.0, double(surface_n - 1));
	double gz = std::clamp(z / surface_cell + (surface_n - 1) * .5, 0.0, double(surface_n - 1));
	int ix = std::min(int(gx), surface_n - 2), iz = std::min(int(gz), surface_n - 2);
	double tx = gx - ix, tz = gz - iz;
	return (surface[iz * surface_n + ix] * (1 - tx) + surface[iz * surface_n + ix + 1] * tx) * (1 - tz) + (surface[(iz + 1) * surface_n + ix] * (1 - tx) + surface[(iz + 1) * surface_n + ix + 1] * tx) * tz;
}
double RoadNetwork::sample_water(double x, double z) const {
	if (surface_n < 2 || water.empty())
		return 0;
	int ix = std::clamp(int(std::round(x / surface_cell + (surface_n - 1) * .5)), 0, surface_n - 1);
	int iz = std::clamp(int(std::round(z / surface_cell + (surface_n - 1) * .5)), 0, surface_n - 1);
	return water[iz * surface_n + ix] ? 1.0 : 0.0;
}

Array RoadNetwork::get_road_metadata() const {
	Array result;
	Array paths = get_road_paths();
	for (size_t i = 0; i < _roads.size(); i++) {
		Dictionary d;
		d["kind"] = _roads[i].kind;
		d["width"] = _roads[i].half_width * 2;
		d["path"] = paths[i];
		result.append(d);
	}
	return result;
}

Array RoadNetwork::get_road_paths() const {
	Array paths;
	for (const RoadSegment &road : _roads) {
		PackedVector3Array path;
		for (size_t i = 0; i < road.pts.size(); i++) {
			Vector3 point = road.pts[i];
			point.y = road.h[i];
			path.push_back(point);
		}
		paths.append(path);
	}
	return paths;
}

PackedVector3Array RoadNetwork::find_path(Ref<TerrainNoise> terrain, Vector2 start, Vector2 goal, double area_half) const {
	PackedVector3Array path;
	if (terrain.is_null())
		return path;

	const double spacing = std::max(PATH_SPACING, 2.0 * area_half / 512.0);
	const int W = (int)std::round((2.0 * area_half) / spacing) + 1;
	const int count = W * W;
	auto nx = [&](int ix) { return -area_half + ix * spacing; };
	auto nz = [&](int iz) { return -area_half + iz * spacing; };
	auto cl = [&](int v) { return v < 0 ? 0 : (v >= W ? W - 1 : v); };

	int sx = cl((int)std::round((start.x + area_half) / spacing));
	int sz = cl((int)std::round((start.y + area_half) / spacing));
	int gx = cl((int)std::round((goal.x + area_half) / spacing));
	int gz = cl((int)std::round((goal.y + area_half) / spacing));
	int start_i = sz * W + sx, goal_i = gz * W + gx;

	std::vector<double> height(count), wet(count);
	for (int iz = 0; iz < W; iz++)
		for (int ix = 0; ix < W; ix++) {
			height[iz * W + ix] = sample_height(terrain, nx(ix), nz(iz));
			wet[iz * W + ix] = sample_water(nx(ix), nz(iz));
		}

	std::vector<double> g(count, std::numeric_limits<double>::infinity());
	std::vector<int> came(count, -1);
	std::vector<bool> closed(count, false);
	auto heur = [&](int i) {
		double dx = nx(i % W) - nx(gx), dz = nz(i / W) - nz(gz);
		return std::sqrt(dx * dx + dz * dz);
	};
	using Item = std::pair<double, int>;
	std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
	g[start_i] = 0.0;
	open.push({ heur(start_i), start_i });
	const int dxs[8] = { 1, -1, 0, 0, 1, 1, -1, -1 };
	const int dzs[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };

	while (!open.empty()) {
		int cur = open.top().second;
		open.pop();
		if (closed[cur])
			continue;
		if (cur == goal_i)
			break;
		closed[cur] = true;
		int cix = cur % W, ciz = cur / W;
		for (int d = 0; d < 8; d++) {
			int nix = cix + dxs[d], niz = ciz + dzs[d];
			if (nix < 0 || nix >= W || niz < 0 || niz >= W)
				continue;
			int ni = niz * W + nix;
			if (closed[ni])
				continue;
			double horiz = (dxs[d] && dzs[d]) ? spacing * 1.41421356 : spacing;
			double dh = std::fabs(height[ni] - height[cur]);
			double slope = dh / horiz;
			double tent = g[cur] + horiz * (1.0 + 8 * slope * slope + 18 * std::max(wet[cur], wet[ni])) + SLOPE_WEIGHT * dh;
			if (tent < g[ni]) {
				g[ni] = tent;
				came[ni] = cur;
				open.push({ tent + heur(ni), ni });
			}
		}
	}

	if (goal_i != start_i && came[goal_i] == -1)
		return path;
	std::vector<int> rev;
	for (int c = goal_i; c != -1; c = came[c])
		rev.push_back(c);
	for (int k = (int)rev.size() - 1; k >= 0; k--) {
		int i = rev[k];
		path.push_back(Vector3(nx(i % W), height[i], nz(i / W)));
	}
	return path;
}

void RoadNetwork::generate_roads(Ref<TerrainNoise> terrain, int grid_size, double cell_size, Dictionary road_cfg) {
	_roads.clear();
	_town_centers.clear();
	if (terrain.is_null())
		return;

	auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
	int num_points = std::clamp((int)cfg_d("num_points", 6.0), 0, 32);
	double min_dist = cfg_d("min_point_dist", 25.0);
	int k_neigh = std::clamp((int)cfg_d("k_neighbors", 2.0), 0, 8);
	int road_smth = std::clamp((int)cfg_d("road_smooth", 3.0), 0, 32);
	if (num_points < 2 || k_neigh == 0)
		return;

	const double area_half = grid_size * cell_size * 0.5;
	if (bool(road_cfg.get("hierarchical_roads", false))) {
		_generate_hierarchy(terrain, area_half, road_cfg);
		return;
	}

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
		// Los destinos pueden estar en cualquier region. A* penaliza el desnivel.
		bool ok = true;
		for (const Vector2 &p : pts) {
			double dx = x - p.x, dz = z - p.y;
			if (std::sqrt(dx * dx + dz * dz) < min_dist) {
				ok = false;
				break;
			}
		}
		if (ok)
			pts.push_back(Vector2(x, z));
	}

	std::set<std::pair<int, int>> seen;
	std::vector<std::pair<int, int>> edges;
	for (int i = 0; i < (int)pts.size(); i++) {
		std::vector<std::pair<double, int>> ds;
		for (int j = 0; j < (int)pts.size(); j++)
			if (j != i)
				ds.push_back({ pts[i].distance_to(pts[j]), j });
		std::sort(ds.begin(), ds.end());
		for (int nn = 0; nn < k_neigh && nn < (int)ds.size(); nn++) {
			int j = ds[nn].second;
			auto key = std::make_pair(std::min(i, j), std::max(i, j));
			if (!seen.count(key)) {
				seen.insert(key);
				edges.push_back({ i, j });
			}
		}
	}

	// Completar la red cuando k vecinos dejan grupos separados.
	std::vector<int> component(pts.size());
	for (int i = 0; i < (int)pts.size(); i++)
		component[i] = i;
	auto merge = [&](int a, int b) { int from = component[b], to = component[a]; for (int &c : component) if (c == from) c = to; };
	for (const auto &e : edges)
		merge(e.first, e.second);
	while (!pts.empty()) {
		double best = std::numeric_limits<double>::infinity();
		int a = -1, b = -1;
		for (int i = 0; i < (int)pts.size(); i++)
			for (int j = i + 1; j < (int)pts.size(); j++) {
				double distance = pts[i].distance_to(pts[j]);
				if (component[i] != component[j] && distance < best) {
					best = distance;
					a = i;
					b = j;
				}
			}
		if (a < 0)
			break;
		edges.push_back({ a, b });
		merge(a, b);
	}

	for (const auto &e : edges) {
		PackedVector3Array pp = find_path(terrain, pts[e.first], pts[e.second], area_half);
		int n = pp.size();
		if (n < 2)
			continue;
		RoadSegment r;
		r.pts.resize(n);
		for (int i = 0; i < n; i++)
			r.pts[i] = pp[i];
		r.h.resize(n);
		for (int i = 0; i < n; i++) {
			double acc = 0.0;
			int cnt = 0;
			for (int j = std::max(0, i - road_smth); j < std::min(n, i + road_smth + 1); j++) {
				acc += r.pts[j].y;
				cnt++;
			}
			r.h[i] = acc / cnt;
		}
		_roads.push_back(r);
	}
}

// S11 CG-B: una red vial de juego sobre T0, independiente del modelo de erosion.
void RoadNetwork::_generate_hierarchy(Ref<TerrainNoise> terrain, double half, Dictionary cfg) {
	if (half < 40)
		return;
	int count = std::clamp(int(cfg.get("town_count", 4)), 2, 8);
	double block = std::clamp(double(cfg.get("block_size", 32.0)), 8.0, half / 4.0);
	double spacing = std::max(PATH_SPACING, 2.0 * half / 512.0);
	double limit = half - block - 12;
	std::mt19937 rng(unsigned(terrain->get_seed()) ^ 0x51a7u);
	std::uniform_real_distribution<double> random(-limit, limit);
	std::vector<Vector2> centers;
	for (int town = 0; town < count; town++) {
		Vector2 best;
		double score = std::numeric_limits<double>::infinity();
		bool found = false;
		for (int attempt = 0; attempt < 180; attempt++) {
			Vector2 p(-half + std::round((random(rng) + half) / spacing) * spacing, -half + std::round((random(rng) + half) / spacing) * spacing);
			bool valid = true;
			for (auto c : centers)
				if (p.distance_to(c) < std::max(block * 3, half * .40))
					valid = false;
			if (!valid)
				continue;
			double slope = 0;
			if (sample_water(p.x, p.y) > 0)
				continue;
			for (int x = -1; x <= 1; x++)
				for (int z = -1; z <= 1; z++) {
					double wx = p.x + x * block, wz = p.y + z * block;
					if (sample_water(wx, wz) > 0)
						slope += 100;
					slope = std::max(slope, std::hypot(sample_height(terrain, wx + 2, wz) - sample_height(terrain, wx - 2, wz), sample_height(terrain, wx, wz + 2) - sample_height(terrain, wx, wz - 2)) / 4);
				}
			if (slope < score) {
				best = p;
				score = slope;
				found = true;
			}
		}
		if (found) {
			centers.push_back(best);
			_town_centers.push_back(Vector3(best.x, sample_height(terrain, best.x, best.y), best.y));
		}
	}
	auto add = [&](PackedVector3Array path, int kind) {
		if (path.size() < 2)
			return;
		RoadSegment r;
		r.kind = kind;
		const char *key = kind == 1 ? "highway_width" : kind == 2 ? "avenue_width"
																  : "street_width";
		r.half_width = std::max(2.0, double(cfg.get(key, kind == 1 ? 14.0 : kind == 2 ? 10.0
																					  : 6.0))) *
				.5;
		for (int i = 0; i < path.size(); i++) {
			r.pts.push_back(path[i]);
			r.h.push_back(path[i].y);
		}
		_roads.push_back(r);
	};
	// Arbol conectado entre poblados y una conexion alternativa cuando hay tres o mas.
	std::vector<bool> connected(centers.size(), false);
	if (!centers.empty())
		connected[0] = true;
	std::set<std::pair<int, int>> links;
	for (size_t step = 1; step < centers.size(); step++) {
		double best = std::numeric_limits<double>::infinity();
		int a = -1, b = -1;
		for (size_t i = 0; i < centers.size(); i++)
			if (connected[i])
				for (size_t j = 0; j < centers.size(); j++)
					if (!connected[j]) {
						double d = centers[i].distance_to(centers[j]);
						if (d < best) {
							best = d;
							a = int(i);
							b = int(j);
						}
					}
		if (a >= 0) {
			connected[b] = true;
			links.insert({ std::min(a, b), std::max(a, b) });
		}
	}
	if (centers.size() > 2) {
		double best = std::numeric_limits<double>::infinity();
		std::pair<int, int> extra(-1, -1);
		for (int i = 0; i < int(centers.size()); i++)
			for (int j = i + 1; j < int(centers.size()); j++)
				if (!links.count({ i, j })) {
					double d = centers[i].distance_to(centers[j]);
					if (d < best) {
						best = d;
						extra = { i, j };
					}
				}
		if (extra.first >= 0)
			links.insert(extra);
	}
	for (auto link : links)
		add(find_path(terrain, centers[link.first], centers[link.second], half), 1);
	// Poblados con orientacion, proporciones y nodos compartidos variables.
	// La deformacion desplaza intersecciones, no extremos de calles por separado.
	std::uniform_real_distribution<double> unit(0.0, 1.0);
	for (auto c : centers) {
		int blocks = unit(rng) < .5 ? 2 : 4;
		double extent = block * (.75 + .45 * unit(rng));
		double angle = unit(rng) * 6.28318530718;
		double sx = .75 + .5 * unit(rng), sz = .75 + .5 * unit(rng);
		// Orientar el eje principal siguiendo aproximadamente las curvas de nivel.
		double hx = sample_height(terrain, c.x + 2, c.y) - sample_height(terrain, c.x - 2, c.y);
		double hz = sample_height(terrain, c.x, c.y + 2) - sample_height(terrain, c.x, c.y - 2);
		if (std::hypot(hx, hz) > .2)
			angle = std::atan2(hx, -hz) + (unit(rng) - .5) * .35;
		std::vector<Vector2> nodes((blocks + 1) * (blocks + 1));
		for (int z = 0; z <= blocks; z++)
			for (int x = 0; x <= blocks; x++) {
				double lx = (double(x) / blocks * 2 - 1) * extent * sx;
				double lz = (double(z) / blocks * 2 - 1) * extent * sz;
				if (x != blocks / 2 || z != blocks / 2) {
					lx += (unit(rng) - .5) * extent * .18;
					lz += (unit(rng) - .5) * extent * .18;
				}
				Vector2 p(c.x + lx * std::cos(angle) - lz * std::sin(angle), c.y + lx * std::sin(angle) + lz * std::cos(angle));
				if (x == blocks / 2 && z == blocks / 2)
					p = c;
				p.x = std::clamp(double(p.x), -half + 2, half - 2);
				p.y = std::clamp(double(p.y), -half + 2, half - 2);
				nodes[z * (blocks + 1) + x] = p;
			}
		for (int axis = 0; axis < 2; axis++)
			for (int row = 0; row <= blocks; row++)
				for (int edge = 0; edge < blocks; edge++) {
					int i = axis == 0 ? row * (blocks + 1) + edge : edge * (blocks + 1) + row;
					int j = i + (axis == 0 ? 1 : blocks + 1);
					Vector2 a = nodes[i], b = nodes[j];
					PackedVector3Array path;
					int samples = std::max(2, int(std::ceil(a.distance_to(b) / 2)));
					// Shared junctions preserve connectivity while roads follow the final relief.
					for (int k = 0; k <= samples; k++) {
						Vector2 p = a.lerp(b, double(k) / samples);
						path.push_back(Vector3(p.x, sample_height(terrain, p.x, p.y), p.y));
					}
					add(path, row == blocks / 2 ? 2 : 3);
				}
	}
}
