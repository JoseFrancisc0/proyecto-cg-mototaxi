extends SceneTree
func _initialize() -> void: capture.call_deferred()
func capture() -> void:
	root.size=Vector2i(1440,900)
	var main=load('res://main.tscn').instantiate()
	var world=main.get_node('TerrainWorld')
	world.generate_on_ready=false
	world.use_editor_scene=false
	world.grid_size=128
	world.cell_size=6.0
	world.erosion_enabled=false
	world.vegetation_enabled=false
	root.add_child(main)
	await process_frame
	main.loading._seed_edit.text='31415'
	main.loading._garage.select_vehicle(5)
	main.loading._on_play()
	var deadline=Time.get_ticks_msec()+45000
	while not world.is_generated() and Time.get_ticks_msec()<deadline: await process_frame
	main.moto.use_input=false
	for f in 100: await process_frame
	for i in [0,5]:
		main.moto.select_vehicle(i)
		main.cam.snap()
		for f in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png('res://../output/vehicle_scale_game_%d.png'%i)
	print('Escala en partida capturada')
	quit()
