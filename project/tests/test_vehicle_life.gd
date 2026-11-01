extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	print('OK ' if ok else 'FAIL ',message)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,2,200)
	shape.shape = box;shape.position.y=-1
	floor_body.add_child(shape);root.add_child(floor_body)
	var moto := load('res://scenes/mototaxi.tscn').instantiate() as Mototaxi
	moto.use_input=false
	root.add_child(moto)
	var hashes := {}
	var turbo_hashes := {}
	var release_hashes := {}
	for i in 6:
		moto.select_vehicle(i)
		var label: String = VehicleCatalog.entry(i).name
		check(moto.wheel_visuals.wheels.size()==(5 if i==2 else 3),label+': todas las ruedas independientes')
		check(moto.get_node('VehicleVisual').scale.is_equal_approx(Vector3.ONE*1.2),label+': escala ampliada')
		var body := moto.get_node('VehicleVisual').find_child('Body',true,false) as Node3D
		var body_transform := body.transform
		moto.wheel_visuals.update_wheels(.1,3.0,.4)
		for wheel: Dictionary in moto.wheel_visuals.wheels:
			check(absf(wheel.spin.rotation.x)>.1,label+': gira '+str(wheel.spin.name))
			check(is_equal_approx(wheel.pivot.rotation.y,.4 if wheel.front else 0.0),label+': dirección solo delante')
			check(wheel.pivot.get_meta('extras',{}).has('wheel_radius'),label+': radio del neumático importado')
			check(wheel.spin.get_meta('extras',{}).get('complete_wheel',false),label+': rueda completa sin fragmentos de carrocería')
			var tire := wheel.spin.find_child('Tire*',false,false) as MeshInstance3D
			var vertices: PackedVector3Array = tire.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var radius: float = wheel.pivot.get_meta('extras').wheel_radius
			var outer_radius := 0.0
			for vertex in vertices: outer_radius=maxf(outer_radius,Vector2(vertex.y,vertex.z).length())
			check(absf(outer_radius-radius)<.002,label+': neumático redondo y centrado')
		var angles: Array[float] = []
		for wheel: Dictionary in moto.wheel_visuals.wheels:
			angles.append(wheel.spin.rotation.x)
		moto.wheel_visuals.update_wheels(.1,0.0,-.4)
		for j in moto.wheel_visuals.wheels.size():
			var wheel: Dictionary = moto.wheel_visuals.wheels[j]
			var before: float = wheel.spin.rotation.x
			check(is_equal_approx(before,angles[j]),label+': parada sin giro de rodadura')
		moto.wheel_visuals.update_wheels(.1,-3.0,-.4)
		for wheel: Dictionary in moto.wheel_visuals.wheels:
			check(absf(wheel.spin.rotation.x)<.001,label+': reversa invierte rodadura')
		check(body.transform.is_equal_approx(body_transform),label+': carrocería no gira con las ruedas')
		var engine: VehicleEngineAudio = moto.engine_audio
		check(engine.idle.stream.get_length()>3.9 and engine.load_sound.stream.get_length()>3.9,label+': dos capas de audio')
		check(engine.idle.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,label+': motor continuo')
		var signature := hash(engine.load_sound.stream.data)
		check(not hashes.has(signature),label+': sonido propio')
		hashes[signature]=true
		engine.update_engine(.5,0,0,20,false)
		var idle_pitch := engine.idle.pitch_scale
		engine.update_engine(.5,12,1,20,true)
		check(engine.idle.pitch_scale>idle_pitch+.2 and engine.load_sound.volume_db>engine.idle.volume_db,label+': sonido responde al acelerar/turbo')
		var turbo_signature := hash(engine.turbo_sound.stream.data)
		var release_signature := hash(engine.turbo_release.stream.data)
		check(not turbo_hashes.has(turbo_signature) and not release_hashes.has(release_signature),label+': turbo y descarga exclusivos')
		turbo_hashes[turbo_signature]=true
		release_hashes[release_signature]=true
		check(engine.turbo_sound.volume_db>-25,label+': turbo audible al activarse')
		engine.update_engine(.2,12,1,20,false)
		check(engine.turbo_release.playing and engine.turbo_sound.volume_db<-50,label+': descarga al soltar turbo')
	# Integración: la conducción mueve los neumáticos sin llamadas manuales al animador.
	moto.select_vehicle(5)
	moto.place_at(Vector3.ZERO,0)
	for f in 60: await physics_frame
	moto.throttle=1.0
	moto.steer_input=.7
	for f in 100: await physics_frame
	check(moto.get_speed_kmh()>10,'Aceleración física real')
	check(moto.engine_audio.rpm>.3,'Motor sigue la conducción real')
	var front: Dictionary = moto.wheel_visuals.wheels[0]
	check(absf(front.spin.rotation.x)>.01 and front.pivot.rotation.y>.05,'Rueda delantera gira y dirige durante la partida')
	print('Sonidos/ruedas: %d errores' % failures)
	quit(failures)
