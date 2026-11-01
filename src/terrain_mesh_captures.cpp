// TerrainMesh: avance (pantalla de carga), capturas de la evolucion de la erosion
// y figuras de cada etapa del pipeline (S13/S14).
#include "terrain_internal.h"
#include "terrain_mesh.h"
#include "terrain_render.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
namespace tr = terrain_render;

namespace {

PackedByteArray to_bytes(const tr::Image &img) {
	PackedByteArray out;
	out.resize((int64_t)img.rgb.size());
	if (!img.rgb.empty())
		memcpy(out.ptrw(), img.rgb.data(), img.rgb.size());
	return out;
}

std::string to_std(const String &s) {
	CharString c = s.utf8();
	return std::string(c.get_data());
}

void stamp_label(tr::Image &img, const Dictionary &options) {
	String label = options.get("label", String());
	if (label.is_empty())
		return;
	int scale = (int)options.get("label_scale", img.width >= 1200 ? 3 : (img.width >= 600 ? 2 : 1));
	const uint8_t white[3] = { 255, 255, 255 };
	tr::text(img, 6 * scale, 6 * scale, to_std(label), scale, white, true);
	String sub = options.get("sublabel", String());
	if (!sub.is_empty())
		tr::text(img, 6 * scale, 6 * scale + 12 * scale, to_std(sub), std::max(1, scale - 1 + (scale == 1)), white, true);
}

// Sub-muestrea una grilla n x n a m x m (m - 1 divide a n - 1); 'stride' componentes por muestra.
std::vector<float> subsample(const std::vector<float> &src, int n, int m, int components) {
	std::vector<float> out;
	if (n < 2 || m < 2 || (n - 1) % (m - 1) != 0 || src.size() != size_t(n) * n * components)
		return out;
	int step = (n - 1) / (m - 1);
	out.resize(size_t(m) * m * components);
	for (int z = 0; z < m; z++)
		for (int x = 0; x < m; x++)
			for (int c = 0; c < components; c++)
				out[(size_t(z) * m + x) * components + c] = src[(size_t(z) * step * n + x * step) * components + c];
	return out;
}

tr::ReliefOptions relief_options(const Dictionary &o) {
	tr::ReliefOptions r;
	r.sun_azimuth = (double)o.get("map_sun_azimuth", r.sun_azimuth);
	r.sun_elevation = (double)o.get("map_sun_elevation", r.sun_elevation);
	r.z_factor = (double)o.get("z_factor", r.z_factor);
	r.contours = (bool)o.get("contours", r.contours);
	r.contour_step = (double)o.get("contour_step", r.contour_step);
	return r;
}

tr::PerspectiveOptions perspective_options(const Dictionary &o) {
	tr::PerspectiveOptions p;
	p.azimuth = (double)o.get("azimuth", p.azimuth);
	p.elevation = (double)o.get("elevation", p.elevation);
	p.distance = (double)o.get("distance", p.distance);
	p.fov = (double)o.get("fov", p.fov);
	p.exaggeration = (double)o.get("exaggeration", p.exaggeration);
	p.sun_azimuth = (double)o.get("sun_azimuth", p.sun_azimuth);
	p.sun_elevation = (double)o.get("sun_elevation", p.sun_elevation);
	p.shadows = (bool)o.get("shadows", p.shadows);
	return p;
}

// Percentil de |v| (para escalas de color robustas).
double abs_percentile(const std::vector<float> &v, double q) {
	if (v.empty())
		return 1.0;
	std::vector<float> a;
	a.reserve(v.size() / 7 + 1);
	for (size_t i = 0; i < v.size(); i += 7)
		a.push_back(std::fabs(v[i]));
	size_t k = std::min(a.size() - 1, size_t(q * (a.size() - 1)));
	std::nth_element(a.begin(), a.begin() + k, a.end());
	return std::max(1e-6, (double)a[k]);
}

const char *stage_name_es(const std::string &stage) {
	if (stage == "fluvial")
		return "erosion fluvial";
	if (stage == "thermal")
		return "termica";
	if (stage == "deposition")
		return "deposicion";
	if (stage == "retarget")
		return "retargeting";
	return "T0";
}

} // namespace

