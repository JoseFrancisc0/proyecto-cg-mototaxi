class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc, P o Start del mando): continuar, reiniciar el turno en el mismo mapa,
## volver al menú principal sin tener que perder, y volumen general del juego.
## Main abre y cierra el menú y pausa el árbol; este nodo sigue activo durante la pausa.

signal resume_requested
signal restart_requested
signal menu_requested

const ACTION := &"game_pause"
const YELLOW := Color(1.0, 0.85, 0.2)
const FONT_PATH := "res://ui/fonts/Bangers-Regular.ttf"

var _continue: Button
var _volume: HSlider
var _volume_label: Label


## Registra la acción de pausa (si no está ya en el Mapa de entrada del proyecto).
static func ensure_action() -> void:
	Mototaxi._add_action(ACTION, [KEY_ESCAPE, KEY_P], [], [JOY_BUTTON_START])


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	ensure_action()
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", YELLOW)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	if font:
		title.add_theme_font_override("font", font)
	box.add_child(title)

	_continue = _button(box, "Continuar", font, func(): resume_requested.emit())
	_button(box, "Reiniciar turno", font, func(): restart_requested.emit())
	_button(box, "Menú principal", font, func(): menu_requested.emit())

	var vol_row := HBoxContainer.new()
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vol_row.add_theme_constant_override("separation", 12)
	box.add_child(vol_row)
	_volume_label = Label.new()
	_volume_label.custom_minimum_size = Vector2(130, 0)
	_volume_label.add_theme_font_size_override("font_size", 20)
	vol_row.add_child(_volume_label)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 100.0
	_volume.step = 5.0
	_volume.custom_minimum_size = Vector2(200, 24)
	_volume.value = roundf(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	_volume.value_changed.connect(_set_volume)
	vol_row.add_child(_volume)
	_set_volume(_volume.value)

	var hint := Label.new()
	hint.text = "Esc / P / Start: continuar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)


func open() -> void:
	visible = true
	_continue.grab_focus()


func close() -> void:
	visible = false


## Volumen general (bus Master) en %; 0 = silencio.
func _set_volume(percent: float) -> void:
	AudioServer.set_bus_mute(0, percent <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(percent, 1.0) / 100.0))
	_volume_label.text = "Volumen %d%%" % roundi(percent)


func _button(parent: Node, text: String, font: Font, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 28)
	if font:
		b.add_theme_font_override("font", font)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
