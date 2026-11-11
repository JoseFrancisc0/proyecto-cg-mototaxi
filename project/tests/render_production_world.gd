extends SceneTree
var failures:=0
func _initialize() -> void:_run.call_deferred()
func check(value: bool,message: String) -> void:
	print("OK " if value else "FAIL ",message)
	if not value:failures+=1
func _capture(camera: Camera3D,p: Vector3,focus: Vector3,key: String) -> void:
	camera.position=p;camera.look_at(focus)
	for frame in 6:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/comparacion/juego/"+key+".png")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../output/comparacion/juego"))
	root.size=Vector2i(1440,900)
	root.msaa_3d=Viewport.MSAA_4X
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();stage.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("a5bbc8");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-30,0);sun.light_energy=1;sun.shadow_enabled=true;stage.add_child(sun)
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.use_editor_scene=false;world.grid_size=512;world.cell_size=1.5;world.erosion_enabled=true;world.vegetation_enabled=true;world.vegetation_density=.7;stage.add_child(world)
	await world.generate_async(67)
	var details:=PeruNeighborhoodDetails.new();stage.add_child(details);details.build(world)
	check(world._generated_ok,"Mapa con resolución y erosión de la partida real")
	if world.houses==null:check(false,"Viviendas disponibles");quit(failures);return
	if not is_instance_valid(world.water_system):
		check(false,"Sistema de agua disponible");quit(failures);return
	var districts: Dictionary={};var regions: Dictionary={};var hillside:=0
	for house: Dictionary in world.houses.houses:
		var key: String=str(house.region)+"_"+str(house.district)
		districts[key]=int(districts.get(key,0))+1;regions[house.region]=int(regions.get(house.region,0))+1
		if int(house.region)==0 and str(house.district)=="ladera":hillside+=1
	print("PRODUCTION_DISTRICTS ",districts)
	check(regions.size()==3,"Viviendas presentes en costa, sierra y selva")
	check(int(regions.get(0,0))>=20,"La costa tiene barrios visibles además de la ladera")
	check(int(regions.get(1,0))>=20,"La sierra tiene un poblado visible, no unas pocas casas aisladas")
	check(int(regions.get(2,0))>=20,"La selva tiene un poblado visible con variedad urbana")
	check(hillside>0,"Conjuntos de ladera presentes en la costa")
	var wet_points:=0;var freeboard:=true;var minimum:=INF
	for road: Dictionary in world.get_roads():
		var path: PackedVector3Array=road.path
		for j in range(1,path.size()):
			var p: Vector3=(path[j-1]+path[j])*.5
			var level:=world.water_system.surface_level_at(p.x,p.z)
			if not is_finite(level):continue
			var gap:=world.get_height(p.x,p.z)-level;minimum=minf(minimum,gap);wet_points+=1
			if gap<1.20:
				freeboard=false;print("LOW_FREEBOARD ",p," gap=",gap," deck=",world.road_layout._bridge_at(p))
	print("WATER_ROAD_CLEARANCE ",minimum," samples=",wet_points)
	check(freeboard,"La calzada cruzando agua conserva altura de seguridad")
	var matches:=true
	for chunk in world._chunk_root.get_children():
		var vertices: PackedVector3Array=chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var parts:=str(chunk.name).split("_");var ox:=int(parts[1])*world.chunk_cells;var oz:=int(parts[2])*world.chunk_cells
		var top_count: int=(mini(world.chunk_cells,world.grid_size-ox)+1)*(mini(world.chunk_cells,world.grid_size-oz)+1)
		for i in range(0,top_count,17):
			var p:=vertices[i]
			if absf(p.y-world._sample_height(p.x,p.z))>.015:matches=false
	check(matches,"Sin separación entre malla y suelo físico después de la erosión")
	var camera:=Camera3D.new();camera.current=true;camera.far=4000;camera.fov=65;stage.add_child(camera)
	for region in 3:
		var selected: Dictionary={};var best_neighbors:=-1
		for house: Dictionary in world.houses.houses:
			if int(house.region)!=region:continue
			var neighbors:=0
			for other: Dictionary in world.houses.houses:
				if int(other.region)==region and (other.position as Vector3).distance_to(house.position)<45:neighbors+=1
			if neighbors>best_neighbors:selected=house;best_neighbors=neighbors
		if selected.is_empty():continue
		var focus: Vector3=selected.position+Vector3.UP*2
		var front:=Basis(Vector3.UP,float(selected.yaw))*Vector3(0,0,1)
		await _capture(camera,focus+front*30+Vector3.UP*13,focus,"mapa_region_"+str(region))
	for child in world.road_layout.get_children():
		if not child is PeruBridges or child.spans.is_empty():continue
		var span: Dictionary=child.spans[0]
		for candidate: Dictionary in child.spans:
			if (candidate.a as Vector3).distance_to(candidate.b)>(span.a as Vector3).distance_to(span.b):span=candidate
		var focus: Vector3=span.middle;focus.y=world.get_height(focus.x,focus.z)
		await _capture(camera,focus+Vector3(24,15,29),focus,"rio_altura");break
	for index in world.road_layout.nodes.size():
		if world.road_layout.pedestrian_links[index].size()<3:continue
		var p: Vector3=world.road_layout.nodes[index]
		await _capture(camera,p+Vector3(20,30,25),p,"cruce_unificado");break
	print("PRODUCTION_WORLD_RESULT ",failures)
	quit(failures)