// ---------------------------------------------------------------------------
// Avance
// ---------------------------------------------------------------------------
void TerrainMesh::begin_run() {
	std::lock_guard<std::mutex> lock(progress_mutex);
	run_start = std::chrono::steady_clock::now();
	progress_value.store(0.0);
}

void TerrainMesh::set_phase(double start, double span, const std::string &stage) {
	phase_start = start;
	phase_span = span;
	progress_value.store(std::clamp(start, 0.0, 1.0));
	std::lock_guard<std::mutex> lock(progress_mutex);
	progress_stage = stage;
}

void TerrainMesh::report(double f, const std::string &stage) {
	f = std::clamp(f, 0.0, 1.0);
	double v = std::clamp(phase_start + phase_span * f, 0.0, 1.0);
	// El avance nunca retrocede dentro de una misma corrida.
	double old = progress_value.load();
	while (v > old && !progress_value.compare_exchange_weak(old, v)) {
	}
	if (!stage.empty()) {
		std::lock_guard<std::mutex> lock(progress_mutex);
		progress_stage = stage;
	}
}

Dictionary TerrainMesh::get_progress() const {
	Dictionary d;
	d["fraction"] = progress_value.load();
	std::lock_guard<std::mutex> lock(progress_mutex);
	d["stage"] = String::utf8(progress_stage.c_str());
	d["elapsed"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - run_start).count();
	d["preview_serial"] = preview_serial;
	return d;
}

Dictionary TerrainMesh::get_preview() const {
	Dictionary d;
	std::lock_guard<std::mutex> lock(progress_mutex);
	d["serial"] = preview_serial;
	d["width"] = preview_size;
	d["height"] = preview_size > 0 ? preview_size * 9 / 16 : 0;
	PackedByteArray bytes;
	bytes.resize((int64_t)preview_rgb.size());
	if (!preview_rgb.empty())
		memcpy(bytes.ptrw(), preview_rgb.data(), preview_rgb.size());
	d["rgb"] = bytes;
	return d;
}

void TerrainMesh::update_preview(const std::vector<float> &h, int n, double cell, double h_lo, double h_hi) {
	if (capture_preview_size <= 0 || n < 2)
		return;
	std::vector<float> biome;
	if (biome_cache_n > 0)
		biome = biome_cache_n == n ? biome_cache : subsample(biome_cache, biome_cache_n, n, 3);
	tr::Field f;
	f.h = h.data();
	f.n = n;
	f.cell = cell;
	f.h_lo = h_lo;
	f.h_hi = h_hi;
	f.biome = biome.size() == size_t(n) * n * 3 ? biome.data() : nullptr;
	tr::PerspectiveOptions o;
	o.shadows = false;
	int w = capture_preview_size, hh = capture_preview_size * 9 / 16;
	tr::Image img = tr::perspective(f, w, hh, o);
	std::lock_guard<std::mutex> lock(progress_mutex);
	preview_rgb = std::move(img.rgb);
	preview_size = w;
	preview_serial++;
}

const std::vector<float> &TerrainMesh::biome_weights(Ref<TerrainNoise> terrain, int n, double cell) {
	if (terrain.is_valid() && (biome_cache_owner != terrain.ptr() || biome_cache_n != n || biome_cache_cell != cell)) {
		biome_cache.assign(size_t(n) * n * 3, 0.0f);
		const double offset = (n - 1) * cell * 0.5;
		for (int z = 0; z < n; z++)
			for (int x = 0; x < n; x++) {
				Vector3 w = terrain->get_biome_weights(x * cell - offset, z * cell - offset);
				size_t i = (size_t(z) * n + x) * 3;
				biome_cache[i] = (float)w.x;
				biome_cache[i + 1] = (float)w.y;
				biome_cache[i + 2] = (float)w.z;
			}
		biome_cache_n = n;
		biome_cache_cell = cell;
		biome_cache_owner = terrain.ptr();
	}
	return biome_cache;
}

// ---------------------------------------------------------------------------
// Capturas
// ---------------------------------------------------------------------------
void TerrainMesh::set_capture_options(Dictionary options) {
	capture_count = std::max(0, (int)options.get("count", capture_count));
	capture_stage_ends = (bool)options.get("stage_ends", capture_stage_ends);
	capture_keep = (bool)options.get("keep", capture_keep);
	capture_preview_size = std::max(0, (int)options.get("preview_size", capture_preview_size));
}

