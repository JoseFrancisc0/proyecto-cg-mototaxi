class_name Mototaxi
extends VehicleBody3D
## Mototaxi de 3 ruedas sobre la física de vehículos de Godot.
##
## Cómo se mueve: VehicleBody3D es un cuerpo rígido; cada VehicleWheel3D lanza un rayo
## hacia el suelo y, según cuánto se comprime, aplica la fuerza del resorte de la
## suspensión, la tracción (engine_force), el freno y la fricción lateral en el punto de
## contacto. Este script solo traduce la entrada del jugador a esas tres magnitudes:
## engine_force (ruedas traseras), brake (todas) y steering (rueda delantera).
##
## Convención: el frente del vehículo es +Z local; steering > 0 gira a la izquierda.

signal was_reset
## Recibió daño: amount en puntos de vida; reason = "choque" o "vuelco".
signal damaged(amount: float, reason: String)
## La vida llegó a 0.
signal destroyed

@export_group("Motor")
@export var max_engine_force := 650.0     ## Fuerza por rueda tractora (N).
@export var max_speed_kmh := 65.0
@export var reverse_force := 350.0
@export var max_reverse_kmh := 15.0
@export var brake_force := 8.0
@export var handbrake_force := 6.0
@export var coast_brake := 1.0             ## Freno motor al soltar el acelerador.
@export var hold_brake := 15.0             ## Freno al estar casi detenida.
@export var park_damp := 20.0              ## Amortiguación al estar estacionada, para no rodar en pendientes.
## "Marcha corta": multiplica la fuerza al arrancar para poder subir cuestas;
## baja hasta 1 al llegar a boost_fade_kmh, así la aceleración en llano no cambia tanto.
@export var low_speed_boost := 1.8
@export var boost_fade_kmh := 30.0

@export_group("Dirección")
@export var max_steer := 0.5               ## Radianes.
@export var steer_at_max_speed := 0.2      ## Fracción del giro máximo a velocidad máxima.
@export var steer_speed := 2.5             ## Radianes por segundo.

@export_group("Vuelco")
@export var upright_threshold := 0.3       ## basis.y · UP por debajo de esto = volcada.
@export var flip_reset_time := 2.5
@export var spawn_height := 0.6

@export_group("Vida (S12)")
@export var max_health := 100.0
## Cambio brusco de velocidad (m/s) en un paso de física a partir del cual un golpe daña.
## Frenar, acelerar o pasar baches cambia menos de ~1 m/s por paso.
@export var crash_threshold := 4.0
@export var crash_damage_per_ms := 4.0     ## Daño por cada m/s por encima del umbral.
@export var flip_damage := 20.0            ## Daño de cada vuelco (al enderezarse).

## Si es false, la entrada se fija desde código (pruebas, IA, cinemáticas).
@export var use_input := true

## Entrada normalizada: throttle en [-1, 1] (negativo = freno/reversa),
## steer_input en [-1, 1] (positivo = izquierda).
var throttle := 0.0
var steer_input := 0.0
var handbrake := false
var turbo_requested := false
var turbo_active := false
var turbo_charge := 1.0
var offroad_amount := 0.0
var mud_amount := 0.0     ## Fracción de ruedas en barro o arena (RoadObstacles).
var mud_drag := 0.9       ## Frenado del barro (por m/s de velocidad, por kg).
var pothole_damage := 0.2 ## Daño por km/h por encima de pothole_safe_kmh al caer en un bache.
var pothole_safe_kmh := 18.0
var _pothole_cool: Array[float] = []
var turbo_multiplier := 2.1
var road_grip := 3.2
var offroad_speed_ratio := 0.61
var vehicle_index := 2
var _turbo_locked := false
var _rough_time := 0.0
const TURBO_SECONDS := 7.0
const TURBO_RECHARGE := 0.18

## Opcional: si se asigna, el reinicio usa la altura del terreno en vez de un rayo.
var terrain: TerrainWorld

var _wheels: Array[VehicleWheel3D] = []
var _flip_timer := 0.0
var _contacts := 0
## Pasó de 90° (patas arriba). Con el chasis redondeado suele volver sola: igual cuenta como vuelco.
var _overturned := false

