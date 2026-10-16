@tool
class_name TerrainWorld
extends Node3D
## Fachada única del terreno para el juego (contrato CG <-> Juego de la semana 10).
## Versión provisional: ruido + caminos actuales sobre una grilla de alturas.
## Cuando llegue la erosión, solo cambia generate(); el resto de la API se mantiene.
##
## Convenciones: metros, origen en el centro del mapa, Y hacia arriba.
## El mapa cubre x, z en [-world_size / 2, world_size / 2].

signal generated

@export var grid_size: int = 512
@export var cell_size: float = 1.0
@export var world_seed: int = 67
@export var generate_on_ready := true
@export var build_collision := true

@export_group("Red de caminos")
@export var num_points := 30
@export var min_point_dist := 15.0
@export var k_neighbors := 2
@export var road_width := 4.0
@export var road_fade := 3.0
@export var road_smooth := 3

var _noise: TerrainNoise
var _roads: RoadNetwork
var _heights := PackedFloat32Array()
var _n := 0
var _half := 0.0
var _landmarks: Array[Dictionary] = []

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D


func _ready() -> void:
	if generate_on_ready:
		generate(world_seed)


## Construye el mapa completo. Con new_seed < 0 usa world_seed.
func generate(new_seed: int = -1) -> void:
	if new_seed >= 0:
		world_seed = new_seed
	_n = grid_size + 1
	_half = grid_size * cell_size * 0.5

	var cfg := {
		"num_points": num_points,
		"min_point_dist": min_point_dist,
		"k_neighbors": k_neighbors,
		"road_width": road_width,
		"road_fade": road_fade,
		"road_smooth": road_smooth,
	}

	_noise = TerrainNoise.new()
	_noise.set_seed(world_seed)
	_roads = RoadNetwork.new()
	_roads.generate_roads(_noise, grid_size, cell_size, cfg)

	var builder := TerrainMesh.new()
	var hm: Dictionary = builder.generate_heightmap(_noise, _roads, grid_size, cell_size, cfg)
	_heights = hm["heights"]
	var mesh := builder.build_mesh(_heights, hm["colors"], grid_size, cell_size)

	_build_nodes(mesh)
	_build_landmarks()
	generated.emit()


# --- API del contrato ---------------------------------------------------------

## Altura del suelo en (x, z), interpolada sobre los mismos triángulos de la malla.
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
	# La malla parte cada celda por la diagonal (00)-(11).
	if tx >= tz:
		return h00 + tx * (h10 - h00) + tz * (h11 - h10)
	return h00 + tz * (h01 - h00) + tx * (h11 - h01)


func get_normal(x: float, z: float) -> Vector3:
	var d := cell_size
	var dhdx := (get_height(x + d, z) - get_height(x - d, z)) / (2.0 * d)
	var dhdz := (get_height(x, z + d) - get_height(x, z - d)) / (2.0 * d)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()


## Pesos (costa, sierra, selva). La costa aún no existe en el stub.
func get_biome(x: float, z: float) -> Vector3:
	if _noise == null:
		return Vector3(0, 0, 1)
	var b := _noise.get_biome_blend(x, z)
	return Vector3(0.0, b, 1.0 - b)


## Área de drenaje (ríos). Stub: siempre 0 hasta tener flow routing.
func get_drainage(_x: float, _z: float) -> float:
	return 0.0


## Puntos de recogida y destino: [{ "id": int, "position": Vector3, "type": String }].
func get_landmarks() -> Array[Dictionary]:
	return _landmarks


## Ruta recomendada de a hacia b (A* sobre el terreno) como lista de puntos sobre el suelo.
func find_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array()
	if _roads == null:
		return path
	path = _roads.find_path(_noise, Vector2(a.x, a.z), Vector2(b.x, b.z), _half)
	for i in path.size():
		var p := path[i]
		p.y = get_height(p.x, p.z)
		path[i] = p
	return path


# --- Utilidades ---------------------------------------------------------------

func get_world_size() -> float:
	return grid_size * cell_size


func is_inside(x: float, z: float) -> bool:
	return absf(x) <= _half and absf(z) <= _half


## Longitud de una ruta (por ejemplo, la de find_route) en metros.
static func route_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# --- Interno ------------------------------------------------------------------

func _build_nodes(mesh: ArrayMesh) -> void:
	# Nodos creados sin owner: no se guardan en el .tscn (la malla no infla la escena).
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		_mesh_instance.material_override = mat
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh

	if not build_collision:
		return
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "TerrainBody"
		add_child(_body)
		_shape = CollisionShape3D.new()
		_body.add_child(_shape)

	# HeightMapShape3D usa espaciado 1 centrado en el origen: se escala de forma
	# uniforme por cell_size y se dividen las alturas para compensar en Y.
	var hms := HeightMapShape3D.new()
	hms.map_width = _n
	hms.map_depth = _n
	if is_equal_approx(cell_size, 1.0):
		hms.map_data = _heights
	else:
		var scaled := PackedFloat32Array()
		scaled.resize(_heights.size())
		for i in _heights.size():
			scaled[i] = _heights[i] / cell_size
		hms.map_data = scaled
	_shape.shape = hms
	_shape.scale = Vector3.ONE * cell_size


func _build_landmarks() -> void:
	_landmarks.clear()
	var pois: PackedVector2Array = _roads.get_poi_points()
	for i in pois.size():
		var p := pois[i]
		_landmarks.append({
			"id": i,
			"position": Vector3(p.x, get_height(p.x, p.y), p.y),
			"type": "poi",
		})
