class_name RaceManager
extends Node3D
## Ciclo de carrera (S11, J-B): estados, zonas de recogida/destino y temporizador.
##
##   LIBRE ──(entra a la zona amarilla despacio)──> CON_PASAJERO
##   CON_PASAJERO ──(llega a la zona verde, a tiempo o con algo de retraso)──> ENTREGADO
##   CON_PASAJERO ──(se acaba el tiempo y también el margen de retraso)──> FALLADO
##   ENTREGADO / FALLADO ──(tras result_time segundos)──> LIBRE (nuevo pasajero)
##
## Los puntos salen de TerrainWorld.get_landmarks(). La ruta recomendada va por las vías
## (TerrainWorld.find_road_route); se muestra en el minimapa del HUD, como en GTA (la cinta
## en el mundo, RouteLine, queda oculta salvo show_route_in_world). El tiempo límite sale
## de su largo y su pendiente (S12).
##
## S13: el pasajero tiene ánimo (1 = contento, 0 = furioso). Baja con los golpes, los
## vuelcos y cuando se acaba el tiempo. Sin propinas: la tarifa sale del largo de la ruta y
## el pasajero paga menos si el servicio fue malo (compute_payment): llegar tarde rebaja el
## pago hasta nada al final del margen de retraso (late_grace), y los golpes y vuelcos lo
## rebajan hasta rough_pay_min. Pasado el margen se baja sin pagar (FALLADO).

enum State { LIBRE, CON_PASAJERO, ENTREGADO, FALLADO }
enum RideKind { CORTO, MEDIO, LARGO }

signal state_changed(state: State)
signal ride_started(time_limit: float, route_length: float)
signal ride_finished(success: bool, time_left: float)
## Al entregar: lo que pagó y la tarifa completa (en soles).
signal paid(amount: float, fare: float)
## El pasajero reacciona (texto corto para el HUD).
signal passenger_said(text: String)

@export_group("Recogida")
@export var pickup_min_dist := 30.0    ## Distancia mínima (m) del pasajero a la mototaxi.
@export var pickup_max_dist := 180.0   ## Distancia máxima preferida.
@export var board_speed_kmh := 20.0    ## Hay que entrar a la zona por debajo de esta velocidad.

## El pasajero pide un viaje corto, medio o largo (distancia en línea recta desde donde sube):
##   corto: ride_min_dist .. ride_max_dist (la mayoría)
##   medio: ride_max_dist .. ride_mid_max_dist (ride_mid_chance)
##   largo: ride_mid_max_dist .. ride_long_max_dist (ride_long_chance), cruza buena parte del mapa
## Los largos pagan más por km (long_fare_bonus) para que valgan el tiempo, y no se piden si no
## alcanzan a terminar antes de que acabe la jornada (time_budget).
@export_group("Destino")
@export var ride_min_dist := 80.0
@export var ride_max_dist := 300.0
@export var ride_mid_max_dist := 800.0
@export var ride_long_max_dist := 1900.0
@export_range(0.0, 1.0) var ride_mid_chance := 0.32
@export_range(0.0, 1.0) var ride_long_chance := 0.18
## En viajes largos, los destinos con nombre (pueblos, miradores) son así de más probables.
@export var long_named_weight := 3.0

@export_group("Tiempo")
@export var base_time := 15.0          ## Segundos extra fijos por carrera.
@export var ref_speed_kmh := 30.0      ## Velocidad media esperada sobre la ruta.
@export var result_time := 3.0         ## Segundos que se muestra el resultado.
## Subir cuesta: la velocidad esperada baja uphill_penalty por cada unidad de pendiente
## (0.2 de pendiente con 2.0 = 40 % más lento), hasta min_speed_factor.
@export var uphill_penalty := 2.0
@export var min_speed_factor := 0.45

@export_group("Pago y ánimo (S13)")
@export var fare_base := 3.0           ## Soles por carrera.
@export var fare_per_km := 4.0         ## Soles por km de ruta recomendada.
## Recargo por viaje largo: el precio por km sube hasta (1 + long_fare_bonus) entre
## long_bonus_from y long_bonus_full metros de ruta. Así un viaje largo rinde más soles por
## minuto que varios cortos (en los cortos pesa la tarifa base), a cambio de más riesgo.
@export var long_fare_bonus := 1.0
@export var long_bonus_from := 200.0
@export var long_bonus_full := 2000.0
## Margen de retraso, como fracción del tiempo límite (con un mínimo en segundos).
@export var late_grace := 0.6
@export var late_grace_min := 15.0
@export var late_pay_start := 0.7      ## Fracción de la tarifa que paga apenas se pasa del tiempo.
@export var rough_pay_min := 0.6       ## Fracción que paga si el viaje fue a puro golpe.
@export var mood_hit_factor := 0.02    ## Ánimo perdido por punto de daño a la mototaxi.
@export var mood_flip_loss := 0.35     ## Ánimo perdido por cada vuelco.
@export var mood_time_start := 0.5     ## Fracción de tiempo restante desde la que se impacienta.

