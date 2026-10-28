extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1440,900)
	var screen = load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	for mode in ["editor","seed"]:
		screen.show_menu({"mode":mode,"seed":96,"erosion_scale":.35})
		for i in range(8): await process_frame
		for node in [screen._root,screen._home,screen._hero,screen._dialog_panel,screen._menu,screen._navigation,screen._play]:
			print(mode," ",node.get_class()," visible=",node.is_visible_in_tree()," rect=",node.get_global_rect()," min=",node.get_combined_minimum_size())
	quit()
