class_name GameOverScreen
extends CanvasLayer
## Pantalla final (S14, J-B): motivo del fin, puntaje (soles ganados) y estadísticas.
## Reintentar = misma mapa, de nuevo desde el inicio. Menú = vuelve a la portada.

signal retry_requested
signal menu_requested

const YELLOW := Color(1.0, 0.85, 0.2)
const FONT_PATH := "res://ui/fonts/Bangers-Regular.ttf"

var _title: Label
var _reason: Label
var _score: Label
var _details: Label
var _retry: Button


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
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_title = _label(box, 72, YELLOW, font)
	_title.text = "FIN DEL TURNO"
	_reason = _label(box, 28, Color(1.0, 0.45, 0.4), font)
	_score = _label(box, 54, Color.WHITE, font)
	_details = _label(box, 22, Color(0.9, 0.9, 0.9), null)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	_retry = _button(buttons, "Reintentar", font, func(): retry_requested.emit())
	_button(buttons, "Menú principal", font, func(): menu_requested.emit())


func show_result(reason: String, stats: Dictionary) -> void:
	_reason.text = reason
	_score.text = "S/ %.2f" % stats.get("earnings", 0.0)
	var t := int(stats.get("time", 0.0))
	_details.text = "Pasajeros entregados: %d     Perdidos: %d\nPropinas: S/ %.2f     Vuelcos: %d\nTiempo de juego: %d:%02d" % [
		stats.get("deliveries", 0), stats.get("failures", 0), stats.get("tips", 0.0),
		stats.get("flips", 0), t / 60, t % 60]
	visible = true
	_retry.grab_focus()


func hide_result() -> void:
	visible = false


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
	b.custom_minimum_size = Vector2(220, 56)
	b.add_theme_font_size_override("font_size", 28)
	if font:
		b.add_theme_font_override("font", font)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
