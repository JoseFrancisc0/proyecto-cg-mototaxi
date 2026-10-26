class_name TerrainWorld
extends Node3D
## Fachada única del terreno para el juego (contrato CG <-> Juego de la semana 10).
##
## Ya no genera su propio terreno: usa el generador de CG de la rama main
## (chunk_mesh.gd + TerrainMesh: regiones costa/sierra/selva, erosión del paper,
## drenaje con ríos y red vial jerárquica), con las mismas texturas e iluminación
## de terrain_demo.tscn. Encima añade lo que necesita el juego: colisión, consultas
## de altura, landmarks sobre las vías y un mapa de transitabilidad para la mototaxi.
##
## S12-S14 (CG): el mapa se parte en chunks de 128 x 128 celdas con LOD y una colisión
## HeightMapShape3D por chunk; landmarks por tipo (picos, confluencias, costa) con
## carteles; vegetación con MultiMesh; y generate_async() para la pantalla de carga
## (semilla -> mapa completo sin congelar la ventana).
##
## Convenciones: metros, origen en el centro del mapa, Y hacia arriba. El nodo debe
## quedarse en el origen sin rotar ni escalar (las consultas son en coordenadas globales).

signal generated
## Avance de generate_async(): etapa (texto) y fracción de 0 a 1.
signal progress(stage: String, fraction: float)

const Generator = preload("res://scripts/chunk_mesh.gd")

@export var grid_size: int = 512
@export var cell_size: float = 1.5
@export var world_seed: int = 67
@export var generate_on_ready := true
@export var build_collision := true

@export_group("Escenario del editor")
## Usa el terreno guardado en editor_scene (el que se arma y erosiona en el editor con los
## botones de chunk_mesh.gd) en lugar de generar uno con los valores de este nodo.
## Se copian todos sus parámetros (regiones costa/sierra/selva, semilla, tamaño, ríos,
## nieve, sol) y su suelo ya erosionado; solo se rehacen las vías con road_max_grade.
## Si la escena no tiene terreno guardado, se genera uno como antes.
@export var use_editor_scene := false
@export_file("*.tscn") var editor_scene := "res://terrain_demo.tscn"

@export_group("Erosión (paper)")
@export var erosion_enabled := true
## Fracción de TODOS los pasos de CG (todas las resoluciones). 1.0 = receta completa del
## paper; 0.1 = vista rápida. Las vías quedan limitadas en pendiente en ambos casos.
@export_range(0.01, 1.0, 0.01) var erosion_scale := 0.1
@export var erosion_fluvial := 3000
@export var erosion_thermal := 600
@export var erosion_deposition := 2000
@export_range(0, 3) var erosion_levels := 2
## Retargeting por difusión (paper 5.1): devuelve picos y crestas a su altura de T0.
@export var retarget_enabled := true

@export_group("Generador CG")
## Propiedades extra de chunk_mesh.gd (por ejemplo {"mountain_amplitude": 85.0}).
## Sirve para probar los mismos valores que terrain_demo.tscn sin tocar este script.
@export var generator_overrides: Dictionary = {}

@export_group("Chunks (S12)")
## Parte la malla en chunks: Godot dibuja solo los que ve la cámara y usa menos detalle lejos.
@export var chunks_enabled := true
@export_range(16, 512, 16) var chunk_cells := 128
## Niveles de detalle por chunk (paso 2, 4, ...). 0 = sin LOD.
@export_range(0, 4) var chunk_lod_levels := 2
## Faldón vertical (m) bajo el borde de cada chunk: tapa las grietas entre LOD distintos.
@export var chunk_skirt_depth := 6.0

@export_group("Mundo (S13-S14)")
## Vegetación con MultiMesh (árboles, cactus, ichu...). Modelos provisionales.
@export var vegetation_enabled := true
@export_range(0.0, 3.0, 0.05) var vegetation_density := 1.0
## Landmarks por tipo además de pueblos y vías: miradores de picos, confluencias y caletas.
@export var typed_landmarks := true
## Distancia máxima (m) del landmark tipado a la vía donde se pone el cartel.
@export var landmark_snap_distance := 160.0
## Carteles 3D con el nombre de cada landmark tipado.
@export var landmark_signs := true

