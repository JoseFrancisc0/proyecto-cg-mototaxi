extends SceneTree
var failures:=0
func check(ok: bool,message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	GameSettings.path="user://test_peru_world.cfg"
	var world:=TerrainWorld.new()
	world.generate_on_ready=false;world.use_editor_scene=false;world.grid_size=192;world.cell_size=6.0
	world.erosion_enabled=false;world.vegetation_enabled=false
	root.add_child(world);world.generate(42)
	check(world.road_layout!=null and world.road_layout.nodes.size()>20,"Red vial construida con grafo de navegación")
	check(world.road_layout.profiles.size()>=2,"Más de un perfil de calzada")
	check(world.water_system!=null and world.water_system.get_node_or_null("OceanoEnElHorizonte")!=null,"Mar continuo alrededor del mapa")
	if world.water_system==null:
		quit(maxi(1,failures));return
	var water:=world.water_system.get_node_or_null("CaucesMayores") as MeshInstance3D
	var banks_fit:=water!=null;var water_faces_up:=water!=null
	if water:
		var vertices: PackedVector3Array=water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size()-2,3):
			if (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).y>0.001:water_faces_up=false
			if vertices[i].y<world._sample_height(vertices[i].x,vertices[i].z)+.015:banks_fit=false
	check(banks_fit,"Agua recortada contra el lecho real del terreno")
	check(water_faces_up,"Las caras del agua miran hacia arriba para recibir iluminación")
	check(world.houses.houses.size()>0,"Viviendas regionales colocadas")
	var regional:=true
	for house: Dictionary in world.houses.houses:
		var model: Dictionary=world.houses._models[int(house.model)].model
		if int(model.region)!=int(house.region) or not str(house.district) in model.zones:regional=false
	check(regional,"Cada vivienda corresponde a su región y zona")
	check(not world.generator.material_override.shader.code.contains("discard;"),"El terreno no abre huecos mediante descarte de fragmentos")
	var matched:=true
	for child in world._chunk_root.get_children():
		var arrays: Array=child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size(),31):
			var p:=vertices[i]
			if p.y>world._sample_height(p.x,p.z)+.02:matched=false
	check(matched,"La malla visible sigue las mismas alturas que la colisión")
	check(world.road_layout.get_node_or_null("Calzadas")==null,"El asfalto se integra al terreno sin duplicar una segunda pista")
	var walks:=world.road_layout.get_node_or_null("Veredas") as MeshInstance3D
	var crossings_clear:=true
	if walks:
		var wa:=walks.mesh.surface_get_arrays(0)
		var wv: PackedVector3Array=wa[Mesh.ARRAY_VERTEX]
		for i in range(0,wv.size()-2,27):
			var p: Vector3=(wv[i]+wv[i+1]+wv[i+2])/3.0
			for segment: Array in world.road_layout._height_buckets.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
				var a: Vector3=segment[0];var b: Vector3=segment[1]
				var closest:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
				if closest.distance_to(Vector2(p.x,p.z))<float(segment[2])-.20 and absf((a.y+b.y)*.5-p.y)<.5:crossings_clear=false
	check(crossings_clear,"Las veredas no atraviesan las calzadas en los cruces")
	var flow_ok:=true
	for from in world.road_layout.links.size():
		for edge: Dictionary in world.road_layout.links[from]:
			if bool(world.road_layout.roads[int(edge.road)].one_way) and int(edge.direction)<0:flow_ok=false
	check(flow_ok,"Los enlaces de circulación respetan las calles de un solo sentido")
	var points:=0
	for road: Dictionary in world.get_roads():
		for p in road.path:
			if points<2:check(world.get_height(p.x,p.z)>=p.y-.02,"Superficie de calzada conservada")
			points+=1
	var moto: Mototaxi=load("res://scenes/mototaxi.tscn").instantiate();moto.freeze=true;moto.use_input=false
	root.add_child(moto)
	var spawn: Vector3=world.road_layout.nodes[world.road_layout.nodes.size()/2]
	var towns:=world.get_town_centers()
	if not towns.is_empty():spawn=towns[0]
	moto.global_position=spawn+Vector3.UP
	var traffic:=PeruTraffic.new();root.add_child(traffic);traffic.setup(world,moto)
	check(traffic.cars.size()>0,"Carrocerías 3D aparecen en la circulación")
	check(traffic.walkers.size()>0,"Peatones regionales aparecen en zonas caminables")
	for frame in 3600:await physics_frame
	var moved:=0
	for actor in traffic.cars:
		print("CAR_MOVEMENT ",actor.kind," travel=",actor.travel," stopped=",actor.stuck)
		if float(actor.travel)>10:moved+=1
		check(is_finite(actor.body.position.y),"Altura finita de vehículo")
		check(actor.visual.wheels.size()==4,"Vehículo con cuatro ruedas mecánicas independientes")
		var expected_radius: float=[.265,.29,.38,.46][int(actor.kind)]
		check(absf(float(actor.visual.wheels[0].radius)-expected_radius)<.001,"Radio de rueda importado coincide con la geometría del vehículo")
		print("WHEEL_CONTACT ",actor.kind," error=",actor.get("contact_error",0)," position=",actor.body.position)
		check(float(actor.get("contact_error",0))<.15,"Neumáticos apoyados en la calzada")
		if float(actor.travel)>5:
			check(absf(actor.visual.wheels[0].spin.rotation.x)>.1,"La marcha del vehículo anima las ruedas")
	traffic.set_night(true)
	if not traffic.cars.is_empty():
		var visual: PeruTrafficVehicle=traffic.cars[0].visual
		moto.position=traffic.cars[0].body.position+Vector3.UP*2
		traffic._sync_headlights()
		check(int(world.generator.material_override.get_shader_parameter("traffic_light_count"))>0,"Los faros aportan iluminación al material del terreno")
		check(visual.lamps[0].visible,"Faros encendidos durante la noche")
		visual.complain(true,2)
		check(visual.horn.playing and visual.voice.playing,"Bocina y voz ante una obstrucción persistente")
	check(moved>0,"Los vehículos avanzan durante la simulación de un minuto")
	var walked:=0
	for actor in traffic.walkers:
		print("WALK_MOVEMENT travel=",actor.travel," stopped=",actor.stuck)
		if float(actor.travel)>3:walked+=1
		if float(actor.get("age",0))>10:check(float(actor.travel)>5 and float(actor.stuck)<1,"Peatón mantiene un recorrido válido sin bloquearse")
		check(traffic._valid_walk(actor.body.position),"Peatón sobre vereda o suelo caminable")
	check(walked>0,"Los peatones avanzan durante la simulación")
	print("PERU_WORLD_RESULT ",failures)
	quit(failures)
