extends SceneTree
## Prueba sin ventana de la dificultad de la partida (pendiente 13, fase A):
##   Godot_console.exe --headless --path project -s res://tests/test_dificultad.gd
## Tabla de Difficulty, tiempo y tarifa en RaceManager, el selector de escenario (dificultad
## bloqueada al cambiar de escenario dentro de la partida) y Main en Difícil sobre el terreno
## guardado: obstáculos, tiempo, pago y que se guarde con la partida.

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CareerSave.path = "user://test_dificultad.cfg"
	print("-- Tabla")
	_check(Difficulty.of({}) == Difficulty.NORMAL, "sin dificultad (partidas viejas) = Normal")
	_check(Difficulty.of({"difficulty": 9}) == Difficulty.DIFICIL, "fuera de rango se recorta")
	var obstacles := []
	var fares := []
	for i in Difficulty.LEVELS.size():
		obstacles.append(Difficulty.get_value(i, "obstacles"))
		fares.append(Difficulty.get_value(i, "fare"))
	_check(obstacles == [1, 2, 3], "obstáculos: pocos, normal, muchos")
	_check(fares[0] < fares[1] and fares[1] < fares[2], "más difícil, mejor pagado")
	_check(Difficulty.get_value(Difficulty.FACIL, "time") > 1.0 and is_equal_approx(Difficulty.get_value(Difficulty.DIFICIL, "time"), 1.0),
		"Fácil da más tiempo; Difícil no lo recorta")

	print("-- RaceManager")
	var race := RaceManager.new()
	var t0 := race.compute_time_limit(250.0)
	var f0 := race.compute_fare(1000.0)
	race.time_factor = 1.2
	race.fare_factor = 1.25
	_check(is_equal_approx(race.compute_time_limit(250.0), t0 * 1.2), "tiempo × 1.2")
	_check(is_equal_approx(race.compute_route_time(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 250)])), t0 * 1.2),
		"tiempo por la ruta × 1.2")
	_check(is_equal_approx(race.compute_fare(1000.0), f0 * 1.25), "tarifa × 1.25")
	race.free()

	print("-- Selector de escenario")
	var picker := ScenarioPicker.new()
	root.add_child(picker)
	picker.set_choice({"mode": "editor", "region": 1, "difficulty": 2})
	_check(picker.get_choice()["difficulty"] == 2, "lee y devuelve la dificultad")
	picker.lock_difficulty(true)
	_check(picker.difficulty.disabled, "bloqueada al seguir la partida")
	_check(picker.difficulty_note.text.contains("partida nueva"), "avisa cómo cambiarla")
	picker.lock_difficulty(false)
	_check(not picker.difficulty.disabled, "se puede elegir al empezar")
	var a := {"mode": "editor", "region": 1, "difficulty": 1}
	var b := {"mode": "editor", "region": 1, "difficulty": 2}
	_check(not ScenarioPicker.same(a, b), "otra dificultad = otro escenario (se regenera)")
	_check(ScenarioPicker.same(a, {"mode": "editor", "region": 1}), "Normal = sin dificultad")
	_check(ScenarioPicker.describe(b).ends_with("Difícil"), "el resumen la muestra: " + ScenarioPicker.describe(b))
	picker.queue_free()

	print("-- Main en Difícil (terreno guardado)")
	CareerSave.reset()
	CareerSave.launch = {"mode": "editor", "seed": 67, "erosion_scale": 0.1, "difficulty": Difficulty.DIFICIL}
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var t := Time.get_ticks_msec()
	while (main.session == null or not main.hud.visible) and Time.get_ticks_msec() - t < 120000:
		await process_frame
	_check(main.session != null, "la partida arranca")
	if main.session != null:
		_check(main.world.obstacle_level == 3, "obstáculos: Muchos")
		_check(is_equal_approx(main.race.fare_factor, 1.25) and is_equal_approx(main.race.time_factor, 1.0),
			"tarifa × 1.25, tiempo × 1.0")
		var data: Dictionary = main.save_game()
		_check(int(data["choice"].get("difficulty", -1)) == Difficulty.DIFICIL, "se guarda con la partida")
		_check(Difficulty.of(CareerSave.load_game().get("choice", {})) == Difficulty.DIFICIL, "y se lee de la partida guardada")
	CareerSave.reset()

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