@export_group("Transitabilidad")
## Pendiente máxima (tan del ángulo) que la mototaxi puede subir con margen.
## Se mide en tests/test_drivability.gd.
@export var max_drive_slope := 0.45
## Pendiente máxima de las vías generadas (más baja que max_drive_slope para que
## las vías sean siempre manejables, incluso arrancando en plena subida).
@export var road_max_grade := 0.25
## Separación de los landmarks a lo largo de las vías (m).
@export var landmark_spacing := 60.0

var generator: Generator
var _surface: TerrainMesh
var _heights := PackedFloat32Array()
var _n := 0
var _half := 0.0
var _landmarks: Array[Dictionary] = []
var _features: Array = []
var _reach := PackedInt32Array()   # Componente transitable de cada muestra (-1 = no transitable).
var _body: StaticBody3D
var _bridge_body: StaticBody3D
var _chunk_root: Node3D
var _sign_root: Node3D
var _generated_ok := false
var _chunk_collision := false
var _editor_t0 := 0
## Tamaño de la vista previa del terreno en la pantalla de carga (0 = sin vista previa).
var preview_size := 0


func _ready() -> void:
	if generate_on_ready:
		generate(world_seed)


func is_generated() -> bool:
	return _generated_ok


## Construye el mapa completo (bloquea hasta terminar). Con new_seed < 0 usa world_seed.
func generate(new_seed: int = -1) -> void:
	if not _prepare_generator(new_seed):
		return
	if use_editor_scene:
		if _copy_editor_scene() and generator.rebuild_saved_ground():
			_report_editor_scene()
			_finish_generate()
			return
		_reset_generator()
	_configure_generator()
	add_child(generator)
	var ok: bool = generator.generate_full() if erosion_enabled else _generate_base_sync()
	if ok:
		_finish_generate()


## Igual que generate(), pero el cálculo pesado corre en otro hilo. Emite progress(etapa, fracción).
## Es una corrutina: await world.generate_async(semilla).
func generate_async(new_seed: int = -1) -> bool:
	if not _prepare_generator(new_seed):
		return false
	generator.preview_size = preview_size
	generator.job_progress.connect(_on_job_progress)
	if use_editor_scene:
		if _copy_editor_scene():
			var rebuilt: bool = await generator.rebuild_saved_ground_async()
			if rebuilt:
				_report_editor_scene()
				await _finish_generate_async()
				return true
		_reset_generator()
		generator.preview_size = preview_size
		generator.job_progress.connect(_on_job_progress)
	_configure_generator()
	add_child(generator)
	var ok := false
	if erosion_enabled:
		ok = await generator.generate_full_async()
	else:
		ok = await generator.generate_base_async()
	if not ok:
		return false
	await _finish_generate_async()
	return true


func _on_job_progress(stage: String, fraction: float) -> void:
	# El cálculo de C++ es el 85% de la carga; el resto son chunks, colisión, landmarks y vegetación.
	progress.emit(stage, fraction * 0.85)


func _prepare_generator(new_seed: int) -> bool:
	if new_seed >= 0:
		world_seed = new_seed
	_generated_ok = false
	_n = grid_size + 1
	_half = grid_size * cell_size * 0.5
	_reset_generator()
	return true


func _reset_generator() -> void:
	_chunk_root = null  # era hijo del generador anterior
	_chunk_collision = false
	if generator != null:
		if generator.is_inside_tree():
			remove_child(generator)
		generator.free()
	generator = Generator.new()
	generator.name = "Terrain"
	generator.auto_generate = false
	generator.keep_surface_arrays = chunks_enabled
	generator.capture_enabled = false
	generator.vegetation_enabled = false  # la crea TerrainWorld al final, con su densidad


