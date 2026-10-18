@tool
extends MeshInstance3D

@export_range(1, 4096, 1) var grid_size: int = 128
@export_range(0.01, 100.0, 0.01) var cell_size: float = 1.0
@export var noise_seed: int = 1337

@export_group("Red de caminos")
@export var num_points := 6
@export var min_point_dist := 25.0
@export var k_neighbors := 2
@export var hierarchical_roads := true
@export_range(2, 8) var town_count := 4
@export var block_size := 32.0
@export var highway_width := 14.0
@export var avenue_width := 10.0
@export var street_width := 6.0
@export var road_width := 4.0
@export var road_fade := 3.0
@export var road_smooth := 3
## Caminos sobre T0, sin necesidad de ejecutar la erosion.
@export var preview_roads := true

@export_group("Rios y drenaje")
@export var hydrology_enabled := true
## No es cantidad de rios. Mayor valor = menos cauces visibles; menor = mas.
## Area de terreno (m2) que aporta agua al cauce. No define el ancho del rio.
## La vista de rios principales usa como minimo el 1% del area del mapa.
@export_range(1000, 500000, 1000) var river_catchment := 60000.0
## Radio inicial en metros; se reduce a la mitad en cada etapa de apertura.
@export_range(2, 100, 1) var breach_radius := 24.0

@export_group("Erosion (paper)")
@export var erosion_enabled := false
@export var erosion_fluvial := 3000
@export var erosion_thermal := 600
@export var erosion_deposition := 2000
## Rondas de upsampling x2 (0 = una sola resolucion). La base es grid_size / 2^levels.
@export_range(0, 3) var erosion_levels := 0

@export_group("S11 CG-B - regiones del T0")
@export var three_regions := true
@export_range(6, 32, 1) var region_patches := 16
@export_range(0.02, 0.25, 0.01) var transition_width := 0.16
@export_range(0.0, 0.30, 0.01) var border_warp := 0.16
@export var coast_base := 4.0
@export var coast_amplitude := 4.0
@export var coast_frequency := 0.003
@export var mountain_base := 130.0
@export var mountain_amplitude := 85.0
@export var mountain_frequency := 0.008
@export var jungle_base := 28.0
@export var jungle_amplitude := 14.0
@export var jungle_frequency := 0.004
@export_group("Mapas del paper - parametros iniciales a calibrar")
@export_range(0, 1, 0.01) var coast_hardness := 0.10
@export_range(0, 1, 0.01) var mountain_hardness := 0.65
@export_range(0, 1, 0.01) var jungle_hardness := 0.35
@export var coast_talus := 0.25
@export var mountain_talus := 1.15
@export var jungle_talus := 0.60
## Publishes rho/s0 to the existing CG-A erosion when regenerating with erosion.
@export var use_regional_erosion_maps := true

@export_tool_button("Vista previa: regiones, rios y caminos") var generar_t0 = generate_base
@export_tool_button("Regenerar con erosion CG-A") var regenerar = generate
@export_tool_button("Volver a la malla guardada") var restaurar = restore_saved_mesh
const TerrainStub = preload("res://scripts/terrain_world_stub.gd")
var terrain_world
var _saved_mesh: Mesh
var _saved_material: Material
var last_road_count := 0
var last_surface: TerrainMesh
var last_roads: RoadNetwork
var _generated_details: Array[MeshInstance3D] = []
var _saved_details: Array[Dictionary] = []

func _region_config() -> Dictionary:
	return {
		"enabled": three_regions, "extent": grid_size * cell_size, "region_patches": region_patches,
		"transition_width": transition_width, "border_warp": border_warp,
		"coast_base": coast_base, "coast_amplitude": coast_amplitude, "coast_frequency": coast_frequency,
		"mountain_base": mountain_base, "mountain_amplitude": mountain_amplitude, "mountain_frequency": mountain_frequency,
		"jungle_base": jungle_base, "jungle_amplitude": jungle_amplitude, "jungle_frequency": jungle_frequency,
		"coast_hardness": coast_hardness, "mountain_hardness": mountain_hardness, "jungle_hardness": jungle_hardness,
		"coast_talus": coast_talus, "mountain_talus": mountain_talus, "jungle_talus": jungle_talus,
	}

func generate_base() -> void:
	_generate(false)


