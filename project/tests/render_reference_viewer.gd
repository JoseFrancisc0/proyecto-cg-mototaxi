extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1440,900)
	var viewer: Control=load("res://scenes/reference_neighborhood_viewer.tscn").instantiate();root.add_child(viewer)
	var failures:=0
	for key: String in ["0_ladera","0_residencial","0_moderna","1_residencial","1_ladera","2_residencial","2_moderna","urban_bus"]:
		var index:=0
		for j in viewer._entries.size():
			if str(viewer._entries[j].key)==key:index=j;break
		viewer._select(index)
		for frame in 10:await process_frame
		await RenderingServer.frame_post_draw
		if viewer._photo.texture==null or viewer._block==null:failures+=1
		var old_radius: float=viewer._radius
		var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
		viewer._orbit_input(wheel)
		if viewer._radius<=old_radius:failures+=1
		viewer._radius=old_radius;viewer._update_camera()
		for frame in 2:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/comparacion/visor_%s.png"%key)
		print("REFERENCE_VIEWER_CAPTURE ",key)
	print("REFERENCE_VIEWER_RESULT ",failures)
	quit(failures)