@export_group("Ruta")
@export var show_route := true
## Dibujar además la cinta con flechas sobre el suelo (antes del minimapa).
@export var show_route_in_world := false
@export var reroute_distance := 25.0   ## Si se aleja más que esto de la ruta, se recalcula.
@export var route_check_time := 1.5

@export_group("Zonas")
@export var zone_radius := 4.0
@export var pickup_color := Color(1.0, 0.8, 0.15)
@export var dropoff_color := Color(0.2, 1.0, 0.45)

var journeys: JourneyEvents
var street_pickups := false
var world: TerrainWorld
var moto: Mototaxi

var state: State = State.LIBRE
var time_left := 0.0
var time_limit := 0.0
var route := PackedVector3Array()
var route_length := 0.0
var deliveries := 0
var failures := 0
var earnings := 0.0       ## Puntaje: soles ganados en la partida.
## Segundos de retraso del viaje actual (cuenta cuando time_left llega a 0).
var late_time := 0.0
var mood := 1.0           ## Ánimo del pasajero a bordo (0..1).
var ride_kind: RideKind = RideKind.CORTO  ## Tipo del viaje actual.
var ride_fare := 0.0      ## Tarifa completa del viaje actual (se conoce al subir).
## Segundos que quedan para pedir un viaje (GameSession pone lo que le queda a la jornada).
var time_budget := INF
var route_line: RouteLine

## Persona que espera, sube y baja (modelo animado).
var passenger: Passenger
var pickup_zone: GlowZone
var dropoff_zone: GlowZone

var _pickup_id := -1
var _dropoff_id := -1
var _result_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _comfort := 1.0       # parte del ánimo que depende de cómo maneja (golpes, vuelcos)
var _off_route_timer := 0.0
var _impatient_said := false
var _late_said := false


func _ready() -> void:
	_ensure_zones()
	_ensure_route_line()


## Arranca el ciclo. rng_seed fija qué pasajeros salen (útil en pruebas).
func start(rng_seed: int = -1) -> void:
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_ensure_zones()
	_ensure_route_line()
	route_line.terrain = world
	route_line.visible = show_route_in_world
	pickup_zone.terrain = world
	dropoff_zone.terrain = world
	if moto and not moto.damaged.is_connected(_on_moto_damaged):
		moto.damaged.connect(_on_moto_damaged)
	deliveries = 0
	failures = 0
	earnings = 0.0
	_result_timer = 0.0
	_new_passenger()


func _physics_process(delta: float) -> void:
	if world == null or moto == null:
		return
	match state:
		State.LIBRE:
			if pickup_zone.contains(moto) and moto.get_speed_kmh() <= board_speed_kmh and (journeys == null or not journeys.negotiating):
				_board()
		State.CON_PASAJERO:
			if time_left > 0.0:
				time_left = maxf(time_left - delta, 0.0)
			else:
				late_time += delta
			_update_mood()
			if dropoff_zone.contains(moto):
				if journeys == null or not journeys.stop_before_finish(): _finish(true)
			elif time_left <= 0.0 and late_time >= get_late_limit() and (journeys == null or journeys.kind != "peligroso"):
				_finish(false)
		State.ENTREGADO, State.FALLADO:
			_result_timer -= delta
			if _result_timer <= 0.0:
				_new_passenger()
	_follow_route(delta)


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


## Tiempo límite para un largo en llano: fijo + lo que tarda a la velocidad de referencia.
func compute_time_limit(length: float) -> float:
	return base_time + length / (ref_speed_kmh / 3.6)


## Tiempo límite para una ruta: como compute_time_limit, pero cada tramo en subida se
## recorre más lento según su pendiente (las bajadas cuentan como llano).
func compute_route_time(path: PackedVector3Array) -> float:
	var v := ref_speed_kmh / 3.6
	var t := base_time
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		if run < 0.001:
			continue
		var grade := maxf((b.y - a.y) / run, 0.0)
		t += a.distance_to(b) / (v * maxf(1.0 - uphill_penalty * grade, min_speed_factor))
	return t


