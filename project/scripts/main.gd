extends Node3D
## Escena principal: menu con semilla y pantalla de carga (S13), genera el terreno en otro
## hilo, coloca la mototaxi sobre un camino, la sigue con la cámara y arranca el ciclo de
## carrera (recoger y entregar pasajeros).
##
## Sin menú (pruebas o atajos): ejecutar con "-- --seed=123" (mundo nuevo desde la semilla)
## o "-- --editor" (terreno guardado en terrain_demo.tscn). "--erosion=0.35" cambia la erosión.

## Muestra el menú de inicio (semilla y tipo de mundo) antes de generar.
@export var show_menu := true

@onready var world: TerrainWorld = $TerrainWorld
@onready var moto: Mototaxi = $Mototaxi
@onready var cam: ChaseCamera = $ChaseCamera
@onready var race: RaceManager = $RaceManager
@onready var hud: RaceHUD = $HUD

var loading: LoadingScreen


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
		world.preview_size = 768
		loading.show_progress()
		var t0 := Time.get_ticks_msec()
		var ok: bool = await world.generate_async(-1 if world.use_editor_scene else int(choice["seed"]))
		if ok and world.is_generated():
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
	return found


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
	race.start()
	get_tree().paused = false
	loading.finish()


## Aparece en un landmark de la zona transitable más grande (donde hay más pasajeros
## alcanzables), orientada a lo largo de la ruta hacia otro landmark de esa zona.
func spawn() -> void:
	var landmarks := world.get_landmarks()
	var pos := Vector3(0.0, world.get_height(0.0, 0.0), 0.0)
	var yaw := 0.0
	var zone := _largest_zone(landmarks)
	var in_zone := landmarks.filter(func(lm): return lm["reach"] == zone)
	if in_zone.size() >= 2:
		pos = in_zone[0]["position"]
		var route := world.find_route(pos, in_zone[1]["position"])
		if route.size() > 4:
			var dir := route[4] - pos
			yaw = atan2(dir.x, dir.z)
	moto.place_at(pos, yaw)
	cam.snap()


func _largest_zone(landmarks: Array[Dictionary]) -> int:
	var counts := {}
	for lm in landmarks:
		if lm["reach"] >= 0:
			counts[lm["reach"]] = counts.get(lm["reach"], 0) + 1
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
