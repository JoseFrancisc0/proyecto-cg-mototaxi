extends SceneTree
func _initialize() -> void:
	_capture.call_deferred()
func _capture() -> void:
	root.size = Vector2i(1440,900)
	var screen = load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	screen.show_menu({"mode":"editor","seed":67})
	screen._open_setup()
	for i in 6:
		screen._garage.select_vehicle(i)
		for f in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/garage_%d.png" % i)
	root.size = Vector2i(390,844)
	for f in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/garage_mobile.png")
	print("Garage capturado")
	quit()
