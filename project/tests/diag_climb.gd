extends SceneTree
## Diagnóstico: pendiente máxima que sube la mototaxi (arrancando desde parada y lanzada).
##   Godot_console.exe --headless --path project -s res://tests/diag_climb.gd

var moto: Mototaxi

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Rampa infinita de pendiente 'grade' (tan) que sube hacia +Z.
func _ramp(grade: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 600)
	cs.shape = box
	b.add_child(cs)
	var ang := atan(grade)
	b.transform = Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(0, -1.0 / cos(ang), 0))
	root.add_child(b)
	return b

func _try(grade: float, run_up: bool) -> float:
	var ramp := _ramp(grade)
	await physics_frame
	var ang := atan(grade)
	var start := Vector3(0, 0, -150.0 if run_up else 0.0)
	start.y = start.z * grade
	moto.global_transform = Transform3D(Basis(Vector3.RIGHT, -ang), start + Vector3.UP * 0.6)
	moto.linear_velocity = Vector3.ZERO
	moto.angular_velocity = Vector3.ZERO
	if run_up:
		moto.linear_velocity = Vector3(0, grade, 1).normalized() * 15.0
	moto.throttle = 1.0
	await _frames(60 * 12)
	var climbed := moto.global_position.z - start.z
	moto.throttle = 0.0
	ramp.queue_free()
	await physics_frame
	return climbed

func _initialize() -> void:
	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	root.add_child(moto)
	await physics_frame
	print("pendiente  grados  avance_desde_parada  avance_lanzada(54km/h)")
	for g in [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.8, 1.0]:
		var a := await _try(g, false)
		var b := await _try(g, true)
		print("%5.2f  %5.1f°  %7.1f m  %7.1f m" % [g, rad_to_deg(atan(g)), a, b])
	quit()
