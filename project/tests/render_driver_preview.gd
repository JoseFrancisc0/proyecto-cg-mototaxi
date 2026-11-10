extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1200,900)
	var stage:=Node3D.new()
	root.add_child(stage)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("283342")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=.7
	stage.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-28,-30,0)
	light.light_energy=1.3
	stage.add_child(light)
	var driver:=DriverAvatar.new()
	stage.add_child(driver)
	driver.setup(2,null,false)
	var camera:=Camera3D.new()
	stage.add_child(camera)
	camera.position=Vector3(.35,1.57,1.1)
	camera.look_at(Vector3(0,1.53,0))
	camera.fov=34
	camera.current=true
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/driver_face.png")
	camera.position=Vector3(1.9,1.2,3.2)
	camera.look_at(Vector3(0,.9,0))
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/driver_full.png")
	driver.queue_free()
	await process_frame
	var moto: Mototaxi=load("res://scenes/mototaxi.tscn").instantiate()
	moto.freeze=true
	moto.use_input=false
	stage.add_child(moto)
	for index in 6:
		moto.select_vehicle(index)
		camera.position=Vector3(2.8,1.9,3.8)
		camera.look_at(Vector3(0,1.1,0))
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/driver_vehicle_%d.png"%index)
	stage.queue_free()
	await process_frame
	var screen: LoadingScreen=load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	screen._show_options()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/driver_options.png")
	screen.queue_free()
	await process_frame
	quit()
