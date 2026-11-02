extends SceneTree
## Captura del menú de pausa en el juego real (terreno del editor).
##   Godot --path project -s res://tests/capture_pause_menu.gd -- --editor   (con ventana)
## Guarda output/pause_menu.png

func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	current_scene = main
	while main.pause_menu == null:
		await process_frame
	for i in 60:
		await process_frame
	main.pause()
	for i in 5:
		await process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../output").simplify_path()
	root.get_texture().get_image().save_png(dir.path_join("pause_menu.png"))
	quit()
