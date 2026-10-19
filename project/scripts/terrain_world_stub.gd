@tool
class_name TerrainWorldStub
extends Node
## Before generation, queries use T0. Afterwards, height and drainage use the final surface.
## Landmarks remain a placeholder; find_route returns a suggested ground path, not a traffic route.
var _terrain: TerrainNoise
var _extent := 768.0
var is_stub := true # Landmarks remain pending. Surface and drainage use generated data.
var _surface: TerrainMesh
var _roads: RoadNetwork

func set_surface(surface: TerrainMesh, roads: RoadNetwork) -> void:
	_surface = surface
	_roads = roads

func clear_surface() -> void:
	_surface = null
	_roads = null

func configure(terrain: TerrainNoise, extent: float) -> void:
	clear_surface()
	_terrain = terrain
	_extent = extent

func generate(seed: int) -> void:
	if _terrain != null:
		_terrain.set_seed(seed)

func get_height(x: float, z: float) -> float:
	if _surface != null: return _surface.get_height(x, z)
	return _terrain.get_height(x, z) if _terrain != null else 0.0

func get_normal(x: float, z: float) -> Vector3:
	var step := 0.5
	return Vector3(-(get_height(x + step, z) - get_height(x - step, z)) / (2 * step), 1, -(get_height(x, z + step) - get_height(x, z - step)) / (2 * step)).normalized()

func get_biome(x: float, z: float) -> Vector3:
	return _terrain.get_biome_weights(x, z) if _terrain != null else Vector3.ZERO

func get_hardness(x: float, z: float) -> float:
	return _terrain.get_hardness(x, z) if _terrain != null else 0.0

func get_critical_slope(x: float, z: float) -> float:
	return _terrain.get_critical_slope(x, z) if _terrain != null else 0.0

func get_drainage(x: float, z: float) -> float:
	return _surface.get_drainage(x, z) if _surface != null else 0.0

func get_landmarks() -> Array:
	return [] # Explicit placeholder, not fabricated landmarks.

func find_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	if _terrain == null:
		return PackedVector3Array()
	var routes := _roads if _roads != null else RoadNetwork.new()
	return routes.find_path(_terrain, Vector2(a.x, a.z), Vector2(b.x, b.z), _extent * 0.5)
