extends Node3D
## Escena principal: menu con semilla y pantalla de carga (S13), genera el terreno en otro
## hilo, coloca la mototaxi sobre un camino, la sigue con la cámara y arranca el ciclo de
## carrera (recoger y entregar pasajeros).
##
## Sin menú (pruebas o atajos): ejecutar con "-- --seed=123" (mundo nuevo desde la semilla)
## o "-- --editor" (terreno guardado en terrain_demo.tscn). "--erosion=0.35" cambia la erosión.
## "--region=costa|sierra|selva" elige la región (mayoría en un mundo nuevo, y donde se empieza)
## y "--solo" deja solo esa región.
##
## La partida es una serie de jornadas con cuota (GameSession): si se junta la cuota, lo que
## sobra va a los ahorros del garaje y sigue el día siguiente; termina si no se junta, por
## vida, por salir del mapa o por quedar atrapada. La pantalla final permite reintentar en el
## mismo mapa. M (o Back del mando) abre el mapa completo (FullMap) y pausa el juego.
## Durante la partida, Esc / P / Start abre el menú de pausa (PauseMenu): continuar,
## reiniciar el turno o volver al menú principal sin tener que perder.

const REGION_NAMES := ["mixta", "costa", "sierra", "selva"]

## Muestra el menú de inicio (semilla y tipo de mundo) antes de generar.
@export var show_menu := true

@onready var world: TerrainWorld = $TerrainWorld
@onready var moto: Mototaxi = $Mototaxi
@onready var cam: ChaseCamera = $ChaseCamera
@onready var race: RaceManager = $RaceManager
@onready var hud: RaceHUD = $HUD

var loading: LoadingScreen
var session: GameSession
var game_over_screen: GameOverScreen
var pause_menu: PauseMenu
var full_map: FullMap
## Región elegida: 0 = mixta, 1 = costa, 2 = sierra, 3 = selva.
var region := 0


func _ready() -> void:
	# Mientras se genera el mundo, el juego queda en pausa (la pantalla de carga sigue viva).
	process_mode = Node.PROCESS_MODE_ALWAYS
	moto.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.visible = false
	get_tree().paused = true
	loading = preload("res://scenes/loading_screen.tscn").instantiate()
	loading.world = world
	add_child(loading)

	var choice := {"mode": "editor" if world.use_editor_scene else "seed", "seed": world.world_seed, "erosion_scale": world.erosion_scale}
	if not _choice_from_args(choice) and show_menu:
		loading.show_menu(choice)
		choice = await loading.start_requested
	world.progress.connect(loading.set_progress)
	while true:
		world.use_editor_scene = choice["mode"] == "editor"
		world.erosion_scale = choice["erosion_scale"]
		region = int(choice.get("region", 0))
		_apply_region_bias(region, bool(choice.get("region_only", false)))
		world.preview_size = 768
		loading.show_progress()
		var t0 := Time.get_ticks_msec()
		var ok: bool = await world.generate_async(-1 if world.use_editor_scene else int(choice["seed"]))
		if ok and world.is_generated():
			moto.select_vehicle(int(choice.get("vehicle", 2)))
			print("Mundo listo en %.1f s (%s)" % [(Time.get_ticks_msec() - t0) / 1000.0, "terreno del editor" if world.use_editor_scene else "semilla %d" % world.world_seed])
			_start_game()
			break
		push_error("No se pudo generar el mundo.")
		loading.show_error()
		choice = await loading.start_requested



## Lee --seed=N, --editor y --erosion=F de los argumentos de usuario. true si hay alguno.
func _choice_from_args(choice: Dictionary) -> bool:
	var found := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			choice["mode"] = "seed"
			choice["seed"] = int(arg.get_slice("=", 1))
			found = true
		elif arg == "--editor":
			choice["mode"] = "editor"
			found = true
		elif arg.begins_with("--erosion="):
			choice["erosion_scale"] = clampf(float(arg.get_slice("=", 1)), 0.01, 1.0)
		elif arg.begins_with("--region="):
			choice["region"] = maxi(REGION_NAMES.find(arg.get_slice("=", 1)), 0)
		elif arg == "--solo":
			choice["region_only"] = true
	return found


## En un mundo nuevo, la región elegida ocupa la mayoría del mapa (o todo con only).
## El terreno guardado ya tiene sus regiones: ahí la región solo decide dónde se empieza.
func _apply_region_bias(r: int, only: bool) -> void:
	world.generator_overrides.erase("biome_bias")
	if r <= 0 or world.use_editor_scene:
		return
	var bias := Vector3.ZERO if only else Vector3(0.1, 0.1, 0.1)
	bias[r - 1] = 0.8 if not only else 1.0
	world.generator_overrides["biome_bias"] = bias


func _start_game() -> void:
	_align_sun()
	moto.terrain = world
	cam.terrain = world
	cam.target = moto
	moto.was_reset.connect(cam.snap)
	spawn()

	race.world = world
	race.moto = moto
	hud.bind(race, moto)
	hud.visible = true

	session = GameSession.new()
	session.name = "GameSession"
	session.world = world
	session.moto = moto
	session.race = race
	add_child(session)
	session.game_over.connect(_on_game_over)
	session.day_completed.connect(_on_day_completed)
	hud.bind_session(session)
	game_over_screen = GameOverScreen.new()
	add_child(game_over_screen)
	game_over_screen.retry_requested.connect(restart)
	game_over_screen.menu_requested.connect(_back_to_menu)
	game_over_screen.next_day_requested.connect(next_day)
	full_map = FullMap.new()
	full_map.name = "FullMap"
	full_map.minimap = hud.minimap
	full_map.race = race
	full_map.moto = moto
	add_child(full_map)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.resume_requested.connect(resume)
	pause_menu.restart_requested.connect(restart)
	pause_menu.menu_requested.connect(_back_to_menu)
	# Main sigue activo en pausa (pantalla de carga, menús); la partida en sí se detiene:
	# así la pausa congela también el reloj del pasajero y los avisos de la sesión.
	for n: Node in [race, session, cam]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE

	race.start()
	_face_route()
	session.start()
	get_tree().paused = false
	loading.finish()