var health := 100.0
var _prev_velocity := Vector3.ZERO
var _hit_grace := 0.0  # segundos sin daño tras aparecer o tras un golpe

var wheel_visuals := VehicleWheelVisuals.new()
var engine_audio: VehicleEngineAudio
# Profundidad del frontal de cada carrocería a la altura del faro (espacio del GLB).
const HEADLIGHT_DEPTHS := [0.91, 0.92, 1.04, 0.79, 0.92, 0.87]
@onready var _headlight := get_node_or_null("Faro") as SpotLight3D


func _ready() -> void:
	_ensure_input_actions()
	add_to_group("mototaxi")  # TreeColliders vuelve sólidos los troncos alrededor
	# Escala física explícita: RigidBody3D conserva su transform sin escalar.
	var visual_scale := VehicleCatalog.MODEL_SCALE
	center_of_mass *= visual_scale
	spawn_height *= visual_scale
	for child in get_children():
		if child is CollisionShape3D:
			child.position *= visual_scale
			child.shape = child.shape.duplicate()
			if child.shape is CapsuleShape3D:
				child.shape.radius *= visual_scale
				child.shape.height *= visual_scale
			elif child.shape is BoxShape3D:
				child.shape.size *= visual_scale
		elif child is VehicleWheel3D:
			child.position *= visual_scale
			child.wheel_radius *= visual_scale
			child.wheel_rest_length *= visual_scale
			child.suspension_travel *= visual_scale
	for c in get_children():
		var w := c as VehicleWheel3D
		if w:
			_wheels.append(w)
	health = max_health
	select_vehicle(vehicle_index)
	continuous_cd = true


func select_vehicle(index: int) -> void:
	vehicle_index = clampi(index, 0, VehicleCatalog.VEHICLES.size()-1)
	var v := VehicleCatalog.entry(vehicle_index)
	max_speed_kmh = v.speed
	max_engine_force = v.force
	road_grip = v.grip
	offroad_speed_ratio = v.offroad
	turbo_multiplier = v.turbo
	max_steer = 0.56 if vehicle_index == 1 else (0.43 if vehicle_index == 4 else 0.5)
	var old := get_node_or_null("VehicleVisual")
	if old:
		remove_child(old)
		old.queue_free()
	var model := VehicleCatalog.create_model(vehicle_index)
	if model:
		model.name = "VehicleVisual"
		# Ground level is -0.08 relative to the settled physics body.
		model.position.y = -0.08 * VehicleCatalog.MODEL_SCALE
		add_child(model)
		wheel_visuals.bind_model(model)
		var body := model.find_child("Body", true, false) as MeshInstance3D
		if body and body.mesh and body.mesh.get_surface_count() > 0:
			var source := body.get_active_material(0) as StandardMaterial3D
			if source:
				var paint := source.duplicate() as StandardMaterial3D
				# Reduce el metal del GLB para que la pintura reciba algo de luz difusa.
				paint.metallic *= 0.55
				body.set_surface_override_material(0, paint)
	if _headlight:
		_headlight.position = Vector3(0.0, 0.82 - 0.08, HEADLIGHT_DEPTHS[vehicle_index] + 0.095) * VehicleCatalog.MODEL_SCALE
	if engine_audio == null:
		engine_audio = VehicleEngineAudio.new()
		engine_audio.name = "EngineAudio"
		add_child(engine_audio)
	engine_audio.configure(vehicle_index)


func _process(_delta: float) -> void:
	if _headlight == null or terrain == null or terrain.generator == null:
		return
	var generator := terrain.generator
	var material := generator.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("headlight_enabled", _headlight.visible)
	if _headlight.visible:
		var direction := generator.global_basis.inverse() * -_headlight.global_basis.z
		material.set_shader_parameter("headlight_origin", generator.to_local(_headlight.global_position))
		material.set_shader_parameter("headlight_direction", direction.normalized())
		material.set_shader_parameter("headlight_range", _headlight.spot_range)
		material.set_shader_parameter("headlight_cone", cos(deg_to_rad(_headlight.spot_angle)))


