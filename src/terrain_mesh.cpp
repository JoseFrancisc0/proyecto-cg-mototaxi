#include "terrain_mesh.h"
#include "erosion.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <limits>
#include <map>
#include <thread>
#include <vector>

using namespace godot;

static inline double lerp_d(double a, double b, double t) { return a + t * (b - a); }
static inline double smoothstep_d(double a, double b, double x) {
	if (a == b)
		return x < a ? 0.0 : 1.0;
	double t = (x - a) / (b - a);
	if (t < 0.0)
		t = 0.0;
	if (t > 1.0)
		t = 1.0;
	return t * t * (3.0 - 2.0 * t);
}

void TerrainMesh::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_water_mesh"), &TerrainMesh::get_water_mesh);
	ClassDB::bind_method(D_METHOD("get_bridge_mesh"), &TerrainMesh::get_bridge_mesh);
	ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &TerrainMesh::get_height);
	ClassDB::bind_method(D_METHOD("get_drainage", "x", "z"), &TerrainMesh::get_drainage);
	ClassDB::bind_method(D_METHOD("get_hydrology_data"), &TerrainMesh::get_hydrology_data);
	ClassDB::bind_method(D_METHOD("generate_mesh", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::generate_mesh);
	ClassDB::bind_method(D_METHOD("erode_ground", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::erode_ground);
	ClassDB::bind_method(D_METHOD("rebuild_surface", "terrain", "roads", "grid_size", "cell_size", "road_cfg"), &TerrainMesh::rebuild_surface);
	ClassDB::bind_method(D_METHOD("get_ground_heights"), &TerrainMesh::get_ground_heights);
	ClassDB::bind_method(D_METHOD("get_surface_heights"), &TerrainMesh::get_surface_heights);
	ClassDB::bind_method(D_METHOD("set_ground_heights", "heights", "grid_size", "cell_size"), &TerrainMesh::set_ground_heights);
}

TerrainMesh::TerrainMesh() {}
namespace {
// Iluminacion global (S12): visibilidad del cielo por vertice, tambien llamada
// oclusion ambiental. Es un ray tracing sobre el heightfield: desde cada vertice
// se lanzan `dirs` rayos horizontales y se busca el angulo de horizonte mas alto
// que tapa el cielo en esa direccion. Con un cielo uniforme, la radiancia que
// llega a un punto (ponderada por el coseno) en una direccion con horizonte de
// elevacion a es proporcional a cos^2(a) = 1 / (1 + tan^2(a)).
// Resultado: 1 = ve todo el cielo (cresta), 0 = cielo tapado (fondo de quebrada).
std::vector<float> sky_visibility(const std::vector<double> &H, int n, double cell, double radius, int dirs) {
	std::vector<float> out((size_t)n * n, 1.0f);
	if (n < 2 || radius <= cell || dirs < 1)
		return out;
	auto sample = [&](double fx, double fz) {
		int x0 = (int)fx, z0 = (int)fz;
		double tx = fx - x0, tz = fz - z0;
		const double *r0 = &H[(size_t)z0 * n + x0], *r1 = r0 + n;
		return (r0[0] * (1 - tx) + r0[1] * tx) * (1 - tz) + (r1[0] * (1 - tx) + r1[1] * tx) * tz;
	};
	std::vector<double> cx(dirs), cz(dirs);
	for (int d = 0; d < dirs; d++) {
		double a = 2.0 * 3.14159265358979 * (d + 0.5) / dirs;
		cx[d] = std::cos(a);
		cz[d] = std::sin(a);
	}
	auto rows = [&](int z_begin, int z_end) {
		for (int z = z_begin; z < z_end; z++)
			for (int x = 0; x < n; x++) {
				double h0 = H[(size_t)z * n + x];
				double sum = 0.0;
				for (int d = 0; d < dirs; d++) {
					double max_tan = 0.0;
					// Pasos que crecen 25%: mucho detalle cerca, poco costo lejos.
					for (double t = cell; t <= radius; t *= 1.25) {
						double fx = x + cx[d] * t / cell, fz = z + cz[d] * t / cell;
						if (fx < 0 || fz < 0 || fx >= n - 1 || fz >= n - 1)
							break;
						max_tan = std::max(max_tan, (sample(fx, fz) - h0) / t);
					}
					sum += 1.0 / (1.0 + max_tan * max_tan);
				}
				out[(size_t)z * n + x] = (float)(sum / dirs);
			}
	};
	int threads = std::max(1, (int)std::thread::hardware_concurrency());
	std::vector<std::thread> pool;
	int chunk = (n + threads - 1) / threads;
	for (int t = 0; t < threads; t++) {
		int a = t * chunk, b = std::min(n, a + chunk);
		if (a < b)
			pool.emplace_back(rows, a, b);
	}
	for (auto &th : pool)
		th.join();
	return out;
}

// Separate water and bridge surfaces leave the drainage bed intact.
struct RibbonMesh {
	PackedVector3Array points, normals;
	void triangle(Vector3 a, Vector3 b, Vector3 c) {
		// Godot fronts use clockwise winding (the terrain indices do too).
		// Lighting normals point upward, opposite the clockwise geometric cross.
		if ((b - a).cross(c - a).y > 0)
			std::swap(b, c);
		Vector3 normal = (c - a).cross(b - a).normalized();
		points.push_back(a);
		points.push_back(b);
		points.push_back(c);
		normals.push_back(normal);
		normals.push_back(normal);
		normals.push_back(normal);
	}
	void quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d) {
		triangle(a, b, c);
		triangle(a, c, d);
	}
	void ribbon(Vector3 a, Vector3 b, double half_width) {
		Vector3 v = b - a;
		v.y = 0;
		if (v.length() < .001)
			return;
		Vector3 side = Vector3(-v.z, 0, v.x).normalized() * half_width;
		quad(a + side, b + side, b - side, a - side);
	}
	Ref<ArrayMesh> mesh() {
		Ref<ArrayMesh> result;
		result.instantiate();
		if (points.is_empty())
			return result;
		Array data;
		data.resize(Mesh::ARRAY_MAX);
		data[Mesh::ARRAY_VERTEX] = points;
		data[Mesh::ARRAY_NORMAL] = normals;
		result->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, data);
		return result;
	}
};
double grid_sample(const std::vector<double> &h, int n, double cell, double x, double z) {
	if (n < 2 || h.empty())
		return 0;
	double gx = std::clamp(x / cell + (n - 1) * .5, 0.0, double(n - 1)), gz = std::clamp(z / cell + (n - 1) * .5, 0.0, double(n - 1));
	int ix = std::min(int(gx), n - 2), iz = std::min(int(gz), n - 2);
	double tx = gx - ix, tz = gz - iz;
	return (h[iz * n + ix] * (1 - tx) + h[iz * n + ix + 1] * tx) * (1 - tz) + (h[(iz + 1) * n + ix] * (1 - tx) + h[(iz + 1) * n + ix + 1] * tx) * tz;
}
} //namespace
double TerrainMesh::get_height(double x, double z) const { return grid_sample(final_height, final_n, final_cell, x, z); }
double TerrainMesh::get_drainage(double x, double z) const { return grid_sample(drainage.accumulation, drainage.n, drainage.cell, x, z); }
Dictionary TerrainMesh::get_hydrology_data() const {
	Dictionary result;
	result["samples"] = drainage.n;
	result["breach_max_depth"] = drainage.breach_max_depth;
	result["breach_volume"] = drainage.breach_volume;
	result["cell_size"] = drainage.cell;
	PackedInt32Array receivers, channel, lakes, protected_water;
	PackedFloat64Array accumulation, level;
	for (size_t i = 0; i < drainage.receiver.size(); i++) {
		receivers.push_back(drainage.receiver[i]);
		channel.push_back(drainage.channel[i]);
		lakes.push_back(drainage.lake[i]);
		protected_water.push_back(drainage.protected_water[i]);
		accumulation.push_back(drainage.accumulation[i]);
		level.push_back(drainage.level[i]);
	}
	result["lakes"] = lakes;
	result["protected_water"] = protected_water;
	result["receivers"] = receivers;
	result["channels"] = channel;
	result["accumulation"] = accumulation;
	result["water_levels"] = level;
	return result;
}