## Tarifa de una carrera según el largo de la ruta recomendada (m), con recargo si es larga.
func compute_fare(length: float) -> float:
	var bonus := long_fare_bonus * smoothstep(long_bonus_from, long_bonus_full, length)
	return fare_base + fare_per_km * length / 1000.0 * (1.0 + bonus)


static func ride_kind_name(k: RideKind) -> String:
	return ["Viaje corto", "Viaje medio", "Viaje largo"][k]


## Lo que paga el pasajero: la tarifa rebajada por el retraso (late_fraction: 0 = a tiempo,
## 1 = al final del margen) y por el maltrato (comfort: 1 = viaje suave, 0 = a puro golpe).
## Se redondea a 10 céntimos; menos de 50 céntimos es no pagar.
func compute_payment(fare: float, late_fraction: float, comfort: float) -> float:
	var punctual := 1.0 if late_fraction <= 0.0 else lerpf(late_pay_start, 0.0, clampf(late_fraction, 0.0, 1.0))
	var treat := lerpf(rough_pay_min, 1.0, clampf(comfort, 0.0, 1.0))
	var pay := snappedf(fare * punctual * treat, 0.1)
	return pay if pay >= 0.5 else 0.0


## Segundos de retraso que aguanta el pasajero antes de bajarse sin pagar.
func get_late_limit() -> float:
	return maxf(time_limit * late_grace, late_grace_min)


## 0 = a tiempo, 1 = se acabó el margen de retraso.
func get_late_fraction() -> float:
	return clampf(late_time / maxf(get_late_limit(), 0.001), 0.0, 1.0)


## Punto hacia el que debe apuntar la flecha: sobre la ruta, un poco por delante.
func get_guide_point(ahead: float = 25.0) -> Vector3:
	if route_line and show_route and state in [State.LIBRE, State.CON_PASAJERO]:
		var p := route_line.point_ahead(ahead)
		if p != Vector3.INF:
			return p
	return get_target()


# --- Transiciones -------------------------------------------------------------

func _new_passenger() -> void:
	dropoff_zone.activate(false)
	_pickup_id = _pick_landmark(moto.global_position, pickup_min_dist, pickup_max_dist, -1)
	if _pickup_id < 0:
		push_warning("RaceManager: no hay landmarks para recoger pasajeros")
		pickup_zone.activate(false)
		return
	var pickup := _street_pickup(_landmark_pos(_pickup_id)) if street_pickups else _landmark_pos(_pickup_id)
	pickup_zone.place(pickup)
	_set_state(State.LIBRE)
	var path := world.find_road_route(moto.global_position, pickup)
	_show_route(path)
	# El conductor usa la fotografía; los clientes conservan sus propios modelos.
	passenger.wait_at(pickup + _roadside_offset(path, pickup))


func _board() -> void:
	var from := pickup_zone.global_position
	_dropoff_id = _pick_destination(from, _roll_ride_kind())
	if _dropoff_id < 0:
		return
	var to := _landmark_pos(_dropoff_id)
	route = world.find_road_route(from, to)
	route_length = TerrainWorld.route_length(route)
	if route.size() < 2:
		route_length = from.distance_to(to) * 1.4  # Sin ruta A*: estimación en línea recta.
		time_limit = compute_time_limit(route_length)
	else:
		time_limit = compute_route_time(route)
	time_left = time_limit
	ride_fare = compute_fare(route_length)
	late_time = 0.0
	mood = 1.0
	_comfort = 1.0
	_impatient_said = false
	_late_said = false

	if journeys and not journeys.before_board(): return
	_begin_ride()


func _begin_ride() -> void:
	pickup_zone.activate(false)
	passenger.board()
	dropoff_zone.place(_landmark_pos(_dropoff_id))
	_set_state(State.CON_PASAJERO)
	_show_route(route)
	if journeys: journeys.begin()
	ride_started.emit(time_limit, route_length)
	var destination := get_target_label()
	if ride_kind == RideKind.LARGO:
		var where := ("Hasta %s" % destination) if not destination.is_empty() else "Lléveme lejos"
		passenger_said.emit("%s, es lejitos. Le pago S/ %.2f." % [where, ride_fare])
	elif not destination.is_empty():
		passenger_said.emit("Hasta %s, por favor." % destination)


