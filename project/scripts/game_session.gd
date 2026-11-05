class_name GameSession
extends Node
## Jornadas y fin de partida (S12-S14, J-A/J-B).
##
## La partida es una serie de jornadas. Cada jornada dura day_length segundos reales, que en el
## reloj del juego van de day_start_hour a day_end_hour (como en GTA: 6 min = 7:00 a 19:00); al final se
## paga la cuota del día al dueño de la mototaxi (sube cada día). Si se juntó, lo que sobra
## va a los ahorros (CareerSave, para el garaje) y sigue el día siguiente (day_completed);
## si no, fin de partida. Si el reloj llega a 0 con un pasajero a bordo, se termina ese viaje.
##
## También termina la partida (game_over) cuando:
##   - la vida de la mototaxi llega a 0 (choques fuertes y vuelcos),
##   - la mototaxi sale de los límites del mapa,
##   - queda atrapada: el jugador acelera pero no logra moverse (un hueco, una quebrada),
##   - se pierden max_failures pasajeros en una jornada (0 = sin límite).
## Avisa con warning(texto, segundos) antes de terminar por atrapado o por salir del mapa.

signal warning(text: String, seconds_left: float)
signal game_over(reason: String, stats: Dictionary)
## Jornada cumplida: stats trae además "quota", "saved" y "savings".
signal day_completed(stats: Dictionary)

@export_group("Jornada")
@export var day_length := 360.0      ## Segundos reales de cada jornada.
@export var day_start_hour := 7.0    ## Hora del reloj del juego al empezar la jornada.
@export var day_end_hour := 19.0     ## Hora en que termina (se paga la cuota).
@export var quota_base := 10.0       ## Cuota (soles) del primer día.
@export var quota_per_day := 4.0     ## Lo que sube la cuota cada día.
@export var max_failures := 0
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
var day := 1
var quota := 0.0
var day_time_left := 0.0
## true cuando el reloj llegó a 0 y se espera que termine el viaje en curso.
var overtime := false
## Segundos pasados después de la hora de cierre (terminando el último viaje).
var overtime_time := 0.0
var play_time := 0.0
var damage_taken := 0.0
var flips := 0

var _anchor := Vector3.ZERO
var _stuck_timer := 0.0


## Partida nueva desde el día 1.
func start() -> void:
	day = 1
	play_time = 0.0
	damage_taken = 0.0
	flips = 0
	start_day()


## Siguiente jornada (tras day_completed). Main repara la mototaxi y reinicia la carrera.
func next_day() -> void:
	day += 1
	start_day()


func start_day() -> void:
	if not moto.destroyed.is_connected(_on_destroyed):
		moto.destroyed.connect(_on_destroyed)
		moto.damaged.connect(_on_damaged)
		race.ride_finished.connect(_on_ride_finished)
	quota = quota_for(day)
	day_time_left = day_length
	overtime = false
	overtime_time = 0.0
	playing = true
	_reset_stuck()


func quota_for(d: int) -> float:
	return quota_base + quota_per_day * (d - 1)


func _physics_process(delta: float) -> void:
	if not playing or moto == null or world == null:
		return
	play_time += delta
	if day_time_left <= 0.0:
		overtime_time += delta
	day_time_left = maxf(day_time_left - delta, 0.0)
	if day_time_left <= 0.0:
		if race.state == RaceManager.State.CON_PASAJERO:
			overtime = true  # Termina el viaje en curso.
		else:
			_end_day()
			return
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


## Minutos del reloj del juego desde la medianoche (sigue corriendo tras el cierre).
func get_clock_minutes() -> float:
	var span := (day_end_hour - day_start_hour) * 60.0
	var elapsed := day_length - day_time_left + overtime_time
	return day_start_hour * 60.0 + elapsed / maxf(day_length, 0.001) * span


## Hora del reloj del juego, "HH:MM".
func get_clock_text(minutes := -1.0) -> String:
	var m := int(get_clock_minutes() if minutes < 0.0 else minutes) % (24 * 60)
	return "%02d:%02d" % [m / 60, m % 60]


func get_closing_text() -> String:
	return get_clock_text(day_end_hour * 60.0)


## Estado de la jornada para guardar la partida. Con fresh_day, el inicio del día siguiente
## (se guarda así al completar un día).
func get_save_data(fresh_day := false) -> Dictionary:
	if fresh_day:
		return {"day": day + 1, "day_time_left": day_length, "earnings": 0.0, "deliveries": 0,
			"failures": 0, "health": moto.max_health, "play_time": play_time,
			"damage": damage_taken, "flips": flips}
	return {"day": day, "day_time_left": day_time_left, "earnings": race.earnings,
		"deliveries": race.deliveries, "failures": race.failures, "health": moto.health,
		"play_time": play_time, "damage": damage_taken, "flips": flips}


## Sigue una partida guardada. Main ya generó el mismo mundo, colocó la mototaxi y llamó a
## race.start() (el viaje que iba en curso no se guarda: empieza con un pasajero nuevo).
func load_save_data(d: Dictionary) -> void:
	day = maxi(int(d.get("day", 1)), 1)
	play_time = float(d.get("play_time", 0.0))
	damage_taken = float(d.get("damage", 0.0))
	flips = int(d.get("flips", 0))
	start_day()
	day_time_left = clampf(float(d.get("day_time_left", day_length)), 0.0, day_length)
	race.earnings = float(d.get("earnings", 0.0))
	race.deliveries = int(d.get("deliveries", 0))
	race.failures = int(d.get("failures", 0))
	moto.health = clampf(float(d.get("health", moto.max_health)), 1.0, moto.max_health)


## Datos para la pantalla final.
func get_stats() -> Dictionary:
	return {
		"day": day,
		"quota": quota,
		"deliveries": race.deliveries,
		"failures": race.failures,
		"earnings": race.earnings,
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
	if not success and max_failures > 0 and race.failures >= max_failures:
		_end("Perdiste %d pasajeros" % max_failures)
	elif overtime:
		_end_day.call_deferred()


## Fin de la jornada: paga la cuota y guarda lo que sobra, o fin de partida.
func _end_day() -> void:
	if not playing:
		return
	playing = false
	_stop_play()
	var stats := get_stats()
	if race.earnings + 0.001 < quota:
		stats["savings"] = CareerSave.get_savings()
		game_over.emit("No juntaste la cuota del día %d: S/ %.2f de S/ %.2f" % [day, race.earnings, quota], stats)
		return
	var saved := race.earnings - quota
	stats["saved"] = saved
	stats["savings"] = CareerSave.add_savings(saved)
	stats["record"] = CareerSave.record_day(day)
	day_completed.emit(stats)


func _stop_play() -> void:
	race.stop()
	moto.use_input = false
	moto.throttle = 0.0
	moto.steer_input = 0.0


func _end(reason: String) -> void:
	if not playing:
		return
	playing = false
	_stop_play()
	var stats := get_stats()
	stats["savings"] = CareerSave.get_savings()
	game_over.emit(reason, stats)
