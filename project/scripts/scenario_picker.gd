class_name ScenarioPicker
extends VBoxContainer
## Elección del escenario: terreno (guardado o nuevo con semilla), región, calidad de generación
## y dificultad de la partida (Difficulty). La dificultad se elige solo al empezar una partida:
## al cambiar de escenario a mitad de ella se muestra bloqueada (lock_difficulty).
## Se usa en el menú principal (Jugar y Modo libre), al terminar el día, al perder y en la pausa
## (Reiniciar partida). get_choice() entrega el mismo diccionario que recibe Main:
## {"mode": "editor"|"seed", "seed", "erosion_scale", "region", "region_only", "difficulty"}.

const MUTED := Color("a7abb7")
const REGIONS := ["Mixta (costa, sierra y selva)", "Costa", "Sierra", "Selva"]
const QUALITY_SCALES := [0.1, 0.35, 1.0]
## Tarjetas de región (pendiente 11): foto del juego real (tools/capture_scenario_previews.gd).
const CARD_NAMES := ["Mixta", "Costa", "Sierra", "Selva"]
const CARD_TEXTS := ["Costa, sierra y selva en un mismo mapa", "Arena, huarangos y ríos en el desierto",
	"Cerros altos, ichu y cumbres nevadas", "Bosque tupido, palmeras y ríos"]
const CARD_IMAGES := ["res://ui/scenarios/mixta.jpg", "res://ui/scenarios/costa.jpg",
	"res://ui/scenarios/sierra.jpg", "res://ui/scenarios/selva.jpg"]
const YELLOW := Color(1.0, 0.85, 0.2)

