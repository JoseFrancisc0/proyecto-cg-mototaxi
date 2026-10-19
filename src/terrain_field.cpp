#include "terrain_field.h"
#include "erosion.h"
#include "terrain_noise.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <limits>
#include <numeric>
#include <queue>
#include <set>
#include <string>
using namespace godot;
namespace {
double smooth(double a, double b, double v) {
	double t = std::clamp((v - a) / (b - a), 0.0, 1.0);
	return t * t * (3 - 2 * t);
}
const int DX[8] = { 1, -1, 0, 0, 1, 1, -1, -1 }, DZ[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };
} //namespace
void TerrainField::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate", "seed", "grid_cells", "cell_size", "config"), &TerrainField::generate);
	ClassDB::bind_method(D_METHOD("erode_input", "input", "samples", "cell_size", "config"), &TerrainField::erode_input);
	ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &TerrainField::get_height);
	ClassDB::bind_method(D_METHOD("get_normal", "x", "z"), &TerrainField::get_normal);
	ClassDB::bind_method(D_METHOD("get_biome", "x", "z"), &TerrainField::get_biome);
	ClassDB::bind_method(D_METHOD("get_drainage", "x", "z"), &TerrainField::get_drainage);
	ClassDB::bind_method(D_METHOD("get_heights"), &TerrainField::get_heights);
	ClassDB::bind_method(D_METHOD("get_initial_heights"), &TerrainField::get_initial_heights);
	ClassDB::bind_method(D_METHOD("get_drainage_map"), &TerrainField::get_drainage_map);
	ClassDB::bind_method(D_METHOD("get_surface_map"), &TerrainField::get_surface_map);
	ClassDB::bind_method(D_METHOD("get_landmarks"), &TerrainField::get_landmarks);
	ClassDB::bind_method(D_METHOD("get_timings"), &TerrainField::get_timings);
	ClassDB::bind_method(D_METHOD("get_regional_maps"), &TerrainField::get_regional_maps);
	ClassDB::bind_method(D_METHOD("find_route", "start", "goal"), &TerrainField::find_route);
	ClassDB::bind_method(D_METHOD("build_chunk", "origin_x", "origin_z", "chunk_cells"), &TerrainField::build_chunk);
	ClassDB::bind_method(D_METHOD("get_chunk_heights", "origin_x", "origin_z", "chunk_cells"), &TerrainField::get_chunk_heights);
}
bool TerrainField::generate(int seed, int grid_cells, double cell_size, Dictionary cfg) {
	if (grid_cells < 8 || grid_cells > 1024 || (grid_cells & (grid_cells - 1)) || !std::isfinite(cell_size) || cell_size <= 0)
		return false;
	cells = grid_cells;
	side = cells + 1;
	spacing = cell_size;
	const size_t count = size_t(side) * side;
	heights.resize(count);
	biomes.resize(count);
	road_mask.assign(count, 0);
	landmarks.clear();
	timings.clear();
	auto now = []() { return std::chrono::steady_clock::now(); };
	auto begin = now(), previous = begin;
	auto stamp = [&](const char *key) { auto t=now(); timings[key]=std::chrono::duration<double>(t-previous).count(); previous=t; };
	Ref<TerrainNoise> noise;
	noise.instantiate();
	noise->set_seed(seed);
	ErosionSteps steps;
	steps.levels = std::clamp(int(cfg.get("levels", 2)), 0, 3);
	steps.iteration_scale = std::clamp(double(cfg.get("iteration_scale", 0.03)), 0.0, 1.0);
	steps.fluvial = std::max(0, int(cfg.get("fluvial", 3000)));
	steps.thermal = std::max(0, int(cfg.get("thermal", 600)));
	steps.deposition = std::max(0, int(cfg.get("deposition", 2000)));
	steps.hardness.resize(count);
	steps.talus.resize(count);
	double extent = cells * spacing;
	for (int z = 0; z < side; z++)
		for (int x = 0; x < side; x++) {
			int i = z * side + x;
			double wx = x * spacing - extent / 2, wz = z * spacing - extent / 2;
			// West-east warped borders; all three weights sum to one.
			double u = double(x) / cells + (noise->get_moisture(wx * 2, wz * 2) - 0.5) * 0.30;
			double coast = 1 - smooth(0.22, 0.40, u), jungle = smooth(0.62, 0.80, u), mountain = 1 - coast - jungle;
			biomes[i] = Vector3(coast, mountain, jungle);
			double detail = noise->get_height(wx, wz);
			double ridge = std::pow(std::max(0.0, std::sin(std::clamp(u, 0.0, 1.0) * 3.141592653589793)), 3.0);
			heights[i] = coast * (2 + detail * 0.08) + mountain * (22 + ridge * 55 + detail * 0.48) + jungle * (7 + detail * 0.18);
			if (bool(cfg.get("preserve_base", false))) {
				// Original TerrainNoise remains T0. Only the coast blends to a plain;
				// the team's existing sierra/selva relief is retained inland.
				heights[i] = detail * (1 - coast) + (2 + detail * 0.08) * coast;
			}
			steps.hardness[i] = float(coast * 0.10 + mountain * (0.55 + 0.15 * noise->get_elevation(wx, wz)) + jungle * 0.35);
			steps.talus[i] = float(coast * 0.25 + mountain * 1.15 * (0.8 + 0.4 * noise->get_moisture(wx * 6, wz * 6)) + jungle * 0.60);
		}
	regional_hardness = steps.hardness;
	regional_talus = steps.talus;
	initial = heights;
	stamp("base");
	std::vector<ErosionTiming> erosion_times;
	steps.timings = &erosion_times;
	if (bool(cfg.get("erosion_enabled", true)))
		erode_terrain(heights, side, spacing, steps);
	stamp("erosion");
	compute_drainage();
	stamp("drainage_before_retarget");
	for (const auto &t : erosion_times) {
		Dictionary level;
		level["fluvial"] = t.fluvial_seconds;
		level["thermal"] = t.thermal_seconds;
		level["deposition"] = t.deposition_seconds;
		timings[String("cells_") + String::num_int64(t.samples - 1)] = level;
	}
	if (bool(cfg.get("retarget_enabled", true)))
		retarget(std::clamp(int(cfg.get("retarget_iterations", 200)), 0, 500));
	stamp("retarget");
	compute_drainage();
	// Sample candidate landforms, then greedily retain spatially separated points.
	struct Candidate {
		int x, z;
		double score;
		const char *type;
	};
	std::vector<Candidate> candidates;
	int stride = std::max(4, cells / 32);
	for (int z = stride; z < cells; z += stride)
		for (int x = stride; x < cells; x += stride) {
			int i = z * side + x;
			Vector3 p = position(x, z);
			double slope = 1 - get_normal(p.x, p.z).y;
			const char *type;
			if (biomes[i].x > 0.6 && slope < 0.1)
				type = "llanura";
			else if (drainage[i] > 16)
				type = "rio";
			else if (drainage[i] < 1.5 && biomes[i].y > 0.4)
				type = "cresta";
			else
				continue;
			double score = type == std::string("rio") ? std::log1p(drainage[i]) * 8 : (type == std::string("llanura") ? 40 - slope * 100 : heights[i]);
			candidates.push_back({ x, z, score, type });
		}
	std::sort(candidates.begin(), candidates.end(), [](const Candidate &a, const Candidate &b) { return a.score > b.score; });
	// Ensure one candidate per type before adding remaining high-score candidates.
	auto add_candidate = [&](const Candidate &c) {
		Vector3 p = position(c.x, c.z);
		for (int j = 0; j < landmarks.size(); j++) {
			Dictionary d = landmarks[j];
			Vector3 q = d["position"];
			if (Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < std::max(0.0, double(cfg.get("min_point_dist", extent * 0.13))))
				return false;
		}
		Dictionary d;
		d["position"] = p;
		d["type"] = c.type;
		landmarks.append(d);
		return true;
	};
	for (const char *type : { "llanura", "rio", "cresta" })
		for (const auto &c : candidates)
			if (std::string(c.type) == type && add_candidate(c))
				break;
	for (const auto &c : candidates) {
		if (landmarks.size() >= std::clamp(int(cfg.get("num_points", 8)), 3, 32))
			break;
		add_candidate(c);
	}
	stamp("drainage_landmarks");
	// Routes are computed after erosion/retargeting and blended into the same heightfield.
	if (bool(cfg.get("roads_enabled", true))) {
		std::set<std::pair<int, int>> edges;
		int neighbors = std::clamp(int(cfg.get("k_neighbors", 2)), 0, 8);
		for (int i = 0; i < landmarks.size(); i++) {
			Dictionary origin = landmarks[i];
			Vector3 p = origin["position"];
			std::vector<std::pair<double, int>> distances;
			for (int j = 0; j < landmarks.size(); j++)
				if (i != j) {
					Dictionary other = landmarks[j];
					Vector3 q = other["position"];
					distances.push_back({ Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)), j });
				}
			std::sort(distances.begin(), distances.end());
			for (int k = 0; k < std::min(neighbors, int(distances.size())); k++)
				edges.insert({ std::min(i, distances[k].second), std::max(i, distances[k].second) });
		}
		double width = std::max(0.1, double(cfg.get("road_width", 4.0)));
		double fade = std::max(0.1, double(cfg.get("road_fade", 3.0)));
		int smoothing = std::clamp(int(cfg.get("road_smooth", 3)), 0, 32);
		for (const auto &edge : edges) {
			Dictionary a = landmarks[edge.first], b = landmarks[edge.second];
			PackedVector3Array path = find_route(a["position"], b["position"]);
			PackedVector3Array raw = path.duplicate();
			for (int i = 0; i < path.size(); i++) {
				double height = 0;
				int count = 0;
				for (int j = std::max(0, i - smoothing); j <= std::min(int(raw.size()) - 1, i + smoothing); j++) {
					height += raw[j].y;
					count++;
				}
				Vector3 p = raw[i];
				p.y = height / count;
				path.set(i, p);
			}
			int radius = std::max(2, int(std::ceil((width + fade) / spacing)));
			for (int k = 0; k < path.size(); k++) {
				Vector3 a = path[k], b = path[std::min(k + 1, int(path.size()) - 1)];
				int samples = std::max(1, int(std::ceil(a.distance_to(b) / spacing)));
				for (int step = 0; step < samples; step++) {
					Vector3 p = a.lerp(b, double(step) / samples);
					int cx = int(std::round(p.x / spacing + cells / 2.0)), cz = int(std::round(p.z / spacing + cells / 2.0));
					for (int dz = -radius; dz <= radius; dz++)
						for (int dx = -radius; dx <= radius; dx++) {
							int x = cx + dx, z = cz + dz;
							if (x < 0 || z < 0 || x > cells || z > cells)
								continue;
							double w = 1 - smooth(width / spacing, (width + fade) / spacing, std::sqrt(double(dx * dx + dz * dz)));
							int i = z * side + x;
							heights[i] = heights[i] * (1 - w) + p.y * w;
							road_mask[i] = std::max(road_mask[i], float(w));
						}
				}
			}
		}
		compute_drainage();
		for (int j = 0; j < landmarks.size(); j++) {
			Dictionary d = landmarks[j];
			Vector3 p = d["position"];
			p.y = get_height(p.x, p.z);
			d["position"] = p;
			landmarks[j] = d;
		}
	}
	stamp("roads");
	timings["total"] = std::chrono::duration<double>(now() - begin).count();
	return true;
}
PackedFloat32Array TerrainField::erode_input(PackedFloat32Array input, int samples, double cell_size, Dictionary cfg) const {
	PackedFloat32Array result;
	if (samples < 3 || samples > 1025 || input.size() != int64_t(samples) * samples || cell_size <= 0 || !std::isfinite(cell_size))
		return result;
	std::vector<double> h(input.size());
	for (int i = 0; i < input.size(); i++) {
		if (!std::isfinite(input[i]))
			return result;
		h[i] = input[i];
	}
	ErosionSteps steps;
	steps.levels = int(cfg.get("levels", 0));
	steps.fluvial = int(cfg.get("fluvial", 1));
	steps.thermal = int(cfg.get("thermal", 0));
	steps.deposition = int(cfg.get("deposition", 0));
	erode_terrain(h, samples, cell_size, steps);
	result.resize(h.size());
	for (size_t i = 0; i < h.size(); i++)
		result.set(i, float(h[i]));
	return result;
}
void TerrainField::compute_drainage() {
	int count = int(heights.size());
	drainage.assign(count, 1.0f);
	std::vector<int> order(count);
	std::iota(order.begin(), order.end(), 0);
	std::sort(order.begin(), order.end(), [&](int a, int b) { return heights[a] > heights[b]; });
	for (int i : order) {
		int x = i % side, z = i / side;
		double weights[8] = {}, sum = 0;
		for (int k = 0; k < 8; k++) {
			int nx = x + DX[k], nz = z + DZ[k];
			if (nx < 0 || nz < 0 || nx >= side || nz >= side)
				continue;
			double slope = (heights[i] - heights[nz * side + nx]) / (spacing * (k < 4 ? 1 : std::sqrt(2.0)));
			if (slope > 0) {
				weights[k] = std::pow(slope, 1.3);
				sum += weights[k];
			}
		}
		if (sum > 0)
			for (int k = 0; k < 8; k++)
				if (weights[k] > 0)
					drainage[(z + DZ[k]) * side + x + DX[k]] += float(drainage[i] * weights[k] / sum);
	}
}
void TerrainField::retarget(int iterations) {
	// Paper section 5.1: low drainage identifies crests; diffuse elevation error
	// while keeping Dirichlet constraints fixed, then add that error to terrain.
	std::vector<double> error(heights.size(), 0), next(error.size());
	std::vector<bool> fixed(error.size(), false);
	for (size_t i = 0; i < error.size(); i++)
		if (drainage[i] < 1.05f && biomes[i].y > 0.45f) {
			fixed[i] = true;
			error[i] = initial[i] - heights[i];
		}
	for (int it = 0; it < iterations; it++) {
		for (int z = 0; z < side; z++)
			for (int x = 0; x < side; x++) {
				int i = z * side + x;
				if (fixed[i]) {
					next[i] = error[i];
					continue;
				}
				double sum = 0;
				int n = 0;
				for (int k = 0; k < 4; k++) {
					int nx = x + DX[k], nz = z + DZ[k];
					if (nx < 0 || nz < 0 || nx >= side || nz >= side)
						continue;
					sum += error[nz * side + nx];
					n++;
				}
				next[i] = sum / n;
			}
		error.swap(next);
	}
	for (size_t i = 0; i < heights.size(); i++)
		heights[i] += error[i];
}
Vector3 TerrainField::position(int x, int z) const { return Vector3((x - cells / 2.0) * spacing, heights[z * side + x], (z - cells / 2.0) * spacing); }
double TerrainField::sample(const std::vector<double> &data, double x, double z) const {
	if (side == 0 || !std::isfinite(x) || !std::isfinite(z))
		return 0;
	double fx = std::clamp(x / spacing + cells / 2.0, 0.0, double(cells)), fz = std::clamp(z / spacing + cells / 2.0, 0.0, double(cells));
	int ix = std::min(int(fx), cells - 1), iz = std::min(int(fz), cells - 1);
	double tx = fx - ix, tz = fz - iz;
	return (data[iz * side + ix] * (1 - tx) + data[iz * side + ix + 1] * tx) * (1 - tz) + (data[(iz + 1) * side + ix] * (1 - tx) + data[(iz + 1) * side + ix + 1] * tx) * tz;
}
double TerrainField::get_height(double x, double z) const { return sample(heights, x, z); }
Vector3 TerrainField::get_normal(double x, double z) const {
	double half = cells * spacing / 2.0;
	double x0 = std::clamp(x - spacing, -half, half), x1 = std::clamp(x + spacing, -half, half), z0 = std::clamp(z - spacing, -half, half), z1 = std::clamp(z + spacing, -half, half);
	if (x0 == x1 || z0 == z1)
		return Vector3(0, 1, 0);
	return Vector3(-(get_height(x1, z) - get_height(x0, z)) / (x1 - x0), 1, -(get_height(x, z1) - get_height(x, z0)) / (z1 - z0)).normalized();
}
Vector3 TerrainField::get_biome(double x, double z) const {
	if (side == 0)
		return Vector3();
	int ix = std::clamp(int(std::round(x / spacing + cells / 2.0)), 0, cells), iz = std::clamp(int(std::round(z / spacing + cells / 2.0)), 0, cells);
	return biomes[iz * side + ix];
}
double TerrainField::get_drainage(double x, double z) const {
	if (side == 0)
		return 0;
	int ix = std::clamp(int(std::round(x / spacing + cells / 2.0)), 0, cells), iz = std::clamp(int(std::round(z / spacing + cells / 2.0)), 0, cells);
	return drainage[iz * side + ix];
}
PackedFloat32Array TerrainField::get_heights() const {
	PackedFloat32Array a;
	a.resize(heights.size());
	for (size_t i = 0; i < heights.size(); i++)
		a.set(i, float(heights[i]));
	return a;
}
Dictionary TerrainField::get_regional_maps() const {
	PackedFloat32Array hardness, talus;
	hardness.resize(regional_hardness.size());
	talus.resize(regional_talus.size());
	for (size_t i = 0; i < regional_hardness.size(); i++) {
		hardness.set(i, regional_hardness[i]);
		talus.set(i, regional_talus[i]);
	}
	Dictionary maps;
	maps["hardness"] = hardness;
	maps["talus"] = talus;
	return maps;
}
PackedFloat32Array TerrainField::get_initial_heights() const {
	PackedFloat32Array a;
	a.resize(initial.size());
	for (size_t i = 0; i < initial.size(); i++)
		a.set(i, float(initial[i]));
	return a;
}
PackedFloat32Array TerrainField::get_drainage_map() const {
	PackedFloat32Array a;
	a.resize(drainage.size());
	for (size_t i = 0; i < drainage.size(); i++)
		a.set(i, drainage[i]);
	return a;
}
PackedFloat32Array TerrainField::get_surface_map() const {
	PackedFloat32Array a;
	a.resize(heights.size() * 4);
	for (size_t i = 0; i < heights.size(); i++) {
		a.set(i * 4, biomes[i].x);
		a.set(i * 4 + 1, biomes[i].y);
		a.set(i * 4 + 2, biomes[i].z);
		a.set(i * 4 + 3, road_mask[i]);
	}
	return a;
}
PackedFloat32Array TerrainField::get_chunk_heights(int ox, int oz, int size) const {
	PackedFloat32Array a;
	if (ox < 0 || oz < 0 || size < 1 || ox + size > cells || oz + size > cells)
		return a;
	a.resize((size + 1) * (size + 1));
	for (int z = 0; z <= size; z++)
		for (int x = 0; x <= size; x++)
			a.set(z * (size + 1) + x, float(heights[(oz + z) * side + ox + x]));
	return a;
}
Ref<ArrayMesh> TerrainField::build_chunk(int ox, int oz, int size) const {
	Ref<ArrayMesh> mesh;
	if (ox < 0 || oz < 0 || size < 1 || ox + size > cells || oz + size > cells)
		return mesh;
	PackedVector3Array vertices, normals;
	PackedVector2Array uv;
	PackedColorArray colors;
	PackedInt32Array indices;
	for (int z = 0; z <= size; z++)
		for (int x = 0; x <= size; x++) {
			Vector3 p = position(ox + x, oz + z);
			vertices.push_back(p);
			normals.push_back(get_normal(p.x, p.z));
			uv.push_back(Vector2(double(ox + x) / cells, double(oz + z) / cells));
			Vector3 b = biomes[(oz + z) * side + ox + x];
			colors.push_back(Color(b.x, b.y, b.z, 1));
		}
	for (int z = 0; z < size; z++)
		for (int x = 0; x < size; x++) {
			int a = z * (size + 1) + x, b = a + 1, c = a + size + 1, d = c + 1;
			indices.push_back(a);
			indices.push_back(d);
			indices.push_back(c);
			indices.push_back(a);
			indices.push_back(b);
			indices.push_back(d);
		}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_TEX_UV] = uv;
	arrays[Mesh::ARRAY_COLOR] = colors;
	arrays[Mesh::ARRAY_INDEX] = indices;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}
