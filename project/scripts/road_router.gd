class_name RoadRouter
extends RefCounted
## Ruta recomendada por las vías (S12-S13, J-B): grafo de las polilíneas de get_roads()
## y búsqueda A* (AStar3D de Godot) sobre él.
##
## Las vías del generador comparten puntos en los cruces y extremos, así que se unen los
## puntos que caen en la misma posición. Si el inicio o el final están lejos de una vía,
## se agrega un tramo a campo traviesa con TerrainWorld.find_route().

const BUCKET := 32.0  ## Lado (m) de las celdas para buscar el nodo más cercano.

var _astar := AStar3D.new()
var _buckets := {}  # Vector2i -> PackedInt32Array de ids


## roads: lo que devuelve TerrainWorld.get_roads().
func build(roads: Array) -> void:
	_astar.clear()
	_buckets.clear()
	var ids := {}  # posición cuantizada (10 cm) -> id
	for road in roads:
		var path: PackedVector3Array = road["path"]
		var prev := -1
		for p in path:
			var key := Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))
			var id: int = ids.get(key, -1)
			if id < 0:
				id = _astar.get_point_count()
				ids[key] = id
				_astar.add_point(id, p)
				var b := _bucket(p)
				var list: PackedInt32Array = _buckets.get(b, PackedInt32Array())
				list.append(id)
				_buckets[b] = list
			if prev >= 0 and prev != id and not _astar.are_points_connected(prev, id):
				_astar.connect_points(prev, id)
			prev = id


func is_empty() -> bool:
	return _astar.get_point_count() == 0


## Nodo de vía más cercano a p (en planta) que cumpla accept(pos) si se da. -1 si no hay.
func nearest_node(p: Vector3, max_dist: float = 400.0, accept: Callable = Callable()) -> int:
	var best := -1
	var best_d := max_dist
	var center := _bucket(p)
	var reach := ceili(max_dist / BUCKET)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var list: PackedInt32Array = _buckets.get(center + Vector2i(dx, dz), PackedInt32Array())
			for id in list:
				var q := _astar.get_point_position(id)
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < best_d and (not accept.is_valid() or accept.call(q)):
					best_d = d
					best = id
	return best


## Puntos de la ruta por vías entre los nodos más cercanos a a y b (vacío si no conectan).
func road_path(a: Vector3, b: Vector3, accept: Callable = Callable()) -> PackedVector3Array:
	var ia := nearest_node(a, 400.0, accept)
	var ib := nearest_node(b, 400.0, accept)
	if ia < 0 or ib < 0:
		return PackedVector3Array()
	if ia == ib:
		return PackedVector3Array([_astar.get_point_position(ia)])
	return _astar.get_point_path(ia, ib)


func _bucket(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