var mode: OptionButton
## Región elegida (oculto: las tarjetas lo cambian; el resto del juego lee region.selected).
var region: OptionButton
var cards: Array[Button] = []
var share_row: VBoxContainer
var share: OptionButton
var region_note: Label
var seed_row: VBoxContainer
var seed_edit: LineEdit
var quality_row: VBoxContainer
var quality: OptionButton
var difficulty: OptionButton
var difficulty_note: Label
## true: la partida sigue y su dificultad no se cambia.
var difficulty_locked := false
## Modo libre: sin reloj ni pago, la dificultad solo cambia lo que hay en el camino.
var free_mode := false:
	set(v):
		free_mode = v
		update_mode()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	add_child(_label("Terreno"))
	mode = _option(["Terreno guardado", "Nuevo terreno"])
	add_child(mode)
	add_child(_label("Región"))
	region = _option(REGIONS)
	region.visible = false
	add_child(region)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	# Con espacio, las cuatro en una fila (sin tener que bajar); si no, de a dos.
	grid.resized.connect(func():
		var wanted := 4 if grid.size.x >= 860.0 else 2
		if grid.columns != wanted:
			grid.columns = wanted)
	for i in CARD_NAMES.size():
		var card := _card(i)
		cards.append(card)
		grid.add_child(card)
	share_row = VBoxContainer.new()
	add_child(share_row)
	share = _option(["Mayoría de esa región", "Solo esa región"])
	share_row.add_child(share)
	region_note = _label("", 15, MUTED)
	region_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(region_note)
	seed_row = VBoxContainer.new()
	add_child(seed_row)
	seed_row.add_child(_label("Semilla"))
	var seed_controls := HBoxContainer.new()
	seed_row.add_child(seed_controls)
	seed_edit = LineEdit.new()
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size.y = 44
	seed_controls.add_child(seed_edit)
	var random := Button.new()
	random.text = "Aleatoria"
	random.custom_minimum_size.y = 44
	random.pressed.connect(func(): seed_edit.text = str(randi() % 2147483647))
	seed_controls.add_child(random)
	quality_row = VBoxContainer.new()
	add_child(quality_row)
	quality_row.add_child(_label("Generación"))
	quality = _option(["Rápida", "Normal", "Completa"])
	quality_row.add_child(quality)
	var note := _label("La misma semilla y los mismos ajustes generan el mismo terreno. La generación completa tarda más.", 15, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_row.add_child(note)
	add_child(_label("Dificultad"))
	var names: Array = []
	for level in Difficulty.LEVELS:
		names.append(level["name"])
	difficulty = _option(names)
	difficulty.name = "Dificultad"
	difficulty.select(Difficulty.NORMAL)
	add_child(difficulty)
	difficulty_note = _label("", 15, MUTED)
	difficulty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(difficulty_note)
	mode.item_selected.connect(update_mode)
	region.item_selected.connect(update_mode)
	difficulty.item_selected.connect(update_mode)
	update_mode()


## Muestra un escenario elegido antes (los campos que faltan se quedan como están).
func set_choice(choice: Dictionary) -> void:
	seed_edit.text = str(choice.get("seed", 67))
	mode.select(0 if choice.get("mode", "editor") == "editor" else 1)
	var scale: float = choice.get("erosion_scale", 0.1)
	quality.select(0 if scale <= 0.15 else (1 if scale <= 0.5 else 2))
	region.select(clampi(int(choice.get("region", region.selected)), 0, 3))
	share.select(1 if choice.get("region_only", share.selected == 1) else 0)
	difficulty.select(Difficulty.of(choice) if choice.has("difficulty") else difficulty.selected)
	update_mode()


## Bloquea la dificultad (cambio de escenario dentro de la partida) o la deja elegir.
func lock_difficulty(locked: bool) -> void:
	difficulty_locked = locked
	difficulty.disabled = locked
	update_mode()


## "" si lo elegido es válido; si no, el motivo.
func validate() -> String:
	var seed_text := seed_edit.text.strip_edges()
	if mode.selected == 1 and (not seed_text.is_valid_int() or int(seed_text) < 0 or int(seed_text) > 2147483647):
		return "Ingresa una semilla entre 0 y 2147483647."
	return ""


func get_choice() -> Dictionary:
	var seed_text := seed_edit.text.strip_edges()
	return {"mode": "editor" if mode.selected == 0 else "seed",
		"seed": int(seed_text) if seed_text.is_valid_int() else 67,
		"erosion_scale": QUALITY_SCALES[quality.selected], "region": region.selected,
		"region_only": share.selected == 1, "difficulty": difficulty.selected}


## true si dos escenarios generan el mismo mapa (con los mismos obstáculos) y se empieza en la
## misma región con la misma dificultad.
static func same(a: Dictionary, b: Dictionary) -> bool:
	if a.get("mode", "editor") != b.get("mode", "editor") or int(a.get("region", 0)) != int(b.get("region", 0)):
		return false
	if Difficulty.of(a) != Difficulty.of(b):
		return false
	if a.get("mode", "editor") == "editor":
		return true
	return int(a.get("seed", 67)) == int(b.get("seed", 67)) \
		and is_equal_approx(float(a.get("erosion_scale", 0.1)), float(b.get("erosion_scale", 0.1))) \
		and (int(a.get("region", 0)) == 0 or bool(a.get("region_only", false)) == bool(b.get("region_only", false)))


## Resumen corto, p. ej. "Terreno guardado · Sierra · Normal" o "Semilla 42 · Costa (solo) · Difícil".
static func describe(choice: Dictionary) -> String:
	var r := int(choice.get("region", 0))
	var region_text: String = "Mixta" if r <= 0 else REGIONS[r]
	var level := Difficulty.level_name(Difficulty.of(choice))
	if choice.get("mode", "editor") == "editor":
		return "Terreno guardado · %s · %s" % [region_text, level]
	if r > 0 and choice.get("region_only", false):
		region_text += " (solo)"
	return "Semilla %d · %s · %s" % [int(choice.get("seed", 67)), region_text, level]


func update_mode(_index := 0) -> void:
	for i in cards.size():
		cards[i].button_pressed = i == region.selected
	seed_row.visible = mode.selected == 1
	quality_row.visible = mode.selected == 1
	share_row.visible = mode.selected == 1 and region.selected > 0
	if region.selected == 0:
		region_note.text = ""
	elif mode.selected == 0:
		region_note.text = "El terreno guardado ya tiene sus regiones: empiezas en la zona de esa región."
	else:
		region_note.text = "El mapa se genera con esa región como protagonista y empiezas en ella."
	region_note.visible = region_note.text != ""
	if free_mode:
		difficulty_note.text = "En el Modo libre solo cambia cuánto hay en el camino."
	elif difficulty_locked:
		difficulty_note.text = "Se mantiene en toda la partida. Para cambiarla, empieza una partida nueva."
	else:
		difficulty_note.text = Difficulty.get_value(difficulty.selected, "hint") + " Se mantiene en toda la partida."


## Tarjeta de una región: foto, nombre y una línea; borde amarillo si está elegida.
func _card(index: int) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(0, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		var chosen: bool = state in ["pressed", "hover_pressed"]
		style.bg_color = Color("232533") if state.begins_with("hover") or chosen else Color("1b1c26")
		style.border_color = YELLOW if chosen else (Color("c9c6d0") if state == "focus" else Color("4a4652"))
		style.set_border_width_all(3 if chosen or state == "focus" else 2)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(6)
		if state == "focus":
			style.draw_center = false
		card.add_theme_stylebox_override(state, style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	card.add_child(box)
	var photo := TextureRect.new()
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.custom_minimum_size = Vector2(0, 124)
	photo.clip_contents = true
	if ResourceLoader.exists(CARD_IMAGES[index]):
		photo.texture = load(CARD_IMAGES[index])
	box.add_child(photo)
	var title := _label(CARD_NAMES[index].to_upper(), 20, Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var text := _label(CARD_TEXTS[index], 14, MUTED)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	# El botón no mide a sus hijos: se le da el alto de la foto, el nombre y dos líneas de texto.
	card.custom_minimum_size.y = 124 + 30 + 42 + 18
	card.pressed.connect(func():
		region.select(index)
		region.item_selected.emit(index))
	return card


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.custom_minimum_size.y = 44
	return o


func _label(text: String, font_size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
