#ifndef TERRAIN_MESH_H
#define TERRAIN_MESH_H

#include "drainage.h"
#include "erosion.h"
#include "road_network.h"
#include "terrain_noise.h"
#include <atomic>
#include <chrono>
#include <map>
#include <mutex>
#include <string>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class TerrainMesh : public RefCounted {
	GDCLASS(TerrainMesh, RefCounted)

private:
	DrainageField drainage;
	// Suelo actual: T0 + erosiones aplicadas, ANTES de rios y caminos.
	std::vector<double> ground_height;
	int ground_n = 0;
	double ground_cell = 1;
	std::vector<double> final_height;
	Ref<ArrayMesh> water_mesh, bridge_mesh;
	int final_n = 0;
	double final_cell = 1;

	// --- Avance (S13: pantalla de carga). Lo escribe el hilo que genera y lo lee el principal.
	std::atomic<double> progress_value{ 0.0 };
	mutable std::mutex progress_mutex;
	std::string progress_stage = "";
	double phase_start = 0.0, phase_span = 1.0;
	std::chrono::steady_clock::time_point run_start = std::chrono::steady_clock::now();
	std::vector<uint8_t> preview_rgb;
	int preview_size = 0;
	int preview_serial = 0;

	// --- Capturas de la evolucion (S14).
	int capture_count = 0;
	bool capture_stage_ends = false;
	bool capture_keep = true; // guardar las fotos (si no, solo la vista previa)
	int capture_preview_size = 0; // 0 = sin vista previa
	std::vector<ErosionFrame> frames;
	std::vector<double> erosion_input; // T0 de la ultima erosion (para volumenes)

	// Pesos de region por muestra (costa, sierra, selva), calculados una vez por terreno.
	std::vector<float> biome_cache;
	int biome_cache_n = 0;
	double biome_cache_cell = 0.0;
	const void *biome_cache_owner = nullptr;

	// Capas para las figuras de cada etapa del pipeline (S14), a resolucion n x n.
	std::map<std::string, std::vector<float>> layers;
	int layers_n = 0;
	Dictionary timings;
	Dictionary retarget_info;

	// Rios en el shader (S13/S14): distancia con signo a la orilla, ancho y direccion.
	std::vector<uint8_t> river_rgba;
	int river_size = 0;
	double river_texel = 1.0;
	double river_threshold_used = 0.0;
	std::vector<float> river_bank; // distancia con signo a la orilla en cada muestra (m)
	std::vector<float> river_level; // nivel del agua del rio mas cercano en cada muestra (m)
	std::vector<float> road_weight; // mascara de caminos por muestra (0..1)

	// Atributos por vertice de la ultima superficie (solo si cfg.keep_arrays): chunks.
	bool keep_arrays = false;
	PackedVector3Array kept_vertices, kept_normals;
	PackedColorArray kept_colors;
	PackedVector2Array kept_uvs;
	PackedFloat32Array kept_regions, kept_ao;

	void begin_run();
	void set_phase(double start, double span, const std::string &stage);
	void report(double fraction_in_phase, const std::string &stage);
	void update_preview(const std::vector<float> &h, int n, double cell, double h_lo, double h_hi);
	const std::vector<float> &biome_weights(Ref<TerrainNoise> terrain, int n, double cell);
	void capture_range(double &lo, double &hi) const;

protected:
	static void _bind_methods();

public:
	TerrainMesh();
	Ref<ArrayMesh> get_water_mesh() const { return water_mesh; }
	Ref<ArrayMesh> get_bridge_mesh() const { return bridge_mesh; }
	double get_height(double x, double z) const;
	double get_drainage(double x, double z) const;
	Dictionary get_hydrology_data() const;

	// T0 desde el ruido (+ erosion si cfg.erosion_enabled) y superficie final.
	Ref<ArrayMesh> generate_mesh(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	// Erosiona el suelo actual (no lo regenera) y reconstruye rios y caminos encima.
	Ref<ArrayMesh> erode_ground(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	// Reconstruye rios, caminos y malla sobre el suelo actual, sin erosionar.
	Ref<ArrayMesh> rebuild_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	PackedFloat32Array get_ground_heights() const;
	// Alturas de la malla final (con rios y caminos). El shader las usa para el ray tracing de sombras.
	PackedFloat32Array get_surface_heights() const;
	bool set_ground_heights(const PackedFloat32Array &heights, int grid_size, double cell_size);

	// --- Erosion de cualquier heightfield (validacion contra el repo oficial, DEM externos).
	PackedFloat32Array erode_heightfield(const PackedFloat32Array &heights, int samples, double cell_size, Dictionary cfg);
	static PackedFloat32Array upsample_heightfield(const PackedFloat32Array &heights, int samples, bool bicubic);
	static Array get_erosion_plan(int samples, Dictionary cfg);

	// --- Avance (S13).
	Dictionary get_progress() const;
	Dictionary get_preview() const;

	// --- Capturas (S14).
	void set_capture_options(Dictionary options);
	int get_capture_count() const { return (int)frames.size(); }
	Dictionary get_capture_info(int index) const;
	PackedFloat32Array get_capture_heights(int index) const;
	PackedByteArray render_capture(int index, String kind, int width, int height, Dictionary options) const;
	Ref<ArrayMesh> build_capture_mesh(int index, Ref<TerrainNoise> terrain, Dictionary options);
	void clear_captures();
	Dictionary get_capture_stats(int index) const;

	// --- Figuras de etapas y tiempos (S14).
	Dictionary get_timings() const { return timings; }
	Dictionary get_retarget_info() const { return retarget_info; }
	PackedStringArray get_layer_names() const;
	PackedByteArray render_layer(String name, int size, Dictionary options) const;
	PackedByteArray render_surface(String kind, int width, int height, Dictionary options);

	// --- Rios en el shader (S13/S14).
	Dictionary get_river_map() const;

	// --- Vegetacion con MultiMesh (S14).
	Dictionary scatter_vegetation(Ref<TerrainNoise> terrain, Array species, Dictionary options);

	// --- Landmarks por tipo: picos, confluencias, costa (S13 CG-B).
	Array find_landmark_features(Ref<TerrainNoise> terrain, Dictionary options);

	// --- Chunks de 128 x 128 con LOD (S12 CG-B).
	Array build_chunks(int chunk_cells, int lod_levels, double skirt_depth);
	void release_arrays();

	// Software render de un heightfield cualquiera (pruebas y validacion).
	static PackedByteArray render_heightfield(const PackedFloat32Array &heights, int samples, double cell_size, String kind, int width, int height, Dictionary options);

private:
	void erode_heights(std::vector<double> &H, Ref<TerrainNoise> terrain, int n, double cell_size, const Dictionary &road_cfg);
	Ref<ArrayMesh> build_surface(Ref<TerrainNoise> terrain, Ref<RoadNetwork> roads, int grid_size, double cell_size, Dictionary road_cfg);
	void build_river_map(int n, double cell, double threshold, const Dictionary &cfg);
};

} //namespace godot

#endif // TERRAIN_MESH_H
