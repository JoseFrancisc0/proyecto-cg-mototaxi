#include "road_network.h"
#include <algorithm>
#include <cmath>
#include <functional>
#include <map>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
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
	ClassDB::bind_method(D_METHOD("find_drivable_path", "heights", "samples", "cell_size", "start", "goal", "max_slope"), &RoadNetwork::find_drivable_path);
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
	return _find_path(terrain, start, goal, area_half, 0.0, nullptr, 0, 1.0);
}

// Juego: ruta recomendada para el vehiculo sobre las alturas FINALES que usa el juego
// (con vias recortadas y puentes), (samples x samples) muestras centradas en el origen.
// Igual que find_path, pero los pasos con pendiente mayor que max_slope cuestan
// muchisimo (no se prohiben: siempre hay ruta). Sin penalizacion de agua: un cauce sin
// puente ya aparece como pendiente fuerte en esas alturas.
PackedVector3Array RoadNetwork::find_drivable_path(PackedFloat32Array heights, int samples, double cell_size, Vector2 start, Vector2 goal, double max_slope) const {
	if (samples < 2 || heights.size() != (int64_t)samples * samples || cell_size <= 0.0)
		return PackedVector3Array();
	std::vector<double> field(heights.size());
	for (int64_t i = 0; i < heights.size(); i++)
		field[i] = heights[i];
	return _find_path(Ref<TerrainNoise>(), start, goal, (samples - 1) * cell_size * 0.5, max_slope, &field, samples, cell_size);
}

