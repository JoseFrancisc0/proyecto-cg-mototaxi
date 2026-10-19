extends SceneTree

var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var source := TerrainNoise.new()
	source.set_seed(68)
	source.configure_regions({"extent": 128.0})
	var config := {"num_points": 8, "k_neighbors": 1, "min_point_dist": 15.0, "road_width": 4.0, "road_fade": 3.0, "erosion_enabled": false}
	var roads := RoadNetwork.new()
	roads.generate_roads(source, 64, 2.0, config)
	var paths: Array = roads.get_road_paths()
	check(paths.size() >= 7, "La red de ocho destinos debe estar conectada")
	var duplicate := RoadNetwork.new()
	duplicate.generate_roads(source, 64, 2.0, config)
	check(paths == duplicate.get_road_paths(), "Caminos reproducibles con la misma semilla")
	var endpoints: Array[Vector2] = []
	for path: PackedVector3Array in paths:
		check(path.size() >= 2, "Ruta con recorrido")
		for point: Vector3 in [path[0], path[-1]]:
			var key := Vector2(point.x, point.z)
			if not endpoints.has(key): endpoints.append(key)
	var reached: Array[Vector2] = [endpoints[0]]
	for iteration in range(endpoints.size()):
		for path: PackedVector3Array in paths:
			if reached.has(Vector2(path[0].x, path[0].z)) and not reached.has(Vector2(path[-1].x, path[-1].z)): reached.append(Vector2(path[-1].x, path[-1].z))
			if reached.has(Vector2(path[-1].x, path[-1].z)) and not reached.has(Vector2(path[0].x, path[0].z)): reached.append(Vector2(path[0].x, path[0].z))
	check(reached.size() == endpoints.size(), "Sin grupos de caminos desconectados")
	var mesh := TerrainMesh.new().generate_mesh(source, roads, 64, 2.0, config)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var changed := 0
	for i in range(0, vertices.size(), 17):
		var p := vertices[i]
		var nearest := INF
		var profile := 0.0
		for path: PackedVector3Array in paths:
			for j in range(path.size() - 1):
				var a := Vector2(path[j].x, path[j].z)
				var b := Vector2(path[j + 1].x, path[j + 1].z)
				var t := clampf((Vector2(p.x, p.z) - a).dot(b - a) / maxf(a.distance_squared_to(b), 0.000001), 0, 1)
				var distance := Vector2(p.x, p.z).distance_to(a.lerp(b, t))
				if distance < nearest:
					nearest = distance
					profile = lerpf(path[j].y, path[j + 1].y, t)
		var weight := 1.0 - smoothstep(4.0, 7.0, nearest)
		var base: float = source.get_height(p.x, p.z)
		check(absf(p.y - lerpf(base, profile, weight)) < 0.0001, "Rasterizado mantiene el perfil del camino mas cercano")
		if absf(p.y - base) > 0.001: changed += 1
	check(changed > 0, "Los caminos deben verse en la malla")
	print("Caminos: %d errores; %d rutas" % [failures, paths.size()])
	quit(0 if failures == 0 else 1)
