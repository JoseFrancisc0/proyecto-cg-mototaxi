class_name RaceHUD
extends CanvasLayer
## HUD de la carrera: velocidad, estado, objetivo y distancia, temporizador, marcador
## (soles), vida de la mototaxi, ánimo del pasajero y lo que dice, minimapa con la ruta
## recomendada (estilo GTA), avisos (atrapado, borde del mapa) y anuncios grandes.
## Los controles se crean por código para no depender de editar la escena.

const COLOR_PICKUP := Color(1.0, 0.85, 0.25)
const COLOR_DROPOFF := Color(0.35, 1.0, 0.5)
const COLOR_FAIL := Color(1.0, 0.3, 0.25)

var race: RaceManager
var moto: Mototaxi
var session: GameSession

var _info: Label
var _objective: Label
var _timer: Label
var _score: Label
var _banner: Label
var _sub_banner: Label
var minimap: Minimap
var _banner_tween: Tween
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _mood_box: VBoxContainer
var _mood_bar: ProgressBar
var _mood_fill: StyleBoxFlat
var _speech: Label
var _speech_tween: Tween
var _warning: Label
var _warning_until := 0
var _damage_flash: ColorRect
var _turbo_bar: ProgressBar
var _turbo_label: Label


func _ready() -> void:
	_turbo_bar = ProgressBar.new()
	_turbo_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Encima de la barra de vida (que ocupa de -64 a -16).
	_turbo_bar.offset_left = -276
	_turbo_bar.offset_right = -16
	_turbo_bar.offset_top = -98
	_turbo_bar.offset_bottom = -78
	_turbo_bar.show_percentage = false
	add_child(_turbo_bar)
	_turbo_label = _label(18, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_turbo_label.offset_left = -300
	_turbo_label.offset_right = -16
	_turbo_label.offset_top = -128
	_turbo_label.offset_bottom = -100
	_info = _label(18, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_info.offset_left = 16
	_info.offset_right = 1000
	_info.offset_top = -70
	_info.offset_bottom = -12
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_objective = _label(22, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_objective.position = Vector2(16, 12)

	_score = _label(22, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_score.offset_left = -320
	_score.offset_right = -16
	_score.offset_top = 12

	_timer = _label(48, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_timer.offset_left = -150
	_timer.offset_right = 150
	_timer.offset_top = 8

	# Minimapa abajo a la izquierda, sobre la línea de velocidad y controles.
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.offset_left = 16
	minimap.offset_right = 16 + 280
	minimap.offset_top = -100 - 200
	minimap.offset_bottom = -100
	add_child(minimap)

	_banner = _label(56, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.offset_left = -600
	_banner.offset_right = 600
	_banner.offset_top = -110
	_banner.offset_bottom = -40
	_sub_banner = _label(26, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_sub_banner.offset_left = -600
	_sub_banner.offset_right = 600
	_sub_banner.offset_top = -35
	_sub_banner.offset_bottom = 5
	_banner.modulate.a = 0.0
	_sub_banner.modulate.a = 0.0

	# Vida (abajo a la derecha).
	var hb := VBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hb.offset_left = -276
	hb.offset_right = -16
	hb.offset_top = -64
	hb.offset_bottom = -16
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	hb.add_child(_small_label("Mototaxi"))
	_health_fill = StyleBoxFlat.new()
	_health_bar = _bar(hb, _health_fill)

	# Ánimo del pasajero (debajo del objetivo, solo con pasajero a bordo).
	_mood_box = VBoxContainer.new()
	_mood_box.position = Vector2(16, 84)
	_mood_box.custom_minimum_size = Vector2(260, 0)
	_mood_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mood_box)
	_mood_box.add_child(_small_label("Ánimo del pasajero"))
	_mood_fill = StyleBoxFlat.new()
	_mood_bar = _bar(_mood_box, _mood_fill)
	_speech = Label.new()
	_speech.add_theme_font_size_override("font_size", 22)
	_speech.add_theme_color_override("font_color", Color(1, 1, 1))
	_speech.add_theme_color_override("font_outline_color", Color.BLACK)
	_speech.add_theme_constant_override("outline_size", 6)
	_speech.modulate.a = 0.0
	_mood_box.add_child(_speech)
	_mood_box.visible = false

	_warning = _label(30, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_warning.offset_left = -500
	_warning.offset_right = 500
	_warning.offset_top = -150
	_warning.offset_bottom = -100
	_warning.modulate = COLOR_FAIL

	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(1, 0, 0, 0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)


## Conecta el HUD al gestor de carrera.
func bind(r: RaceManager, m: Mototaxi) -> void:
	race = r
	moto = m
	race.ride_started.connect(_on_ride_started)
	race.ride_finished.connect(_on_ride_finished)
	race.state_changed.connect(_on_state_changed)
	race.paid.connect(_on_paid)
	race.passenger_said.connect(say)
	moto.damaged.connect(_on_damaged)
	if r.world:
		if minimap == null:  # bind antes de entrar al árbol: el minimapa se crea en _ready
			await ready
		minimap.setup(r.world, r, m)


func bind_session(s: GameSession) -> void:
	session = s
	session.warning.connect(_on_warning)


func _process(_delta: float) -> void:
	if moto:
		_turbo_bar.value = moto.turbo_charge * 100.0
		_turbo_label.text = "TURBO ACTIVO" if moto.turbo_active else "TURBO · SHIFT / X"
		_turbo_label.modulate = Color("ffdb38") if moto.turbo_active else Color.WHITE
		_info.text = "%d km/h
W/S: acelerar / frenar y reversa   A/D: girar   Espacio: freno de mano   Shift: turbo   R: enderezar   M: mapa   Esc: pausa" 			% roundi(moto.get_speed_kmh())
		if moto.offroad_amount > 0.45:
			_info.text = "TIERRA · MENOR AGARRE   " + _info.text
		var hp := moto.get_health_ratio()
		_health_bar.value = hp * 100.0
		_health_fill.bg_color = Color(0.9, 0.2, 0.15).lerp(Color(0.25, 0.85, 0.3), hp)
	if Time.get_ticks_msec() > _warning_until:
		_warning.text = ""
	if race == null:
		return

	if session and session.playing:
		var met := race.earnings + 0.001 >= session.quota
		# Reloj del juego acelerado (como en GTA): la jornada va de 7:00 a 19:00 en 6 min reales.
		var clock := "%s  ·  termina este viaje" % session.get_clock_text() if session.overtime else "%s  (cierra %s)" % [session.get_clock_text(), session.get_closing_text()]
		_score.text = "Día %d  ·  %s\nS/ %.2f / cuota S/ %.2f%s\nEntregas: %d   Perdidos: %d" % [
			session.day, clock, race.earnings, session.quota, "  ✓" if met else "",
			race.deliveries, race.failures]
		_score.modulate = COLOR_DROPOFF if met else Color.WHITE
	else:
		_score.text = "S/ %.2f\nEntregas: %d   Perdidos: %d" % [race.earnings, race.deliveries, race.failures]
	_mood_box.visible = race.state == RaceManager.State.CON_PASAJERO
	if _mood_box.visible:
		_mood_bar.value = race.mood * 100.0
		_mood_fill.bg_color = Color(0.9, 0.2, 0.15).lerp(Color(0.25, 0.85, 0.3), race.mood)

	var dist := race.get_target_distance()
	match race.state:
		RaceManager.State.LIBRE:
			_objective.text = "Recoge al pasajero que te hace señas\n%d m  ·  detente a su lado (< %d km/h)" \
				% [roundi(dist), roundi(race.board_speed_kmh)]
			_objective.modulate = COLOR_PICKUP
			_timer.text = ""
		RaceManager.State.CON_PASAJERO:
			var destination := race.get_target_label()
			_objective.text = "Destino: %s\n%d m" % [destination, roundi(dist)] if not destination.is_empty() \
				else "Lleva al pasajero al punto verde del mapa\n%d m" % roundi(dist)
			_objective.modulate = COLOR_DROPOFF
			if race.time_left > 0.0:
				_timer.text = _fmt_time(race.time_left)
				var urgent := race.time_left < 10.0
				_timer.modulate = COLOR_FAIL if urgent else Color.WHITE
				if urgent:  # Parpadeo en los últimos segundos.
					_timer.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.015)
			else:
				# Tarde: paga menos; al acabarse el margen se baja sin pagar.
				_timer.text = "TARDE +%s" % _fmt_time(race.late_time)
				_timer.modulate = COLOR_FAIL
				_timer.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.015)
		_:
			_objective.text = "Esperando nuevo pasajero..."
			_objective.modulate = Color.WHITE

	var c := COLOR_PICKUP if race.state == RaceManager.State.LIBRE else COLOR_DROPOFF
	minimap.route_color = c
	minimap.target_color = c


func _on_state_changed(s: RaceManager.State) -> void:
	if s == RaceManager.State.LIBRE:
		_timer.text = ""


func _on_ride_started(limit: float, length: float) -> void:
	show_banner("¡Pasajero a bordo!", "Ruta de %d m · tienes %s" % [roundi(length), _fmt_time(limit)], COLOR_DROPOFF)


func _on_ride_finished(success: bool, _time_left: float) -> void:
	_timer.text = ""
	if not success:
		show_banner("¡DEMASIADO TARDE!", "El pasajero se bajó molesto y no pagó", COLOR_FAIL)


func _on_paid(amount: float, fare: float) -> void:
	if amount <= 0.0:
		show_banner("ENTREGADO, PERO NO PAGÓ", "Pasaje de S/ %.2f  ·  el servicio fue muy malo" % fare, COLOR_FAIL)
	elif amount >= fare - 0.05:
		show_banner("¡PASAJERO ENTREGADO!", "Pagó el pasaje completo: S/ %.2f" % amount, COLOR_DROPOFF)
	else:
		var why := "por llegar tarde" if race.late_time > 0.0 else "por los golpes"
		show_banner("PASAJERO ENTREGADO", "Pagó S/ %.2f de S/ %.2f  ·  %s" % [amount, fare, why], COLOR_PICKUP)


## Lo que dice el pasajero, bajo su barra de ánimo.
func say(text: String) -> void:
	_speech.text = "\"%s\"" % text
	if _speech_tween:
		_speech_tween.kill()
	_speech.modulate.a = 1.0
	_speech_tween = create_tween()
	_speech_tween.tween_property(_speech, "modulate:a", 0.0, 0.8).set_delay(2.5)


func _on_damaged(amount: float, _reason: String) -> void:
	var a := clampf(amount / 40.0, 0.12, 0.45)
	_damage_flash.color.a = a
	create_tween().tween_property(_damage_flash, "color:a", 0.0, 0.5)


func _on_warning(text: String, seconds_left: float) -> void:
	_warning.text = text if seconds_left < 0.0 else "%s  (%d s)" % [text, ceili(seconds_left)]
	_warning_until = Time.get_ticks_msec() + 300


## Limpia anuncios, avisos y temporizador (al reiniciar la partida).
func reset_view() -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_sub_banner.modulate.a = 0.0
	_speech.modulate.a = 0.0
	_warning.text = ""
	_timer.text = ""
	_damage_flash.color.a = 0.0


## Muestra un anuncio grande en el centro que se desvanece solo.
func show_banner(title: String, subtitle: String, c: Color, seconds := 2.5) -> void:
	_banner.text = title
	_sub_banner.text = subtitle
	_banner.modulate = c
	_sub_banner.modulate = Color.WHITE
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween().set_parallel()
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6).set_delay(seconds)
	_banner_tween.tween_property(_sub_banner, "modulate:a", 0.0, 0.6).set_delay(seconds)


static func _fmt_time(t: float) -> String:
	var s := ceili(t)
	return "%d:%02d" % [s / 60, s % 60]


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l


func _bar(parent: Control, fill: StyleBoxFlat) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260, 18)
	bar.show_percentage = false
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	fill.set_corner_radius_all(4)
	fill.bg_color = Color(0.25, 0.85, 0.3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _label(size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
