@tool
extends MeshInstance3D
## Controlador del terreno de terrain_demo.tscn.
##
## Flujo de trabajo (botones al final del Inspector):
##   1. "Generar terreno nuevo (T0)": crea el terreno desde el ruido con la configuracion
##      actual del Inspector (regiones, rios y caminos segun sus opciones). Sin erosion.
##   2. "Aplicar erosion al terreno actual": erosiona el terreno que se esta viendo, no uno
##      nuevo. Cada clic se acumula. Los rios y caminos se recalculan encima del suelo erosionado.
##   3. "Volver a la version guardada": restaura la malla guardada en la escena y su configuracion.
##
## Al guardar la escena (Ctrl+S) se guardan juntos la malla, la configuracion con la que se
## genero (terrain_snapshot) y el suelo (ground_bytes = T0 + erosiones, sin rios ni caminos).
## Al abrir la escena, el Inspector muestra la configuracion del terreno guardado.

@export_range(1, 4096, 1) var grid_size: int = 128
@export_range(0.01, 100.0, 0.01) var cell_size: float = 1.0
@export var noise_seed: int = 1337

@export_group("Red de caminos")
## Activa o desactiva todos los caminos.
@export var preview_roads := true
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

@export_group("Rios y drenaje")
@export var hydrology_enabled := true
## No es cantidad de rios. Mayor valor = menos cauces visibles; menor = mas.
## Area de terreno (m2) que aporta agua al cauce. No define el ancho del rio.
## La vista de rios principales usa como minimo el 1% del area del mapa.
@export_range(1000, 500000, 1000) var river_catchment := 60000.0
## Radio inicial en metros; se reduce a la mitad en cada etapa de apertura.
@export_range(2, 100, 1) var breach_radius := 24.0

@export_group("Erosion (paper)")
## Pasos de la primera resolucion. Se aplican con el boton "2. Aplicar erosion".
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
## Usa rho/s0 de cada region cuando se aplica la erosion.
@export var use_regional_erosion_maps := true
@export_group("")

@export_tool_button("1. Generar terreno nuevo (T0)") var boton_generar = generate_base
@export_tool_button("2. Aplicar erosion al terreno actual") var boton_erosion = apply_erosion
@export_tool_button("Volver a la version guardada") var boton_restaurar = restore_saved_mesh

## Configuracion con la que se genero la malla visible, mas la lista de erosiones aplicadas.
@export_storage var terrain_snapshot: Dictionary = {}
## Suelo de la malla visible (T0 + erosiones), sin rios ni caminos, en float32.
@export_storage var ground_bytes: PackedByteArray = PackedByteArray()

## Parametros que definen el terreno. Se guardan con la malla y se restauran con ella.
const BASE_PARAMS := [
	"grid_size", "cell_size", "noise_seed",
	"preview_roads", "num_points", "min_point_dist", "k_neighbors", "hierarchical_roads", "town_count",
	"block_size", "highway_width", "avenue_width", "street_width", "road_width", "road_fade", "road_smooth",
	"hydrology_enabled", "river_catchment", "breach_radius",
	"three_regions", "region_patches", "transition_width", "border_warp",
	"coast_base", "coast_amplitude", "coast_frequency",
	"mountain_base", "mountain_amplitude", "mountain_frequency",
	"jungle_base", "jungle_amplitude", "jungle_frequency",
	"coast_hardness", "mountain_hardness", "jungle_hardness",
	"coast_talus", "mountain_talus", "jungle_talus", "use_regional_erosion_maps",
]
## Parametros de cada aplicacion de erosion (se registran en el historial).
const EROSION_PARAMS := ["erosion_fluvial", "erosion_thermal", "erosion_deposition", "erosion_levels"]

const TerrainStub = preload("res://scripts/terrain_world_stub.gd")
var terrain_world
var last_road_count := 0
var last_surface: TerrainMesh
var last_roads: RoadNetwork
var _saved_mesh: Mesh
var _saved_material: Material
var _saved_snapshot: Dictionary = {}
var _saved_ground: PackedByteArray = PackedByteArray()
var _saved_details: Array[Dictionary] = []
var _generated_details: Array[MeshInstance3D] = []


func _ready() -> void:
	# Abrir la escena nunca reemplaza el terreno guardado.
	_saved_mesh = mesh
	_saved_material = material_override
	_saved_snapshot = terrain_snapshot.duplicate(true)
	_saved_ground = ground_bytes.duplicate()
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail := get_node_or_null(detail_name) as MeshInstance3D
		if detail != null:
			_saved_details.append({"name": detail_name, "mesh": detail.mesh, "material": detail.material_override})
			_generated_details.append(detail)
	# El Inspector muestra la configuracion con la que se genero el terreno guardado.
	if not terrain_snapshot.is_empty():
		_apply_params(terrain_snapshot.get("params", {}))
	_configure_stub()
	if mesh == null:
		generate_base()


# ---------------------------------------------------------------------------
# Botones
# ---------------------------------------------------------------------------

## 1. Terreno nuevo desde el ruido, sin erosion.
func generate_base() -> void:
	if not _valid_grid():
		return
	var terrain := _configure_stub()
	var cfg := _build_cfg()
	var roads := _make_roads(terrain, cfg)
	var builder := TerrainMesh.new()
	var t0 := Time.get_ticks_msec()
	var generated := builder.generate_mesh(terrain, roads, grid_size, cell_size, cfg)
	if generated == null:
		push_error("No se pudo generar el terreno.")
		return
	terrain_snapshot = {"params": _current_params(), "erosions": []}
	_show(builder, roads, generated, "Terreno T0 generado", t0)