void TerrainMesh::clear_captures() {
	frames.clear();
	frames.shrink_to_fit();
}

void TerrainMesh::capture_range(double &lo, double &hi) const {
	lo = 1e300;
	hi = -1e300;
	for (const ErosionFrame &f : frames)
		for (float v : f.heights) {
			lo = std::min(lo, (double)v);
			hi = std::max(hi, (double)v);
		}
	if (lo > hi) {
		lo = 0.0;
		hi = 1.0;
	}
	double margin = std::max(1.0, (hi - lo) * 0.03);
	lo -= margin;
	hi += margin;
}

Dictionary TerrainMesh::get_capture_info(int index) const {
	Dictionary d;
	if (index < 0 || index >= (int)frames.size())
		return d;
	const ErosionFrame &f = frames[index];
	d["index"] = f.index;
	d["stage"] = String(f.stage.c_str());
	d["stage_es"] = String(stage_name_es(f.stage));
	d["level"] = f.level;
	d["levels"] = f.levels;
	d["samples"] = f.samples;
	d["cell"] = f.cell;
	d["iteration"] = f.iteration;
	d["stage_total"] = f.stage_total;
	d["fluvial"] = f.fluvial;
	d["thermal"] = f.thermal;
	d["deposition"] = f.deposition;
	d["level_fluvial"] = f.level_fluvial;
	d["level_thermal"] = f.level_thermal;
	d["level_deposition"] = f.level_deposition;
	d["global_iteration"] = (int64_t)f.global_iteration;
	d["total_iterations"] = (int64_t)f.total_iterations;
	d["seconds"] = f.seconds;
	return d;
}

PackedFloat32Array TerrainMesh::get_capture_heights(int index) const {
	PackedFloat32Array out;
	if (index < 0 || index >= (int)frames.size())
		return out;
	const auto &h = frames[index].heights;
	out.resize((int64_t)h.size());
	if (!h.empty())
		memcpy(out.ptrw(), h.data(), h.size() * sizeof(float));
	return out;
}

Dictionary TerrainMesh::get_capture_stats(int index) const {
	Dictionary d;
	if (index < 0 || index >= (int)frames.size())
		return d;
	const ErosionFrame &f = frames[index];
	const int m = f.samples;
	const int n = (int)std::lround(std::sqrt((double)erosion_input.size()));
	double lo = 1e300, hi = -1e300, sum = 0.0, eroded = 0.0, deposited = 0.0, sq = 0.0, slope_sum = 0.0;
	bool comparable = n >= 2 && m >= 2 && (n - 1) % (m - 1) == 0;
	int step = comparable ? (n - 1) / (m - 1) : 1;
	const double area = f.cell * f.cell;
	for (int z = 0; z < m; z++)
		for (int x = 0; x < m; x++) {
			double h = f.heights[size_t(z) * m + x];
			lo = std::min(lo, h);
			hi = std::max(hi, h);
			sum += h;
			if (comparable) {
				double d0 = h - erosion_input[size_t(z) * step * n + x * step];
				if (d0 < 0)
					eroded -= d0 * area;
				else
					deposited += d0 * area;
				sq += d0 * d0;
			}
			if (x + 1 < m && z + 1 < m) {
				double gx = (f.heights[size_t(z) * m + x + 1] - h) / f.cell;
				double gz = (f.heights[size_t(z + 1) * m + x] - h) / f.cell;
				slope_sum += std::sqrt(gx * gx + gz * gz);
			}
		}
	double count = double(m) * m;
	d["min_height"] = lo;
	d["max_height"] = hi;
	d["mean_height"] = sum / count;
	d["relief"] = hi - lo;
	d["eroded_volume_m3"] = eroded;
	d["deposited_volume_m3"] = deposited;
	d["rms_change_m"] = comparable ? std::sqrt(sq / count) : 0.0;
	d["mean_slope"] = slope_sum / std::max(1.0, double(m - 1) * (m - 1));
	return d;
}

