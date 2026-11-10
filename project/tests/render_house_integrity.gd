extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1440,900)
	var output:="res://../output/house_integrity"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer: Control=load("res://scenes/house_study_viewer.tscn").instantiate();root.add_child(viewer)
	var views: Array=[["frente",0.0,.08],["izquierda",-PI*.5,.12],["derecha",PI*.5,.12],["atras",PI,.12],["arriba",.6,1.1]]
	for index in viewer._entries.size():
		viewer._select(index)
		var key: String=viewer._entries[index].key
		for view: Array in views:
			viewer._set_view(float(view[1]),float(view[2]))
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			viewer._viewport.get_texture().get_image().save_png(output+"/"+key+"_"+str(view[0])+".png")
		if str(viewer._entries[index].model.style) in ["casa_moderna","andina_actual","tropical_actual"]:
			viewer._yaw=.45;viewer._pitch=.18;viewer._update_camera()
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/comparacion_"+key+".png")
		print("HOUSE_REVIEW_CAPTURE ",key)
	print("HOUSE_REVIEW_RESULT 0");quit()