func _configure_generator() -> void:
	generator.grid_size = grid_size
	generator.cell_size = cell_size
	generator.noise_seed = world_seed
	generator.erosion_fluvial = erosion_fluvial
	generator.erosion_thermal = erosion_thermal
	generator.erosion_deposition = erosion_deposition
	generator.erosion_levels = erosion_levels
	generator.erosion_iteration_scale = erosion_scale
	generator.retarget_enabled = retarget_enabled
	generator.road_max_grade = road_max_grade
	for key in generator_overrides:
		generator.set(key, generator_overrides[key])


func _generate_base_sync() -> bool:
	generator.generate_base()
	return generator.last_surface != null


## Pasos comunes tras crear la superficie: alturas, colisión, landmarks y transitabilidad.
func _finish_generate() -> void:
	if not _collect_surface():
		return
	if chunks_enabled:
		_build_chunks()
	if build_collision:
		_build_collision()
	_add_bridge_decks()
	_build_reachability()
	_build_landmarks()
	_build_vegetation()
	_generated_ok = true
	generated.emit()


## Igual que _finish_generate, informando el avance y dejando respirar a la ventana.
func _finish_generate_async() -> void:
	if not _collect_surface():
		return
	var steps := [
		["Chunks con LOD", _build_chunks if chunks_enabled else Callable()],
		["Colisión del terreno", _build_collision if build_collision else Callable()],
		["Puentes", _add_bridge_decks],
		["Zonas transitables", _build_reachability],
		["Landmarks (picos, confluencias, costa)", _build_landmarks],
		["Vegetación (MultiMesh)", _build_vegetation],
	]
	for k in steps.size():
		progress.emit(steps[k][0], 0.85 + 0.15 * k / steps.size())
		await get_tree().process_frame
		var step: Callable = steps[k][1]
		if step.is_valid():
			step.call()
	_generated_ok = true
	progress.emit("Listo", 1.0)
	generated.emit()


func _collect_surface() -> bool:
	_surface = generator.last_surface
	_heights = _surface.get_surface_heights() if _surface else PackedFloat32Array()
	if _heights.size() != _n * _n:
		push_error("TerrainWorld: el generador no devolvió alturas (%d de %d)" % [_heights.size(), _n * _n])
		return false
	return true