static bool valid_grid(int grid_size, double cell_size) {
	return grid_size >= 1 && grid_size <= 4096 && std::isfinite(cell_size) && cell_size > 0.0;
}

Ref<ArrayMesh> TerrainMesh::generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
	if (terrain.is_null() || !valid_grid(grid_size, cell_size))
		return Ref<ArrayMesh>();

	// 1. Suelo T0 desde el ruido.
	const int n = grid_size + 1;
	const double offset = grid_size * cell_size * 0.5;
	ground_height.assign((size_t)n * n, 0.0);
	ground_n = n;
	ground_cell = cell_size;
	for (int iz = 0; iz < n; iz++)
		for (int ix = 0; ix < n; ix++)
			ground_height[(size_t)iz * n + ix] = terrain->get_height(ix * cell_size - offset, iz * cell_size - offset);

	// 2. Erosion opcional en el mismo paso (compatibilidad con pruebas y scripts anteriores).
	if ((bool)road_cfg.get("erosion_enabled", false))
		erode_heights(ground_height, terrain, n, cell_size, road_cfg);

	// 3. Rios, caminos y malla sobre el suelo.
	return build_surface(terrain, roads, grid_size, cell_size, road_cfg);
}

Ref<ArrayMesh> TerrainMesh::erode_ground(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
	if (terrain.is_null() || !valid_grid(grid_size, cell_size) || ground_n != grid_size + 1 ||
			ground_height.size() != (size_t)ground_n * ground_n)
		return Ref<ArrayMesh>();
	erode_heights(ground_height, terrain, ground_n, cell_size, road_cfg);
	Dictionary cfg = road_cfg.duplicate();
	cfg["erosion_enabled"] = true; // los caminos deben seguir el suelo erosionado
	return build_surface(terrain, roads, grid_size, cell_size, cfg);
}

