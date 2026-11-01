extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene: PackedScene = load("res://scenes/loading_screen.tscn")
	var screen = scene.instantiate()
	root.add_child(screen)
	await process_frame
	check(screen._music_player.stream.get_length()>100 and screen._music_player.stream.loop,"Pista completa y reproducción en bucle")
	var radio_bus: int = AudioServer.get_bus_index(screen._bus_name)
	check(radio_bus>0 and screen._music_player.bus!=&"Master","La saturación solo se aplica al bus del menú")
	var previous_file: String = screen._custom_music
	screen._load_custom_music(ProjectSettings.globalize_path("res://audio/no_frills_cumbia.mp3"),false)
	check(screen._music_player.stream.get_length()>100,"El selector puede cargar un MP3 local real")
	screen._custom_music=previous_file
	var saved_enabled: bool = screen._music_enabled
	var saved_volume: float = screen._music_volume
	screen._set_music(false,false)
	check(screen._music_player.stream_paused,"La radio puede silenciarse")
	screen._set_music(true,false)
	check(not screen._music_player.stream_paused,"La radio puede reanudarse")
	screen._set_music_volume(.1,false)
	check(is_equal_approx(screen._music_player.volume_db,-20),"El volumen se aplica al reproductor")
	screen._set_music(saved_enabled,false)
	screen._set_music_volume(saved_volume,false)
	var choices: Array = []
	screen.start_requested.connect(func(choice): choices.append(choice))
	screen.show_menu({"mode":"editor","seed":67,"erosion_scale":.1})
	check(not screen._seed_row.visible and not screen._quality_row.visible,"La ruta guardada no ofrece opciones que no se aplican")
	root.size=Vector2i(1440,900)
	screen._mode.select(1)
	screen._mode.item_selected.emit(1)
	for frame in range(8): await process_frame
	screen._open_setup()
	check(screen._dialog.visible and screen._menu.visible,"Jugar abre la configuración en una pantalla aparte")
	screen._mode.select(0)
	screen._mode.item_selected.emit(0)
	screen._on_play()
	screen._on_play()
	check(choices.size()==1 and choices[0].mode=="editor","Arranque único, modo guardado conservado")
	screen.show_menu({"mode":"seed","seed":42,"erosion_scale":.35})
	check(screen._seed_row.visible and screen._quality.selected==1,"Selección de semilla y calidad recuperadas")
	screen._seed_edit.text="abc"
	screen._on_play()
	check(choices.size()==1 and screen._notice.visible,"Semilla inválida no inicia el juego")
	screen._seed_edit.text="2147483648"
	screen._on_play()
	check(choices.size()==1,"Semilla fuera de rango rechazada")
	screen._seed_edit.text="12345"
	screen._on_play()
	check(choices.size()==2 and choices[1].seed==12345 and is_equal_approx(choices[1].erosion_scale,.35),"Semilla y escala originales entregadas a Main")
	screen.show_progress()
	screen.set_progress("Fluvial",.5)
	screen.set_progress("Retargeting",.2)
	check(is_equal_approx(screen._bar.value,50),"El progreso real no retrocede")
	check(not screen._navigation.visible and screen._progress_box.visible,"La carga evita acciones que interrumpan la generación")
	check(screen._music_toggle.is_visible_in_tree(),"El silencio sigue disponible durante la carga")
	check(not screen._hero.visible,"La carga deja el área principal al terreno en vivo")
	screen.set_progress("Listo",3)
	check(is_equal_approx(screen._bar.value,100),"Progreso limitado a 100")
	screen.show_error()
	check(screen._menu.visible and screen._notice.visible and not screen._play.disabled,"Un error devuelve un menú utilizable")
	screen._show_dialog("Ayuda","Controles")
	check(screen._dialog.visible,"Ayuda accesible antes del juego")
	screen._close_dialog()
	check(not screen._dialog.visible,"Ayuda cerrable")
	root.size=Vector2i(720,900)
	screen._responsive()
	check(screen._navigation.vertical and screen._navigation.get_child_count()==5,"La lista original de la plantilla conserva su distribución")
	for viewport_size in [Vector2i(1440,900),Vector2i(960,640),Vector2i(720,900),Vector2i(390,844),Vector2i(640,360)]:
		root.size=viewport_size
		screen.show_menu({"mode":"seed","seed":42})
		for frame in range(5): await process_frame
		for button in screen._navigation.get_children():
			var rect: Rect2 = button.get_global_rect()
			check(rect.position.y>=0 and rect.end.y<=viewport_size.y,"Botones dentro de la ventana %s" % viewport_size)
		screen._open_setup()
		for frame in range(5): await process_frame
		var panel: Rect2 = screen._dialog_panel.get_global_rect()
		check(panel.position.x>=0 and panel.position.y>=0 and panel.end.x<=viewport_size.x and panel.end.y<=viewport_size.y,"Submenú dentro de la ventana %s" % viewport_size)
	get_tree_pause_test(screen)
	var removed_bus: String = screen._bus_name
	screen.queue_free()
	await process_frame
	check(AudioServer.get_bus_index(removed_bus)==-1,"El efecto se retira al terminar el menú")
	print("Interfaz previa: %d errores" % failures)
	quit(0 if failures==0 else 1)
func get_tree_pause_test(screen) -> void:
	paused=true
	check(screen.process_mode==Node.PROCESS_MODE_ALWAYS,"La interfaz funciona mientras el mundo está pausado")
	paused=false