PackedByteArray TerrainMesh::render_capture(int index, String kind, int width, int height, Dictionary options) const {
	if (index < 0 || index >= (int)frames.size() || width < 8 || height < 8)
		return PackedByteArray();
	const ErosionFrame &f = frames[index];
	double lo, hi;
	capture_range(lo, hi);
	lo = (double)options.get("h_min", lo);
	hi = (double)options.get("h_max", hi);
	std::vector<float> biome;
	if (biome_cache_n > 0)
		biome = biome_cache_n == f.samples ? biome_cache : subsample(biome_cache, biome_cache_n, f.samples, 3);
	tr::Field field;
	field.h = f.heights.data();
	field.n = f.samples;
	field.cell = f.cell;
	field.h_lo = lo;
	field.h_hi = hi;
	field.biome = biome.size() == size_t(f.samples) * f.samples * 3 ? biome.data() : nullptr;
	tr::Image img;
	if (kind == "perspectiva") {
		img = tr::perspective(field, width, height, perspective_options(options));
	} else if (kind == "diferencia") {
		const int n = (int)std::lround(std::sqrt((double)erosion_input.size()));
		std::vector<float> diff(f.heights.size(), 0.0f);
		if (n >= 2 && f.samples >= 2 && (n - 1) % (f.samples - 1) == 0) {
			int step = (n - 1) / (f.samples - 1);
			for (int z = 0; z < f.samples; z++)
				for (int x = 0; x < f.samples; x++)
					diff[size_t(z) * f.samples + x] = f.heights[size_t(z) * f.samples + x] - (float)erosion_input[size_t(z) * step * n + x * step];
		}
		double r = (double)options.get("range", 0.0);
		if (r <= 0.0)
			r = abs_percentile(diff, 0.99);
		img = tr::scalar(diff.data(), f.samples, width, -r, r, 2);
	} else {
		img = tr::relief(field, width, relief_options(options));
	}
	stamp_label(img, options);
	return to_bytes(img);
}

Ref<ArrayMesh> TerrainMesh::build_capture_mesh(int index, Ref<TerrainNoise> terrain, Dictionary options) {
	Ref<ArrayMesh> am;
	if (index < 0 || index >= (int)frames.size())
		return am;
	const ErosionFrame &f = frames[index];
	const int n = f.samples;
	const double cell = f.cell;
	const double offset = (n - 1) * cell * 0.5;
	std::vector<double> H(f.heights.begin(), f.heights.end());
	std::vector<float> biome;
	if (biome_cache_n > 0)
		biome = biome_cache_n == n ? biome_cache : subsample(biome_cache, biome_cache_n, n, 3);
	std::vector<float> sky = terrain_sky_visibility(H, n, cell, (double)options.get("ao_radius", 200.0), (int)options.get("ao_directions", 8));
	PackedVector3Array verts, norms;
	PackedColorArray cols;
	PackedVector2Array uvs;
	PackedFloat32Array regions, ao;
	verts.resize((int64_t)n * n);
	norms.resize((int64_t)n * n);
	cols.resize((int64_t)n * n);
	uvs.resize((int64_t)n * n);
	regions.resize((int64_t)n * n * 4);
	ao.resize((int64_t)n * n);
	auto Hv = [&](int x, int z) {
		x = std::clamp(x, 0, n - 1);
		z = std::clamp(z, 0, n - 1);
		return H[size_t(z) * n + x];
	};
	for (int z = 0; z < n; z++)
		for (int x = 0; x < n; x++) {
			int64_t i = (int64_t)z * n + x;
			double wx = x * cell - offset, wz = z * cell - offset;
			verts.set(i, Vector3(wx, H[i], wz));
			uvs.set(i, Vector2(wx, wz));
			cols.set(i, Color(1, 1, 1, 0));
			Vector3 bw = biome.size() == size_t(n) * n * 3 ? Vector3(biome[i * 3], biome[i * 3 + 1], biome[i * 3 + 2])
															  : (terrain.is_valid() ? terrain->get_biome_weights(wx, wz) : Vector3(0, 1, 0));
			regions.set(i * 4, (float)bw.x);
			regions.set(i * 4 + 1, (float)bw.y);
			regions.set(i * 4 + 2, (float)bw.z);
			regions.set(i * 4 + 3, 0.0f);
			ao.set(i, sky[i]);
			double dhdx = (Hv(x + 1, z) - Hv(x - 1, z)) / ((x == 0 || x == n - 1 ? 1.0 : 2.0) * cell);
			double dhdz = (Hv(x, z + 1) - Hv(x, z - 1)) / ((z == 0 || z == n - 1 ? 1.0 : 2.0) * cell);
			norms.set(i, Vector3(-dhdx, 1.0, -dhdz).normalized());
		}
	PackedInt32Array idx;
	idx.resize((int64_t)(n - 1) * (n - 1) * 6);
	int64_t k = 0;
	for (int z = 0; z < n - 1; z++)
		for (int x = 0; x < n - 1; x++) {
			int i00 = z * n + x, i10 = i00 + 1, i01 = i00 + n, i11 = i01 + 1;
			idx.set(k++, i00);
			idx.set(k++, i10);
			idx.set(k++, i01);
			idx.set(k++, i10);
			idx.set(k++, i11);
			idx.set(k++, i01);
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
	am.instantiate();
	int64_t custom_format = (int64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT) |
			(int64_t(Mesh::ARRAY_CUSTOM_R_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM1_SHIFT);
	am->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), (BitField<Mesh::ArrayFormat>)custom_format);
	return am;
}

