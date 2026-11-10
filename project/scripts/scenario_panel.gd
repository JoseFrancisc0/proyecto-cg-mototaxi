class_name ScenarioPanel
extends PanelContainer
## Panel para elegir el escenario dentro de la partida (fin del día, fin de partida, pausa):
## un aviso, el ScenarioPicker y "confirmar" / "Volver". Lo usan GameOverScreen y PauseMenu.

signal confirmed(choice: Dictionary)
signal cancelled

const YELLOW := Color(1.0, 0.85, 0.2)

var picker: ScenarioPicker
var _title: Label
var _note: Label
var _error: Label
var _confirm: Button


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
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", YELLOW)
	layout.add_child(_title)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 17)
	layout.add_child(_note)
	picker = ScenarioPicker.new()
	layout.add_child(picker)
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
	var v := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	custom_minimum_size.x = clampf(v.x - 80.0, 320.0, 640.0)
	visible = true
	_confirm.grab_focus()


func confirm() -> void:
	var error := picker.validate()
	if error != "":
		_error.text = error
		return
	confirmed.emit(picker.get_choice())
