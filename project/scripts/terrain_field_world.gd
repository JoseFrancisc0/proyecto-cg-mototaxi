@tool
class_name TerrainFieldWorld
extends Node3D
## Coordinates are local to this node. Keep scale (1,1,1); use to_local/to_global for gameplay.
signal generation_progress(stage: String, fraction: float)
signal generation_finished(success: bool)

@export_range(32, 1024, 32) var grid_cells := 256
@export var cell_size := 1.0
@export var chunk_cells := 128
@export var iteration_scale := 0.03
@export_range(0, 2) var erosion_levels := 2
@export var erosion_enabled := true
@export var retarget_enabled := true
@export var roads_enabled := true
@export var stub_mode := false
@export var preserve_base := false
@export var fluvial_steps := 3000
@export var thermal_steps := 600
@export var deposition_steps := 2000
var road_config: Dictionary = {}

var field: TerrainField
var seed_value := 68
var busy := false
var _thread: Thread
var _candidate: TerrainField
var _chunks: Node3D
var _material: ShaderMaterial

func generate(seed: int) -> void:
	if busy:
		return
	if grid_cells < 32 or grid_cells > 1024 or (grid_cells & (grid_cells - 1)) != 0 or chunk_cells < 1 or grid_cells % chunk_cells != 0 or not is_finite(cell_size) or cell_size <= 0.0:
		push_error("Resolucion: potencia de dos, divisible por chunk_cells; celda positiva.")
		generation_finished.emit(false)
		return
	busy = true
	seed_value = seed
	generation_progress.emit("Calculando terreno y erosion en C++…", 0.05)
	_candidate = TerrainField.new()
	var config := {
		"levels": erosion_levels if grid_cells >= 128 else 0,
		"iteration_scale": iteration_scale,
		"erosion_enabled": erosion_enabled and not stub_mode,
		"retarget_enabled": retarget_enabled and not stub_mode,
		"roads_enabled": roads_enabled and not stub_mode,
		"retarget_iterations": 200,
		"preserve_base": preserve_base,
		"fluvial": fluvial_steps,
		"thermal": thermal_steps,
		"deposition": deposition_steps,
	}
	config.merge(road_config, true)
	_thread = Thread.new()
	var error := _thread.start(_candidate.generate.bind(seed, grid_cells, cell_size, config))
	if error != OK:
		busy = false
		generation_finished.emit(false)
		return
	while _thread.is_alive():
		await get_tree().process_frame
	var success: bool = _thread.wait_to_finish()
	if not success:
		busy = false
		generation_finished.emit(false)
		return
	field = _candidate
	_candidate = null
	generation_progress.emit("Preparando texturas y drenaje…", 0.60)
	_create_material()
	if _chunks != null:
		remove_child(_chunks)
		_chunks.queue_free()
	_chunks = Node3D.new()
	_chunks.name = "Chunks"
	add_child(_chunks)
	var chunks_per_side := grid_cells / chunk_cells
	var completed := 0
	for z in range(0, grid_cells, chunk_cells):
		for x in range(0, grid_cells, chunk_cells):
			_build_chunk(x, z)
			completed += 1
			generation_progress.emit("Creando chunks y colisiones %d/%d" % [completed, chunks_per_side * chunks_per_side], 0.60 + 0.38 * completed / float(chunks_per_side * chunks_per_side))
			await get_tree().process_frame
	busy = false
	generation_progress.emit("Mapa listo", 1.0)
	generation_finished.emit(true)

func _create_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/terrain.gdshader")
	_material.set_shader_parameter("sand_texture", preload("res://textures/sand.svg"))
	_material.set_shader_parameter("rock_texture", preload("res://textures/rock.svg"))
	_material.set_shader_parameter("grass_texture", preload("res://textures/grass.svg"))
	var side := grid_cells + 1
	var surface := Image.create_from_data(side, side, false, Image.FORMAT_RGBAF, field.get_surface_map().to_byte_array())
	var drainage := Image.create_from_data(side, side, false, Image.FORMAT_RF, field.get_drainage_map().to_byte_array())
	_material.set_shader_parameter("surface_map", ImageTexture.create_from_image(surface))
	_material.set_shader_parameter("drainage_map", ImageTexture.create_from_image(drainage))
	_material.set_shader_parameter("grid_cells", float(grid_cells))
	_material.set_shader_parameter("world_size", grid_cells * cell_size)
	_material.set_shader_parameter("river_threshold", grid_cells * 0.8)

func _build_chunk(x: int, z: int) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Chunk_%d_%d" % [x, z]
	visual.mesh = field.build_chunk(x, z, chunk_cells)
	visual.material_override = _material
	_chunks.add_child(visual)
	var body := StaticBody3D.new()
	visual.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = chunk_cells + 1
	shape.map_depth = chunk_cells + 1
	shape.map_data = field.get_chunk_heights(x, z, chunk_cells)
	collision.shape = shape
	collision.scale = Vector3(cell_size, 1.0, cell_size)
	collision.position = Vector3((x + chunk_cells * 0.5 - grid_cells * 0.5) * cell_size, 0.0, (z + chunk_cells * 0.5 - grid_cells * 0.5) * cell_size)
	body.add_child(collision)

func get_height(x: float, z: float) -> float:
	return field.get_height(x, z) if field != null else 0.0

func get_normal(x: float, z: float) -> Vector3:
	return field.get_normal(x, z) if field != null else Vector3.UP

func get_biome(x: float, z: float) -> Vector3:
	return field.get_biome(x, z) if field != null else Vector3.ZERO

func get_drainage(x: float, z: float) -> float:
	return field.get_drainage(x, z) if field != null else 0.0

func get_landmarks() -> Array:
	return field.get_landmarks() if field != null else []

func find_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	return field.find_route(a, b) if field != null else PackedVector3Array()

func get_timings() -> Dictionary:
	return field.get_timings() if field != null else {}

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