// ---------------------------------------------------------------------------
// Figuras de cada etapa
// ---------------------------------------------------------------------------
PackedStringArray TerrainMesh::get_layer_names() const {
	PackedStringArray names;
	for (const auto &entry : layers)
		names.push_back(String(entry.first.c_str()));
	if (!river_bank.empty())
		names.push_back("rios");
	if (biome_cache_n == layers_n && !biome_cache.empty())
		names.push_back("regiones");
	return names;
}

PackedByteArray TerrainMesh::render_layer(String name, int size, Dictionary options) const {
	const std::string key = to_std(name);
	const int n = layers_n;
	if (size < 8 || n < 2)
		return PackedByteArray();
	tr::Image img;
	auto relief_of = [&](const std::vector<float> &h, const float *water) {
		double lo = 1e300, hi = -1e300;
		for (float v : h) {
			lo = std::min(lo, (double)v);
			hi = std::max(hi, (double)v);
		}
		tr::Field f;
		f.h = h.data();
		f.n = n;
		f.cell = final_cell > 0 && final_n == n ? final_cell : (ground_n == n ? ground_cell : 1.0);
		f.h_lo = (double)options.get("h_min", lo);
		f.h_hi = (double)options.get("h_max", hi);
		f.biome = biome_cache_n == n ? biome_cache.data() : nullptr;
		f.water = water;
		return tr::relief(f, size, relief_options(options));
	};
	if (key == "regiones") {
		if (biome_cache_n != n)
			return PackedByteArray();
		std::vector<float> rgb(size_t(n) * n * 3);
		for (size_t i = 0; i < size_t(n) * n; i++) {
			const float *w = &biome_cache[i * 3];
			rgb[i * 3] = w[0] * 0.93f + w[1] * 0.55f + w[2] * 0.18f;
			rgb[i * 3 + 1] = w[0] * 0.80f + w[1] * 0.45f + w[2] * 0.55f;
			rgb[i * 3 + 2] = w[0] * 0.45f + w[1] * 0.38f + w[2] * 0.20f;
		}
		img = tr::scalar(rgb.data(), n, size, 0, 1, 4);
	} else if (key == "rios") {
		if (river_bank.size() != size_t(n) * n)
			return PackedByteArray();
		auto it = layers.find("superficie");
		std::vector<float> water(river_bank.size());
		for (size_t i = 0; i < water.size(); i++)
			water[i] = river_bank[i] < 0.0f ? 1.0f : 0.0f;
		if (it != layers.end())
			img = relief_of(it->second, water.data());
		else
			img = tr::scalar(water.data(), n, size, 0, 1, 1);
	} else {
		auto it = layers.find(key);
		if (it == layers.end())
			return PackedByteArray();
		const std::vector<float> &v = it->second;
		if (key == "t0" || key == "superficie" || key == "antes_breach") {
			img = relief_of(v, nullptr);
		} else if (key == "dureza") {
			img = tr::scalar(v.data(), n, size, 0.0, 1.0, 3);
		} else if (key == "talud") {
			double lo = 1e300, hi = -1e300;
			for (float x : v) {
				lo = std::min(lo, (double)x);
				hi = std::max(hi, (double)x);
			}
			img = tr::scalar(v.data(), n, size, lo, std::max(hi, lo + 1e-3), 3);
		} else if (key == "retarget_error" || key == "cambio_erosion") {
			double r = abs_percentile(v, 0.99);
			img = tr::scalar(v.data(), n, size, -r, r, 2);
		} else if (key == "breach_cut") {
			double r = abs_percentile(v, 0.995);
			img = tr::scalar(v.data(), n, size, 0.0, r, 3);
		} else if (key == "drenaje") {
			double lo = 1e300, hi = -1e300;
			for (float x : v) {
				lo = std::min(lo, (double)x);
				hi = std::max(hi, (double)x);
			}
			img = tr::scalar(v.data(), n, size, lo, hi, 1);
		} else if (key == "retarget_puntos") {
			auto base = layers.find("superficie");
			if (base == layers.end())
				base = layers.find("t0");
			if (base != layers.end()) {
				img = relief_of(base->second, nullptr);
				for (int py = 0; py < size; py++)
					for (int px = 0; px < size; px++) {
						int x = std::clamp(int((px + 0.5) / size * n), 0, n - 1), z = std::clamp(int((py + 0.5) / size * n), 0, n - 1);
						if (v[size_t(z) * n + x] > 0.5f) {
							uint8_t *p = &img.rgb[(size_t(py) * size + px) * 3];
							p[0] = 230;
							p[1] = 40;
							p[2] = 40;
						}
					}
			} else {
				img = tr::scalar(v.data(), n, size, 0, 1, 0);
			}
		} else {
			double lo = 1e300, hi = -1e300;
			for (float x : v) {
				lo = std::min(lo, (double)x);
				hi = std::max(hi, (double)x);
			}
			img = tr::scalar(v.data(), n, size, lo, std::max(hi, lo + 1e-6), 0);
		}
	}
	stamp_label(img, options);
	return to_bytes(img);
}