PackedVector3Array RoadNetwork::_find_path(Ref<TerrainNoise> terrain, Vector2 start, Vector2 goal, double area_half, double max_slope, const std::vector<double> *field, int field_n, double field_cell, double window) const {
	PackedVector3Array path;
	if (terrain.is_null() && field == nullptr)
		return path;
	auto field_height = [&](double x, double z) {
		double gx = std::clamp(x / field_cell + (field_n - 1) * .5, 0.0, double(field_n - 1));
		double gz = std::clamp(z / field_cell + (field_n - 1) * .5, 0.0, double(field_n - 1));
		int ix = std::min(int(gx), field_n - 2), iz = std::min(int(gz), field_n - 2);
		double tx = gx - ix, tz = gz - iz;
		const std::vector<double> &f = *field;
		return (f[iz * field_n + ix] * (1 - tx) + f[iz * field_n + ix + 1] * tx) * (1 - tz) + (f[(iz + 1) * field_n + ix] * (1 - tx) + f[(iz + 1) * field_n + ix + 1] * tx) * tz;
	};

	// Con alturas del juego se recorre su misma grilla: con un paso mas grueso, una
	// cresta angosta puede quedar entre dos muestras y la ruta pasaria por encima.
	const double spacing = field != nullptr ? field_cell : std::max(PATH_SPACING, 2.0 * area_half / 512.0);
	const int full = (int)std::round((2.0 * area_half) / spacing) + 1;
	auto lattice = [&](double v) { return std::clamp((int)std::round((v + area_half) / spacing), 0, full - 1); };
	// window > 0: buscar solo en un cuadrado de la misma grilla que cubre inicio y meta con
	// ese margen (m). Los nodos son los mismos que en la grilla completa.
	int W = full, ox = 0, oz = 0;
	if (window > 0.0) {
		const int ax = lattice(start.x), az = lattice(start.y), bx = lattice(goal.x), bz = lattice(goal.y);
		const int pad = (int)std::ceil(window / spacing);
		const int side = std::max(std::abs(ax - bx), std::abs(az - bz)) + 2 * pad + 1;
		if (side < full) {
			W = side;
			ox = std::clamp((ax + bx) / 2 - side / 2, 0, full - side);
			oz = std::clamp((az + bz) / 2 - side / 2, 0, full - side);
		}
	}
	const int count = W * W;
	auto nx = [&](int ix) { return -area_half + (ox + ix) * spacing; };
	auto nz = [&](int iz) { return -area_half + (oz + iz) * spacing; };
	auto cl = [&](int v) { return v < 0 ? 0 : (v >= W ? W - 1 : v); };

	int sx = cl(lattice(start.x) - ox);
	int sz = cl(lattice(start.y) - oz);
	int gx = cl(lattice(goal.x) - ox);
	int gz = cl(lattice(goal.y) - oz);
	int start_i = sz * W + sx, goal_i = gz * W + gx;

	std::vector<double> height(count), wet(count);
	for (int iz = 0; iz < W; iz++)
		for (int ix = 0; ix < W; ix++) {
			if (field != nullptr) {
				height[iz * W + ix] = field_height(nx(ix), nz(iz));
				wet[iz * W + ix] = 0.0;
			} else {
				height[iz * W + ix] = sample_height(terrain, nx(ix), nz(iz));
				wet[iz * W + ix] = sample_water(nx(ix), nz(iz));
			}
		}

	// When designing a carriageway, measure the surrounding ground as well as the axis.
	const bool design = field == nullptr && max_slope > 0;
	std::vector<float> roughness;
	if (design) {
		roughness.resize(count);
		const int reach = std::max(1, int(std::ceil(6.0 / spacing)));
		for (int z = 0; z < W; z++)
			for (int x = 0; x < W; x++) {
				const double dx = height[z * W + cl(x + reach)] - height[z * W + cl(x - reach)];
				const double dz = height[cl(z + reach) * W + x] - height[cl(z - reach) * W + x];
				roughness[z * W + x] = float(std::hypot(dx, dz) / (2 * reach * spacing));
			}
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
	const int dxs[] = { 1, -1, 0, 0, 1, 1, -1, -1, 2, 2, -2, -2, 1, 1, -1, -1, 3, 3, -3, -3, 1, 1, -1, -1 };
	const int dzs[] = { 0, 0, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 2, -2, 2, -2, 1, -1, 1, -1, 3, -3, 3, -3 };
	const int directions = design ? 24 : 8;

	while (!open.empty()) {
		int cur = open.top().second;
		open.pop();
		if (closed[cur])
			continue;
		if (cur == goal_i)
			break;
		closed[cur] = true;
		int cix = cur % W, ciz = cur / W;
		for (int d = 0; d < directions; d++) {
			int nix = cix + dxs[d], niz = ciz + dzs[d];
			if (nix < 0 || nix >= W || niz < 0 || niz >= W)
				continue;
			int ni = niz * W + nix;
			if (closed[ni])
				continue;
			double horiz = spacing * std::hypot(dxs[d], dzs[d]);
			double dh = std::fabs(height[ni] - height[cur]);
			double slope = dh / horiz;
			double water_cost = std::max(wet[cur], wet[ni]);
			if (design && d >= 8) {
				const int intervals = std::max(std::abs(dxs[d]), std::abs(dzs[d]));
				double previous = height[cur];
				for (int step = 1; step <= intervals; step++) {
					const double t = double(step) / intervals;
					const double x = nx(cix) + dxs[d] * spacing * t;
					const double z = nz(ciz) + dzs[d] * spacing * t;
					const double sample = step == intervals ? height[ni] : sample_height(terrain, x, z);
					slope = std::max(slope, std::abs(sample - previous) * intervals / horiz);
					water_cost = std::max(water_cost, sample_water(x, z));
					previous = sample;
				}
			}
			double tent = g[cur] + horiz * (1.0 + 8 * slope * slope + 18 * water_cost) + SLOPE_WEIGHT * dh;
			if (design) {
				const double flank = std::max(0.0, double(std::max(roughness[cur], roughness[ni])) - .24);
				tent += horiz * 14.0 * flank * flank;
				// In steep terrain, favor a traversing alignment over climbing directly
				// uphill. A longer alignment is cheaper than a series of large cuts.
				const double target = std::min(max_slope, .10);
				const double excess = std::max(0.0, slope - target);
				tent += horiz * (30.0 * excess + 120.0 * excess * excess);
				if (came[cur] >= 0) {
					const Vector2 incoming(cix - came[cur] % W, ciz - came[cur] / W);
					const Vector2 outgoing(dxs[d], dzs[d]);
					const double bend = 1.0 - incoming.normalized().dot(outgoing.normalized());
					tent += 8.0 * bend + 12.0 * bend * bend;
				}
			}
			if (field != nullptr && max_slope > 0.0 && slope > max_slope)
				tent += horiz * 1000.0;
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
		const Vector3 point(nx(i % W), height[i], nz(i / W));
		if (design && !path.is_empty()) {
			const Vector3 previous = path[path.size() - 1];
			const double distance = std::hypot(point.x - previous.x, point.z - previous.z);
			const int intervals = std::max(1, int(std::round(distance / spacing)));
			for (int step = 1; step < intervals; step++) {
				Vector3 sample = previous.lerp(point, double(step) / intervals);
				sample.y = sample_height(terrain, sample.x, sample.z);
				path.push_back(sample);
			}
		}
		path.push_back(point);
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
	constexpr double tau = 6.283185307179586;
	std::uniform_real_distribution<double> unit(0.0, 1.0);
	const double rotation = unit(rng) * tau;
	std::vector<Vector2> centers;
	// One search per sector: gently favor buildable ground without clustering all towns in one valley.
	for (int town = 0; town < count; town++) {
		const double angle = rotation + tau * town / count;
		const Vector2 direction(std::cos(angle), std::sin(angle));
		const Vector2 target = direction * (limit * .76 / std::max(std::abs(direction.x), std::abs(direction.y)));
		Vector2 best;
		double score = std::numeric_limits<double>::infinity();
		for (int attempt = 0; attempt < 220; attempt++) {
			const double bearing = angle + (unit(rng) - .5) * tau / count * .96;
			const Vector2 ray(std::cos(bearing), std::sin(bearing));
			const double radius = limit * (.40 + .58 * unit(rng)) / std::max(std::abs(ray.x), std::abs(ray.y));
			Vector2 p = ray * radius;
			p.x = -half + std::round((p.x + half) / spacing) * spacing;
			p.y = -half + std::round((p.y + half) / spacing) * spacing;
			if (sample_water(p.x, p.y) > 0)
				continue;
			if (std::any_of(centers.begin(), centers.end(), [&](Vector2 c) {
					return p.distance_to(c) < std::min(block * 1.5, half * .25);
				}))
				continue;
			double grade = 0.0;
			for (int x = -1; x <= 1; x++)
				for (int z = -1; z <= 1; z++) {
					const double wx = p.x + x * block * .5, wz = p.y + z * block * .5;
					const double dx = sample_height(terrain, wx + 2, wz) - sample_height(terrain, wx - 2, wz);
					const double dz = sample_height(terrain, wx, wz + 2) - sample_height(terrain, wx, wz - 2);
					grade += std::hypot(dx, dz) / 36.0 + sample_water(wx, wz) * .12;
				}
			const double cost = grade + 1.2 * p.distance_to(target) / half;
			if (cost < score) {
				best = p;
				score = cost;
			}
		}
		if (std::isfinite(score)) {
			centers.push_back(best);
			_town_centers.push_back(Vector3(best.x, sample_height(terrain, best.x, best.y), best.y));
		}
	}
	auto add = [&](PackedVector3Array path, int kind) { _add_road(path, kind, cfg); };
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
		const int towns = int(centers.size());
		const double inf = std::numeric_limits<double>::infinity();
		std::vector<std::vector<double>> network_dist(towns, std::vector<double>(towns, inf));
		for (int i = 0; i < towns; i++)
			network_dist[i][i] = 0;
		for (const auto &[i, j] : links)
			network_dist[i][j] = network_dist[j][i] = centers[i].distance_to(centers[j]);
		for (int k = 0; k < towns; k++)
			for (int i = 0; i < towns; i++)
				for (int j = 0; j < towns; j++)
					network_dist[i][j] = std::min(network_dist[i][j], network_dist[i][k] + network_dist[k][j]);
		double best = -inf;
		std::pair<int, int> extra(-1, -1);
		for (int i = 0; i < towns; i++)
			for (int j = i + 1; j < towns; j++)
				if (!links.count({ i, j })) {
					const double direct = centers[i].distance_to(centers[j]);
					const double saved = network_dist[i][j] - direct;
					if (saved > best) {
						best = saved;
						extra = { i, j };
					}
				}
		if (extra.first >= 0)
			links.insert(extra);
	}
	const double grade = double(cfg.get("road_max_grade", .16));
	for (auto link : links) {
		auto path = _find_path(terrain, centers[link.first], centers[link.second], half, grade > 0.0 ? grade : .16, nullptr, 0, 1.0);
		_round_path(terrain, path, spacing);
		add(path, 1);
	}
	// Pendiente 10, fase 2: red mas residencial (mas enlaces, cuadras, trochas).
	if (bool(cfg.get("grow_network", true))) {
		_grow_network(terrain, half, cfg, centers);
		return;
	}
	// Only add a local street if it connects two roads through buildable ground.
	// Mountain junctions keep their through routes instead of gaining dead-end spurs.
	const size_t trunk_count = _roads.size();
	for (const auto &c : centers) {
		std::vector<Vector3> entrances;
		for (size_t r = 0; r < trunk_count; r++) {
			const auto &points = _roads[r].pts;
			const bool forward = Vector2(points.front().x, points.front().z).distance_to(c) < .05;
			if (!forward && Vector2(points.back().x, points.back().z).distance_to(c) >= .05)
				continue;
			for (size_t i = 1; i + 1 < points.size(); i++) {
				const auto &p = points[forward ? i : points.size() - 1 - i];
				if (Vector2(p.x, p.z).distance_to(c) >= block * 1.5) {
					entrances.push_back(p);
					break;
				}
			}
		}
		bool built = false;
		for (size_t i = 0; i < entrances.size() && !built; i++)
			for (size_t j = i + 1; j < entrances.size() && !built; j++) {
				const auto a = entrances[i], b = entrances[j];
				const Vector2 start(a.x, a.z), end(b.x, b.z);
				const double length = start.distance_to(end);
				if (length < block || length > block * 2.6 || start.lerp(end, .5).distance_to(c) < block * .75)
					continue;
				const int count = std::max(2, int(std::ceil(length / spacing)));
				const Vector2 direction = (end - start).normalized();
				const Vector2 cross = Vector2(-direction.y, direction.x) * 4.0;
				PackedVector3Array local;
				for (int k = 0; k <= count; k++) {
					const Vector2 p = start.lerp(end, double(k) / count);
					const double h = sample_height(terrain, p.x, p.y);
					const Vector2 left = p + cross, right = p - cross;
					const double flank = std::abs(sample_height(terrain, left.x, left.y) - sample_height(terrain, right.x, right.y));
					if (sample_water(p.x, p.y) > 0 || flank > 2.2 ||
							(k > 0 && std::abs(h - local[k - 1].y) > .18 * length / count))
						break;
					local.push_back(Vector3(p.x, h, p.y));
				}
				if (local.size() == count + 1) {
					add(local, 3);
					built = true;
				}
			}
	}
}

void RoadNetwork::_add_road(const PackedVector3Array &path, int kind, const Dictionary &cfg) {
	if (path.size() < 2)
		return;
	RoadSegment r;
	r.kind = kind;
	const char *key = kind == 1 ? "highway_width" : kind == 2 ? "avenue_width" : kind == 0 ? "trail_width" : "street_width";
	const double default_width = kind == 1 ? 9.5 : kind == 2 ? 7.5 : kind == 0 ? 4.5 : 5.5;
	r.half_width = std::max(2.0, double(cfg.get(key, default_width))) * .5;
	for (int i = 0; i < path.size(); i++) {
		r.pts.push_back(path[i]);
		r.h.push_back(path[i].y);
	}
	_roads.push_back(r);
}

// Round the staircase from A* without moving junctions or introducing water crossings.
// Extend the rounding over several samples; a bend is an arc rather than a collection
// of grid corners. Bound the lateral and vertical adjustment.
void RoadNetwork::_round_path(Ref<TerrainNoise> terrain, PackedVector3Array &path, double spacing) const {
	const PackedVector3Array raw = path;
	for (int pass = 0; pass < 9; pass++) {
		const PackedVector3Array previous = path;
		for (int i = 1; i + 1 < path.size(); i++) {
			const Vector3 old = previous[i];
			Vector3 p = old * .5 + (previous[i - 1] + previous[i + 1]) * .25;
			if (sample_water(p.x, p.z) != sample_water(old.x, old.z))
				continue;
			p.y = sample_height(terrain, p.x, p.z);
			const Vector3 offset = p - raw[i];
			if (std::hypot(offset.x, offset.z) <= spacing * 1.6 && std::abs(offset.y) <= spacing * .35)
				path.set(i, p);
		}
	}
}

namespace {

using VertexKey = std::pair<long long, long long>;
VertexKey vertex_key(const Vector3 &p) { return { std::llround(p.x * 100), std::llround(p.z * 100) }; }
double flat_distance(const Vector3 &a, const Vector3 &b) { return std::hypot(a.x - b.x, a.z - b.z); }

double path_length(const std::vector<Vector3> &p) {
	double total = 0;
	for (size_t i = 1; i < p.size(); i++)
		total += flat_distance(p[i - 1], p[i]);
	return total;
}

// Peor pendiente del trazo medida en tramos de `window` metros (alturas de sus puntos).
double worst_grade(const std::vector<Vector3> &p, double window) {
	const size_t n = p.size();
	if (n < 2)
		return 0;
	std::vector<double> s(n, 0.0);
	for (size_t i = 1; i < n; i++)
		s[i] = s[i - 1] + flat_distance(p[i - 1], p[i]);
	if (s[n - 1] <= window)
		return s[n - 1] > 0 ? std::abs(p[n - 1].y - p[0].y) / s[n - 1] : 0.0;
	double worst = 0;
	size_t j = 0;
	for (size_t i = 0; i < n; i++) {
		while (j < n && s[j] - s[i] < window)
			j++;
		if (j == n)
			break;
		worst = std::max(worst, std::abs(p[j].y - p[i].y) / (s[j] - s[i]));
	}
	return worst;
}

// Indice espacial de los puntos de todas las vias: (via, punto).
struct VertexGrid {
	double bucket = 24.0;
	std::map<std::pair<long long, long long>, std::vector<std::pair<int, int>>> cells;
	std::pair<long long, long long> cell(double x, double z) const { return { (long long)std::floor(x / bucket), (long long)std::floor(z / bucket) }; }
	void add(const std::vector<RoadSegment> &roads, int r) {
		for (int i = 0; i < (int)roads[r].pts.size(); i++)
			cells[cell(roads[r].pts[i].x, roads[r].pts[i].z)].push_back({ r, i });
	}
	template <class Visit>
	void within(double x, double z, double reach, Visit visit) const {
		const auto c = cell(x, z);
		const long long span = (long long)std::ceil(reach / bucket);
		for (long long dz = -span; dz <= span; dz++)
			for (long long dx = -span; dx <= span; dx++) {
				auto found = cells.find({ c.first + dx, c.second + dz });
				if (found != cells.end())
					for (const auto &entry : found->second)
						visit(entry.first, entry.second);
			}
	}
	// Punto mas cercano cuya distancia es menor que limit(via); false si no hay.
	template <class Limit>
	bool nearest(const std::vector<RoadSegment> &roads, double x, double z, double reach, Limit limit, int &road, int &index) const {
		double best = std::numeric_limits<double>::infinity();
		road = -1;
		within(x, z, reach, [&](int r, int i) {
			const Vector3 &p = roads[r].pts[i];
			const double d = std::hypot(p.x - x, p.z - z);
			if (d < best && d < limit(r)) {
				best = d;
				road = r;
				index = i;
			}
		});
		return road >= 0;
	}
};

// Grafo de la red: los puntos iguales (al centimetro) son el mismo nodo, como en el
// aplanado de cruces (terrain_mesh.cpp) y en el GPS del juego (RoadRouter).
struct RoadGraph {
	std::map<VertexKey, int> ids;
	std::vector<std::vector<std::pair<int, double>>> next;
	explicit RoadGraph(const std::vector<RoadSegment> &roads) {
		for (const RoadSegment &road : roads) {
			int previous = -1;
			for (size_t i = 0; i < road.pts.size(); i++) {
				auto inserted = ids.emplace(vertex_key(road.pts[i]), int(next.size()));
				if (inserted.second)
					next.emplace_back();
				const int id = inserted.first->second;
				if (previous >= 0 && previous != id) {
					const double d = flat_distance(road.pts[i - 1], road.pts[i]);
					next[previous].push_back({ id, d });
					next[id].push_back({ previous, d });
				}
				previous = id;
			}
		}
	}
	int find(const Vector3 &p) const {
		auto found = ids.find(vertex_key(p));
		return found == ids.end() ? -1 : found->second;
	}
	std::vector<double> distances(int source) const {
		std::vector<double> d(next.size(), std::numeric_limits<double>::infinity());
		if (source < 0)
			return d;
		using Item = std::pair<double, int>;
		std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
		d[source] = 0;
		open.push({ 0.0, source });
		while (!open.empty()) {
			const Item top = open.top();
			open.pop();
			if (top.first > d[top.second])
				continue;
			for (const auto &edge : next[top.second])
				if (top.first + edge.second < d[edge.first]) {
					d[edge.first] = top.first + edge.second;
					open.push({ d[edge.first], edge.first });
				}
		}
		return d;
	}
};

} // namespace

// Pendiente 10, fase 2. Sobre las carreteras entre pueblos agrega:
//  2a. enlaces que ahorran mucho rodeo (pueblo-pueblo y pueblo-via), solo si el trazo no es
//      empinado ni da muchas vueltas: en la sierra no salen y queda una sola via;
//  2b. una cuadricula de calles en cada pueblo, tramo por tramo donde el suelo es llano y seco;
//  2c. trochas de tierra (kind 0) hacia chacras; algunas vuelven a unirse con otra via.
// 2d. Cruces: todo trazo nuevo se corta donde toca una via y su extremo se pega a un punto
// exacto de ella; asi el aplanado (is_node/uses) y el GPS ven el cruce.
void RoadNetwork::_grow_network(Ref<TerrainNoise> terrain, double half, const Dictionary &cfg, const std::vector<Vector2> &centers) {
	if (_roads.empty())
		return;
	std::mt19937 rng(unsigned(terrain->get_seed()) ^ 0x7a11u);
	std::uniform_real_distribution<double> unit(0.0, 1.0);
	const double spacing = std::max(PATH_SPACING, 2.0 * half / 512.0);
	const double block = std::clamp(double(cfg.get("block_size", 32.0)), 8.0, half / 4.0);
	const double configured_grade = double(cfg.get("road_max_grade", .16));
	const double grade = configured_grade > 0.0 ? configured_grade : .16;
	const double edge = half - 12.0;
	const double margin = 2.5;
	auto inside = [&](double x, double z) { return std::abs(x) < edge && std::abs(z) < edge; };
	auto half_width = [&](int kind) {
		const char *key = kind == 1 ? "highway_width" : kind == 2 ? "avenue_width" : kind == 0 ? "trail_width" : "street_width";
		const double default_width = kind == 1 ? 9.5 : kind == 2 ? 7.5 : kind == 0 ? 4.5 : 5.5;
		return std::max(2.0, double(cfg.get(key, default_width))) * .5;
	};
	double widest = 0;
	for (int kind = 0; kind < 4; kind++)
		widest = std::max(widest, half_width(kind));
	VertexGrid grid;
	for (int r = 0; r < (int)_roads.size(); r++)
		grid.add(_roads, r);

	auto along = [&](int r, int i, int j) {
		if (i > j)
			std::swap(i, j);
		double s = 0;
		for (int k = i; k < j; k++)
			s += flat_distance(_roads[r].pts[k], _roads[r].pts[k + 1]);
		return s;
	};
	// Inserta un trazo: los tramos que no tocan la red se vuelven vias; cada tramo empieza
	// y termina en el punto de la via que toca. open_end: un extremo del trazo puede quedar
	// sin salida. Devuelve cuantas vias agrego.
	auto insert = [&](const std::vector<Vector3> &path, int kind, bool open_end, double min_length) {
		const int n = int(path.size());
		if (n < 2)
			return 0;
		const double own = half_width(kind);
		std::vector<int> touch_road(n, -1), touch_index(n, -1);
		for (int k = 0; k < n; k++)
			grid.nearest(_roads, path[k].x, path[k].z, own + widest + margin, [&](int r) { return own + _roads[r].half_width + margin; }, touch_road[k], touch_index[k]);
		int added = 0;
		for (int k = 0; k < n;) {
			if (touch_road[k] >= 0) {
				k++;
				continue;
			}
			const int s = k;
			while (k < n && touch_road[k] < 0)
				k++;
			const int e = k - 1;
			const bool from = s > 0, to = e + 1 < n;
			if ((!from || !to) && !open_end)
				continue;
			// Suelto por ambos lados: solo una calle del pueblo, que otra puede cruzar despues.
			if (!from && !to && kind != 3)
				continue;
			PackedVector3Array piece;
			if (from)
				piece.push_back(_roads[touch_road[s - 1]].pts[touch_index[s - 1]]);
			for (int i = s; i <= e; i++)
				piece.push_back(path[i]);
			if (to)
				piece.push_back(_roads[touch_road[e + 1]].pts[touch_index[e + 1]]);
			double length = 0;
			for (int i = 1; i < piece.size(); i++)
				length += flat_distance(piece[i - 1], piece[i]);
			if (piece.size() < 2 || length < min_length)
				continue;
			if (from && to) {
				const int ra = touch_road[s - 1], ia = touch_index[s - 1];
				const int rb = touch_road[e + 1], ib = touch_index[e + 1];
				if (ra == rb && ia == ib)
					continue;
				// Sale y vuelve a la misma via: solo sirve si es un atajo, no una paralela.
				if (ra == rb && along(ra, ia, ib) < 1.3 * length)
					continue;
			}
			_add_road(piece, kind, cfg);
			grid.add(_roads, int(_roads.size()) - 1);
			added++;
		}
		return added;
	};
	auto trace = [&](const Vector3 &a, const Vector3 &b) {
		const double reach = std::max(150.0, .5 * flat_distance(a, b));
		PackedVector3Array p = _find_path(terrain, Vector2(a.x, a.z), Vector2(b.x, b.z), half, grade, nullptr, 0, 1.0, reach);
		_round_path(terrain, p, spacing);
		std::vector<Vector3> out;
		for (int i = 0; i < p.size(); i++)
			out.push_back(p[i]);
		return out;
	};

	// Puntos exactos de los pueblos (extremos de las carreteras).
	std::vector<Vector3> towns;
	for (const Vector2 &c : centers) {
		int r, i;
		if (grid.nearest(_roads, c.x, c.y, 1.0, [](int) { return .05; }, r, i))
			towns.push_back(_roads[r].pts[i]);
	}
	const size_t trunk_count = _roads.size();

	// 2a. Enlaces extra.
	const bool debug = bool(cfg.get("debug_roads", false));
	const int extra_links = std::clamp(int(cfg.get("extra_links", 4)), 0, 16);
	const double detour = std::max(1.05, double(cfg.get("detour_ratio", 1.4)));
	const double link_grade = double(cfg.get("extra_link_grade", .18));
	if (extra_links > 0 && towns.size() >= 2) {
		struct Candidate {
			Vector3 a, b;
			int kind;
			double score;
		};
		std::vector<Candidate> candidates;
		const RoadGraph graph(_roads);
		for (size_t t = 0; t < towns.size(); t++) {
			const std::vector<double> dist = graph.distances(graph.find(towns[t]));
			for (size_t u = t + 1; u < towns.size(); u++) {
				const int target = graph.find(towns[u]);
				const double direct = flat_distance(towns[t], towns[u]);
				if (target >= 0 && dist[target] > detour * direct)
					candidates.push_back({ towns[t], towns[u], 1, dist[target] - direct });
			}
			// Una carretera que pasa cerca pero se alcanza dando mucha vuelta.
			for (size_t r = 0; r < trunk_count; r++) {
				const auto &pts = _roads[r].pts;
				if (vertex_key(pts.front()) == vertex_key(towns[t]) || vertex_key(pts.back()) == vertex_key(towns[t]))
					continue;
				double best = 0;
				Vector3 spot;
				const size_t stride = std::max(1, int(std::round(120.0 / spacing)));
				for (size_t i = stride; i + stride < pts.size(); i += stride) {
					const double direct = flat_distance(towns[t], pts[i]);
					const int target = graph.find(pts[i]);
					if (direct < 250 || direct > 1100 || target < 0 || sample_water(pts[i].x, pts[i].z) > 0)
						continue;
					if (dist[target] > detour * direct && dist[target] - direct > best) {
						best = dist[target] - direct;
						spot = pts[i];
					}
				}
				if (best > 0)
					candidates.push_back({ towns[t], spot, 2, best });
			}
		}
		// Travesanos entre dos carreteras cercanas que por la red quedan lejos.
		std::vector<Vector3> samples;
		const size_t sample_stride = std::max(1, int(std::round(150.0 / spacing)));
		for (size_t r = 0; r < trunk_count; r++)
			for (size_t i = sample_stride; i + sample_stride < _roads[r].pts.size(); i += sample_stride)
				if (sample_water(_roads[r].pts[i].x, _roads[r].pts[i].z) <= 0)
					samples.push_back(_roads[r].pts[i]);
		for (size_t a = 0; a < samples.size(); a++) {
			const std::vector<double> dist = graph.distances(graph.find(samples[a]));
			for (size_t b = a + 1; b < samples.size(); b++) {
				const double direct = flat_distance(samples[a], samples[b]);
				const int target = graph.find(samples[b]);
				if (direct >= 150 && direct <= 700 && target >= 0 && dist[target] > 2.5 * direct)
					candidates.push_back({ samples[a], samples[b], 2, dist[target] - direct });
			}
		}
		std::stable_sort(candidates.begin(), candidates.end(), [](const Candidate &a, const Candidate &b) { return a.score > b.score; });
		int accepted = 0, tries = 0;
		std::vector<Vector3> middles;
		for (const Candidate &c : candidates) {
			if (accepted >= extra_links || tries >= extra_links * 5)
				break;
			// Repartidos por el mapa, no todos en el mismo valle.
			const Vector3 middle = (c.a + c.b) * .5;
			if (std::any_of(middles.begin(), middles.end(), [&](const Vector3 &m) { return flat_distance(m, middle) < 400.0; }))
				continue;
			// Un enlace anterior puede haber resuelto ya este rodeo.
			const RoadGraph now(_roads);
			const int target = now.find(c.b);
			const double direct = flat_distance(c.a, c.b);
			if (target < 0 || now.distances(now.find(c.a))[target] <= detour * direct)
				continue;
			tries++;
			const std::vector<Vector3> path = trace(c.a, c.b);
			if (debug)
				UtilityFunctions::print("enlace ", c.kind, " ", c.a, " -> ", c.b, " directo ", direct, " largo ", path_length(path), " pendiente ", worst_grade(path, 40.0));
			if (path.size() < 2 || path_length(path) > 1.5 * direct || worst_grade(path, 40.0) > link_grade)
				continue;
			// Que abra terreno nuevo: no sirve una via que corre pegada a otra.
			int beside = 0;
			for (const Vector3 &p : path) {
				if (flat_distance(p, c.a) < 80.0 || flat_distance(p, c.b) < 80.0)
					continue;
				int nr, ni;
				if (grid.nearest(_roads, p.x, p.z, 60.0, [](int) { return 60.0; }, nr, ni))
					beside++;
			}
			if (debug)
				UtilityFunctions::print("  junto a otra via: ", beside, " de ", int(path.size()));
			if (beside > int(path.size()) * .45)
				continue;
			if (insert(path, c.kind, false, 60.0) > 0) {
				accepted++;
				middles.push_back(middle);
			}
		}
	}

	// 2b. Cuadras de cada pueblo, alineadas con la primera via que sale de el.
	const int blocks = std::clamp(int(cfg.get("town_blocks", 4)), 0, 8);
	if (blocks >= 2) {
		for (const Vector3 &c : towns) {
			Vector2 u(1, 0);
			for (size_t r = 0; r < trunk_count; r++) {
				const auto &pts = _roads[r].pts;
				const bool forward = vertex_key(pts.front()) == vertex_key(c);
				if (!forward && vertex_key(pts.back()) != vertex_key(c))
					continue;
				for (size_t i = 1; i < pts.size(); i++) {
					const Vector3 &p = pts[forward ? i : pts.size() - 1 - i];
					if (flat_distance(p, c) >= block) {
						u = Vector2(p.x - c.x, p.z - c.z).normalized();
						break;
					}
				}
				break;
			}
			const Vector2 v(-u.y, u.x);
			const int lo = -blocks / 2, hi = blocks - blocks / 2, side = hi - lo + 1;
			std::vector<Vector3> node(side * side);
			std::vector<bool> usable(side * side);
			for (int b = 0; b < side; b++)
				for (int a = 0; a < side; a++) {
					const Vector2 p = Vector2(c.x, c.z) + u * ((a + lo) * block) + v * ((b + lo) * block);
					node[b * side + a] = (a + lo == 0 && b + lo == 0) ? c : Vector3(p.x, sample_height(terrain, p.x, p.y), p.y);
					usable[b * side + a] = inside(p.x, p.y) && sample_water(p.x, p.y) <= 0;
				}
			const int steps = std::max(2, int(std::ceil(block / spacing)));
			const double step_rise = .18 * block / steps;
			// Tramo de una cuadra: llano, seco y sin ladera de costado.
			auto stretch = [&](int i, int j, std::vector<Vector3> &out) {
				if (!usable[i] || !usable[j])
					return false;
				const Vector3 a = node[i], b = node[j];
				if (std::abs(b.y - a.y) > grade * block)
					return false;
				const Vector2 dir = Vector2(b.x - a.x, b.z - a.z).normalized();
				const Vector2 cross = Vector2(-dir.y, dir.x) * 4.0;
				double previous = a.y;
				out.clear();
				for (int k = 1; k < steps; k++) {
					const Vector2 p = Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), double(k) / steps);
					const double h = sample_height(terrain, p.x, p.y);
					const Vector2 l = p + cross, r = p - cross;
					if (sample_water(p.x, p.y) > 0 || std::abs(sample_height(terrain, l.x, l.y) - sample_height(terrain, r.x, r.y)) > 2.2 || std::abs(h - previous) > step_rise)
						return false;
					out.push_back(Vector3(p.x, h, p.y));
					previous = h;
				}
				return std::abs(b.y - previous) <= step_rise;
			};
			std::vector<Vector3> inner;
			for (int axis = 0; axis < 2; axis++)
				for (int line = 0; line < side; line++) {
					std::vector<Vector3> run;
					for (int step = 0; step + 1 < side; step++) {
						const int i = axis == 0 ? line * side + step : step * side + line;
						const int j = axis == 0 ? i + 1 : i + side;
						if (stretch(i, j, inner)) {
							if (run.empty())
								run.push_back(node[i]);
							run.insert(run.end(), inner.begin(), inner.end());
							run.push_back(node[j]);
						} else if (!run.empty()) {
							insert(run, 3, true, block * .6);
							run.clear();
						}
					}
					if (!run.empty())
						insert(run, 3, true, block * .6);
				}
		}
	}

	// 2c. Trochas a chacras y caserios, lejos de los pueblos.
	int tracks = int(cfg.get("farm_tracks", -1));
	const double loop_chance = std::clamp(double(cfg.get("track_loop_chance", .4)), 0.0, 1.0);
	const double track_grade = double(cfg.get("track_max_grade", .24));
	if (tracks < 0) {
		double rural = 0;
		for (size_t r = 0; r < trunk_count; r++)
			rural += path_length(_roads[r].pts);
		tracks = std::clamp(int(rural / 450.0), 0, 24);
	}
	if (tracks > 0) {
		const double town_reach = block * (blocks / 2 + 1) + 40.0;
		std::vector<std::pair<int, int>> seeds;
		for (int r = 0; r < (int)_roads.size(); r++) {
			if (_roads[r].kind != 1 && _roads[r].kind != 2)
				continue;
			const auto &pts = _roads[r].pts;
			const int stride = std::max(1, int(std::round(70.0 / spacing)));
			for (int i = stride; i + stride < (int)pts.size(); i += stride) {
				const Vector3 &p = pts[i];
				if (!inside(p.x, p.z) || sample_water(p.x, p.z) > 0)
					continue;
				if (std::any_of(towns.begin(), towns.end(), [&](const Vector3 &t) { return flat_distance(t, p) < town_reach; }))
					continue;
				seeds.push_back({ r, i });
			}
		}
		for (int i = int(seeds.size()) - 1; i > 0; i--)
			std::swap(seeds[i], seeds[std::min(i, int(unit(rng) * (i + 1)))]);
		std::vector<Vector3> starts;
		int built = 0;
		for (const auto &seed : seeds) {
			if (built >= tracks)
				break;
			const int r = seed.first, i = seed.second;
			const Vector3 o = _roads[r].pts[i];
			if (std::any_of(starts.begin(), starts.end(), [&](const Vector3 &s) { return flat_distance(s, o) < 160.0; }))
				continue;
			const Vector3 pa = _roads[r].pts[i - 1], pb = _roads[r].pts[i + 1];
			const Vector2 tangent = Vector2(pb.x - pa.x, pb.z - pa.z).normalized();
			const Vector2 normal = Vector2(-tangent.y, tangent.x) * (unit(rng) < .5 ? 1.0 : -1.0);
			const bool wants_loop = unit(rng) < loop_chance;
			Vector3 target;
			bool found = false, loop = false;
			if (wants_loop) {
				// Volver a otra via que por la red queda lejos: arma una vuelta.
				const RoadGraph graph(_roads);
				const std::vector<double> dist = graph.distances(graph.find(o));
				double best = std::numeric_limits<double>::infinity();
				grid.within(o.x, o.z, 420.0, [&](int rr, int ii) {
					if (rr == r)
						return;
					const Vector3 &p = _roads[rr].pts[ii];
					const double direct = flat_distance(o, p);
					if (direct < 140 || direct > 420 || direct >= best || sample_water(p.x, p.z) > 0)
						return;
					if (Vector2(p.x - o.x, p.z - o.z).dot(normal) < .3 * direct)
						return;
					const int id = graph.find(p);
					if (id >= 0 && dist[id] > 2.2 * direct) {
						best = direct;
						target = p;
						found = loop = true;
					}
				});
			}
			if (!found) {
				double best = std::numeric_limits<double>::infinity();
				for (int attempt = 0; attempt < 10; attempt++) {
					const double turn = (unit(rng) - .5) * 1.4;
					const Vector2 dir = normal.rotated(turn);
					const Vector2 p = Vector2(o.x, o.z) + dir * (90.0 + 170.0 * unit(rng));
					if (!inside(p.x, p.y) || sample_water(p.x, p.y) > 0)
						continue;
					int nr, ni;
					if (grid.nearest(_roads, p.x, p.y, 45.0, [](int) { return 45.0; }, nr, ni))
						continue;
					const double dx = sample_height(terrain, p.x + 4, p.y) - sample_height(terrain, p.x - 4, p.y);
					const double dz = sample_height(terrain, p.x, p.y + 4) - sample_height(terrain, p.x, p.y - 4);
					const double steep = std::hypot(dx, dz) / 8.0;
					if (steep < best && steep < track_grade) {
						best = steep;
						target = Vector3(p.x, sample_height(terrain, p.x, p.y), p.y);
						found = true;
					}
				}
			}
			if (!found)
				continue;
			const std::vector<Vector3> path = trace(o, target);
			const double direct = flat_distance(o, target);
			if (path.size() < 2 || path_length(path) > 1.8 * direct || worst_grade(path, 30.0) > track_grade)
				continue;
			if (insert(path, 0, !loop, 35.0) > 0) {
				starts.push_back(o);
				built++;
			}
		}
	}

	// Quitar lo que quedo suelto: solo se conserva lo unido a las carreteras.
	std::vector<int> parent(_roads.size());
	for (size_t r = 0; r < parent.size(); r++)
		parent[r] = int(r);
	std::function<int(int)> root = [&](int r) { return parent[r] == r ? r : parent[r] = root(parent[r]); };
	std::map<VertexKey, int> owner;
	for (int r = 0; r < (int)_roads.size(); r++)
		for (const Vector3 &p : _roads[r].pts) {
			auto inserted = owner.emplace(vertex_key(p), r);
			if (!inserted.second)
				parent[root(r)] = root(inserted.first->second);
		}
	std::set<int> kept;
	for (size_t r = 0; r < trunk_count; r++)
		kept.insert(root(int(r)));
	std::vector<RoadSegment> joined;
	for (int r = 0; r < (int)_roads.size(); r++)
		if (kept.count(root(r)))
			joined.push_back(_roads[r]);
	_roads.swap(joined);
}
