extends SceneTree
## Pasajero visible en el juego real (terreno del editor):
## espera junto a la vía, saluda al acercarse la mototaxi, sube y baja.
##   Godot --headless --fixed-fps 60 --path project -s res://tests/test_passenger.gd
## Con ventana (sin --headless) además guarda capturas en output/passengers/.

var errors := 0
var main: Node
var shots := DisplayServer.get_name() != "headless"


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		errors += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(file: String, cam_from: Vector3, look: Vector3) -> void:
	if not shots:
		return
	var cam: Camera3D = main.cam
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.look_at_from_position(cam_from, look, Vector3.UP)
	for i in 6:
		await process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/passengers").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(file))
	cam.set_process(true)
	cam.set_physics_process(true)


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var race: RaceManager = main.race
	var moto: Mototaxi = main.moto
	var world: TerrainWorld = main.world
	var p := race.passenger
	moto.use_input = false
	await _frames(30)

	print("-- Espera")
	_check(p != null and p.visible and p.mode == Passenger.Mode.WAITING, "hay un pasajero esperando")
	var gp := p.global_position
	_check(absf(gp.y - world.get_height(gp.x, gp.z)) < 0.05, "está parado sobre el suelo")
	_check(race.pickup_zone.global_position.distance_to(gp) < race.zone_radius, "está dentro de la zona de recogida")
	_check(race.pickup_zone.global_position.distance_to(gp) > 1.5, "a un costado de la vía, no en el centro")
	_check(p.model_index >= 0, "modelo %s" % Passenger.MODELS[p.model_index])

	# La mototaxi se acerca hasta ~12 m por la ruta y se detiene.
	var pick := race.pickup_zone.global_position
	var approach := pick + (moto.global_position - pick).normalized() * 12.0
	moto.place_at(Vector3(approach.x, world.get_height(approach.x, approach.z), approach.z), atan2(pick.x - approach.x, pick.z - approach.z))
	await _frames(20)
	_check(p._anim.current_animation.ends_with("Wave"), "hace señas al acercarse (%s)" % p._anim.current_animation)
	var to_moto := moto.global_position - p.global_position
	var facing := Vector3(sin(p.rotation.y), 0, cos(p.rotation.y))
	_check(facing.dot(Vector3(to_moto.x, 0, to_moto.z).normalized()) > 0.8, "mira a la mototaxi")
	await _shot("1_espera_y_saluda.png", moto.global_position + (moto.global_position - pick).normalized() * 5.0 + Vector3.UP * 2.5, p.global_position + Vector3.UP)

	var waiting_model := p.model_index
	print("-- Sube")
	moto.place_at(Vector3(pick.x, world.get_height(pick.x, pick.z), pick.z), moto.rotation.y)
	await _frames(10)
	_check(race.state == RaceManager.State.CON_PASAJERO, "la carrera empieza al detenerse en la zona")
	_check(p.mode == Passenger.Mode.BOARDING or p.mode == Passenger.Mode.HIDDEN, "camina hacia la mototaxi")
	await _frames(int(p.board_time * 60) + 10)
	_check(not p.visible, "ya subió (oculto)")

	print("-- Baja")
	race.mood = 0.9
	var drop := race.dropoff_zone.global_position
	moto.place_at(Vector3(drop.x, world.get_height(drop.x, drop.z), drop.z), 0.0)
	await _frames(10)
	_check(race.state == RaceManager.State.ENTREGADO, "entregado al llegar al destino")
	_check(p.visible and p.mode == Passenger.Mode.GETTING_OFF, "baja de la mototaxi")
	_check(p._anim.current_animation.ends_with("Interact"), "contento: paga (%s)" % p._anim.current_animation)
	_check(p.global_position.distance_to(moto.global_position) < 3.0, "aparece junto a la mototaxi")
	_check(p.model_index == waiting_model, "baja la misma persona que subió (%s)" % Passenger.MODELS[p.model_index])
	await _shot("2_baja_y_paga.png", moto.global_position + (-moto.global_basis.x * 6.0) + moto.global_basis.z * 3.0 + Vector3.UP * 2.0, p.global_position + Vector3.UP)
	var start := p.global_position
	await _frames(int(2.5 * 60))
	_check(p.mode == Passenger.Mode.LEAVING and p.global_position.distance_to(start) > 0.5, "se va caminando")
	await _frames(int(p.leave_time * 60) + 30)
	_check(not is_instance_valid(p), "desaparece al alejarse")
	var nxt := race.passenger
	_check(is_instance_valid(nxt) and nxt.visible and nxt.mode == Passenger.Mode.WAITING, "el siguiente pasajero es otra persona y ya espera")
	p = nxt

	print("-- Fin de partida")
	race.stop()
	_check(not p.visible, "sin pasajero al terminar la partida")

	print("RESULTADO: " + ("OK" if errors == 0 else "%d fallas" % errors))
	quit(1 if errors else 0)