Ref<ArrayMesh> TerrainMesh::rebuild_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
	if (terrain.is_null() || !valid_grid(grid_size, cell_size) || ground_n != grid_size + 1 ||
			ground_height.size() != (size_t)ground_n * ground_n)
		return Ref<ArrayMesh>();
	return build_surface(terrain, roads, grid_size, cell_size, road_cfg);
}

PackedFloat32Array TerrainMesh::get_ground_heights() const {
	PackedFloat32Array out;
	out.resize((int64_t)ground_height.size());
	for (size_t i = 0; i < ground_height.size(); i++)
		out.set((int64_t)i, (float)ground_height[i]);
	return out;
}

PackedFloat32Array TerrainMesh::get_surface_heights() const {
	PackedFloat32Array out;
	out.resize((int64_t)final_height.size());
	for (size_t i = 0; i < final_height.size(); i++)
		out.set((int64_t)i, (float)final_height[i]);
	return out;
}

bool TerrainMesh::set_ground_heights(const PackedFloat32Array &heights, int grid_size, double cell_size) {
	if (!valid_grid(grid_size, cell_size))
		return false;
	const int n = grid_size + 1;
	if (heights.size() != (int64_t)n * n)
		return false;
	ground_height.resize((size_t)n * n);
	for (int64_t i = 0; i < heights.size(); i++) {
		double h = heights[i];
		if (!std::isfinite(h))
			return false;
		ground_height[(size_t)i] = h;
	}
	ground_n = n;
	ground_cell = cell_size;
	return true;
}

