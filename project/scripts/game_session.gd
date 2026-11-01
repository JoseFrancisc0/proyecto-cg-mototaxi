class_name GameSession
extends Node
## Fin de partida y reinicio (S12, J-A/J-B). La partida termina cuando:
##   - la vida de la mototaxi llega a 0 (choques fuertes y vuelcos),
##   - la mototaxi sale de los límites del mapa,
##   - queda atrapada: el jugador acelera pero no logra moverse (un hueco, una quebrada),
##   - se pierden max_failures pasajeros.
## Avisa con warning(texto, segundos) antes de terminar por atrapado o por salir del mapa.

signal warning(text: String, seconds_left: float)
signal game_over(reason: String, stats: Dictionary)

@export var max_failures := 3
@export_group("Atrapado")
@export var stuck_radius := 8.0      ## Moverse menos que esto (m) ...
@export var stuck_time := 12.0       ## ... durante tanto tiempo acelerando = atrapado.
@export var stuck_warning := 5.0     ## Segundos de aviso antes del fin.
@export_group("Límites")
@export var edge_warning := 40.0     ## A esta distancia del borde se avisa.
@export var fall_depth := 25.0       ## Más abajo que esto bajo el suelo = cayó del mapa.

var world: TerrainWorld
var moto: Mototaxi
var race: RaceManager

var playing := false
var play_time := 0.0
var damage_taken := 0.0
var flips := 0

var _anchor := Vector3.ZERO
var _stuck_timer := 0.0


func start() -> void:
	if not moto.destroyed.is_connected(_on_destroyed):
		moto.destroyed.connect(_on_destroyed)
		moto.damaged.connect(_on_damaged)
		race.ride_finished.connect(_on_ride_finished)
	playing = true
	play_time = 0.0
	damage_taken = 0.0
	flips = 0
	_reset_stuck()


func _physics_process(delta: float) -> void:
	if not playing or moto == null or world == null:
		return
	play_time += delta
	var p := moto.global_position

	# Fuera del mapa: pasó el borde o cayó muy por debajo del suelo.
	var half := world.get_world_size() * 0.5
	var edge := half - maxf(absf(p.x), absf(p.z))
	if edge < 0.0 or p.y < world.get_height(p.x, p.z) - fall_depth:
		_end("Saliste de los límites del mapa")
		return
	if edge < edge_warning:
		warning.emit("¡Cuidado! Te acercas al borde del mapa", -1.0)

	# Atrapada: acelera (o retrocede) pero no se aleja del punto de referencia.
	if Vector2(p.x - _anchor.x, p.z - _anchor.z).length() > stuck_radius:
		_reset_stuck()
	elif absf(moto.throttle) > 0.2:
		_stuck_timer += delta
		var left := stuck_time - _stuck_timer
		if left <= 0.0:
			_end("La mototaxi quedó atrapada")
			return
		if left <= stuck_warning:
			warning.emit("¡Atrapado! Sal de aquí", left)


## Datos para la pantalla final.
func get_stats() -> Dictionary:
	return {
		"deliveries": race.deliveries,
		"failures": race.failures,
		"earnings": race.earnings,
		"tips": race.tips_total,
		"time": play_time,
		"damage": damage_taken,
		"flips": flips,
	}


func _reset_stuck() -> void:
	_anchor = moto.global_position if moto else Vector3.ZERO
	_stuck_timer = 0.0


func _on_damaged(amount: float, reason: String) -> void:
	damage_taken += amount
	if reason == "vuelco":
		flips += 1
	# Enderezarse cambia de lugar: no cuenta como atrapada.
	_reset_stuck()


func _on_destroyed() -> void:
	_end("La mototaxi quedó destrozada")


func _on_ride_finished(success: bool, _time_left: float) -> void:
	if not success and race.failures >= max_failures:
		_end("Perdiste %d pasajeros" % max_failures)


func _end(reason: String) -> void:
	if not playing:
		return
	playing = false
	race.stop()
	moto.use_input = false
	moto.throttle = 0.0
	moto.steer_input = 0.0
	game_over.emit(reason, get_stats())
