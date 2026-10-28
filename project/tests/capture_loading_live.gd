extends SceneTree
var _done := false
var _ok := false
func _initialize() -> void:
	_run.call_deferred()
func _generate(world: TerrainWorld) -> void:
	_ok = await world.generate_async(96)
	_done = true
func _run() -> void:
	root.size = Vector2i(1440,900)
	var screen = load("res://scenes/loading_screen.tscn").instantiate()
	root.add_child(screen)
	screen.show_menu({"mode":"seed","seed":96,"erosion_scale":.1})
	var world := TerrainWorld.new()
	world.generate_on_ready=false
	world.use_editor_scene=false
	world.grid_size=256
	world.cell_size=6
	world.erosion_levels=1
	world.erosion_fluvial=600
	world.erosion_thermal=100
	world.erosion_deposition=250
	world.erosion_scale=.1
	world.preview_size=768
	world.vegetation_enabled=false
	root.add_child(world)
	screen.world=world
	world.progress.connect(screen.set_progress)
	screen.show_progress()
	var previous := -1
	var first := false
	var latest := false
	var hashes := {}
	_generate.call_deferred(world)
	var deadline := Time.get_ticks_msec()+90000
	while not _done and Time.get_ticks_msec()<deadline:
		await process_frame
		if screen._preview_updates>0 and screen._preview_serial!=previous:
			previous=screen._preview_serial
			hashes[hash(screen._preview.texture.get_image().get_data())]=true
			await RenderingServer.frame_post_draw
			var path := "loading_live_first" if not first else "loading_live"
			root.get_texture().get_image().save_png("res://../output/ui_review/"+path+".png")
			if first: latest=true
			first=true
	var failures := 0
	if not _ok or not latest or hashes.size()<2 or screen._preview.texture==null:
		failures+=1
		push_error("Deben verse varias capturas distintas del terreno real mientras se genera")
	if not screen._music_player.playing:
		failures+=1
		push_error("La música debe continuar durante la carga")
	print("Carga real en vivo: %d errores; %d imágenes distintas; %d actualizaciones; %d px" % [failures,hashes.size(),screen._preview_updates,world.preview_size])
	screen.queue_free()
	world.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
