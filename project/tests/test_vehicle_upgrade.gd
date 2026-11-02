extends SceneTree
var failures := 0
var moto: Mototaxi
class SurfaceWorld extends TerrainWorld:
	var offroad := false
	func get_offroad_amount(_x: float, _z: float) -> float:
		return 1.0 if offroad else 0.0
func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok: failures += 1
func frames(count: int) -> void:
	for i in count: await physics_frame
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Engine.physics_ticks_per_second = 60
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500,2,2000)
	shape.shape = box
	shape.position.y = -1
	floor_body.add_child(shape)
	root.add_child(floor_body)
	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	root.add_child(moto)
	for i in 6:
		moto.select_vehicle(i)
		check(moto.get_node_or_null("VehicleVisual") != null,"Modelo %s importado" % VehicleCatalog.entry(i).name)
		check(is_equal_approx(moto.max_engine_force,VehicleCatalog.entry(i).force),"Ficha y motor coinciden")
	moto.select_vehicle(2)
	var surface := SurfaceWorld.new()
	surface.generate_on_ready = false
	root.add_child(surface)
	moto.terrain = surface
	moto.place_at(Vector3.ZERO,0)
	await frames(90)
	moto.throttle = 1
	await frames(360)
	var road_speed := moto.get_speed_kmh()
	surface.offroad = true
	await frames(360)
	check(moto.get_speed_kmh() < road_speed * 0.75,"Tierra reduce velocidad: %.1f vs %.1f km/h" % [moto.get_speed_kmh(),road_speed])
	check(moto.get_node("WheelRearL").wheel_friction_slip < moto.road_grip * 0.7,"Tierra reduce agarre")
	surface.offroad = false
	moto.turbo_requested = true
	await frames(90)
	check(moto.turbo_active and moto.turbo_charge < 0.9,"Turbo consume reserva")
	await frames(420)
	check(not moto.turbo_active and moto.turbo_charge < 0.28,"Turbo agotado espera recarga mínima")
	moto.turbo_requested = false
	await frames(120)
	check(moto.turbo_charge > 0.28,"Turbo se recarga")
	# Reinicio en rampa real de 35 grados, desde reposo y con acelerador/turbo.
	moto.terrain = null
	moto.throttle = 0
	moto.turbo_requested = false
	floor_body.rotation.x = -atan(0.7)
	floor_body.position.y = -0.22
	await frames(2)
	moto.place_at(Vector3.ZERO,0)
	moto.rotation.x = -atan(0.7)
	await frames(90)
	moto.turbo_charge = 1
	moto._turbo_locked = false
	moto.throttle = 1
	moto.turbo_requested = true
	var start := moto.global_position
	await frames(300)
	check(moto.global_position.z > start.z + 12 and moto.global_position.y > start.y + 8,"Turbo arranca en rampa 35°: avance %.1f, subida %.1f m" % [moto.global_position.z-start.z,moto.global_position.y-start.y])
	check(moto.is_upright(),"Subida sin vuelco")
	# La ayuda de subida no acelera un vehículo suspendido en el aire.
	moto.place_at(Vector3(0,200,0),0)
	moto.rotation.x = -0.5
	moto.linear_velocity = Vector3.ZERO
	await frames(30)
	check(absf(moto.linear_velocity.z) < 0.1,"Sin empuje de turbo en el aire")
	print("Garage/conducción: %d errores" % failures)
	quit(failures)
