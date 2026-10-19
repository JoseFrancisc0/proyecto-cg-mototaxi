class_name ChaseCamera
extends Camera3D
## Cámara de persecución: se ubica detrás y arriba del objetivo, lo sigue con
## suavizado exponencial y nunca baja de la superficie del terreno.

@export var target: Node3D
@export var distance := 6.5
@export var height := 2.6
@export var look_height := 1.2
@export var follow_speed := 5.0
@export var ground_clearance := 1.0

var terrain: TerrainWorld

var _flat_fwd := Vector3.FORWARD


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_speed * delta))
	_look()


## Salta directo a la posición final (al aparecer o reiniciar).
func snap() -> void:
	if target == null:
		return
	global_position = _desired_position()
	_look()


func _desired_position() -> Vector3:
	var fwd := target.global_basis.z
	fwd.y = 0.0
	if fwd.length() > 0.1:  # Si el vehículo apunta al cielo o al suelo, se mantiene la última dirección.
		_flat_fwd = fwd.normalized()
	var pos := target.global_position - _flat_fwd * distance + Vector3.UP * height
	if terrain:
		pos.y = maxf(pos.y, terrain.get_height(pos.x, pos.z) + ground_clearance)
	return pos


func _look() -> void:
	var at := target.global_position + Vector3.UP * look_height
	if global_position.distance_squared_to(at) > 0.01:
		look_at(at)
