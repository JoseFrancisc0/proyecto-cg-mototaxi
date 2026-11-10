class_name JourneyEvents
extends CanvasLayer
## Encuentros independientes: precio acordado, personalidad, incidencias y peligro opcional.
signal hijack_requested
var race: RaceManager
var moto: Mototaxi
var negotiating := false
var kind := "normal"
var profile := "Tranquilo"
var danger_cooldown := 0.0
var dangerous_rolls := 0
var force_event := ""
var _rng := RandomNumberGenerator.new()
var _panel: PanelContainer
var _title: Label
var _message: Label
var _offers: HBoxContainer
var _badge: Label
var _waiting := 0.0
var _input_before := true
var _reference := 0.0
var _ceiling := 0.0
var _counter := false
var _event_done := false
var _threats := 0
var _hijacked := false
var _stop_wait := -1.0
var _final_destination := Vector3.ZERO
var _active := false
const PROFILES := ["Tranquilo","Ahorrador","Apurado","Conversador"]

func setup(manager: RaceManager, saved: Dictionary = {}) -> void:
	race = manager
	moto = race.moto
	layer = 42
	_rng.seed = hash("viajes-%d" % race.world.world_seed)
	danger_cooldown = float(saved.get("danger_cooldown",0))
	_build_ui()
	race.ride_finished.connect(func(_success,_left): _finish())

func _build_ui() -> void:
	_badge = Label.new()
	_badge.position = Vector2(16,154)
	_badge.add_theme_font_size_override("font_size",18)
	_badge.add_theme_color_override("font_color",Color("ffdb38"))
	_badge.add_theme_constant_override("outline_size",5)
	_badge.add_theme_color_override("font_outline_color",Color.BLACK)
	add_child(_badge)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 500
	var box := StyleBoxFlat.new()
	box.bg_color = Color("141922f5")
	box.border_color = Color("ffdb38")
	box.set_border_width_all(2)
	box.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel",box)
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	_panel.add_child(column)
	_title = Label.new()
	_title.text = "ACUERDA EL PASAJE"
	_title.add_theme_font_size_override("font_size",26)
	_title.add_theme_color_override("font_color",Color("ffdb38"))
	column.add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 450
	column.add_child(_message)
	_offers = HBoxContainer.new()
	column.add_child(_offers)
	_panel.hide()

func before_board() -> bool:
	if negotiating: return false
	profile = PROFILES[_rng.randi_range(0,PROFILES.size()-1)]
	_reference = maxf(.5,snappedf(race.ride_fare,.5))
	_ceiling = _reference * (1.04 if profile=="Ahorrador" else (1.4 if profile=="Apurado" else 1.2))
	if not bool(GameSettings.get_option("regateo",true)): return true
	negotiating = true
	_counter = false
	_waiting = 18.0
	_input_before = moto.use_input
	moto.use_input = false
	moto.throttle = 0
	moto.handbrake = true
	var destination := "Destino elegido"
	for landmark in race.world.get_landmarks():
		if landmark.id==race._dropoff_id: destination=str(landmark.get("label",destination))
	_message.text = "%s · %s\n%s · tarifa orientativa S/ %.2f\nElige cuánto cobrar. Puedes rechazar el viaje." % [profile,destination,RaceManager.ride_kind_name(race.ride_kind),_reference]
	_show_offers([snappedf(_reference*.9,.5),_reference,snappedf(_reference*1.3,.5)])
	_panel.show()
	return false

func _show_offers(values: Array) -> void:
	for child in _offers.get_children():
		_offers.remove_child(child)
		child.queue_free()
	for value in values:
		var button := Button.new()
		button.text = "S/ %.2f" % value
		button.custom_minimum_size = Vector2(100,45)
		button.pressed.connect(offer.bind(float(value)))
		_offers.add_child(button)
	var reject := Button.new()
	reject.text = "No, gracias"
	reject.pressed.connect(reject_ride)
	_offers.add_child(reject)
	_offers.get_child(0).grab_focus()

func offer(amount: float) -> void:
	if not negotiating: return
	if amount>_ceiling+.01 and not _counter:
		_counter = true
		_message.text = "«Se me hace mucho, jefe. ¿En S/ %.2f y vamos?»\nPuedes aceptar la contraoferta o esperar otro cliente." % _reference
		_show_offers([_reference])
		return
	race.ride_fare = clampf(amount,.5,_reference*1.6)
	_close_negotiation()
	race._begin_ride()

func _close_negotiation() -> void:
	negotiating = false
	_panel.hide()
	moto.handbrake = false
	moto.use_input = _input_before

func reject_ride() -> void:
	if not negotiating: return
	_close_negotiation()
	race.passenger_said.emit("Está bien, esperaré otra moto.")
	race._new_passenger()

