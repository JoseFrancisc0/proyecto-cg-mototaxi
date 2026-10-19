class_name RaceManager
extends Node3D
## Ciclo de carrera (S11, J-B): estados, zonas de recogida/destino y temporizador.
##
##   LIBRE ──(entra a la zona amarilla despacio)──> CON_PASAJERO
##   CON_PASAJERO ──(llega a la zona verde a tiempo)──> ENTREGADO
##   CON_PASAJERO ──(se acaba el tiempo)──> FALLADO
##   ENTREGADO / FALLADO ──(tras result_time segundos)──> LIBRE (nuevo pasajero)
##
## Los puntos salen de TerrainWorld.get_landmarks() y el tiempo límite del largo de
## find_route(), así que cuando CG entregue la API real esto no cambia.

enum State { LIBRE, CON_PASAJERO, ENTREGADO, FALLADO }

signal state_changed(state: State)
signal ride_started(time_limit: float, route_length: float)
signal ride_finished(success: bool, time_left: float)

@export_group("Recogida")
@export var pickup_min_dist := 30.0    ## Distancia mínima (m) del pasajero a la mototaxi.
@export var pickup_max_dist := 180.0   ## Distancia máxima preferida.
@export var board_speed_kmh := 20.0    ## Hay que entrar a la zona por debajo de esta velocidad.

@export_group("Destino")
@export var ride_min_dist := 80.0
@export var ride_max_dist := 260.0

@export_group("Tiempo")
@export var base_time := 15.0          ## Segundos extra fijos por carrera.
@export var ref_speed_kmh := 30.0      ## Velocidad media esperada sobre la ruta.
@export var result_time := 3.0         ## Segundos que se muestra el resultado.

@export_group("Zonas")
@export var zone_radius := 4.0
@export var pickup_color := Color(1.0, 0.8, 0.15)
@export var dropoff_color := Color(0.2, 1.0, 0.45)

var world: TerrainWorld
var moto: Mototaxi

var state: State = State.LIBRE
var time_left := 0.0
var time_limit := 0.0
var route := PackedVector3Array()
var route_length := 0.0
var deliveries := 0
var failures := 0

var pickup_zone: GlowZone
var dropoff_zone: GlowZone

var _pickup_id := -1
var _dropoff_id := -1
var _result_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_ensure_zones()


## Arranca el ciclo. rng_seed fija qué pasajeros salen (útil en pruebas).
func start(rng_seed: int = -1) -> void:
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_ensure_zones()
	deliveries = 0
	failures = 0
	_new_passenger()


func _physics_process(delta: float) -> void:
	if world == null or moto == null:
		return
	match state:
		State.LIBRE:
			if pickup_zone.contains(moto) and moto.get_speed_kmh() <= board_speed_kmh:
				_board()
		State.CON_PASAJERO:
			time_left = maxf(time_left - delta, 0.0)
			if dropoff_zone.contains(moto):
				_finish(true)
			elif time_left <= 0.0:
				_finish(false)
		State.ENTREGADO, State.FALLADO:
			_result_timer -= delta
			if _result_timer <= 0.0:
				_new_passenger()


## Punto al que debe ir el jugador ahora (Vector3.INF si no hay ninguno).
func get_target() -> Vector3:
	match state:
		State.LIBRE:
			return pickup_zone.global_position
		State.CON_PASAJERO:
			return dropoff_zone.global_position
	return Vector3.INF


func get_target_distance() -> float:
	var t := get_target()
	if t == Vector3.INF or moto == null:
		return 0.0
	return Vector2(t.x - moto.global_position.x, t.z - moto.global_position.z).length()


static func state_name(s: State) -> String:
	return ["Libre", "Con pasajero", "Entregado", "Fallado"][s]


## Tiempo límite para una ruta: fijo + lo que tarda a la velocidad de referencia.
func compute_time_limit(length: float) -> float:
	return base_time + length / (ref_speed_kmh / 3.6)


# --- Transiciones -------------------------------------------------------------

func _new_passenger() -> void:
	dropoff_zone.activate(false)
	_pickup_id = _pick_landmark(moto.global_position, pickup_min_dist, pickup_max_dist, -1)
	if _pickup_id < 0:
		push_warning("RaceManager: no hay landmarks para recoger pasajeros")
		pickup_zone.activate(false)
		return
	pickup_zone.place(_landmark_pos(_pickup_id))
	_set_state(State.LIBRE)


func _board() -> void:
	var from := _landmark_pos(_pickup_id)
	_dropoff_id = _pick_landmark(from, ride_min_dist, ride_max_dist, _pickup_id)
	if _dropoff_id < 0:
		return
	var to := _landmark_pos(_dropoff_id)
	route = world.find_route(from, to)
	route_length = TerrainWorld.route_length(route)
	if route.size() < 2:
		route_length = from.distance_to(to) * 1.4  # Sin ruta A*: estimación en línea recta.
	time_limit = compute_time_limit(route_length)
	time_left = time_limit

	pickup_zone.activate(false)
	dropoff_zone.place(to)
	_set_state(State.CON_PASAJERO)
	ride_started.emit(time_limit, route_length)


func _finish(success: bool) -> void:
	dropoff_zone.activate(false)
	if success:
		deliveries += 1
	else:
		failures += 1
	_result_timer = result_time
	_set_state(State.ENTREGADO if success else State.FALLADO)
	ride_finished.emit(success, time_left)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


# --- Selección de puntos ------------------------------------------------------

## Landmark al azar a una distancia en [min_d, max_d] de origin. Si ninguno cumple,
## el más lejano que supere min_d; si tampoco, el más lejano de todos.
func _pick_landmark(origin: Vector3, min_d: float, max_d: float, exclude: int) -> int:
	var lms := world.get_landmarks()
	var candidates: Array[int] = []
	var far_id := -1
	var far_d := -1.0
	for lm in lms:
		var id: int = lm["id"]
		if id == exclude:
			continue
		var p: Vector3 = lm["position"]
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d >= min_d and d <= max_d:
			candidates.append(id)
		if d > far_d:
			far_d = d
			far_id = id
	if not candidates.is_empty():
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	return far_id


func _landmark_pos(id: int) -> Vector3:
	for lm in world.get_landmarks():
		if lm["id"] == id:
			return lm["position"]
	return Vector3.ZERO


func _ensure_zones() -> void:
	if pickup_zone == null:
		pickup_zone = _make_zone("PickupZone", pickup_color)
		dropoff_zone = _make_zone("DropoffZone", dropoff_color)


func _make_zone(zone_name: String, c: Color) -> GlowZone:
	var z := GlowZone.new()
	z.name = zone_name
	z.radius = zone_radius
	z.color = c
	add_child(z)
	z.activate(false)
	return z
