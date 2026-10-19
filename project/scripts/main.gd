extends Node3D
## Escena principal: genera el terreno, coloca la mototaxi sobre un camino,
## la sigue con la cámara y arranca el ciclo de carrera (recoger y entregar pasajeros).

@onready var world: TerrainWorld = $TerrainWorld
@onready var moto: Mototaxi = $Mototaxi
@onready var cam: ChaseCamera = $ChaseCamera
@onready var race: RaceManager = $RaceManager
@onready var hud: RaceHUD = $HUD


func _ready() -> void:
	moto.terrain = world
	cam.terrain = world
	cam.target = moto
	moto.was_reset.connect(cam.snap)
	spawn()

	race.world = world
	race.moto = moto
	hud.bind(race, moto)
	race.start()


## Aparece en el primer landmark, orientada a lo largo del camino hacia el segundo.
func spawn() -> void:
	var landmarks := world.get_landmarks()
	var pos := Vector3(0.0, world.get_height(0.0, 0.0), 0.0)
	var yaw := 0.0
	if landmarks.size() >= 2:
		pos = landmarks[0]["position"]
		var route := world.find_route(pos, landmarks[1]["position"])
		if route.size() > 4:
			var dir := route[4] - pos
			yaw = atan2(dir.x, dir.z)
	moto.place_at(pos, yaw)
	cam.snap()
