extends Camera3D
## Fits the existing Camera to the existing Terrain; does not replace the scene.
var target := Vector3.ZERO
var distance := 600.0
var yaw := 0.65
var pitch := 0.75
var rotating := false

func _ready() -> void:
	current = true
	var terrain := get_node("../Terrain")
	distance = terrain.grid_size * terrain.cell_size * 1.25
	far = distance * 6.0
	target = terrain.global_position
	terrain.generation_finished.connect(_fit_after_generation)
	_update_camera()

func _fit_after_generation(success: bool) -> void:
	if success:
		var terrain := get_node("../Terrain")
		target = terrain.to_global(Vector3(0, terrain.get_height(0, 0), 0))
		_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rotating = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10, distance * 0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(4000, distance * 1.1)
	if event is InputEventMouseMotion and rotating:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch + event.relative.y * 0.005, 0.15, 1.5)
	_update_camera()

func _update_camera() -> void:
	global_position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at(target, Vector3.UP)
