extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1280,900)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();stage.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b6c5cd")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.30
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=.72;stage.add_child(sun)
	var camera:=Camera3D.new();camera.current=true;stage.add_child(camera);camera.fov=38
	for key in PeruTraffic.FLEET:
		var model: Node3D=load("res://assets/traffic/%s.glb"%key).instantiate();stage.add_child(model)
		var bounds:=Passenger.HeadModel.bounds(model);var center:=bounds.get_center()
		camera.position=center+Vector3(2.5,1.5,3.4)*maxf(bounds.size.z,2)*.48;camera.look_at(center)
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/peru_traffic_%s.png"%key)
		model.queue_free();await process_frame
	for index in TerrainHouses.MODELS.size():
		var item: Dictionary=TerrainHouses.MODELS[index]
		var model: Node3D=load(TerrainHouses.DIR+item.file).instantiate();stage.add_child(model)
		var bounds:=Passenger.HeadModel.bounds(model);var center:=bounds.get_center()
		camera.position=center+Vector3(1.15,.72,1.8)*maxf(bounds.size.y,bounds.size.x);camera.look_at(center)
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/peru_house_%02d.png"%index)
		model.queue_free();await process_frame
	for region in 3:
		for variant in 2:
			var person:=PeruPersonVisual.new();stage.add_child(person);person.setup(region,variant);person.set_process(false)
			camera.position=Vector3(1.2,1,3.4);camera.look_at(Vector3(0,.9,0))
			for frame in 6:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../output/peru_person_%d_%d.png"%[region,variant])
			person.queue_free();await process_frame
	quit()