func begin() -> void:
	_active = true
	_event_done = false
	_threats = 0
	_hijacked = false
	_stop_wait = -1
	kind = "normal"
	if bool(GameSettings.get_option("eventos_pasajeros",true)):
		kind = ["normal","apurado","bonificacion","cambio_destino","parada"][_rng.randi_range(0,4)]
	# Zona ficticia independiente de la región, la ropa y el nivel económico.
	var p := race.pickup_zone.global_position
	var zone := Vector2i(floori(p.x/180),floori(p.z/180))
	var eligible := posmod(hash("riesgo-%d-%d-%d" % [race.world.world_seed,zone.x,zone.y]),5)==0
	if bool(GameSettings.get_option("pasajeros_peligrosos",false)) and eligible and danger_cooldown<=0:
		dangerous_rolls += 1
		if _rng.randf() < clampf(float(GameSettings.get_option("robberPassengerChance",.10)),0,1):
			kind = "peligroso"
			danger_cooldown = 240
	if not force_event.is_empty(): kind = force_event
	match kind:
		"apurado":
			race.time_left *= .9
			race.time_limit = race.time_left
			race.ride_fare *= 1.2
			race.passenger_said.emit("Voy con el tiempo justo. Le pago un poco más si llegamos.")
		"bonificacion": race.passenger_said.emit("Si llegamos a tiempo y sin golpes, le dejo una propina.")
		"peligroso":
			var destination_id := race._pick_destination(moto.global_position,RaceManager.RideKind.LARGO)
			if destination_id>=0:
				var destination := race._landmark_pos(destination_id)
				var long_route := race.world.find_road_route(moto.global_position,destination)
				if long_route.size()>1:
					race._dropoff_id=destination_id
					race.ride_kind=RaceManager.RideKind.LARGO
					race.route=long_route
					race.route_length=TerrainWorld.route_length(long_route)
					race.dropoff_zone.place(destination)
					race._show_route(long_route)
			race.time_left = maxf(race.time_left,race.compute_route_time(race.route))
			race.time_limit = race.time_left
			race.passenger_said.emit("Llévame rápido. No quiero que pares por nada.")
		"normal":
			if profile=="Conversador": race.passenger_said.emit("Qué bonito está el camino hoy, ¿no?")
	_badge.text = {"normal":"","apurado":"CLIENTE APURADO · pasaje especial","bonificacion":"BONIFICACIÓN POR VIAJE SUAVE","cambio_destino":"CLIENTE CON CAMBIO DE PLANES","parada":"PARADA INTERMEDIA","peligroso":"PASAJERO PELIGROSO"}.get(kind,"")

func modify_payment(pay: float, success: bool) -> float:
	if success and kind=="bonificacion" and race.late_time<=0 and race._comfort>.75:
		return snappedf(pay+maxf(1.0,race.ride_fare*.2),.1)
	return pay

func _process(delta: float) -> void:
	danger_cooldown = maxf(0,danger_cooldown-delta)
	if negotiating:
		_waiting -= delta
		if _waiting<=0: reject_ride()
	if not _active or race.state!=RaceManager.State.CON_PASAJERO: return
	var fraction := race.time_left/maxf(race.time_limit,.1)
	if kind=="peligroso":
		if fraction<.5 and (_threats&1)==0:
			_threats |= 1
			race.passenger_said.emit("Te dije que era urgente. Sigue por la ruta.")
		if fraction<.2 and (_threats&2)==0:
			_threats |= 2
			race.passenger_said.emit("¡Última oportunidad, apúrate!")
		if race.time_left<=0:
			_badge.text = "PELIGRO · margen %.0f s" % maxf(0,8-race.late_time)
		if race.late_time>=8 and not _hijacked:
			_hijacked = true
			hijack_requested.emit()
	elif kind=="cambio_destino" and fraction<.65 and not _event_done:
		_event_done = true
		_change_destination()
	elif kind=="parada" and fraction<.9 and not _event_done:
		_event_done = true
		if race.route.size()>6:
			_final_destination = race.dropoff_zone.global_position
			var mid := race.route[race.route.size()/2]
			race.dropoff_zone.place(mid)
			race.route = race.world.find_road_route(moto.global_position,mid)
			race._show_route(race.route)
			_stop_wait = 0
			race.passenger_said.emit("¿Puede parar un momento a mitad del camino? Le sumo el tiempo.")
	if _stop_wait>0:
		_stop_wait -= delta
		if _stop_wait<=0: _resume_after_stop()

func stop_before_finish() -> bool:
	if kind!="parada" or _stop_wait<0: return false
	if _stop_wait==0:
		_stop_wait = 2.0
		moto.throttle = 0
	return true

func _resume_after_stop() -> void:
	_stop_wait = -1
	race.dropoff_zone.place(_final_destination)
	race.time_left += 12
	race.route = race.world.find_road_route(moto.global_position,_final_destination)
	race._show_route(race.route)
	race.passenger_said.emit("Listo, gracias. Ahora sí, al destino.")

func _change_destination() -> void:
	var id := race._pick_destination(moto.global_position,RaceManager.RideKind.CORTO)
	if id<0 or id==race._dropoff_id: return
	var destination := race._landmark_pos(id)
	var path := race.world.find_road_route(moto.global_position,destination)
	if path.size()<2: return
	race._dropoff_id = id
	race.route = path
	race.route_length = TerrainWorld.route_length(path)
	race.time_left = maxf(race.time_left,race.compute_route_time(path))
	race.time_limit = race.time_left
	race.dropoff_zone.place(destination)
	race._show_route(path)
	race.passenger_said.emit("Cambio de planes: mejor hasta %s. Tenemos tiempo para llegar." % race.get_target_label())

func _finish() -> void:
	_active = false
	_badge.text = ""
	if negotiating: _close_negotiation()

func get_save_data() -> Dictionary:
	return {"danger_cooldown":danger_cooldown}