func _unhandled_key_input(event: InputEvent) -> void:
	if use_input and _headlight and event.is_action_pressed("moto_headlights", false):
		_headlight.visible = not _headlight.visible


func _physics_process(delta: float) -> void:
	if use_input:
		_read_input()

	var speed := get_forward_speed()
	_update_surface(delta)
	if _turbo_locked and turbo_charge >= 0.28:
		_turbo_locked = false
	turbo_active = turbo_requested and throttle > 0.01 and not handbrake and not _turbo_locked and turbo_charge > 0.0
	if turbo_active:
		turbo_charge = maxf(0.0, turbo_charge - delta / TURBO_SECONDS)
		if turbo_charge <= 0.0:
			_turbo_locked = true
	else:
		turbo_charge = minf(1.0, turbo_charge + delta * TURBO_RECHARGE)
	var surface_limit := lerpf(1.0, offroad_speed_ratio, offroad_amount)
	var max_speed := max_speed_kmh / 3.6 * surface_limit * (1.24 if turbo_active else 1.0)
	var max_rev := max_reverse_kmh / 3.6

	# Motor y freno. Acelerar mientras va en reversa (o frenar yendo hacia delante)
	# primero frena; recién detenida pasa a la otra marcha.
	var force := 0.0
	var brk := 0.0
	if throttle > 0.01:
		# Fuerza completa hasta el 85 % de la velocidad máxima; luego baja a 0 en el tope.
		force = max_engine_force * _gear(speed) * throttle * clampf((max_speed - speed) / (0.15 * max_speed), 0.0, 1.0)
		force *= (turbo_multiplier if turbo_active else 1.0) * lerpf(1.0, 0.78, offroad_amount)
		# Si va hacia atrás (reversa, o rodando cuesta abajo) además frena, pero sin
		# cortar el motor: así puede retomar una subida en la que se quedó sin impulso.
		if speed < -0.5:
			brk = brake_force * throttle
	elif throttle < -0.01:
		if speed > 0.5:
			brk = brake_force * -throttle
		else:
			force = -reverse_force * _gear(speed) * -throttle * clampf((max_rev + speed) / (0.3 * max_rev), 0.0, 1.0)
	else:
		brk = hold_brake if absf(speed) < 1.5 else coast_brake
	engine_force = force

	var contacts := 0
	var contact_normal := Vector3.ZERO
	for w in _wheels:
		w.wheel_friction_slip = road_grip * (0.83 if w.use_as_steering else 1.0) * lerpf(1.0, 0.56, offroad_amount) * lerpf(1.0, 0.6, mud_amount)
		w.wheel_roll_influence = lerpf(0.05, 0.16, offroad_amount)
		w.brake = brk + (handbrake_force if handbrake and w.use_as_traction else 0.0)
		if w.is_in_contact():
			contacts += 1
			contact_normal += w.get_contact_normal()
	# El freno de Godot es un impulso limitado y en pendientes deja deslizar un poco;
	# estacionada y con todas las ruedas apoyadas, se amortigua el movimiento.
	_contacts = contacts
	var parked := absf(throttle) <= 0.01 and absf(speed) < 0.5 and contacts == _wheels.size()
	linear_damp = park_damp if parked else 0.0
	if contacts >= 2:
		# Estabilizador de balanceo arcade; en tierra deja sentir más el terreno.
		var roll_axis := global_basis.z.normalized()
		var roll_error := global_basis.y.cross(Vector3.UP).dot(roll_axis)
		var roll_rate := angular_velocity.dot(roll_axis)
		apply_torque(roll_axis * mass * (roll_error * 8.0 - roll_rate * 1.6) * lerpf(1.0, 0.3, offroad_amount))
		if turbo_active and contact_normal.length_squared() > 0.1:
			# La escala mayor aumenta el brazo de palanca: evita levantar la rueda
			# delantera al arrancar con turbo, siguiendo la pendiente real del apoyo.
			var pitch_axis := global_basis.x.normalized()
			var pitch_error := global_basis.y.cross(contact_normal.normalized()).dot(pitch_axis)
			apply_torque(pitch_axis*mass*(pitch_error*12.0-angular_velocity.dot(pitch_axis)*2.2))
		# Resistencia continua: desacelera también al entrar a tierra por inercia.
		var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		apply_central_force(-horizontal * mass * offroad_amount * 0.34)
		# Barro o arena de la vía: frena mucho más que la tierra.
		apply_central_force(-horizontal * mass * mud_amount * mud_drag)
		# Asistencia de pendiente solo con apoyo: no empuja en el aire ni cuesta abajo.
		if turbo_active and global_basis.z.y > 0.02:
			var forward := global_basis.z.normalized()
			apply_central_force(forward * mass * 9.8 * minf(forward.y, 0.75) * 0.85)
		_rough_time += delta * clampf(absf(speed), 0.0, 18.0)
		var roughness := offroad_amount * clampf(absf(speed) / 12.0, 0.0, 1.0)
		apply_torque(global_basis.z * sin(_rough_time * 2.4) * mass * roughness * 0.24)
		apply_torque(Vector3.UP * sin(_rough_time * 1.7) * mass * roughness * 0.12)

	# Dirección: se reduce con la velocidad y se mueve gradualmente hacia el objetivo.
	var speed_factor := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var target := steer_input * max_steer * lerpf(1.0, steer_at_max_speed, speed_factor)
	steering = move_toward(steering, target, steer_speed * delta)
	wheel_visuals.update_wheels(delta,speed,steering)
	engine_audio.update_engine(delta,speed,throttle,max_speed_kmh/3.6,turbo_active)

	_check_crash(delta)

	# Detección de vuelco: volcada y casi quieta durante un rato -> se endereza y daña.
	if global_basis.y.dot(Vector3.UP) < upright_threshold and linear_velocity.length() < 3.0:
		_flip_timer += delta
	else:
		_flip_timer = 0.0
	if global_basis.y.dot(Vector3.UP) < 0.0:
		_overturned = true
	var manual_reset := use_input and Input.is_action_just_pressed("moto_reset")
	if _flip_timer > flip_reset_time or (manual_reset and not is_upright()):
		_overturned = false
		apply_damage(flip_damage, "vuelco")
		if health > 0.0:
			reset_upright()
	elif _overturned and is_upright():
		# Dio la vuelta y se enderezó sola: un vuelco, una sola vez.
		_overturned = false
		apply_damage(flip_damage, "vuelco")
	elif manual_reset:
		reset_upright()


