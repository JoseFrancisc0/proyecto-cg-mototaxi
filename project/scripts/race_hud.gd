class_name RaceHUD
extends CanvasLayer
## HUD básico de la carrera: velocidad, estado, objetivo y distancia, temporizador,
## marcador, flecha hacia el objetivo y anuncios grandes (recogida, entrega, fallo).
## Los controles se crean por código para no depender de editar la escena.

const COLOR_PICKUP := Color(1.0, 0.85, 0.25)
const COLOR_DROPOFF := Color(0.35, 1.0, 0.5)
const COLOR_FAIL := Color(1.0, 0.3, 0.25)

var race: RaceManager
var moto: Mototaxi

var _info: Label
var _objective: Label
var _timer: Label
var _score: Label
var _banner: Label
var _sub_banner: Label
var _arrow: _Arrow
var _banner_tween: Tween


func _ready() -> void:
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

	_arrow = _Arrow.new()
	_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_arrow.offset_left = -30
	_arrow.offset_right = 30
	_arrow.offset_top = 80
	_arrow.offset_bottom = 140
	add_child(_arrow)

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


## Conecta el HUD al gestor de carrera.
func bind(r: RaceManager, m: Mototaxi) -> void:
	race = r
	moto = m
	race.ride_started.connect(_on_ride_started)
	race.ride_finished.connect(_on_ride_finished)
	race.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	if moto:
		_info.text = "%d km/h\nW/S: acelerar / frenar y reversa   A/D: girar   Espacio: freno de mano   R: enderezar" \
			% roundi(moto.get_speed_kmh())
	if race == null:
		return

	_score.text = "Entregas: %d\nFallidas: %d" % [race.deliveries, race.failures]

	var dist := race.get_target_distance()
	match race.state:
		RaceManager.State.LIBRE:
			_objective.text = "Busca al pasajero (zona amarilla)\n%d m  ·  entra despacio (< %d km/h)" \
				% [roundi(dist), roundi(race.board_speed_kmh)]
			_objective.modulate = COLOR_PICKUP
			_timer.text = ""
		RaceManager.State.CON_PASAJERO:
			_objective.text = "Lleva al pasajero al destino (zona verde)\n%d m" % roundi(dist)
			_objective.modulate = COLOR_DROPOFF
			_timer.text = _fmt_time(race.time_left)
			var urgent := race.time_left < 10.0
			_timer.modulate = COLOR_FAIL if urgent else Color.WHITE
			if urgent:  # Parpadeo en los últimos segundos.
				_timer.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.015)
		_:
			_objective.text = "Esperando nuevo pasajero..."
			_objective.modulate = Color.WHITE

	# Flecha: arriba = hacia donde mira la mototaxi; gira hacia el objetivo.
	var target := race.get_target()
	_arrow.visible = target != Vector3.INF and moto != null
	if _arrow.visible:
		_arrow.color = COLOR_PICKUP if race.state == RaceManager.State.LIBRE else COLOR_DROPOFF
		var fwd := moto.global_basis.z
		var to := target - moto.global_position
		fwd.y = 0.0
		to.y = 0.0
		if fwd.length() > 0.01 and to.length() > 0.01:
			# Ángulo positivo = objetivo a la izquierda; en pantalla se rota en sentido antihorario.
			var ang := atan2(fwd.cross(to).y, fwd.dot(to))
			_arrow.rotation = -ang


func _on_state_changed(s: RaceManager.State) -> void:
	if s == RaceManager.State.LIBRE:
		_timer.text = ""


func _on_ride_started(limit: float, length: float) -> void:
	show_banner("¡Pasajero a bordo!", "Ruta de %d m · tienes %s" % [roundi(length), _fmt_time(limit)], COLOR_DROPOFF)


func _on_ride_finished(success: bool, time_left: float) -> void:
	_timer.text = ""
	if success:
		show_banner("¡PASAJERO ENTREGADO!", "Llegaste con %s de sobra" % _fmt_time(time_left), COLOR_DROPOFF)
	else:
		show_banner("¡SE ACABÓ EL TIEMPO!", "El pasajero se bajó molesto", COLOR_FAIL)


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


## Flecha triangular simple dibujada a mano; gira alrededor de su centro.
class _Arrow:
	extends Control

	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(func(): pivot_offset = size * 0.5)
		pivot_offset = size * 0.5

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array([
			c + Vector2(0, -r),
			c + Vector2(r * 0.7, r * 0.8),
			c + Vector2(0, r * 0.4),
			c + Vector2(-r * 0.7, r * 0.8),
		])
		draw_colored_polygon(pts, color)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 2.0, true)
