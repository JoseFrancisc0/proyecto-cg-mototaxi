extends SceneTree
## Numerical preview only: no scene is instantiated or saved.
func _initialize() -> void:
	var cases := []
	for seed_value: int in [68, 2026, 1337, 42]:
		var terrain := TerrainNoise.new()
		terrain.set_seed(seed_value)
		terrain.configure_regions({"enabled": true, "extent": 768.0})
		var roads := RoadNetwork.new()
		var config := {"num_points": 8, "k_neighbors": 2, "min_point_dist": 15.0, "erosion_enabled": false}
		roads.generate_roads(terrain, 128, 6.0, config)
		var mesh := TerrainMesh.new().generate_mesh(terrain, roads, 128, 6.0, config)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var heights := []
		var weights := []
		for p: Vector3 in vertices:
			heights.append(p.y)
			var w: Vector3 = terrain.get_biome_weights(p.x, p.z)
			weights.append([w.x, w.y, w.z])
		var paths := []
		for path: PackedVector3Array in roads.get_road_paths():
			var points := []
			for point: Vector3 in path: points.append([point.x,point.y,point.z])
			paths.append(points)
		cases.append({"seed": seed_value, "regions": true, "side": 129, "heights": heights, "weights": weights, "roads": paths})
	var folder := ProjectSettings.globalize_path("res://../output/s11_cgb")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/samples.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cases))
	print("Regiones y caminos exportados sin erosion ni cambios a la escena guardada")
	quit()
