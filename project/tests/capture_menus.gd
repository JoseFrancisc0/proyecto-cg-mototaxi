extends SceneTree
## Capturas del menú principal con partida guardada ("Continuar" y "Nueva partida"), del panel
## "Reiniciar partida" de la pausa y del garaje en la pausa de la carrera, en 1440x900 y 1280x720.
##   Godot --path project -s res://tests/capture_menus.gd   (con ventana; usa el archivo de prueba)
## Guarda output/ui_review/menus_*.png
func _initialize() -> void:
	_capture.call_deferred()


func save_frame(path: String) -> void:
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://../output/ui_review").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(path + ".png"))


func _capture() -> void:
	CareerSave.reset()
	CareerSave.save_game({"day": 3, "choice": {"mode": "editor"}})
	CareerSave.add_savings(12.5)
	for sz in [Vector2i(1440, 900), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		var tag := "%dx%d" % [sz.x, sz.y]
		var screen = load("res://scenes/loading_screen.tscn").instantiate()
		root.add_child(screen)
		screen.show_menu({"mode": "editor", "seed": 67, "erosion_scale": .1})
		await save_frame("menus_portada_" + tag)
		screen._open_setup()
		await save_frame("menus_nueva_partida_" + tag)
		screen.queue_free()
		var pause := PauseMenu.new()
		pause.current_choice = {"mode": "editor", "region": 0}
		root.add_child(pause)
		pause.open()
		await save_frame("menus_pausa_" + tag)
		pause.open_scenario()
		await save_frame("menus_reiniciar_" + tag)
		pause.close()
		pause.open()
		pause.open_garage()
		await save_frame("menus_garaje_" + tag)
		pause.queue_free()
	CareerSave.reset()
	quit()
