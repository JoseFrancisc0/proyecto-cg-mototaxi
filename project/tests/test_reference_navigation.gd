extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	GameSettings.path="user://test_reference_navigation.cfg"
	root.size=Vector2i(1280,800)
	var main: Node=load("res://main.tscn").instantiate();root.add_child(main);current_scene=main
	for frame in 20:await process_frame
	var returned:=_menu_is_ready()
	for file in ["reference_neighborhood_viewer","house_study_viewer"]:
		if not returned:break
		if change_scene_to_file("res://scenes/%s.tscn"%file)!=OK:
			returned=false
			break
		await scene_changed
		current_scene._back()
		await scene_changed
		for frame in 15:await process_frame
		returned=_menu_is_ready()
	print("REFERENCE_NAVIGATION_RESULT ",0 if returned else 1)
	quit(0 if returned else 1)

func _menu_is_ready() -> bool:
	return current_scene!=null and current_scene.find_child("GarageButton",true,false)!=null \
		and current_scene.find_child("ReferenceNeighborhoodsButton",true,false)==null \
		and current_scene.find_child("HouseStudyButton",true,false)==null