PackedByteArray TerrainMesh::render_surface(String kind, int width, int height, Dictionary options) {
	const int n = final_n;
	if (n < 2 || final_height.size() != size_t(n) * n)
		return PackedByteArray();
	std::vector<float> h(final_height.begin(), final_height.end());
	std::vector<float> water;
	if (river_bank.size() == h.size()) {
		water.resize(h.size());
		for (size_t i = 0; i < h.size(); i++)
			water[i] = std::clamp(-river_bank[i] / 0.75f + 0.5f, 0.0f, 1.0f);
	}
	double lo = 1e300, hi = -1e300;
	for (float v : h) {
		lo = std::min(lo, (double)v);
		hi = std::max(hi, (double)v);
	}
	tr::Field f;
	f.h = h.data();
	f.n = n;
	f.cell = final_cell;
	f.h_lo = (double)options.get("h_min", lo);
	f.h_hi = (double)options.get("h_max", hi);
	f.biome = biome_cache_n == n ? biome_cache.data() : nullptr;
	f.water = water.empty() ? nullptr : water.data();
	tr::Image img = kind == "perspectiva" ? tr::perspective(f, width, height, perspective_options(options)) : tr::relief(f, width, relief_options(options));
	stamp_label(img, options);
	return to_bytes(img);
}

PackedByteArray TerrainMesh::render_heightfield(const PackedFloat32Array &heights, int samples, double cell_size, String kind, int width, int height, Dictionary options) {
	if (samples < 2 || heights.size() != (int64_t)samples * samples)
		return PackedByteArray();
	std::vector<float> h(heights.ptr(), heights.ptr() + heights.size());
	double lo = 1e300, hi = -1e300;
	for (float v : h) {
		lo = std::min(lo, (double)v);
		hi = std::max(hi, (double)v);
	}
	tr::Image img;
	if (kind == "escalar") {
		img = tr::scalar(h.data(), samples, width, (double)options.get("min", lo), (double)options.get("max", hi), (int)options.get("palette", 0));
	} else {
		tr::Field f;
		f.h = h.data();
		f.n = samples;
		f.cell = cell_size;
		f.h_lo = (double)options.get("h_min", lo);
		f.h_hi = (double)options.get("h_max", hi);
		img = kind == "perspectiva" ? tr::perspective(f, width, height, perspective_options(options)) : tr::relief(f, width, relief_options(options));
	}
	stamp_label(img, options);
	return to_bytes(img);
}