func _finish(success: bool) -> void:
	dropoff_zone.activate(false)
	_show_route(PackedVector3Array())
	var fare := 0.0
	var pay := 0.0
	if success:
		deliveries += 1
		fare = ride_fare
		pay = compute_payment(fare, get_late_fraction(), _comfort)
		if journeys: pay = journeys.modify_payment(pay,success)
		earnings += pay
		if pay <= 0.0:
			passenger_said.emit("¡Con este servicio no le pago nada!")
		elif late_time > 0.0:
			passenger_said.emit("Llegamos tarde. Le doy S/ %.2f nomás." % pay)
		elif pay < fare - 0.05:
			passenger_said.emit("Casi me mata. Le doy S/ %.2f." % pay)
	else:
		failures += 1
		mood = 0.0
	# Baja por la derecha y se aleja de la vía; contento si llegó a tiempo y de buen ánimo.
	# El que baja sigue su camino solo; el siguiente pasajero es otra persona.
	var right := -moto.global_basis.x
	var leaving := passenger
	passenger = _make_passenger()
	leaving.get_off(moto.global_position + right * 2.0, right, success and pay > 0.0 and mood >= 0.5)
	_result_timer = result_time
	_set_state(State.ENTREGADO if success else State.FALLADO)
	ride_finished.emit(success, time_left)
	if success:
		paid.emit(pay, fare)


## Detiene el ciclo (fin de partida): sin zonas ni ruta.
func stop() -> void:
	if journeys: journeys._finish()
	passenger.hide_now()
	pickup_zone.activate(false)
	dropoff_zone.activate(false)
	_show_route(PackedVector3Array())
	state = State.FALLADO
	_result_timer = INF


# --- Ánimo del pasajero -------------------------------------------------------

func _update_mood() -> void:
	var f := time_left / maxf(time_limit, 0.001)
	var patience := clampf(f / mood_time_start, 0.0, 1.0)
	mood = clampf(_comfort * (0.35 * (1.0 - get_late_fraction()) + 0.65 * patience), 0.0, 1.0)
	if late_time > 0.0 and not _late_said:
		_late_said = true
		passenger_said.emit("¡Ya es tarde! Le voy a pagar menos.")
	if patience < 0.6 and not _impatient_said:
		_impatient_said = true
		passenger_said.emit("¡Apúrese, por favor, que llego tarde!")


func _on_moto_damaged(amount: float, reason: String) -> void:
	if state != State.CON_PASAJERO:
		return
	if reason == "vuelco":
		_comfort -= mood_flip_loss
		passenger_said.emit("¡¿Qué le pasa?! ¡Casi me mata!")
	elif reason == "bache":
		_comfort -= amount * mood_hit_factor + 0.03
		if amount >= 3.0:
			passenger_said.emit("¡Ay! ¿No vio ese hueco?")
	else:
		_comfort -= amount * mood_hit_factor
		if amount >= 8.0:
			passenger_said.emit("¡Cuidado con los golpes!")
	_comfort = maxf(_comfort, 0.0)


# --- Ruta recomendada ---------------------------------------------------------

func _show_route(path: PackedVector3Array) -> void:
	_off_route_timer = 0.0
	if route_line == null:
		return
	route_line.color = pickup_color if state == State.LIBRE else dropoff_color
	route_line.set_route(path if show_route else PackedVector3Array())


## Recorta lo ya recorrido y recalcula si la mototaxi se alejó de la ruta (tomó un atajo).
func _follow_route(delta: float) -> void:
	if route_line == null or not show_route or state not in [State.LIBRE, State.CON_PASAJERO]:
		return
	var off := route_line.advance(moto.global_position)
	_off_route_timer = _off_route_timer + delta if off > reroute_distance else 0.0
	if _off_route_timer > route_check_time:
		_show_route(world.find_road_route(moto.global_position, get_target()))


func _ensure_route_line() -> void:
	if route_line == null:
		route_line = RouteLine.new()
		route_line.name = "RouteLine"
		add_child(route_line)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


# --- Selección de puntos ------------------------------------------------------

## Landmark al azar a una distancia en [min_d, max_d] de origin, al que se pueda llegar
## manejando desde origin (TerrainWorld.is_reachable). Si ninguno cumple la distancia,
## el más lejano alcanzable.
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
		if not world.is_reachable(origin, p):
			continue
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d >= min_d and d <= max_d:
			candidates.append(id)
		if d > far_d:
			far_d = d
			far_id = id
	if not candidates.is_empty():
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	return far_id


## Tipo de viaje que pide el pasajero, al azar según ride_mid_chance y ride_long_chance.
func _roll_ride_kind() -> RideKind:
	var r := _rng.randf()
	if r < ride_long_chance:
		return RideKind.LARGO
	if r < ride_long_chance + ride_mid_chance:
		return RideKind.MEDIO
	return RideKind.CORTO


