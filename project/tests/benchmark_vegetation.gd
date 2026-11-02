extends SceneTree
## FPS y triángulos dibujados con la vegetación, en el juego real (terreno del editor).
##   Godot --path project -s res://tests/benchmark_vegetation.gd -- --editor   (con ventana)
## Mide desde la mototaxi en 3 puntos de vista (al inicio y girando) y guarda una captura.

func _measure(label: String, seconds := 4.0) -> void:
	for i in 30:
		await process_frame
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t0
	while Time.get_ticks_usec() - t0 < seconds * 1_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	var fps := frames / ((Time.get_ticks_usec() - t0) / 1_000_000.0)
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("%s: %.0f FPS (peor cuadro %.0f ms), %.1f M triángulos, %d draw calls" % [label, fps, worst, tris / 1e6, calls])


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var moto: Mototaxi = main.moto
	moto.use_input = false
	main.race.stop()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	if "--nocol" in args:
		for n in root.find_children("Troncos", "TreeColliders", true, false):
			n.queue_free()
	if "--nodiscard" in args:
		for m in VegetationModels.materials():
			m.set_shader_parameter("alpha_cut", 0.0)
	if "--half" in args:
		root.scaling_3d_scale = 0.5
	if "--noveg" in args:
		for n in root.find_children("Vegetacion", "", true, false):
			n.visible = false
	await _measure("vista 1")
	for k in 2:
		moto.place_at(moto.global_position, moto.rotation.y + PI * 0.66)
		await _measure("vista %d" % (k + 2))
	var dir := ProjectSettings.globalize_path("res://").path_join("../output").simplify_path()
	root.get_texture().get_image().save_png(dir.path_join("benchmark_vegetacion.png"))
	quit()
