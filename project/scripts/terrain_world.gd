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
## Convenciones: metros, origen en el centro del mapa, Y hacia arriba. El nodo debe
## quedarse en el origen sin rotar ni escalar (las consultas son en coordenadas globales).

signal generated

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
## Fracción de los pasos de CG que se aplican (1.0 = receta completa, ~60-90 s a 512
## celdas; 0.1 = ~15 s). Las vías quedan limitadas en pendiente en ambos casos.
@export_range(0.01, 1.0, 0.01) var erosion_scale := 0.1
@export var erosion_fluvial := 3000
@export var erosion_thermal := 600
@export var erosion_deposition := 2000
@export_range(0, 3) var erosion_levels := 2

@export_group("Generador CG")
## Propiedades extra de chunk_mesh.gd (por ejemplo {"mountain_amplitude": 85.0}).
## Sirve para probar los mismos valores que terrain_demo.tscn sin tocar este script.
@export var generator_overrides: Dictionary = {}

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
var _reach := PackedInt32Array()   # Componente transitable de cada muestra (-1 = no transitable).
var _body: StaticBody3D
var _bridge_body: StaticBody3D


func _ready() -> void:
	if generate_on_ready:
		generate(world_seed)


## Construye el mapa completo. Con new_seed < 0 usa world_seed.
func generate(new_seed: int = -1) -> void:
	if new_seed >= 0:
		world_seed = new_seed
	_n = grid_size + 1
	_half = grid_size * cell_size * 0.5

	if generator != null:
		remove_child(generator)
		generator.free()
	generator = Generator.new()
	generator.name = "Terrain"
	if use_editor_scene:
		if _load_editor_scene():
			return
		if generator.is_inside_tree():  # Falló a medias: se empieza con un generador limpio.
			remove_child(generator)
			generator.free()
			generator = Generator.new()
			generator.name = "Terrain"
	generator.grid_size = grid_size
	generator.cell_size = cell_size
	generator.noise_seed = world_seed
	generator.erosion_fluvial = maxi(1, roundi(erosion_fluvial * erosion_scale))
	generator.erosion_thermal = maxi(1, roundi(erosion_thermal * erosion_scale))
	generator.erosion_deposition = maxi(1, roundi(erosion_deposition * erosion_scale))
	generator.erosion_levels = erosion_levels
	generator.road_max_grade = road_max_grade
	for key in generator_overrides:
		generator.set(key, generator_overrides[key])
	add_child(generator)  # Dentro del árbol, su _ready ya genera el T0 (no hay malla previa).
	if generator.last_surface == null:
		generator.generate_base()
	if erosion_enabled:
		generator.apply_erosion()

	_finish_generate()


## Pasos comunes tras crear la superficie: alturas, colisión, landmarks y transitabilidad.
func _finish_generate() -> void:
	_surface = generator.last_surface
	_heights = _surface.get_surface_heights() if _surface else PackedFloat32Array()
	if _heights.size() != _n * _n:
		push_error("TerrainWorld: el generador no devolvió alturas (%d de %d)" % [_heights.size(), _n * _n])
		return
	if build_collision:
		_build_collision()
	_add_bridge_decks()
	_build_reachability()
	_build_landmarks()
	generated.emit()


## Copia el nodo Terrain de editor_scene (sus propiedades, sin la malla) y rehace la
## superficie sobre su suelo guardado. Devuelve false si no hay terreno que usar.
func _load_editor_scene() -> bool:
	var t0 := Time.get_ticks_msec()
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
	if not generator.rebuild_saved_ground():
		return false
	print("TerrainWorld: escenario de %s (%d celdas x %.1f m = %.0f m, semilla %d) en %.1f s" % [
		editor_scene, grid_size, cell_size, get_world_size(), world_seed, (Time.get_ticks_msec() - t0) / 1000.0])
	_finish_generate()
	return true


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
func get_landmarks() -> Array[Dictionary]:
	return _landmarks


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


static func route_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# --- Interno ------------------------------------------------------------------

func _build_collision() -> void:
	if _body == null:
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
	var cs := _body.get_child(0) as CollisionShape3D
	cs.shape = hms
	cs.scale = Vector3.ONE * cell_size

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
func _build_landmarks() -> void:
	_landmarks.clear()
	var points: Array[Vector3] = []
	var types: Array[String] = []
	if generator.last_roads:
		for c in generator.last_roads.get_town_centers():
			points.append(c)
			types.append("pueblo")
	for road in get_roads():
		var path: PackedVector3Array = road["path"]
		var acc := landmark_spacing  # Incluye el primer punto de cada vía.
		for i in path.size():
			if i > 0:
				acc += path[i - 1].distance_to(path[i])
			if acc >= landmark_spacing:
				acc = 0.0
				points.append(path[i])
				types.append("via")
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
		_landmarks.append({
			"id": _landmarks.size(),
			"position": pos,
			"type": types[i],
			"reach": get_reach_id(pos.x, pos.z),
		})
