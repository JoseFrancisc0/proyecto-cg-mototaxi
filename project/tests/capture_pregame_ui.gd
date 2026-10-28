extends SceneTree
func _initialize() -> void:
	_capture.call_deferred()
func save_frame(path: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/ui_review/"+path+".png")
func _capture() -> void:
	root.size=Vector2i(1440,900)
	var screen=load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	screen.show_menu({"mode":"editor","seed":67,"erosion_scale":.1})
	await save_frame("menu")
	screen.show_menu({"mode":"seed","seed":142857,"erosion_scale":.35})
	screen._open_setup()
	await save_frame("new_route")
	screen._help.pressed.emit()
	await save_frame("controls")
	screen._show_options()
	await save_frame("options")
	screen._close_dialog()
	screen.show_progress()
	screen.set_progress("Fluvial",.42)
	await save_frame("loading")
	screen.show_error()
	await save_frame("error")
	for entry in [[960,640,"compact"],[390,844,"mobile"],[640,360,"short"]]:
		root.size=Vector2i(entry[0],entry[1])
		screen.show_menu({"mode":"seed","seed":142857,"erosion_scale":.1})
		await save_frame(entry[2])
		screen._open_setup()
		await save_frame(entry[2]+"_setup")
	print("Capturas guardadas")
	screen.queue_free()
	await process_frame
	quit()
