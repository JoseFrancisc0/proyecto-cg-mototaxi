extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1200,1000)
	var model_path:=ProjectSettings.globalize_path("res://../tmp/driver_pifu/driver.glb")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): model_path=arg.trim_prefix("--model=")
	var stage:=Node3D.new()
	root.add_child(stage)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("26313d")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.65
	stage.add_child(env)
	for yaw in [-25,150]:
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=Vector3(-30,yaw,0)
		light.light_energy=1.0 if yaw==-25 else .5
		stage.add_child(light)
	var driver:=DriverAvatar.new()
	stage.add_child(driver)
	var source:=DriverAvatar.load_avatar(model_path)
	if source==null:
		push_error("No se pudo abrir el modelo reconstruido")
		quit(1)
		return
	driver.setup(0,source,false)
	var camera:=Camera3D.new()
	stage.add_child(camera)
	camera.current=true
	camera.fov=34
	var views:=[Vector3(0,1,3.3),Vector3(2.5,1.1,2.5),Vector3(3.3,1,0),Vector3(0,1,-3.3),Vector3(0,1.6,.85)]
	var names:=["front","three_quarter","side","back","face"]
	for i in views.size():
		camera.position=views[i]
		camera.look_at(Vector3(0,1.58,0) if i==4 else Vector3(0,.9,0))
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/rebuilt_driver_%s.png"%names[i])
	driver.queue_free()
	await process_frame
	var moto: Mototaxi=load("res://scenes/mototaxi.tscn").instantiate()
	moto.freeze=true
	moto.use_input=false
	stage.add_child(moto)
	moto.select_vehicle(0)
	if moto.driver:
		moto.remove_child(moto.driver)
		moto.driver.queue_free()
	var seated:=DriverAvatar.new()
	moto.add_child(seated)
	seated.setup(0,DriverAvatar.load_avatar(model_path),true)
	camera.position=Vector3(2.6,1.8,3.9)
	camera.look_at(Vector3(0,1.1,0))
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/rebuilt_driver_seated.png")
	stage.queue_free()
	await process_frame
	quit()