## Copia el nodo Terrain de editor_scene (sus propiedades, sin la malla) en el generador.
## Devuelve false si la escena no tiene terreno guardado. Después hay que reconstruir la
## superficie sobre su suelo (rebuild_saved_ground o su versión en hilo).
func _copy_editor_scene() -> bool:
	_editor_t0 = Time.get_ticks_msec()
	var scene := load(editor_scene) as PackedScene
	if scene == null:
		push_warning("TerrainWorld: no se pudo cargar %s; se genera un terreno nuevo." % editor_scene)
		return false
	var state := scene.get_state()
	var props := {}
	for i in state.get_node_count():
		if state.get_node_name(i) != "Terrain":
			continue
		for p in state.get_node_property_count(i):
			props[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
		break
	var ground: PackedByteArray = props.get("ground_bytes", PackedByteArray())
	if ground.is_empty() or props.get("terrain_snapshot", {}).is_empty():
		push_warning("TerrainWorld: %s no tiene terreno guardado; se genera uno nuevo." % editor_scene)
		return false
	for key in props:
		if key not in ["script", "mesh", "material_override", "transform"]:
			generator.set(key, props[key])
	generator.auto_generate = false
	generator.keep_surface_arrays = chunks_enabled
	generator.capture_enabled = false
	generator.vegetation_enabled = false
	add_child(generator)  # _ready aplica los parámetros guardados en terrain_snapshot.
	# Opciones del juego encima de las del editor.
	generator.road_max_grade = road_max_grade
	for key in generator_overrides:
		generator.set(key, generator_overrides[key])
	grid_size = generator.grid_size
	cell_size = generator.cell_size
	world_seed = generator.noise_seed
	_n = grid_size + 1
	_half = grid_size * cell_size * 0.5
	return true


func _report_editor_scene() -> void:
	print("TerrainWorld: escenario de %s (%d celdas x %.1f m = %.0f m, semilla %d) en %.1f s" % [
		editor_scene, grid_size, cell_size, get_world_size(), world_seed, (Time.get_ticks_msec() - _editor_t0) / 1000.0])


# --- API del contrato ---------------------------------------------------------

## Altura del suelo en (x, z), sobre los mismos triángulos que la colisión (y los puentes).
func get_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := clampf((x + _half) / cell_size, 0.0, grid_size)
	var fz := clampf((z + _half) / cell_size, 0.0, grid_size)
	var ix := mini(int(fx), grid_size - 1)
	var iz := mini(int(fz), grid_size - 1)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _heights[iz * _n + ix]
	var h10 := _heights[iz * _n + ix + 1]
	var h01 := _heights[(iz + 1) * _n + ix]
	var h11 := _heights[(iz + 1) * _n + ix + 1]
	# Misma diagonal (10)-(01) que HeightMapShape3D y la malla.
	if tx + tz <= 1.0:
		return h00 + tx * (h10 - h00) + tz * (h01 - h00)
	return h11 + (1.0 - tx) * (h01 - h11) + (1.0 - tz) * (h10 - h11)


func get_normal(x: float, z: float) -> Vector3:
	var d := cell_size
	var dhdx := (get_height(x + d, z) - get_height(x - d, z)) / (2.0 * d)
	var dhdz := (get_height(x, z + d) - get_height(x, z - d)) / (2.0 * d)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()


## Pesos (costa, sierra, selva).
func get_biome(x: float, z: float) -> Vector3:
	return generator.terrain_world.get_biome(x, z) if generator else Vector3(0, 0, 1)


## Área de drenaje en m² (alto = río).
func get_drainage(x: float, z: float) -> float:
	return _surface.get_drainage(x, z) if _surface else 0.0


## Puntos de recogida y destino: [{ "id", "position", "type" }], todos sobre vías.
## "reach" indica la zona transitable a la que pertenece (ver is_reachable()).
## Tipos: "pueblo", "via" y, con typed_landmarks, "pico", "confluencia" y "costa"
## (estos traen además "label" y "feature": el punto del pico/confluencia/costa).
func get_landmarks() -> Array[Dictionary]:
	return _landmarks


## Rasgos del terreno detectados (antes de pegarlos a las vías).
func get_terrain_features() -> Array:
	return _features


## Ruta recomendada de a hacia b: A* del equipo (penaliza pendiente y agua) que además
## evita los pasos más empinados que max_drive_slope, para que la mototaxi pueda seguirla.
func find_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	if generator == null or generator.last_roads == null or _heights.is_empty():
		return PackedVector3Array()
	var path: PackedVector3Array = generator.last_roads.find_drivable_path(
		_heights, _n, cell_size, Vector2(a.x, a.z), Vector2(b.x, b.z), max_drive_slope)
	for i in path.size():
		var p := path[i]
		p.y = get_height(p.x, p.z)
		path[i] = p
	return path


# --- Transitabilidad ----------------------------------------------------------

## Zona transitable del punto (x, z): mismo número = se puede ir de uno a otro
## sin pasar por pendientes mayores que max_drive_slope. -1 = punto demasiado empinado.
func get_reach_id(x: float, z: float) -> int:
	if _reach.is_empty():
		return -1
	var ix := clampi(roundi((x + _half) / cell_size), 0, grid_size)
	var iz := clampi(roundi((z + _half) / cell_size), 0, grid_size)
	var r := _reach[iz * _n + ix]
	if r >= 0:
		return r
	# Justo sobre un borde empinado: se acepta la zona de un vecino.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var jx := clampi(ix + d.x, 0, grid_size)
		var jz := clampi(iz + d.y, 0, grid_size)
		if _reach[jz * _n + jx] >= 0:
			return _reach[jz * _n + jx]
	return -1


## true si la mototaxi puede manejar de a hasta b según el mapa de pendientes.
func is_reachable(a: Vector3, b: Vector3) -> bool:
	var ra := get_reach_id(a.x, a.z)
	return ra >= 0 and ra == get_reach_id(b.x, b.z)


## Pendiente (tan) en el punto, la mayor hacia sus 4 vecinos.
func get_slope(x: float, z: float) -> float:
	var n := get_normal(x, z)
	return sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(n.y, 0.001)


# --- Utilidades ---------------------------------------------------------------

func get_world_size() -> float:
	return grid_size * cell_size


func is_inside(x: float, z: float) -> bool:
	return absf(x) <= _half and absf(z) <= _half


## Polilíneas de las vías generadas: [{ "kind", "width", "path": PackedVector3Array }].
func get_roads() -> Array:
	return generator.last_roads.get_road_metadata() if generator and generator.last_roads else []


## Cantidad de chunks visuales (0 si la malla no se partió).
func get_chunk_count() -> int:
	return _chunk_root.get_child_count() if _chunk_root != null else 0


static func route_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# --- Interno ------------------------------------------------------------------

## Chunks de chunk_cells x chunk_cells con LOD y faldones (TerrainMesh.build_chunks).
## Comparten el material del terreno; la malla completa se libera.
func _build_chunks() -> void:
	if _chunk_root != null:
		_chunk_root.queue_free()
		_chunk_root = null
	var chunks: Array = _surface.build_chunks(chunk_cells, chunk_lod_levels, chunk_skirt_depth)
	_surface.release_arrays()
	if chunks.is_empty():
		return
	_chunk_root = Node3D.new()
	_chunk_root.name = "Chunks"
	generator.add_child(_chunk_root)
	for k in chunks.size():
		var c: Dictionary = chunks[k]
		var mi := MeshInstance3D.new()
		var origin: Vector2i = c["origin"]
		mi.name = "Chunk_%d_%d" % [origin.x / chunk_cells, origin.y / chunk_cells]
		mi.mesh = c["mesh"]
		mi.material_override = generator.material_override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk_root.add_child(mi)
	# La malla entera ya no hace falta: los chunks la reemplazan (menos memoria de video).
	generator.mesh = null
	if build_collision:
		_build_chunk_collision(chunks)


## Una HeightMapShape3D por chunk (bordes compartidos con el vecino).
func _build_chunk_collision(chunks: Array) -> void:
	if _body != null:
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	add_child(_body)
	for c: Dictionary in chunks:
		var samples: Vector2i = c["samples"]
		var heights: PackedFloat32Array = c["heights"]
		var hms := HeightMapShape3D.new()
		hms.map_width = samples.x
		hms.map_depth = samples.y
		if not is_equal_approx(cell_size, 1.0):
			for i in heights.size():
				heights[i] = heights[i] / cell_size
		hms.map_data = heights
		var cs := CollisionShape3D.new()
		cs.shape = hms
		cs.scale = Vector3.ONE * cell_size
		cs.position = c["center"]
		_body.add_child(cs)
	_chunk_collision = true


func _build_collision() -> void:
	if not _chunk_collision:
		# Una sola HeightMapShape3D para todo el mapa (sin chunks).
		if _body != null:
			_body.queue_free()
		_body = StaticBody3D.new()
		_body.name = "TerrainBody"
		add_child(_body)
		var shape := CollisionShape3D.new()
		_body.add_child(shape)
		# HeightMapShape3D usa espaciado 1 centrado en el origen: se escala de forma
		# uniforme por cell_size y se dividen las alturas para compensar en Y.
		var hms := HeightMapShape3D.new()
		hms.map_width = _n
		hms.map_depth = _n
		var scaled := _heights
		if not is_equal_approx(cell_size, 1.0):
			scaled = PackedFloat32Array()
			scaled.resize(_heights.size())
			for i in _heights.size():
				scaled[i] = _heights[i] / cell_size
		hms.map_data = scaled
		shape.shape = hms
		shape.scale = Vector3.ONE * cell_size

	# Los puentes son una malla aparte: sin colisión la mototaxi caería al cauce.
	if _bridge_body != null:
		_bridge_body.queue_free()
		_bridge_body = null
	var bridges := _surface.get_bridge_mesh()
	if bridges != null and bridges.get_surface_count() > 0:
		_bridge_body = StaticBody3D.new()
		_bridge_body.name = "BridgeBody"
		var bs := CollisionShape3D.new()
		bs.shape = bridges.create_trimesh_shape()
		_bridge_body.add_child(bs)
		add_child(_bridge_body)


## Los puentes son una malla aparte, sobre el cauce. Se "pintan" en la copia de alturas
## del juego para que get_height y la transitabilidad los vean como suelo (la colisión
## de la grilla no cambia: el puente tiene su propia colisión).
func _add_bridge_decks() -> void:
	var bridges := _surface.get_bridge_mesh()
	if bridges == null or bridges.get_surface_count() == 0:
		return
	_heights = _heights.duplicate()
	for si in bridges.get_surface_count():
		var arrays := bridges.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var tri_count: int = (idx.size() if idx != null else v.size()) / 3
		for t in tri_count:
			var a := v[idx[t * 3] if idx != null else t * 3]
			var b := v[idx[t * 3 + 1] if idx != null else t * 3 + 1]
			var c := v[idx[t * 3 + 2] if idx != null else t * 3 + 2]
			var x0 := clampi(floori((minf(a.x, minf(b.x, c.x)) + _half) / cell_size), 0, grid_size)
			var x1 := clampi(ceili((maxf(a.x, maxf(b.x, c.x)) + _half) / cell_size), 0, grid_size)
			var z0 := clampi(floori((minf(a.z, minf(b.z, c.z)) + _half) / cell_size), 0, grid_size)
			var z1 := clampi(ceili((maxf(a.z, maxf(b.z, c.z)) + _half) / cell_size), 0, grid_size)
			var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(den) < 1e-9:
				continue
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var px := ix * cell_size - _half
					var pz := iz * cell_size - _half
					var w0 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
					var w1 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
					var w2 := 1.0 - w0 - w1
					if w0 < -0.01 or w1 < -0.01 or w2 < -0.01:
						continue
					var y := w0 * a.y + w1 * b.y + w2 * c.y
					var i := iz * _n + ix
					if y > _heights[i]:
						_heights[i] = y


## Etiqueta las zonas conectadas por pendientes manejables (BFS sobre la grilla).
func _build_reachability() -> void:
	var count := _n * _n
	_reach = PackedInt32Array()
	_reach.resize(count)
	_reach.fill(-2)  # -2 = sin visitar
	var max_dh := max_drive_slope * cell_size
	var max_dh_diag := max_drive_slope * cell_size * 1.41421356
	var label := 0
	var queue := PackedInt32Array()
	queue.resize(count)
	for start in count:
		if _reach[start] != -2:
			continue
		_reach[start] = label
		var head := 0
		var tail := 0
		queue[tail] = start
		tail += 1
		while head < tail:
			var cur := queue[head]
			head += 1
			var cx := cur % _n
			var cz := cur / _n
			var hc := _heights[cur]
			for dz in range(-1, 2):
				var nz := cz + dz
				if nz < 0 or nz >= _n:
					continue
				for dx in range(-1, 2):
					var nx := cx + dx
					if (dx == 0 and dz == 0) or nx < 0 or nx >= _n:
						continue
					var ni := nz * _n + nx
					if _reach[ni] != -2:
						continue
					var lim := max_dh_diag if dx != 0 and dz != 0 else max_dh
					if absf(_heights[ni] - hc) <= lim:
						_reach[ni] = label
						queue[tail] = ni
						tail += 1
		label += 1


## Landmarks = centros de poblado + puntos a lo largo de las vías, separados entre sí.
## Con typed_landmarks se agregan primero los rasgos del terreno (S13 CG-B): picos,
## confluencias de ríos y costa, cada uno en el punto de vía más cercano (miradores).
func _build_landmarks() -> void:
	_landmarks.clear()
	_features = []
	var points: Array[Vector3] = []
	var types: Array[String] = []
	var extra: Array[Dictionary] = []
	var roads := get_roads()
	if typed_landmarks and _surface != null and generator.last_terrain != null:
		_features = _surface.find_landmark_features(generator.last_terrain, {"min_spacing": maxf(landmark_spacing * 2.5, 120.0)})
		for f: Dictionary in _features:
			var spot := _nearest_road_point(f["position"], roads)
			if spot == Vector3.INF:
				continue
			points.append(spot)
			types.append(f["type"])
			extra.append({"label": f["label"], "feature": f["position"]})
	if generator.last_roads:
		for c in generator.last_roads.get_town_centers():
			points.append(c)
			types.append("pueblo")
			extra.append({})
	for road in roads:
		var path: PackedVector3Array = road["path"]
		var acc := landmark_spacing  # Incluye el primer punto de cada vía.
		for i in path.size():
			if i > 0:
				acc += path[i - 1].distance_to(path[i])
			if acc >= landmark_spacing:
				acc = 0.0
				points.append(path[i])
				types.append("via")
				extra.append({})
	var min_d := landmark_spacing * 0.5
	for i in points.size():
		var p := points[i]
		if not is_inside(p.x, p.z):
			continue
		var close := false
		for lm in _landmarks:
			if Vector2(lm["position"].x - p.x, lm["position"].z - p.z).length() < min_d:
				close = true
				break
		if close:
			continue
		var pos := Vector3(p.x, get_height(p.x, p.z), p.z)
		var lm := {
			"id": _landmarks.size(),
			"position": pos,
			"type": types[i],
			"reach": get_reach_id(pos.x, pos.z),
		}
		lm.merge(extra[i])
		_landmarks.append(lm)
	if landmark_signs:
		_build_signs()


## Punto de vía más cercano a p (dentro de landmark_snap_distance y transitable), o INF.
func _nearest_road_point(p: Vector3, roads: Array) -> Vector3:
	var best := Vector3.INF
	var best_d := landmark_snap_distance
	for road in roads:
		var path: PackedVector3Array = road["path"]
		for q in path:
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if d < best_d and get_reach_id(q.x, q.z) >= 0:
				best_d = d
				best = q
	return best


## Carteles provisionales (poste + tablero de color + nombre) en los landmarks tipados.
func _build_signs() -> void:
	if _sign_root != null:
		_sign_root.queue_free()
	_sign_root = Node3D.new()
	_sign_root.name = "Carteles"
	add_child(_sign_root)
	var colors := {"pico": Color(0.85, 0.45, 0.15), "confluencia": Color(0.15, 0.45, 0.85), "costa": Color(0.95, 0.80, 0.30)}
	for lm in _landmarks:
		if not colors.has(lm["type"]):
			continue
		var sign := Node3D.new()
		sign.name = "Cartel_%d" % lm["id"]
		var p: Vector3 = lm["position"]
		# El cartel va al costado de la vía, mirando hacia el rasgo del terreno.
		var feature: Vector3 = lm.get("feature", p + Vector3.FORWARD)
		var toward := Vector3(feature.x - p.x, 0, feature.z - p.z)
		if toward.length() < 0.5:
			toward = Vector3.FORWARD
		toward = toward.normalized()
		var spot := p + toward.cross(Vector3.UP).normalized() * 6.0
		spot.y = get_height(spot.x, spot.z)
		sign.position = spot
		sign.add_child(_sign_part(BoxMesh.new(), Vector3(0.12, 2.6, 0.12), Vector3(0, 1.3, 0), Color(0.35, 0.25, 0.15)))
		sign.add_child(_sign_part(BoxMesh.new(), Vector3(1.8, 0.8, 0.08), Vector3(0, 2.5, 0), colors[lm["type"]]))
		var label := Label3D.new()
		label.text = lm.get("label", lm["type"])
		label.position = Vector3(0, 3.4, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.outline_size = 12
		label.pixel_size = 0.01
		label.visibility_range_end = 140.0
		sign.add_child(label)
		# Mirando hacia el rasgo (sin look_at: el nodo puede no estar en el arbol todavia).
		sign.basis = Basis.looking_at(toward, Vector3.UP)
		_sign_root.add_child(sign)


func _sign_part(mesh: BoxMesh, size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	return mi


## Vegetación del mapa del juego (MultiMesh por especie y chunk).
func _build_vegetation() -> void:
	if not vegetation_enabled or generator == null or generator.last_surface == null:
		return
	generator.vegetation_density = vegetation_density
	generator.vegetation_enabled = true  # el setter arma la vegetación sobre la superficie actual
