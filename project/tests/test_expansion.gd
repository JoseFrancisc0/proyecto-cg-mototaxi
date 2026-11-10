extends SceneTree
const Scripts = [preload("res://scripts/main.gd"),preload("res://scripts/driver_studio.gd"),preload("res://scripts/peru_world_life.gd"),preload("res://scripts/game_radio.gd"),preload("res://scripts/journey_events.gd")]
var failures := 0
func check(condition: bool, description: String) -> void:
	print("OK " if condition else "FAIL ",description)
	if not condition: failures+=1
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	CareerSave.path="user://test_expansion_career.cfg"
	GameSettings.path="user://test_expansion_settings.cfg"
	CareerSave.reset()
	GameSettings.set_option("regateo",true)
	GameSettings.set_option("emisora",0)
	GameSettings.set_option("pasajeros_peligrosos",false)
	var main: Node3D=load("res://main.tscn").instantiate()
	main.show_menu=false
	var world: TerrainWorld=main.get_node("TerrainWorld")
	world.use_editor_scene=false
	world.generate_on_ready=false
	world.grid_size=128
	world.cell_size=6.0
	world.erosion_enabled=false
	world.vegetation_enabled=false
	root.add_child(main)
	var deadline:=Time.get_ticks_msec()+45000
	while main.session==null or paused:
		await create_timer(.05,true).timeout
		if Time.get_ticks_msec()>deadline:
			push_error("La partida no inició")
			quit(1)
			return
	await create_timer(1,true).timeout
	check(main.journeys!=null and main.world_life!=null and main.radio!=null,"Módulos conectados a la partida real")
	check(main.world_life._cars.size()>0 and main.world_life._walkers.size()>0,"Tráfico y peatones aparecen cerca de las vías")
	var heights:=world._heights.duplicate()
	main.world_life._process(2)
	check(heights==world._heights,"La ambientación conserva el terreno")
	var clock: float=main.session.day_time_left
	main.session.day_time_left=0
	main.world_life._process(2)
	check(main.get_node("Sun").light_energy<.15,"El sol se atenúa al finalizar la tarde")
	main.session.day_time_left=clock
	var race: RaceManager=main.race
	var events: JourneyEvents=main.journeys
	race._board()
	check(events.negotiating and not main.moto.use_input,"El regateo retiene la recogida y detiene el acelerador")
	events.offer(events._reference*2)
	check(events._counter and events.negotiating,"Una oferta excesiva recibe contraoferta")
	events.force_event="bonificacion"
	events.offer(events._reference)
	check(race.state==RaceManager.State.CON_PASAJERO and not events.negotiating,"Aceptar inicia el viaje")
	check(events.modify_payment(10,true)>10 and events.modify_payment(10,false)==10,"Propina condicionada al viaje completado")
	events.danger_cooldown=83
	check(main.save_game().journeys.danger_cooldown==83,"Se guarda el tiempo entre encuentros peligrosos")
	events.force_event="parada"
	events.begin()
	race.time_left=race.time_limit*.8
	events._process(0)
	if events._stop_wait==0:
		var final: Vector3=events._final_destination
		check(events.stop_before_finish(),"Parada intermedia no cobra el viaje como entrega")
		events._process(2.1)
		check(race.dropoff_zone.global_position.is_equal_approx(final),"Después de parar se recupera el destino final")
	check(main.radio.player.stream!=null and main.radio.ambience.stream!=null,"Radio y ambiente tienen audio importado")
	var before: AudioStream=main.radio.player.stream
	main.radio.station=1
	main.radio._tune()
	check(main.radio.player.stream!=before and main.radio.live.url==GameRadio.STATIONS[1][1],"Cambiar emisora selecciona otra señal real")
	var source: Node3D=DriverAvatar.load_avatar()
	check(source!=null,"Conductor de la fotografía disponible")
	if source:
		var driver:=DriverAvatar.new()
		root.add_child(driver)
		check(driver.setup(2,source,true) and driver.skeleton!=null,"Conductor articulado sentado")
		var hip:=driver._bone(["Hips"])
		check(hip>=0,"Esqueleto reconoce la pelvis del conductor")
		driver.queue_free()
	for i in 90: await physics_frame
	# Peligro: una sola tirada por encuentro elegible, nunca por fotograma.
	GameSettings.set_option("pasajeros_peligrosos",true)
	GameSettings.set_option("robberPassengerChance",1.0)
	events.force_event=""
	events.danger_cooldown=0
	var pickup: Vector3=race.pickup_zone.global_position
	for x in range(-2,3):
		if posmod(hash("riesgo-%d-%d-%d"%[world.world_seed,x,0]),5)==0:
			race.pickup_zone.global_position=Vector3(x*180+1,0,1)
			break
	var rolls: int=events.dangerous_rolls
	events.begin()
	check(events.kind=="peligroso" and events.dangerous_rolls==rolls+1,"Una tirada en una zona elegible")
	for i in 20: events._process(.01)
	check(events.dangerous_rolls==rolls+1 and events.danger_cooldown>239,"Sin repetir tiradas y con enfriamiento")
	race.pickup_zone.global_position=pickup
	main._on_hijack()
	await create_timer(6,true).timeout
	check(main.game_over_screen.visible and not main.session.playing,"Asalto termina la jornada mediante las reglas de carrera")
	check(main.game_over_screen._title.text=="MOTOTAXI ROBADA","Opción sin muerte respetada")
	main.restart()
	check(main.moto.driver.visible and main.cam.target==main.moto and not main._hijacking,"Reintentar recupera conductor, cámara y controles")
	paused=false
	main.queue_free()
	await process_frame
	CareerSave.reset()
	print("Expansión: %d errores"%failures)
	quit(0 if failures==0 else 1)
