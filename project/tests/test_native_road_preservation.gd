extends SceneTree
var failures:=0
func _initialize() -> void:_run.call_deferred()
func check(value: bool,message: String) -> void:
	print("OK " if value else "FAIL ",message)
	if not value:failures+=1
func _run() -> void:
	var all_lanes:={}
	var raw:=PackedVector3Array([Vector3.ZERO,Vector3(10,30,2),Vector3(20,-8,6),Vector3(30,8,2),Vector3(40,2,0)])
	var graded:=TerrainMesh.new().grade_road_profile(raw,.16)
	var bounded:=graded[0]==raw[0] and graded[-1]==raw[-1]
	for i in graded.size():
		bounded=bounded and Vector2(graded[i].x,graded[i].z)==Vector2(raw[i].x,raw[i].z)
		if i>0:
			var delta:=graded[i]-graded[i-1]
			bounded=bounded and absf(delta.y)<=Vector2(delta.x,delta.z).length()*.16001
	check(bounded,"El limitador original suaviza desniveles fuertes sin mover curvas ni extremos")
	var water_samples:=0;var water_safe:=true
	var seeds: Array=[42,67]
	if not OS.get_cmdline_user_args().is_empty():seeds=[int(OS.get_cmdline_user_args()[0])]
	for seed_value in seeds:
		var world:=TerrainWorld.new()
		world.generate_on_ready=false;world.use_editor_scene=false
		world.grid_size=256;world.cell_size=3
		world.erosion_enabled=seed_value==67;world.vegetation_enabled=false;world.houses_enabled=false
		root.add_child(world);world.generate(seed_value)
		var original: Array=world.generator.last_roads.get_road_metadata()
		var native_nodes:={}
		for road: Dictionary in world.get_roads():
			if not road.get("native",false):continue
			for point: Vector3 in road.path:native_nodes[Vector2(point.x,point.z)]=true
		var joined:=true;var connectors:=0
		for road: Dictionary in world.get_roads():
			if bool(road.get("native",false)) or int(road.kind)!=1:continue
			var end: Vector3=road.path[-1];connectors+=1
			joined=joined and native_nodes.has(Vector2(end.x,end.z))
			for point: Vector3 in road.path:native_nodes[Vector2(point.x,point.z)]=true
		check(joined and connectors>0,"Los accesos enlazan con la red original o con un acceso ya conectado")
		var same:=true;var lanes:={};var max_change:=0.0;var samples:=0
		for i in original.size():
			var road: Dictionary=world.get_roads()[i]
			var expected: PackedVector3Array=original[i].path
			var trims:=world.road_layout.trimmed_ends
			var start: Vector3=trims.get(Vector2(expected[0].x,expected[0].z),expected[0])
			var end: Vector3=trims.get(Vector2(expected[-1].x,expected[-1].z),expected[-1])
			expected=expected.slice(expected.find(start),expected.rfind(end)+1)
			same=same and road.path==expected and is_equal_approx(float(road.width),float(original[i].width))
			lanes[int(road.lanes)]=true
			all_lanes[int(road.lanes)]=true
		for road: Dictionary in world.get_roads():lanes[int(road.lanes)]=true;all_lanes[int(road.lanes)]=true
		var native:=world.native_road_surface
		for i in native.influence.size():
			if native.influence[i]<1.0:continue
			samples+=1;max_change=maxf(max_change,absf(world._heights[i]-native.protected_heights[i]))
		check(same,"Semilla %d: %d rutas conservan su perfil hasta el empalme activo"%[seed_value,original.size()])
		check(samples>0 and max_change<.00001,"La superficie nativa de las pistas no se vuelve a nivelar: %d muestras, error %.6f m"%[samples,max_change])
		var drive_error:=0.0
		for road: Dictionary in original:
			var path: PackedVector3Array=road.path
			for i in range(0,path.size(),3):
				var p:=path[i]
				var expected:=native.height_at(p.x,p.z,native._ground_height(p.x,p.z))
				drive_error=maxf(drive_error,absf(world.get_height(p.x,p.z)-expected))
		check(drive_error<.20,"Altura de circulación coincide con el suelo y los tableros originales: error %.4f m"%drive_error)
		var deck:=world._surface.get_bridge_mesh()
		if deck and deck.get_surface_count()>0:
			var visual:=world.generator.get_node_or_null("PuentesGenerados") as MeshInstance3D
			check(visual!=null and visual.visible and world._bridge_body!=null,"Tableros originales visibles y con colisión")
			check(visual.mesh!=null and visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==deck.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"La integración conserva todos los vértices de los tableros originales")
		check(lanes.has(2) and lanes.has(4),"Calzadas de 2 y 4 carriles con su ancho generado por CG")
		for road: Dictionary in world.get_roads():
			var reported:=false
			for p: Vector3 in road.path:
				var level:=world.water_system.surface_level_at(p.x,p.z)
				if not is_finite(level):continue
				water_samples+=1
				if world.get_height(p.x,p.z)-level<1.20:
					water_safe=false
					if not reported:print("LOW_NATIVE_WATER seed=",seed_value," native=",road.get("native",false)," id=",road.id," p=",p," gap=",world.get_height(p.x,p.z)-level," ground=",world._sample_height(p.x,p.z)," cap=",native.water_ceiling(p.x,p.z));reported=true
		world.queue_free();await process_frame
	check(all_lanes.has(1),"Trochas de un carril donde el generador encuentra terreno adecuado")
	check(water_safe and (seeds.size()==1 or water_samples>0),"Las pistas muestreadas sobre agua conservan altura de seguridad: %d muestras"%water_samples)
	print("NATIVE_ROAD_PRESERVATION_RESULT ",failures)
	quit(failures)
