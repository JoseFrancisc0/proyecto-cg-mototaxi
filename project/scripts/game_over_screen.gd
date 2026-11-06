class_name GameOverScreen
extends CanvasLayer
## Pantalla final (S14, J-B): motivo del fin, lo ganado en la jornada, cuota y ahorros perdidos.
## Reintentar = mismo mapa, partida nueva desde el día 1. Menú = vuelve a la portada.
## Con show_day_complete hace de resumen de una jornada cumplida: "Siguiente día" y "Garaje"
## (comprar o cambiar de mototaxi con los ahorros de la partida antes de seguir).
## En las dos, "Cambiar escenario" (ScenarioPanel): al terminar el día, el siguiente empieza en
## el escenario elegido (con los ahorros); tras perder, el día 1 empieza ahí.

signal retry_requested
signal menu_requested
signal next_day_requested
## Seguir (día siguiente, o día 1 tras perder) en otro escenario.
signal scenario_requested(choice: Dictionary)

const YELLOW := Color(1.0, 0.85, 0.2)
const FONT_PATH := "res://ui/fonts/Bangers-Regular.ttf"

var _box: VBoxContainer
var _title: Label
var _reason: Label
var _score: Label
var _details: Label
var _retry: Button
var _garage_button: Button
var _garage_panel: PanelContainer
var _garage: VehicleGarage
var _scenario_button: Button
var _scenario: ScenarioPanel
## Escenario en juego (para mostrarlo al abrir el panel).
var current_choice := {}
var _day_complete := false
var _last_stats := {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 14)
	center.add_child(_box)

	_title = _label(_box, 72, YELLOW, font)
	_title.text = "FIN DEL TURNO"
	_reason = _label(_box, 28, Color(1.0, 0.45, 0.4), font)
	_score = _label(_box, 54, Color.WHITE, font)
	_details = _label(_box, 22, Color(0.9, 0.9, 0.9), null)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	_box.add_child(buttons)
	_retry = _button(buttons, "Reintentar", font, func():
		if _day_complete:
			next_day_requested.emit()
		else:
			retry_requested.emit())
	_garage_button = _button(buttons, "Garaje", font, open_garage)
	_scenario_button = _button(buttons, "Cambiar escenario", font, open_scenario)
	_button(buttons, "Menú principal", font, func(): menu_requested.emit())
	_build_garage(center)
	_scenario = ScenarioPanel.new()
	center.add_child(_scenario)
	_scenario.confirmed.connect(func(choice: Dictionary): scenario_requested.emit(choice))
	_scenario.cancelled.connect(_close_panels)


## Garaje dentro de la pantalla del día cumplido (oculto hasta pulsar "Garaje").
func _build_garage(parent: Control) -> void:
	_garage_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171820")
	style.border_color = Color("67616a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	_garage_panel.add_theme_stylebox_override("panel", style)
	_garage_panel.visible = false
	parent.add_child(_garage_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_garage_panel.add_child(layout)
	_garage = VehicleGarage.new()
	_garage.custom_minimum_size = Vector2(900, 0)
	layout.add_child(_garage)
	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(close_garage)
	layout.add_child(back)


func open_garage() -> void:
	var v := get_viewport().get_visible_rect().size
	_garage.custom_minimum_size.x = clampf(v.x - 80.0, 320.0, 900.0)
	_garage.refresh()
	_box.visible = false
	_garage_panel.visible = true


## Panel del escenario: al terminar el día, para el día siguiente; tras perder, para el día 1.
func open_scenario() -> void:
	_box.visible = false
	if _day_complete:
		var next := int(_last_stats.get("day", 1)) + 1
		_scenario.open("Escenario del día %d" % next,
			"Se genera el mapa elegido y el día %d empieza ahí. Tus ahorros se quedan." % next,
			"Ir al día %d" % next, current_choice)
	else:
		_scenario.open("Empezar en otro escenario",
			"La partida empieza de cero en el día 1 en el escenario elegido.",
			"Empezar de cero", current_choice)


## Vuelve al resumen del día con los ahorros al día (pudo haberse comprado algo).
func close_garage() -> void:
	_last_stats["savings"] = CareerSave.get_savings()
	show_day_complete(_last_stats)


func show_result(reason: String, stats: Dictionary) -> void:
	_day_complete = false
	_close_panels()
	_title.text = "FIN DE LA PARTIDA"
	_title.modulate = Color.WHITE
	_reason.text = reason
	_score.text = "Llegaste al día %d" % stats.get("day", 1)
	var t := int(stats.get("time", 0.0))
	_details.text = "Ganado hoy: S/ %.2f de S/ %.2f de cuota\nPasajeros entregados: %d     Perdidos: %d     Vuelcos: %d\nTiempo de juego: %d:%02d" % [
		stats.get("earnings", 0.0), stats.get("quota", 0.0),
		stats.get("deliveries", 0), stats.get("failures", 0), stats.get("flips", 0),
		t / 60, t % 60]
	var lost := float(stats.get("lost", 0.0))
	if lost > 0.0:
		_details.text += "\nSe perdieron los ahorros de la partida: S/ %.2f" % lost
	_retry.text = "Reintentar"
	_garage_button.visible = false
	visible = true
	_retry.grab_focus()


## Resumen de una jornada cumplida: cuota pagada y lo que pasó a los ahorros.
func show_day_complete(stats: Dictionary) -> void:
	_day_complete = true
	_last_stats = stats
	_close_panels()
	_title.text = "¡DÍA %d COMPLETO!" % stats.get("day", 1)
	_reason.text = "Partida guardada" + ("  ·  Récord: tu mejor jornada" if stats.get("record", false) else "")
	_score.text = "+ S/ %.2f a tus ahorros" % stats.get("saved", 0.0)
	_details.text = "Ganado: S/ %.2f     Cuota pagada al dueño: S/ %.2f\nPasajeros entregados: %d     Perdidos: %d\nAhorros de la partida: S/ %.2f" % [
		stats.get("earnings", 0.0), stats.get("quota", 0.0),
		stats.get("deliveries", 0), stats.get("failures", 0), stats.get("savings", 0.0)]
	_retry.text = "Siguiente día"
	_garage_button.visible = true
	visible = true
	_retry.grab_focus()


## true si muestra el resumen de un día cumplido (no el fin de la partida).
func is_day_complete() -> bool:
	return _day_complete


func hide_result() -> void:
	_close_panels()
	visible = false


func _close_panels() -> void:
	_garage_panel.visible = false
	_scenario.visible = false
	_box.visible = true


func _label(parent: Node, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	if font:
		l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, font: Font, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 56)
	b.add_theme_font_size_override("font_size", 28)
	if font:
		b.add_theme_font_override("font", font)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