PackedVector3Array TerrainField::find_route(Vector3 start, Vector3 goal) const {
	PackedVector3Array path;
	if (side == 0)
		return path;
	int stride = std::max(1, cells / 128), width = cells / stride + 1, count = width * width;
	auto coord = [&](double v) { return std::clamp(int(std::round((v / spacing + cells / 2.0) / stride)), 0, width - 1); };
	int sx = coord(start.x), sz = coord(start.z), gx = coord(goal.x), gz = coord(goal.z), source = sz * width + sx, target = gz * width + gx;
	auto height = [&](int i) { return heights[(i / width) * stride * side + (i % width) * stride]; };
	auto heuristic = [&](int i) { return std::hypot(double(i % width - gx), double(i / width - gz)) * spacing * stride; };
	std::vector<double> cost(count, std::numeric_limits<double>::infinity());
	std::vector<int> parent(count, -1);
	std::vector<bool> done(count, false);
	using Item = std::pair<double, int>;
	std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
	cost[source] = 0;
	open.push({ heuristic(source), source });
	while (!open.empty()) {
		int i = open.top().second;
		open.pop();
		if (done[i])
			continue;
		if (i == target)
			break;
		done[i] = true;
		for (int k = 0; k < 8; k++) {
			int x = i % width + DX[k], z = i / width + DZ[k];
			if (x < 0 || z < 0 || x >= width || z >= width)
				continue;
			int j = z * width + x;
			double distance = spacing * stride * (k < 4 ? 1 : std::sqrt(2.0)), slope = std::abs(height(j) - height(i)) / distance;
			double candidate = cost[i] + distance * (1 + 12 * slope * slope);
			if (candidate < cost[j]) {
				cost[j] = candidate;
				parent[j] = i;
				open.push({ candidate + heuristic(j), j });
			}
		}
	}
	std::vector<int> reverse;
	for (int i = target; i != -1; i = parent[i])
		reverse.push_back(i);
	for (auto it = reverse.rbegin(); it != reverse.rend(); ++it) {
		int i = *it;
		path.push_back(position((i % width) * stride, (i / width) * stride));
	}
	return path;
}