## Rango de distancia en línea recta [mín, máx] de cada tipo de viaje.
func ride_range(k: RideKind) -> Vector2:
	match k:
		RideKind.MEDIO:
			return Vector2(ride_max_dist, ride_mid_max_dist)
		RideKind.LARGO:
			return Vector2(ride_mid_max_dist, ride_long_max_dist)
	return Vector2(ride_min_dist, ride_max_dist)


## Destino para un viaje del tipo pedido desde origin. Si no hay ninguno de ese tipo (borde
## del mapa, zona chica) o no alcanza el tiempo de la jornada, prueba con uno más corto.
## Deja en ride_kind el tipo que salió.
func _pick_destination(origin: Vector3, wanted: RideKind) -> int:
	var lms := world.get_landmarks()
	for k in range(wanted, -1, -1):
		var span := ride_range(k)
		# Estimación del tiempo límite sin calcular la ruta: las vías dan ~1.4 veces la recta.
		if k > RideKind.CORTO and compute_time_limit(span.x * 1.4) > time_budget:
			continue
		var ids: Array[int] = []
		var weights := PackedFloat32Array()
		var total := 0.0
		for lm in lms:
			var id: int = lm["id"]
			if id == _pickup_id:
				continue
			var p: Vector3 = lm["position"]
			var d := Vector2(p.x - origin.x, p.z - origin.z).length()
			if d < span.x or d > span.y or not world.is_reachable(origin, p):
				continue
			if k > RideKind.CORTO and compute_time_limit(d * 1.4) > time_budget:
				continue
			var w := 1.0
			if k == RideKind.LARGO and not str(lm.get("label", "")).is_empty():
				w = long_named_weight
			ids.append(id)
			weights.append(w)
			total += w
		if ids.is_empty():
			continue
		ride_kind = k as RideKind
		var r := _rng.randf() * total
		for i in ids.size():
			r -= weights[i]
			if r <= 0.0:
				return ids[i]
		return ids[ids.size() - 1]
	ride_kind = RideKind.CORTO
	return _pick_landmark(origin, ride_min_dist, ride_max_dist, _pickup_id)


## Desplazamiento desde el centro de la vía hasta la vereda derecha, según cómo se llega
## (último tramo de la ruta). Queda dentro de la zona de recogida.
func _roadside_offset(path: PackedVector3Array, at: Vector3) -> Vector3:
	var dir := Vector3.FORWARD
	if path.size() >= 2:
		dir = path[path.size() - 1] - path[maxi(path.size() - 4, 0)]
	elif moto:
		dir = at - moto.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	return dir.normalized().cross(Vector3.UP) * minf(zone_radius * 0.7, 3.0)


func get_target_label() -> String:
	var id := _dropoff_id if state == State.CON_PASAJERO else _pickup_id
	for lm in world.get_landmarks():
		if lm["id"] == id:
			return str(lm.get("label", ""))
	return ""


func _landmark_pos(id: int) -> Vector3:
	for lm in world.get_landmarks():
		if lm["id"] == id:
			return lm["position"]
	return Vector3.ZERO


func _ensure_zones() -> void:
	if pickup_zone == null:
		pickup_zone = _make_zone("PickupZone", pickup_color, false)  # la persona ya marca el lugar
		dropoff_zone = _make_zone("DropoffZone", dropoff_color)
	if passenger == null:
		passenger = _make_passenger()
	passenger.world = world
	passenger.moto = moto


func _make_passenger() -> Passenger:
	var p := Passenger.new()
	p.name = "Passenger"
	p.world = world
	p.moto = moto
	add_child(p, true)
	return p


func _make_zone(zone_name: String, c: Color, marker := true) -> GlowZone:
	var z := GlowZone.new()
	z.name = zone_name
	z.marker_enabled = marker
	z.radius = zone_radius
	z.color = c
	add_child(z)
	z.activate(false)
	return z


func _street_pickup(fallback: Vector3) -> Vector3:
	var roads := world.get_roads()
	for attempt in 36:
		if roads.is_empty(): break
		var road: Dictionary = roads[_rng.randi_range(0,roads.size()-1)]
		var path: PackedVector3Array = road.path
		if path.size()<2: continue
		var i := _rng.randi_range(1,path.size()-1)
		var p := path[i-1].lerp(path[i],_rng.randf_range(.15,.85))
		var distance := Vector2(p.x-moto.global_position.x,p.z-moto.global_position.z).length()
		if distance<pickup_min_dist or distance>pickup_max_dist: continue
		if world.get_slope(p.x,p.z)>.22 or world.get_hazard(p.x,p.z)!=0: continue
		if not world.is_reachable(p,moto.global_position): continue
		p.y = world.get_height(p.x,p.z)
		return p
	return fallback
