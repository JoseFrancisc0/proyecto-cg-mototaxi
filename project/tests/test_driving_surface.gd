extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	print('OK ' if ok else 'FAIL ', message)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := TerrainWorld.new()
	world.generate_on_ready = false
	world.grid_size = 128
	world.cell_size = 2.5
	world.chunk_cells = 32
	world.vegetation_enabled = false
	world.erosion_enabled = false
	root.add_child(world)
	world.generate(67)
	await physics_frame
	await physics_frame
	check(world._chunk_root.get_child_count()>1,'LOD visual conserva múltiples bloques')
	check(world._body.get_child_count()==1,'Colisión continua sin bordes internos de bloques')
	var worst := 0.0
	var samples := 0
	for boundary in [-80.0,0.0,80.0]:
		for side in [-0.05,0.0,0.05]:
			for z in [-110.0,-40.0,20.0,100.0]:
				var x: float = boundary+side
				var q := PhysicsRayQueryParameters3D.create(Vector3(x,500,z),Vector3(x,-100,z))
				var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty():
					worst = maxf(worst,absf(hit.position.y-world.get_height(x,z)))
					samples += 1
	check(samples==36 and worst < 0.05,'Suelo visible y físico en uniones: %d rayos, error máx. %.4f m' % [samples,worst])
	var roads := world.get_roads()
	check(not roads.is_empty(),'Red vial disponible')
	var road_samples := 0
	for road: Dictionary in roads:
		var path: PackedVector3Array = road.path
		if path.size()>1:
			var p := path[path.size()/2]
			if world.get_offroad_amount(p.x,p.z) < 0.01: road_samples += 1
	check(road_samples==roads.size(),'Todas las pistas se reconocen como asfalto')
	print('Superficie continua: %d errores' % failures)
	quit(failures)