## 2. Erosiona el terreno actual. Se acumula con cada clic.
func apply_erosion() -> void:
	if terrain_snapshot.is_empty() or ground_bytes.is_empty():
		push_warning("Este terreno no tiene un suelo guardado para erosionar. Usa primero '1. Generar terreno nuevo (T0)'.")
		return
	var params: Dictionary = terrain_snapshot.get("params", {})
	var changed := _changed_params(params)
	if not changed.is_empty():
		push_warning("La erosion se aplica al terreno actual con su configuracion. Se ignoran los cambios en: %s. Para usarlos, genera un terreno nuevo." % ", ".join(changed))
	_apply_params(params)
	if not _valid_grid():
		return
	var terrain := _configure_stub()
	var cfg := _build_cfg()
	var roads := _make_roads(terrain, cfg)
	var builder := TerrainMesh.new()
	if not builder.set_ground_heights(ground_bytes.to_float32_array(), grid_size, cell_size):
		push_error("El suelo guardado no coincide con Grid Size y Cell Size.")
		return
	var t0 := Time.get_ticks_msec()
	var generated := builder.erode_ground(terrain, roads, grid_size, cell_size, cfg)
	if generated == null:
		push_error("No se pudo erosionar el terreno.")
		return
	var applied := {"regional_maps": cfg["regional_erosion_maps"]}
	for param: String in EROSION_PARAMS:
		applied[param] = get(param)
	var erosions: Array = terrain_snapshot.get("erosions", [])
	erosions.append(applied)
	terrain_snapshot["erosions"] = erosions
	_show(builder, roads, generated, "Erosion aplicada", t0)


## 3. Vuelve a la malla guardada en la escena, con su configuracion y su suelo.
func restore_saved_mesh() -> void:
	_clear_details()
	last_surface = null
	last_roads = null
	terrain_snapshot = _saved_snapshot.duplicate(true)
	ground_bytes = _saved_ground.duplicate()
	if not terrain_snapshot.is_empty():
		_apply_params(terrain_snapshot.get("params", {}))
	_configure_stub()
	if _saved_mesh != null:
		mesh = _saved_mesh
		material_override = _saved_material
		for detail: Dictionary in _saved_details:
			_add_detail(detail.name, detail.mesh, Color.WHITE)
			_generated_details[-1].material_override = detail.material


## Compatibilidad: T0 y una erosion en un solo paso.
func generate() -> void:
	generate_base()
	apply_erosion()


# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------

func _valid_grid() -> bool:
	if grid_size < 1 or grid_size > 4096 or not is_finite(cell_size) or cell_size <= 0.0:
		push_error("El terreno requiere entre 1 y 4096 celdas y un tamano de celda positivo y finito.")
		return false
	return true


func _current_params() -> Dictionary:
	var params := {}
	for param: String in BASE_PARAMS:
		params[param] = get(param)
	return params


func _apply_params(params: Dictionary) -> void:
	for param: String in params:
		if param in BASE_PARAMS:
			set(param, params[param])


## Nombres de los parametros del Inspector que difieren de 'params'.
func _changed_params(params: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	for param: String in params:
		if not param in BASE_PARAMS:
			continue
		var current = get(param)
		var saved = params[param]
		var same: bool = is_equal_approx(current, saved) if typeof(current) == TYPE_FLOAT else current == saved
		if not same:
			changed.append(param)
	return changed


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


func _build_cfg() -> Dictionary:
	return {
		"num_points": num_points if preview_roads else 0,
		"min_point_dist": min_point_dist,
		"k_neighbors": k_neighbors,
		"hierarchical_roads": hierarchical_roads,
		"town_count": town_count, "block_size": block_size,
		"highway_width": highway_width, "avenue_width": avenue_width, "street_width": street_width,
		"road_width": road_width,
		"road_fade": road_fade,
		"road_smooth": road_smooth,
		"erosion_enabled": false,
		"hydrology_enabled": hydrology_enabled, "river_catchment": river_catchment,
		"breach_radius": breach_radius,
		"regional_erosion_maps": three_regions and use_regional_erosion_maps,
		"erosion_fluvial": erosion_fluvial,
		"erosion_thermal": erosion_thermal,
		"erosion_deposition": erosion_deposition,
		"erosion_levels": erosion_levels,
	}


func _make_roads(terrain: TerrainNoise, cfg: Dictionary) -> RoadNetwork:
	var roads := RoadNetwork.new()
	# La red jerarquica se construye en C++ sobre el suelo final; la simple, aqui sobre T0.
	if not hierarchical_roads:
		roads.generate_roads(terrain, grid_size, cell_size, cfg)
	return roads


# ---------------------------------------------------------------------------
# Mostrar el resultado
# ---------------------------------------------------------------------------

func _show(builder: TerrainMesh, roads: RoadNetwork, generated: ArrayMesh, label: String, t0: int) -> void:
	mesh = generated
	ground_bytes = builder.get_ground_heights().to_byte_array()
	last_surface = builder
	last_roads = roads
	last_road_count = roads.get_road_count()
	terrain_world.set_surface(builder, roads)
	_clear_details()
	_add_detail("AguaGenerada", builder.get_water_mesh(), Color(0.08, 0.36, 0.53))
	_add_detail("PuentesGenerados", builder.get_bridge_mesh(), Color(0.20, 0.22, 0.24))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	print("%s en %.1f s (erosiones acumuladas: %d)" % [label, (Time.get_ticks_msec() - t0) / 1000.0, terrain_snapshot.get("erosions", []).size()])


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
