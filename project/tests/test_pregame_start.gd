extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	var world = main.get_node("TerrainWorld")
	world.generate_on_ready = false
	world.use_editor_scene = false
	world.grid_size = 128
	world.cell_size = 6.0
	world.erosion_enabled = false
	world.vegetation_enabled = false
	root.add_child(main)
	await process_frame
	main.loading._seed_edit.text = "31415"
	main.loading._on_play()
	var deadline := Time.get_ticks_msec()+45000
	while not world.is_generated() and Time.get_ticks_msec()<deadline:
		await create_timer(.05,true).timeout
		if is_instance_valid(main.loading) and main.loading._notice.visible: break
	var failures := 0
	if not world.is_generated() or paused or not main.hud.visible or world.world_seed!=31415:
		failures+=1
		push_error("El menú debe entregar una nueva ruta real y entrar a la partida")
	await create_timer(.5,true).timeout
	if is_instance_valid(main.loading):
		failures+=1
		push_error("La pantalla de carga debe desaparecer al entrar al juego")
	paused=false
	main.queue_free()
	await process_frame
	print("Inicio real desde menú: %d errores" % failures)
	quit(0 if failures==0 else 1)