## Daño por choque: un cambio brusco de velocidad en un solo paso (sin contar la gravedad)
## es un golpe contra el suelo, una roca o un puente. El daño crece con la violencia.
func _check_crash(delta: float) -> void:
	var gravity := get_gravity() * delta
	var dv := (linear_velocity - _prev_velocity - gravity).length()
	_prev_velocity = linear_velocity
	if _hit_grace > 0.0:
		_hit_grace -= delta
		return
	if dv > crash_threshold:
		apply_damage((dv - crash_threshold) * crash_damage_per_ms, "choque")
		_hit_grace = 0.4  # un mismo golpe dura varios pasos


## Resta vida. Emite damaged y, si llega a 0, destroyed (una sola vez).
func apply_damage(amount: float, reason: String) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, reason)
	if health <= 0.0:
		destroyed.emit()


## Vida al máximo (al reiniciar la partida).
func repair() -> void:
	health = max_health


## Ruedas apoyadas en el último paso de física.
func wheels_in_contact() -> int:
	return _contacts


func get_health_ratio() -> float:
	return health / max_health

func _update_surface(delta: float) -> void:
	var amount := 0.0
	var mud := 0.0
	if _pothole_cool.size() != _wheels.size():
		_pothole_cool.resize(_wheels.size())
		_pothole_cool.fill(0.0)
	if terrain:
		for k in _wheels.size():
			var wheel := _wheels[k]
			var p := wheel.global_position
			amount += terrain.get_offroad_amount(p.x, p.z)
			_pothole_cool[k] -= delta
			match terrain.get_hazard(p.x, p.z):
				RoadObstacles.HAZARD_SLOW:
					mud += 1.0
				RoadObstacles.HAZARD_BUMP:
					if _pothole_cool[k] <= 0.0 and wheel.is_in_contact():
						_pothole_cool[k] = 0.6
						_hit_pothole(wheel)
		amount /= maxf(1.0, _wheels.size())
		mud /= maxf(1.0, _wheels.size())
	offroad_amount = move_toward(offroad_amount, amount, delta * 3.0)
	mud_amount = mud


