class_name ScenarioPicker
extends VBoxContainer
## Elección del escenario: terreno (guardado o nuevo con semilla), región y calidad de generación.
## Se usa en el menú principal (Jugar y Modo libre), al terminar el día, al perder y en la pausa
## (Reiniciar partida). get_choice() entrega el mismo diccionario que recibe Main:
## {"mode": "editor"|"seed", "seed", "erosion_scale", "region", "region_only"}.

const MUTED := Color("a7abb7")
const REGIONS := ["Mixta (costa, sierra y selva)", "Costa", "Sierra", "Selva"]
const QUALITY_SCALES := [0.1, 0.35, 1.0]

var mode: OptionButton
var region: OptionButton
var share_row: VBoxContainer
var share: OptionButton
var region_note: Label
var seed_row: VBoxContainer
var seed_edit: LineEdit
var quality_row: VBoxContainer
var quality: OptionButton


func _init() -> void:
	add_theme_constant_override("separation", 12)
	add_child(_label("Terreno"))
	mode = _option(["Terreno guardado", "Nuevo terreno"])
	add_child(mode)
	add_child(_label("Región"))
	region = _option(REGIONS)
	add_child(region)
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
	mode.item_selected.connect(update_mode)
	region.item_selected.connect(update_mode)
	update_mode()


## Muestra un escenario elegido antes (los campos que faltan se quedan como están).
func set_choice(choice: Dictionary) -> void:
	seed_edit.text = str(choice.get("seed", 67))
	mode.select(0 if choice.get("mode", "editor") == "editor" else 1)
	var scale: float = choice.get("erosion_scale", 0.1)
	quality.select(0 if scale <= 0.15 else (1 if scale <= 0.5 else 2))
	region.select(clampi(int(choice.get("region", region.selected)), 0, 3))
	share.select(1 if choice.get("region_only", share.selected == 1) else 0)
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
		"region_only": share.selected == 1}


## true si dos escenarios generan el mismo mapa y se empieza en la misma región.
static func same(a: Dictionary, b: Dictionary) -> bool:
	if a.get("mode", "editor") != b.get("mode", "editor") or int(a.get("region", 0)) != int(b.get("region", 0)):
		return false
	if a.get("mode", "editor") == "editor":
		return true
	return int(a.get("seed", 67)) == int(b.get("seed", 67)) \
		and is_equal_approx(float(a.get("erosion_scale", 0.1)), float(b.get("erosion_scale", 0.1))) \
		and (int(a.get("region", 0)) == 0 or bool(a.get("region_only", false)) == bool(b.get("region_only", false)))


## Resumen corto, p. ej. "Terreno guardado · Sierra" o "Semilla 42 · Costa (solo)".
static func describe(choice: Dictionary) -> String:
	var r := int(choice.get("region", 0))
	var region_text: String = "Mixta" if r <= 0 else REGIONS[r]
	if choice.get("mode", "editor") == "editor":
		return "Terreno guardado · %s" % region_text
	if r > 0 and choice.get("region_only", false):
		region_text += " (solo)"
	return "Semilla %d · %s" % [int(choice.get("seed", 67)), region_text]


func update_mode(_index := 0) -> void:
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