void TerrainMesh::erode_heights(std::vector<double> &H, Ref<TerrainNoise> terrain, int n, double cell_size, const Dictionary &road_cfg) {
	auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
	const double offset = (n - 1) * cell_size * 0.5;
	{
		ErosionSteps steps;
		steps.fluvial = (int)cfg_d("erosion_fluvial", 3000.0);
		steps.thermal = (int)cfg_d("erosion_thermal", 600.0);
		steps.deposition = (int)cfg_d("erosion_deposition", 2000.0);
		steps.levels = (int)cfg_d("erosion_levels", 0.0);
		if (bool(road_cfg.get("regional_erosion_maps", false))) {
			// S11 CG-B publishes rho(p) and s0(p). The EXISTING CG-A erosion
			// consumes them (paper sections 4.2 and 4.3); it is not replaced.
			steps.hardness.resize(H.size());
			steps.talus.resize(H.size());
			for (int z = 0; z < n; z++)
				for (int x = 0; x < n; x++) {
					double wx = x * cell_size - offset, wz = z * cell_size - offset;
					steps.hardness[z * n + x] = terrain->get_hardness(wx, wz);
					steps.talus[z * n + x] = terrain->get_critical_slope(wx, wz);
				}
		}
		erode_terrain(H, n, cell_size, steps);
	}
}

