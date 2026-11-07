extends SceneTree
## Capturas del selector de escenario con tarjetas (pendiente 11) y del garaje del Modo libre
## (pendiente 12). Con ventana:  Godot --path project -s res://tests/capture_escenario_ui.gd
## Guarda output/ui_review/escenario_*.png
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
	root.size = Vector2i(1440, 900)
	var screen = load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	screen.show_menu({"mode": "editor", "seed": 67, "erosion_scale": .1, "region": 2})
	screen._open_setup()
	await save_frame("escenario_jugar")
	screen._picker.cards[3].pressed.emit()
	screen._picker.mode.select(1)
	screen._picker.update_mode()
	await save_frame("escenario_nuevo_selva")
	root.size = Vector2i(960, 640)
	await save_frame("escenario_compacto")
	screen.queue_free()
	root.size = Vector2i(1440, 900)
	var panel := ScenarioPanel.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	center.add_child(panel)
	panel.open("Cambiar escenario", "", "Explorar", {"mode": "editor", "region": 1})
	await save_frame("escenario_panel_pausa")
	center.queue_free()
	var pause := PauseMenu.new()
	pause.free_mode = true
	root.add_child(pause)
	pause.open()
	await save_frame("libre_pausa")
	pause.open_garage()
	await save_frame("libre_garaje")
	quit()
