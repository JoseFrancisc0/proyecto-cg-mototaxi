extends SceneTree
## Regresión: un fallo de generación no debe arrancar una partida sin terreno.
class FailedWorld extends TerrainWorld:
	var attempts := 0
	func generate_async(_new_seed: int = -1) -> bool:
		attempts += 1
		return false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	var old_world: Node = main.get_node("TerrainWorld")
	main.remove_child(old_world)
	old_world.free()
	var failed_world := FailedWorld.new()
	failed_world.name = "TerrainWorld"
	failed_world.generate_on_ready = false
	main.add_child(failed_world)
	root.add_child(main)
	await process_frame
	var failures := 0
	var loading = main.loading
	loading._on_play()
	await process_frame
	if failed_world.attempts!=1 or not paused or main.hud.visible:
		failures+=1
		push_error("No debe iniciarse una carrera tras fallar la carga")
	if not loading._menu.visible or not loading._notice.visible:
		failures+=1
		push_error("El fallo debe mostrar el menú con una explicación")
	loading._on_play()
	await process_frame
	if failed_world.attempts!=2:
		failures+=1
		push_error("Debe poder reintentarse la generación")
	paused=false
	main.queue_free()
	await process_frame
	print("Recuperación de carga: %d errores (dos fallos simulados intencionalmente)" % failures)
	quit(0 if failures==0 else 1)
