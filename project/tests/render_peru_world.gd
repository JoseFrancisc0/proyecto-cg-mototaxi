extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1440,900)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();stage.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("9fb6ca")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.75
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-25,0);sun.light_energy=1.1;sun.shadow_enabled=true;stage.add_child(sun)
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.use_editor_scene=false;world.grid_size=192;world.cell_size=6.0
	world.erosion_enabled=false;world.vegetation_enabled=true;stage.add_child(world);world.generate(42)
	var camera:=Camera3D.new();camera.current=true;camera.fov=60;camera.far=5000;stage.add_child(camera)
	var moto: Mototaxi=load("res://scenes/mototaxi.tscn").instantiate();moto.freeze=true;moto.use_input=false;stage.add_child(moto)
	var traffic:=PeruTraffic.new();stage.add_child(traffic)
	for region in 3:
		var choice: Dictionary={}
		for house: Dictionary in world.houses.houses:
			if int(house.region)==region:
				choice=house
				if str(house.zone)=="pueblo":break
		if choice.is_empty():continue
		var p: Vector3=choice.position;var forward:=Basis(Vector3.UP,float(choice.yaw))*Vector3.FORWARD
		var focus:=p+Vector3.UP*2
		camera.position=focus-forward*22+Vector3.UP*9;camera.look_at(focus)
		moto.position=p-forward*15;moto.position.y=world.get_height(moto.position.x,moto.position.z)+.3
		if region==0:traffic.setup(world,moto)
		for frame in 18:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/peru_world_region_%d.png"%region)
	if not world.water_system.reaches.is_empty():
		var reach: Dictionary=world.water_system.reaches[0]
		for candidate: Dictionary in world.water_system.reaches:
			if float(candidate.half_width)*(2 if int(candidate.region)==2 else 1)>float(reach.half_width)*(2 if int(reach.region)==2 else 1):reach=candidate
		var p: Vector3=reach.a
		var water:=world.water_system.get_node_or_null("CaucesMayores") as MeshInstance3D
		if water:
			var vertices: PackedVector3Array=water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var nearest:=INF;var wet:=p
			for i in range(0,vertices.size()-2,3):
				var centre: Vector3=(vertices[i]+vertices[i+1]+vertices[i+2])/3.0
				if centre.distance_squared_to(p)<nearest:nearest=centre.distance_squared_to(p);wet=centre
			p=wet
		camera.position=p+Vector3(32,65,35);camera.look_at(p)
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/peru_world_river.png")
	for child in world.road_layout.get_children():
		if not child is PeruBridges or child.spans.is_empty():continue
		var span: Dictionary=child.spans[0]
		for candidate: Dictionary in child.spans:
			if (candidate.a as Vector3).distance_to(candidate.b)>(span.a as Vector3).distance_to(span.b):span=candidate
		var a: Vector3=span.a;var b: Vector3=span.b;var p: Vector3=span.middle
		p.y=maxf(world.get_height(p.x,p.z),float(span.deck_max))
		var side:=(b-a).cross(Vector3.UP).normalized()
		camera.position=p+side*maxf(22,a.distance_to(b)*.7)+Vector3.UP*maxf(12,a.distance_to(b)*.3)
		camera.look_at(p)
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/peru_world_bridge.png")
	quit()