## Nueva partida en el mismo mapa: vida llena, de vuelta al inicio, marcador en cero.
func restart() -> void:
	game_over_screen.hide_result()
	pause_menu.close()
	hud.visible = true
	hud.reset_view()
	moto.repair()
	moto.use_input = true
	spawn()
	race.start()
	_face_route()
	session.start()
	get_tree().paused = false


## Jornada siguiente en el mismo mapa: mototaxi reparada, cuota más alta.
func next_day() -> void:
	game_over_screen.hide_result()
	hud.visible = true
	hud.reset_view()
	moto.repair()
	moto.use_input = true
	spawn()
	race.start()
	_face_route()
	session.next_day()
	get_tree().paused = false
	hud.show_banner("DÍA %d" % session.day, "Cuota de hoy: S/ %.2f" % session.quota, Color(1.0, 0.85, 0.25))


## Gira la mototaxi (en su lugar) hacia donde sale la ruta al primer pasajero.
func _face_route() -> void:
	var ahead := race.route_line.point_ahead(12.0)
	var p := moto.global_position
	var d := ahead - p
	if ahead == Vector3.INF or Vector2(d.x, d.z).length() < 1.0:
		return
	moto.place_at(Vector3(p.x, world.get_height(p.x, p.z), p.z), atan2(d.x, d.z))
	cam.snap()


func _unhandled_input(event: InputEvent) -> void:
	if full_map and full_map.visible and (event.is_action_pressed(FullMap.ACTION) or event.is_action_pressed(PauseMenu.ACTION)):
		full_map.close()
		get_tree().paused = false
		get_viewport().set_input_as_handled()
		return
	if full_map and event.is_action_pressed(FullMap.ACTION) and not get_tree().paused and not game_over_screen.visible and session and session.playing:
		get_tree().paused = true
		full_map.route_color = hud.minimap.route_color
		full_map.open()
		get_viewport().set_input_as_handled()
		return
	if pause_menu == null or not event.is_action_pressed(PauseMenu.ACTION):
		return
	if pause_menu.visible:
		resume()
	elif not game_over_screen.visible and not get_tree().paused:
		pause()
	get_viewport().set_input_as_handled()


func pause() -> void:
	get_tree().paused = true
	pause_menu.open()


func resume() -> void:
	pause_menu.close()
	get_tree().paused = false


func _on_game_over(reason: String, stats: Dictionary) -> void:
	print("Fin de partida: %s %s" % [reason, stats])
	get_tree().paused = true
	hud.visible = false
	game_over_screen.show_result(reason, stats)


func _on_day_completed(stats: Dictionary) -> void:
	print("Día completo: %s" % stats)
	get_tree().paused = true
	hud.visible = false
	game_over_screen.show_day_complete(stats)


func _back_to_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## Aparece en un landmark de la zona transitable más grande (donde hay más pasajeros
## alcanzables), orientada a lo largo de la ruta hacia otro landmark de esa zona.
## Con una región elegida, la zona y el landmark son los de esa región.
func spawn() -> void:
	var landmarks := world.get_landmarks()
	var pos := Vector3(0.0, world.get_height(0.0, 0.0), 0.0)
	var yaw := 0.0
	var weight := func(lm: Dictionary) -> float:
		return 1.0 if region <= 0 else world.get_biome(lm["position"].x, lm["position"].z)[region - 1]
	var zone := _largest_zone(landmarks, weight)
	var in_zone := landmarks.filter(func(lm): return lm["reach"] == zone)
	if region > 0:  # El más típico de la región primero.
		in_zone.sort_custom(func(a, b): return weight.call(a) > weight.call(b))
	if in_zone.size() >= 2:
		pos = in_zone[0]["position"]
		var route := world.find_road_route(pos, in_zone[1]["position"])
		if route.size() > 4:
			var dir := route[4] - pos
			yaw = atan2(dir.x, dir.z)
	elif in_zone.size() == 1:
		pos = in_zone[0]["position"]
	moto.place_at(pos, yaw)
	cam.snap()


## Zona transitable con más landmarks; con una región, cuenta solo los de esa región
## (peso > 0.5). Si la región no tiene landmarks, vale el peso más alto que haya.
func _largest_zone(landmarks: Array[Dictionary], weight: Callable) -> int:
	var counts := {}
	var best_w := -1.0
	var best_w_zone := -1
	for lm in landmarks:
		if lm["reach"] < 0:
			continue
		var w: float = weight.call(lm)
		if w > best_w:
			best_w = w
			best_w_zone = lm["reach"]
		if w > 0.5:
			counts[lm["reach"]] = counts.get(lm["reach"], 0) + 1
	if counts.is_empty():
		return best_w_zone
	var best := -1
	for z in counts:
		if best < 0 or counts[z] > counts[best]:
			best = z
	return best


## El shader del terreno calcula su propia luz con el sol de CG (sun_azimuth/elevation);
## se orienta la luz de la escena igual para que las sombras de la mototaxi coincidan.
func _align_sun() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null or world.generator == null:
		return
	var to_sun: Vector3 = world.generator.sun_direction()
	sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.999 else Vector3.FORWARD)
