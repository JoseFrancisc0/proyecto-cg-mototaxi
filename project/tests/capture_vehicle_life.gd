extends SceneTree
func _initialize() -> void: capture.call_deferred()
func capture() -> void:
	root.size=Vector2i(1440,900)
	var screen=load('res://scenes/loading_screen.tscn').instantiate()
	root.add_child(screen)
	screen.show_menu({'mode':'editor','seed':67})
	screen._open_setup()
	for i in 6:
		screen._garage.select_vehicle(i)
		screen._garage._yaw=-.55
		var visuals:=VehicleWheelVisuals.new()
		visuals.bind_model(screen._garage._model_root.get_child(0))
		visuals.update_wheels(.2,2.0,.45)
		for f in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png('res://../output/wheel_life_%d.png'%i)
	print('Animaciones capturadas')
	quit()