## Una rueda cae en un bache: sacudón y, si va rápido, algo de daño.
func _hit_pothole(wheel: VehicleWheel3D) -> void:
	var kmh := get_speed_kmh()
	if kmh < 6.0:
		return
	var jolt := mass * clampf(kmh / 60.0, 0.15, 0.8)
	apply_impulse(Vector3.UP * jolt, wheel.global_position - global_position)
	if kmh > pothole_safe_kmh:
		apply_damage((kmh - pothole_safe_kmh) * pothole_damage, "bache")


## Multiplicador de fuerza según la velocidad (marcha corta al arrancar).
func _gear(speed: float) -> float:
	return lerpf(low_speed_boost, 1.0, clampf(absf(speed) / (boost_fade_kmh / 3.6), 0.0, 1.0))


## Velocidad con signo a lo largo del frente (m/s): negativa en reversa.
func get_forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func get_speed_kmh() -> float:
	return absf(get_forward_speed()) * 3.6


func is_upright() -> bool:
	return global_basis.y.dot(Vector3.UP) >= upright_threshold


## Coloca la mototaxi sobre ground_pos mirando hacia yaw (0 = +Z) y la detiene.
func place_at(ground_pos: Vector3, yaw: float) -> void:
	# Estacionada, la física la duerme y un cuerpo dormido ignora el cambio de posición:
	# se despierta y se fija también en el servidor de física.
	sleeping = false
	var t := Transform3D(Basis(Vector3.UP, yaw), ground_pos + Vector3.UP * spawn_height)
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	steering = 0.0
	_flip_timer = 0.0
	_overturned = false
	_prev_velocity = Vector3.ZERO
	_hit_grace = 1.0  # al aparecer cae unos centímetros y la suspensión se asienta


## Endereza la mototaxi donde está, conservando hacia dónde miraba.
func reset_upright() -> void:
	var fwd := global_basis.z
	fwd.y = 0.0
	var yaw := atan2(fwd.x, fwd.z) if fwd.length() > 0.1 else 0.0
	var p := global_position
	place_at(Vector3(p.x, _ground_height(p), p.z), yaw)
	was_reset.emit()


func _ground_height(p: Vector3) -> float:
	if terrain:
		return terrain.get_height(p.x, p.z)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 50.0, p + Vector3.DOWN * 50.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else p.y


func _read_input() -> void:
	throttle = Input.get_action_strength("moto_accelerate") - Input.get_action_strength("moto_brake")
	steer_input = Input.get_axis("moto_right", "moto_left")
	handbrake = Input.is_action_pressed("moto_handbrake")
	turbo_requested = Input.is_action_pressed("moto_turbo")


# Las acciones se registran por código para no depender de editar el Input Map a mano.
# Si alguien las define en Proyecto > Configuración > Mapa de entrada, se respetan esas.
static func _ensure_input_actions() -> void:
	_add_action("moto_accelerate", [KEY_W, KEY_UP], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [])
	_add_action("moto_brake", [KEY_S, KEY_DOWN], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [])
	_add_action("moto_left", [KEY_A, KEY_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], [])
	_add_action("moto_right", [KEY_D, KEY_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], [])
	_add_action("moto_handbrake", [KEY_SPACE], [], [JOY_BUTTON_A])
	_add_action("moto_headlights", [KEY_L], [], [])
	_add_action("moto_reset", [KEY_R], [], [JOY_BUTTON_Y])
	_add_action("moto_turbo", [KEY_SHIFT], [], [JOY_BUTTON_X])


static func _add_action(action: StringName, keys: Array, axes: Array, buttons: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		InputMap.action_add_event(action, m)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