Ref<ArrayMesh> TerrainMesh::build_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg) {
	auto cfg_d = [&](const char *k, double def) { Variant v = road_cfg.get(k, def); return (double)v; };
	double road_width = std::max(0.0, cfg_d("road_width", 4.0));
	double road_fade = std::max(0.01, cfg_d("road_fade", 3.0));

	const double area_half = grid_size * cell_size * 0.5;
	const int n = grid_size + 1;
	const double offset = area_half;
	// Se trabaja sobre una copia: el suelo guardado no lleva rios ni caminos.
	std::vector<double> H = ground_height;
	std::vector<Color> Cv((size_t)n * n);

	const std::vector<RoadSegment> *roads_ptr = roads.is_valid() ? &roads->get_roads_internal() : nullptr;

	// Compute drainage only when explicitly requested. T0 still has no CG-A erosion.
	// Paper 5.2: breach the actual terrain, then recompute the paper 4.1 flow.
	drainage = DrainageField();
	water_mesh.unref();
	bridge_mesh.unref();
	bool hydrology = bool(road_cfg.get("hydrology_enabled", false));
	RibbonMesh water_geometry, bridge_geometry;
	double river_threshold = 0.0; // se reutiliza abajo para la humedad por vertice
	if (hydrology) {
		// Main-river display needs meaningful catchments, not tiny tributaries on every slope.
 double threshold = std::max({cell_size * cell_size * 8,grid_size*cell_size*grid_size*cell_size*.01,cfg_d("river_catchment",60000.0)});
		drainage.breach_multiscale(H, n, cell_size, cfg_d("breach_radius", 24.0));
		drainage.compute(H, n, cell_size, threshold);
		river_threshold = threshold;

		// Display the corrected ground drainage; no automatic filling of depressions.
		for (int i = 0; i < n * n; i++)
			if (drainage.channel[i]) {
				int j = drainage.receiver[i];
				if (j < 0)
					continue;
				double distance=std::hypot((i%n-j%n)*cell_size,(i/n-j/n)*cell_size);
                double grade=(drainage.level[i]-drainage.level[j])/distance;
                // A static water sheet cannot represent a waterfall. Keep its drainage,
                // but do not paint steep mountain sides blue.
                if(grade>.20)continue;
                double width=std::clamp(.35+.20*std::sqrt(drainage.accumulation[i]/threshold),.45,1.2);
				Vector3 a((i % n) * cell_size - offset, drainage.level[i] + .08, (i / n) * cell_size - offset);
				Vector3 b((j % n) * cell_size - offset, drainage.level[j] + .08, (j / n) * cell_size - offset);
				Vector3 direction=b-a;direction.y=0;
                Vector3 side=Vector3(-direction.z,0,direction.x).normalized()*width;
                // Keep water cross-sections level. Projecting each corner onto the
                // banks creates vertical blue curtains across narrow breached valleys.
                water_geometry.quad(a+side,b+side,b-side,a-side);
			}

		water_mesh = water_geometry.mesh();
	}
	// Rebuild hierarchical roads AFTER CG-A and drainage, using the actual surface.
	if (roads.is_valid() && bool(road_cfg.get("hierarchical_roads", false))) {
		roads->set_surface(H, drainage.protected_water, n, cell_size);
		roads->generate_roads(terrain, grid_size, cell_size, road_cfg);
	}
	// The old road generator is kept for compatibility; final profiles still follow CG-A.
	if (roads.is_valid() && (hydrology || bool(road_cfg.get("erosion_enabled", false)))) {
		auto &network = roads->get_roads_mutable();
		for (auto &road : network) {
			int count = int(road.pts.size());
			std::vector<unsigned char> wet(count, 0), deck(count, 0);
			for (int k = 0; k < count; k++) {
				auto p = road.pts[k];
				road.h[k] = grid_sample(H, n, cell_size, p.x, p.z);
				if (hydrology) {
					int x = std::clamp(int(std::round((p.x + offset) / cell_size)), 0, n - 1), z = std::clamp(int(std::round((p.z + offset) / cell_size)), 0, n - 1);
					wet[k] = drainage.protected_water[z * n + x];
				}
			}
			// Group crossings and provide approach ramps, rather than isolated floating road tiles.
			for (int k = 0; k < count; k++)
				if (wet[k]) {
					int first = k, last = k;
					while (last + 1 < count && wet[last + 1])
						last++;
					double shoulder = (road.half_width > 0 ? road.half_width : road_width) + 6;
					int a = first, b = last;
					double distance = 0;
					while (a > 0 && distance < shoulder) {
						distance += road.pts[a].distance_to(road.pts[a - 1]);
						--a;
					}
					distance = 0;
					while (b + 1 < count && distance < shoulder) {
						distance += road.pts[b].distance_to(road.pts[b + 1]);
						++b;
					}
					double top = -std::numeric_limits<double>::infinity();
					for (int t = a; t <= b; t++) {
						auto p = road.pts[t];
						top = std::max(top, std::max(grid_sample(H, n, cell_size, p.x, p.z), grid_sample(drainage.level, n, cell_size, p.x, p.z)) + 1.2);
					}
					for (int t = a; t <= b; t++) {
						road.h[t] = std::max(road.h[t], top);
						deck[t] = 1;
					}
					for (int direction : { -1, 1 }) {
						int t = direction < 0 ? a : b;
						double run = 0;
						while (t + direction >= 0 && t + direction < count && run < 24) {
							int next = t + direction;
							run += road.pts[t].distance_to(road.pts[next]);
							road.h[next] = std::max(road.h[next], lerp_d(top, grid_sample(H, n, cell_size, road.pts[next].x, road.pts[next].z), std::min(1.0, run / 24.0)));
							deck[next] = 1;
							t = next;
						}
					}
					k = last;
				}
			road.elevated = deck;
		}
		// Share bridge-junction elevations across all incident streets and add approaches.
		// Otherwise one raised avenue could meet a street at ground level.
		using Junction = std::pair<long long, long long>;
		auto key = [](Vector3 p) { return Junction(std::llround(p.x * 100), std::llround(p.z * 100)); };
		std::map<Junction, double> junctions;
		for (const auto &road : network)
			if (!road.pts.empty())
				for (size_t k : { size_t(0), road.pts.size() - 1 }) {
					auto location = key(road.pts[k]);
					auto found = junctions.find(location);
					if (found == junctions.end())
						junctions[location] = road.h[k];
					else
						found->second = std::max(found->second, road.h[k]);
				}
		for (auto &road : network) {
			int count = int(road.pts.size());
			if (count < 2)
				continue;
			for (int direction : { 1, -1 }) {
				int start = direction == 1 ? 0 : count - 1;
				double top = junctions[key(road.pts[start])];
				if (top <= road.h[start] + .001)
					continue;
				double distance = 0;
				int t = start;
				road.h[t] = top;
				road.elevated[t] = 1;
				while (t + direction >= 0 && t + direction < count && distance < 24) {
					int next = t + direction;
					// Do not raise the opposite shared junction while shaping this approach.
					if (next == 0 || next == count - 1)
						break;
					distance += road.pts[next].distance_to(road.pts[t]);
					double target = lerp_d(top, road.h[next], std::min(1.0, distance / 24));
					if (target > road.h[next] + .001) {
						road.h[next] = target;
						road.elevated[next] = 1;
					}
					t = next;
				}
			}
		}
		for (const auto &road : network)
			for (size_t k = 0; k + 1 < road.pts.size(); k++)
				if (road.elevated[k] || road.elevated[k + 1]) {
					auto a = road.pts[k], b = road.pts[k + 1];
					a.y = road.h[k] + .04;
					b.y = road.h[k + 1] + .04;
					bridge_geometry.ribbon(a, b, road.half_width > 0 ? road.half_width : road_width);
				}
		bridge_mesh = bridge_geometry.mesh();
	}

	// Rasterizar solo la vecindad de cada segmento. Conserva el perfil original
	// sin comparar cada vertice del mapa con todos los segmentos de caminos.
	std::vector<double> road_distance(H.size(), std::numeric_limits<double>::infinity());
	std::vector<double> road_height(H.size(), 0.0);
	std::vector<double> influence(H.size(), 0.0);
	std::vector<int> kinds(H.size(), 0);
	if (roads_ptr)
		for (const RoadSegment &road : *roads_ptr) {
			for (size_t segment = 0; segment + 1 < road.pts.size(); segment++) {
				const Vector3 &a = road.pts[segment], &b = road.pts[segment + 1];
				double width = road.half_width > 0 ? road.half_width : road_width;
				double radius = width + road_fade;
				int x0 = std::clamp(int(std::floor((std::min(a.x, b.x) - radius + offset) / cell_size)), 0, n - 1);
				int x1 = std::clamp(int(std::ceil((std::max(a.x, b.x) + radius + offset) / cell_size)), 0, n - 1);
				int z0 = std::clamp(int(std::floor((std::min(a.z, b.z) - radius + offset) / cell_size)), 0, n - 1);
				int z1 = std::clamp(int(std::ceil((std::max(a.z, b.z) + radius + offset) / cell_size)), 0, n - 1);
				double abx = b.x - a.x, abz = b.z - a.z, len2 = abx * abx + abz * abz;
				for (int z = z0; z <= z1; z++)
					for (int x = x0; x <= x1; x++) {
						double wx = x * cell_size - offset, wz = z * cell_size - offset;
						double t = len2 > 0 ? std::clamp(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0) : 0.0;
						double distance = std::hypot(wx - a.x - t * abx, wz - a.z - t * abz);
						size_t i = size_t(z) * n + x;
						double weight = 1.0 - smoothstep_d(width, width + road_fade, distance);
						if (weight > influence[i] || (weight == influence[i] && distance < road_distance[i])) {
							influence[i] = weight;
							kinds[i] = road.kind;
							road_distance[i] = distance;
							road_height[i] = lerp_d(road.h[segment], road.h[segment + 1], t);
						}
					}
			}
		}

	// Apply roads after erosion so the final surface preserves the road profile.
	for (int iz = 0; iz < n; iz++) {
		for (int ix = 0; ix < n; ix++) {
			double x = ix * cell_size - offset;
			double z = iz * cell_size - offset;
			double base_h = H[(size_t)iz * n + ix];
			Color col = terrain->get_biome_color(x, z, base_h);
			size_t i = size_t(iz) * n + ix;
			double w = influence[i];
			if (hydrology && drainage.protected_water[i])
				w = 0;
			if (w > 0.0) {
				base_h = lerp_d(base_h, road_height[i], w);
				col = col.lerp(kinds[i] == 0 ? Color(0.40, 0.28, 0.16) : (kinds[i] == 3 ? Color(0.27, 0.28, 0.29) : Color(0.13, 0.14, 0.16)), w);
			}

			// Alfa del color = mascara de camino (0 = suelo, 1 = camino). El shader
			// de texturas la usa para pintar el camino encima de las texturas.
			col.a = (float)w;
			H[(size_t)iz * n + ix] = base_h;
			Cv[(size_t)iz * n + ix] = col;
		}
	}

	final_height = H;
	final_n = n;
	final_cell = cell_size;
	PackedVector3Array verts;
	PackedColorArray cols;
	PackedVector3Array norms;
	// Texture mapping (clase S10): cada vertice recibe coordenadas 2D (u, v).
	// Un heightfield se parametriza sin cortes ni distorsion en planta:
	// (u, v) = (x, z) en metros. La GPU interpola (u, v) dentro de cada
	// triangulo con coordenadas baricentricas.
	PackedVector2Array uvs;
	// Funciones sobre la malla: valores por vertice que la GPU tambien
	// interpola. CUSTOM0 = (peso costa, peso sierra, peso selva, humedad).
	PackedFloat32Array regions;
	regions.resize((int64_t)n * n * 4);
	// CUSTOM1 = visibilidad del cielo (oclusion ambiental) por vertice.
	std::vector<float> sky = sky_visibility(H, n, cell_size, cfg_d("ao_radius", 300.0), (int)cfg_d("ao_directions", 16.0));
	PackedFloat32Array ao;
	ao.resize((int64_t)n * n);
	for (int64_t i = 0; i < (int64_t)n * n; i++)
		ao.set(i, sky[(size_t)i]);
	auto Hv = [&](int ix, int iz) {
		if (ix < 0)
			ix = 0;
		if (ix >= n)
			ix = n - 1;
		if (iz < 0)
			iz = 0;
		if (iz >= n)
			iz = n - 1;
		return H[(size_t)iz * n + ix];
	};
	for (int iz = 0; iz < n; iz++) {
		for (int ix = 0; ix < n; ix++) {
			double x = ix * cell_size - offset;
			double z = iz * cell_size - offset;
			verts.push_back(Vector3(x, H[(size_t)iz * n + ix], z));
			cols.push_back(Cv[(size_t)iz * n + ix]);
			uvs.push_back(Vector2(x, z));
			Vector3 bw = terrain->get_biome_weights(x, z);
			size_t vi = (size_t)iz * n + ix;
			double wet = 0.0;
			if (river_threshold > 0.0 && drainage.accumulation.size() == (size_t)n * n)
				wet = smoothstep_d(0.15 * river_threshold, river_threshold, drainage.accumulation[vi]);
			regions.set((int64_t)vi * 4 + 0, (float)bw.x);
			regions.set((int64_t)vi * 4 + 1, (float)bw.y);
			regions.set((int64_t)vi * 4 + 2, (float)bw.z);
			regions.set((int64_t)vi * 4 + 3, (float)wet);
			double dhdx = (Hv(ix + 1, iz) - Hv(ix - 1, iz)) / ((ix == 0 || ix == n - 1 ? 1.0 : 2.0) * cell_size);
			double dhdz = (Hv(ix, iz + 1) - Hv(ix, iz - 1)) / ((iz == 0 || iz == n - 1 ? 1.0 : 2.0) * cell_size);
			norms.push_back(Vector3(-dhdx, 1.0, -dhdz).normalized());
		}
	}

	PackedInt32Array idx;
	for (int iz = 0; iz < grid_size; iz++) {
		for (int ix = 0; ix < grid_size; ix++) {
			int i00 = iz * n + ix, i10 = iz * n + ix + 1;
			int i01 = (iz + 1) * n + ix, i11 = (iz + 1) * n + ix + 1;
			idx.push_back(i00);
			idx.push_back(i11);
			idx.push_back(i01);
			idx.push_back(i00);
			idx.push_back(i10);
			idx.push_back(i11);
		}
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_NORMAL] = norms;
	arrays[Mesh::ARRAY_COLOR] = cols;
	arrays[Mesh::ARRAY_TEX_UV] = uvs;
	arrays[Mesh::ARRAY_CUSTOM0] = regions;
	arrays[Mesh::ARRAY_CUSTOM1] = ao;
	arrays[Mesh::ARRAY_INDEX] = idx;

	Ref<ArrayMesh> am;
	am.instantiate();
	// CUSTOM0 viaja como 4 floats por vertice; CUSTOM1 como 1 float.
	int64_t custom_format = (int64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT) |
			(int64_t(Mesh::ARRAY_CUSTOM_R_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM1_SHIFT);
	am->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), (BitField<Mesh::ArrayFormat>)custom_format);
	return am;
}