// ---------------------------------------------------------------------------
// Erosion de un heightfield cualquiera (validacion y DEM externos)
// ---------------------------------------------------------------------------
PackedFloat32Array TerrainMesh::erode_heightfield(const PackedFloat32Array &heights, int samples, double cell_size, Dictionary cfg) {
	PackedFloat32Array out;
	if (samples < 3 || heights.size() != (int64_t)samples * samples || !std::isfinite(cell_size) || cell_size <= 0.0)
		return out;
	std::vector<double> H(heights.ptr(), heights.ptr() + heights.size());
	begin_run();
	timings = Dictionary();
	set_phase(0.0, 1.0, "Erosion");
	frames.clear();
	erosion_input = H;
	ErosionSteps steps;
	steps.fluvial = (int)cfg.get("fluvial", 3000);
	steps.thermal = (int)cfg.get("thermal", 600);
	steps.deposition = (int)cfg.get("deposition", 2000);
	steps.levels = (int)cfg.get("levels", 0);
	steps.iteration_scale = (double)cfg.get("iteration_scale", 1.0);
	steps.upsampling = (int)cfg.get("upsampling", 1);
	PackedFloat32Array hardness = cfg.get("hardness", PackedFloat32Array());
	PackedFloat32Array talus = cfg.get("talus", PackedFloat32Array());
	if (hardness.size() == heights.size() && talus.size() == heights.size()) {
		steps.hardness.assign(hardness.ptr(), hardness.ptr() + hardness.size());
		steps.talus.assign(talus.ptr(), talus.ptr() + talus.size());
	}
	std::vector<ErosionTiming> erosion_times;
	steps.timings = &erosion_times;
	steps.capture_count = capture_keep ? capture_count : 0;
	steps.capture_stage_ends = capture_stage_ends && capture_keep && capture_count > 0;
	if (steps.capture_count > 0)
		steps.frames = &frames;
	steps.progress = [&](double f, const std::string &label) { report(f, label); };
	auto begin = std::chrono::steady_clock::now();
	erode_terrain(H, samples, cell_size, steps);
	timings["erosion"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - begin).count();
	Array levels;
	for (const ErosionTiming &t : erosion_times) {
		Dictionary level;
		level["samples"] = t.samples;
		level["fluvial_seconds"] = t.fluvial_seconds;
		level["thermal_seconds"] = t.thermal_seconds;
		level["deposition_seconds"] = t.deposition_seconds;
		level["fluvial_iterations"] = t.fluvial_iterations;
		level["thermal_iterations"] = t.thermal_iterations;
		level["deposition_iterations"] = t.deposition_iterations;
		levels.push_back(level);
	}
	timings["erosion_levels"] = levels;
	out.resize((int64_t)H.size());
	for (size_t i = 0; i < H.size(); i++)
		out.set((int64_t)i, (float)H[i]);
	report(1.0, "Listo");
	return out;
}

PackedFloat32Array TerrainMesh::upsample_heightfield(const PackedFloat32Array &heights, int samples, bool bicubic) {
	PackedFloat32Array out;
	if (samples < 2 || heights.size() != (int64_t)samples * samples)
		return out;
	std::vector<double> h(heights.ptr(), heights.ptr() + heights.size());
	std::vector<double> up = upsample_heights_x2(h, samples, bicubic);
	out.resize((int64_t)up.size());
	for (size_t i = 0; i < up.size(); i++)
		out.set((int64_t)i, (float)up[i]);
	return out;
}

Array TerrainMesh::get_erosion_plan(int samples, Dictionary cfg) {
	ErosionSteps steps;
	steps.fluvial = (int)cfg.get("fluvial", (int)cfg.get("erosion_fluvial", 3000));
	steps.thermal = (int)cfg.get("thermal", (int)cfg.get("erosion_thermal", 600));
	steps.deposition = (int)cfg.get("deposition", (int)cfg.get("erosion_deposition", 2000));
	steps.levels = (int)cfg.get("levels", (int)cfg.get("erosion_levels", 0));
	steps.iteration_scale = (double)cfg.get("iteration_scale", (double)cfg.get("erosion_iteration_scale", 1.0));
	Array out;
	for (const ErosionLevelPlan &p : erosion_plan(samples, steps)) {
		Dictionary d;
		d["samples"] = p.samples;
		d["fluvial"] = p.fluvial;
		d["thermal"] = p.thermal;
		d["deposition"] = p.deposition;
		out.push_back(d);
	}
	return out;
}
