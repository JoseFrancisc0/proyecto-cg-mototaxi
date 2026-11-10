extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	GameSettings.path="user://test_reference_navigation.cfg"
	root.size=Vector2i(1280,800)
	var main: Node=load("res://main.tscn").instantiate();root.add_child(main);current_scene=main
	for frame in 20:await process_frame
	var button:=main.find_child("ReferenceNeighborhoodsButton",true,false) as Button
	if button==null:
		print("REFERENCE_NAVIGATION_RESULT missing menu button");quit(1);return
	button.pressed.emit()
	for frame in 15:await process_frame
	var viewer:=current_scene
	if viewer==null or viewer.name!="CompararBarrios":
		print("REFERENCE_NAVIGATION_RESULT viewer did not open");quit(1);return
	viewer._back()
	for frame in 15:await process_frame
	var returned:=current_scene!=null and current_scene.find_child("ReferenceNeighborhoodsButton",true,false)!=null
	print("REFERENCE_NAVIGATION_RESULT ",0 if returned else 1)
	quit(0 if returned else 1)
