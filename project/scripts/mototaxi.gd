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

## Si es false, la entrada se fija desde código (pruebas, IA, cinemáticas).
@export var use_input := true

## Entrada normalizada: throttle en [-1, 1] (negativo = freno/reversa),
## steer_input en [-1, 1] (positivo = izquierda).
var throttle := 0.0
var steer_input := 0.0
var handbrake := false

## Opcional: si se asigna, el reinicio usa la altura del terreno en vez de un rayo.
var terrain: TerrainWorld

var _wheels: Array[VehicleWheel3D] = []
var _flip_timer := 0.0


func _ready() -> void:
	_ensure_input_actions()
	for c in get_children():
		var w := c as VehicleWheel3D
		if w:
			_wheels.append(w)


func _physics_process(delta: float) -> void:
	if use_input:
		_read_input()

	var speed := get_forward_speed()
	var max_speed := max_speed_kmh / 3.6
	var max_rev := max_reverse_kmh / 3.6

	# Motor y freno. Acelerar mientras va en reversa (o frenar yendo hacia delante)
	# primero frena; recién detenida pasa a la otra marcha.
	var force := 0.0
	var brk := 0.0
	if throttle > 0.01:
		# Fuerza completa hasta el 85 % de la velocidad máxima; luego baja a 0 en el tope.
		force = max_engine_force * _gear(speed) * throttle * clampf((max_speed - speed) / (0.15 * max_speed), 0.0, 1.0)
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
	for w in _wheels:
		w.brake = brk + (handbrake_force if handbrake and w.use_as_traction else 0.0)
		if w.is_in_contact():
			contacts += 1
	# El freno de Godot es un impulso limitado y en pendientes deja deslizar un poco;
	# estacionada y con todas las ruedas apoyadas, se amortigua el movimiento.
	var parked := absf(throttle) <= 0.01 and absf(speed) < 0.5 and contacts == _wheels.size()
	linear_damp = park_damp if parked else 0.0

	# Dirección: se reduce con la velocidad y se mueve gradualmente hacia el objetivo.
	var speed_factor := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var target := steer_input * max_steer * lerpf(1.0, steer_at_max_speed, speed_factor)
	steering = move_toward(steering, target, steer_speed * delta)

	# Detección de vuelco: volcada y casi quieta durante un rato -> se endereza.
	if global_basis.y.dot(Vector3.UP) < upright_threshold and linear_velocity.length() < 3.0:
		_flip_timer += delta
	else:
		_flip_timer = 0.0
	var manual_reset := use_input and Input.is_action_just_pressed("moto_reset")
	if _flip_timer > flip_reset_time or manual_reset:
		reset_upright()


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
	global_transform = Transform3D(Basis(Vector3.UP, yaw), ground_pos + Vector3.UP * spawn_height)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	steering = 0.0
	_flip_timer = 0.0


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


# Las acciones se registran por código para no depender de editar el Input Map a mano.
# Si alguien las define en Proyecto > Configuración > Mapa de entrada, se respetan esas.
static func _ensure_input_actions() -> void:
	_add_action("moto_accelerate", [KEY_W, KEY_UP], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [])
	_add_action("moto_brake", [KEY_S, KEY_DOWN], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [])
	_add_action("moto_left", [KEY_A, KEY_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], [])
	_add_action("moto_right", [KEY_D, KEY_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], [])
	_add_action("moto_handbrake", [KEY_SPACE], [], [JOY_BUTTON_A])
	_add_action("moto_reset", [KEY_R], [], [JOY_BUTTON_Y])


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
