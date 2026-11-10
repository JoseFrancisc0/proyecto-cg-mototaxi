extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1440,900)
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("a7becb");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;stage.add_child(env)
	var sun:=DirectionalLight3D.new();sun.name="Sun";sun.rotation_degrees=Vector3(-55,-25,0);sun.light_energy=1.05;sun.shadow_enabled=true;stage.add_child(sun)
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.use_editor_scene=false;world.grid_size=256;world.cell_size=6.0;world.erosion_enabled=false;world.vegetation_enabled=true;world.vegetation_density=.65;stage.add_child(world);world.generate(42)
	var camera:=Camera3D.new();camera.current=true;camera.fov=64;camera.far=5000;stage.add_child(camera)
	var moto: Mototaxi=load("res://scenes/mototaxi.tscn").instantiate();moto.freeze=true;moto.use_input=false;stage.add_child(moto)
	var session:=GameSession.new();session.free_mode=true
	var life:=PeruWorldLife.new();stage.add_child(life)
	moto.position=world.get_town_centers()[0]+Vector3.UP;life.setup(world,moto,session);life._time=125;life._process(1);life.set_process(false)
	for region in 3:
		var selected: Dictionary={}
		for house: Dictionary in world.houses.houses:
			if int(house.region)==region and str(house.zone)=="pueblo":selected=house;break
		if selected.is_empty():
			for house: Dictionary in world.houses.houses:
				if int(house.region)==region:selected=house;break
		if selected.is_empty():continue
		var closest:=Vector3.ZERO;var tangent:=Vector3.FORWARD;var distance:=INF
		for road: Dictionary in world.get_roads():
			var path: PackedVector3Array=road.path
			for j in range(1,path.size()):
				var d:=path[j].distance_squared_to(selected.position)
				if d<distance:distance=d;closest=path[j];tangent=(path[j]-path[j-1]).normalized()
		var p:=closest-tangent*8;p.y=world.get_height(p.x,p.z)+3.2
		if world.houses.is_blocked(p.x,p.z,.2):p=closest+Vector3.UP*4
		camera.position=p;camera.look_at(closest+tangent*35+Vector3.UP*3)
		moto.position=closest-tangent*8;moto.position.y=world.get_height(moto.position.x,moto.position.z)+.2
		for frame in 90:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/district_street_%d.png"%region)
	life._time=375;life._clock=1;life._process(.1)
	env.environment.background_color=Color("111d2b")
	if not life.traffic.cars.is_empty():
		var actor: Dictionary=life.traffic.cars[0];var p: Vector3=actor.body.position
		camera.position=p+actor.body.basis*Vector3(8,4,15);camera.look_at(p+Vector3.UP*.8)
		for frame in 15:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/traffic_night.png")
	session.free();quit()
