class_name ScenarioPanel
extends PanelContainer
## Panel para elegir el escenario dentro de la partida (fin del día, fin de partida, pausa):
## un aviso, el ScenarioPicker y "confirmar" / "Volver". Lo usan GameOverScreen y PauseMenu.
## El picker va en un ScrollContainer: el panel nunca pasa del alto de la pantalla y los
## botones de abajo siempre se ven.

signal confirmed(choice: Dictionary)
signal cancelled

const YELLOW := Color(1.0, 0.85, 0.2)

var picker: ScenarioPicker
var _title: Label
var _note: Label
var _error: Label
var _confirm: Button
var _layout: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171820")
	style.border_color = Color("67616a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)
	visible = false
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	_layout = layout
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", YELLOW)
	layout.add_child(_title)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 17)
	layout.add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	picker = ScenarioPicker.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(picker)
	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_font_size_override("font_size", 16)
	_error.add_theme_color_override("font_color", Color("ff839c"))
	layout.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	layout.add_child(buttons)
	_confirm = Button.new()
	_confirm.custom_minimum_size = Vector2(0, 48)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(confirm)
	buttons.add_child(_confirm)
	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(0, 48)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): cancelled.emit())
	buttons.add_child(back)


## Abre el panel con el escenario actual ya elegido. lock_difficulty: la partida sigue (fin del
## día) y su dificultad no se cambia; free: Modo libre.
func open(title: String, note: String, confirm_text: String, choice: Dictionary, lock_difficulty := false, free := false) -> void:
	picker.free_mode = free
	picker.lock_difficulty(lock_difficulty)
	_title.text = title
	_note.text = note
	_note.visible = note != ""
	_confirm.text = confirm_text
	_error.text = ""
	picker.set_choice(choice)
	visible = true
	_fit()
	_fit.call_deferred()  # De nuevo cuando el texto del aviso ya tiene su alto final.
	_confirm.grab_focus()


func _ready() -> void:
	get_viewport().size_changed.connect(func(): if visible: _fit())
	picker.minimum_size_changed.connect(func(): if visible: _fit.call_deferred())
	_note.minimum_size_changed.connect(func(): if visible: _fit.call_deferred())


## Ancho para las cuatro tarjetas en fila si cabe; alto del scroll = lo que sobra de la pantalla.
func _fit() -> void:
	if not is_inside_tree():
		return
	var v := get_viewport().get_visible_rect().size
	custom_minimum_size.x = clampf(v.x - 80.0, 320.0, 960.0)
	var others := _layout.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var margins := 40.0 + 4.0  # Contenido del panel (20 arriba y abajo) y borde.
	var room := v.y - 40.0 - margins - others
	_scroll.custom_minimum_size.y = clampf(picker.get_combined_minimum_size().y, 120.0, maxf(room, 120.0))
	reset_size()


func confirm() -> void:
	var error := picker.validate()
	if error != "":
		_error.text = error
		return
	confirmed.emit(picker.get_choice())