func _ready() -> void:
	# Never replace the saved terrain merely by opening or running the scene.
	# S11 CG-B is reviewed explicitly using the T0 button in the inspector.
	_saved_mesh = mesh
	_saved_material = material_override
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail := get_node_or_null(detail_name) as MeshInstance3D
		if detail != null:
			_saved_details.append({"name": detail_name, "mesh": detail.mesh, "material": detail.material_override})
			_generated_details.append(detail)
	_configure_stub()
	if mesh == null:
		generate_base()

func restore_saved_mesh() -> void:
	_clear_details()
	last_surface = null
	last_roads = null
	if terrain_world != null: terrain_world.clear_surface()
	if _saved_mesh != null:
		mesh = _saved_mesh
		material_override = _saved_material
		for detail: Dictionary in _saved_details:
			_add_detail(detail.name, detail.mesh, Color.WHITE)
			_generated_details[-1].material_override = detail.material

func _configure_stub() -> TerrainNoise:
	var terrain := TerrainNoise.new()
	terrain.set_seed(noise_seed)
	terrain.configure_regions(_region_config())
	if terrain_world == null:
		terrain_world = TerrainStub.new()
		terrain_world.name = "TerrainWorld"
		add_child(terrain_world)
	terrain_world.configure(terrain, grid_size * cell_size)
	return terrain

func generate() -> void:
	_generate(erosion_enabled)

func _generate(apply_erosion: bool) -> void:
	if grid_size < 1 or grid_size > 4096 or not is_finite(cell_size) or cell_size <= 0.0:
		push_error("El terreno requiere entre 1 y 4096 celdas y un tamano de celda positivo y finito.")
		return
	# 1. Configurar ruido y biomas
	var terrain := _configure_stub()

	# 2. Generar caminos sobre el terreno
	var cfg := {
		"num_points": num_points if apply_erosion or preview_roads else 0,
		"min_point_dist": min_point_dist,
		"k_neighbors": k_neighbors,
		"hierarchical_roads": hierarchical_roads,
		"town_count": town_count, "block_size": block_size,
		"highway_width": highway_width, "avenue_width": avenue_width, "street_width": street_width,
		"road_width": road_width,
		"road_fade": road_fade,
		"road_smooth": road_smooth,
		"erosion_enabled": apply_erosion,
		"hydrology_enabled": hydrology_enabled, "river_catchment": river_catchment,
		"breach_radius": breach_radius,
		"regional_erosion_maps": three_regions and use_regional_erosion_maps,
		"erosion_fluvial": erosion_fluvial,
		"erosion_thermal": erosion_thermal,
		"erosion_deposition": erosion_deposition,
		"erosion_levels": erosion_levels,
	}
	var roads := RoadNetwork.new()
	if not hierarchical_roads:
		roads.generate_roads(terrain, grid_size, cell_size, cfg)


	# 3. Ensamblar la geometría final
	var mesh_builder := TerrainMesh.new()
	var t0 := Time.get_ticks_msec()
	var generated := mesh_builder.generate_mesh(terrain, roads, grid_size, cell_size, cfg)
	if generated == null:
		push_error("No se pudo generar el terreno.")
		return
	mesh = generated
	last_surface = mesh_builder
	last_roads = roads
	last_road_count = roads.get_road_count()
	terrain_world.set_surface(mesh_builder, roads)
	_clear_details()
	_add_detail("AguaGenerada", mesh_builder.get_water_mesh(), Color(0.08, 0.36, 0.53))
	_add_detail("PuentesGenerados", mesh_builder.get_bridge_mesh(), Color(0.20, 0.22, 0.24))
	print("Terreno generado en %.1f s (erosion: %s, niveles: %d)" % [(Time.get_ticks_msec() - t0) / 1000.0, apply_erosion, erosion_levels])

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	material_override = mat

func _clear_details() -> void:
	for detail in _generated_details:
		if is_instance_valid(detail):
			remove_child(detail)
			detail.queue_free()
	_generated_details.clear()

func _add_detail(detail_name: String, detail_mesh: ArrayMesh, color: Color) -> void:
	if detail_mesh == null or detail_mesh.get_surface_count() == 0:
		return
	var detail := MeshInstance3D.new()
	detail.name = detail_name
	detail.mesh = detail_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 0.35 if detail_name == "AguaGenerada" else 0.9
	detail.material_override = material
	add_child(detail)
	if owner != null: detail.owner = owner
	_generated_details.append(detail)
