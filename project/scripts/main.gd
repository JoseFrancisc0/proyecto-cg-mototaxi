extends Node3D
## Escena principal: genera el terreno, coloca la mototaxi sobre un camino,
## la sigue con la cámara y arranca el ciclo de carrera (recoger y entregar pasajeros).

@onready var world: TerrainWorld = $TerrainWorld
@onready var moto: Mototaxi = $Mototaxi
@onready var cam: ChaseCamera = $ChaseCamera
@onready var race: RaceManager = $RaceManager
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	_align_sun()
	moto.terrain = world
	cam.terrain = world
	cam.target = moto
	moto.was_reset.connect(cam.snap)
	spawn()

	race.world = world
	race.moto = moto
	hud.bind(race, moto)
	race.start()


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
