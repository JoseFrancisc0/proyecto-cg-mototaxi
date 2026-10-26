class_name LoadingScreen
extends CanvasLayer
## Menu de inicio y pantalla de carga (S13: semilla -> mapa completo con pantalla de carga).
##
## 1. Menu: semilla (o al azar), de donde sale el mundo (terreno del editor o nuevo desde la
##    semilla) y cuanta erosion aplicar.
## 2. Carga: barra de avance con la etapa que esta corriendo en C++ (en otro hilo), tiempo
##    transcurrido y estimado, y una vista previa 3D del terreno mientras se erosiona
##    (TerrainMesh.get_preview, render por software desde el hilo de la erosion).
## Los controles se crean por codigo para no depender de editar la escena.

## mode: "editor" o "seed"; seed: semilla; erosion_scale: fraccion de la receta del paper.
signal start_requested(choice: Dictionary)

const TIPS := [
	"Erosion fluvial (stream power): cada celda baja k * A^0.8 * S^2 por paso. A = agua que le llega, S = pendiente.",
	"Multiescala: se erosiona a baja resolucion, se sube x2 con interpolacion bicubica y se vuelve a erosionar.",
	"Estabilizacion termica: el material se desliza mientras la pendiente pase el angulo de reposo s0(p).",
	"Deposicion: el agua que pierde fuerza en los valles deja el sedimento que traia.",
	"Retargeting: un mapa de error difundido devuelve picos y crestas a su altura original.",
	"Breaching multiescala: se abren salidas al agua con cortes suavizados, sin canones de una celda.",
	"Rios: un campo de distancia a la orilla, interpolado por la GPU, dibuja cauces suaves en el shader.",
	"Sombras: desde cada pixel se lanza un rayo hacia el sol sobre el mapa de alturas.",
	"Vegetacion: un MultiMesh por especie y por chunk; Godot no dibuja los chunks que no ve la camara.",
]

var world: TerrainWorld
var _menu: Control
var _progress_box: Control
var _seed_edit: LineEdit
var _mode: OptionButton
var _quality: OptionButton
var _bar: ProgressBar
var _stage: Label
var _detail: Label
var _tip: Label
var _preview: TextureRect
var _preview_serial := -1
var _started_at := 0
var _fraction := 0.0
var _tip_index := 0
var _tip_time := 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(760, 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title := _label("CRAZY MOTOTAXI", 56, Color(1.0, 0.82, 0.25))
	column.add_child(title)
	column.add_child(_label("Costa, sierra y selva generadas con erosion multiescala (Schott et al. 2024)", 18, Color(0.75, 0.78, 0.82)))

	# --- Menu ---
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	column.add_child(_menu)
	var row := HBoxContainer.new()
	row.add_child(_label("Semilla", 20, Color.WHITE))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(200, 0)
	_seed_edit.text = "67"
	row.add_child(_seed_edit)
	var random := Button.new()
	random.text = "Al azar"
	random.pressed.connect(func(): _seed_edit.text = str(randi() % 100000))
	row.add_child(random)
	_menu.add_child(row)
	_mode = OptionButton.new()
	_mode.add_item("Terreno guardado en el editor (terrain_demo.tscn)")
	_mode.add_item("Mundo nuevo desde la semilla (T0 + erosion + retargeting)")
	_mode.item_selected.connect(func(_i): _quality.disabled = _mode.selected == 0)
	_menu.add_child(_mode)
	_quality = OptionButton.new()
	_quality.add_item("Erosion rapida (10% de la receta, segundos)")
	_quality.add_item("Erosion media (35%)")
	_quality.add_item("Erosion del paper (100%, puede tardar minutos)")
	_menu.add_child(_quality)
	var play := Button.new()
	play.text = "Jugar"
	play.custom_minimum_size = Vector2(0, 48)
	play.add_theme_font_size_override("font_size", 24)
	play.pressed.connect(_on_play)
	_menu.add_child(play)

	# --- Carga ---
	_progress_box = VBoxContainer.new()
	_progress_box.add_theme_constant_override("separation", 8)
	_progress_box.visible = false
	column.add_child(_progress_box)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(760, 428)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.visible = false  # aparece con la primera vista previa (solo cuando hay erosion)
	_progress_box.add_child(_preview)
	_stage = _label("Preparando...", 22, Color.WHITE)
	_progress_box.add_child(_stage)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.max_value = 100.0
	_progress_box.add_child(_bar)
	_detail = _label("", 16, Color(0.7, 0.72, 0.76))
	_progress_box.add_child(_detail)
	_tip = _label(TIPS[0], 16, Color(0.6, 0.8, 0.95))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress_box.add_child(_tip)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Muestra el menu con los valores por defecto. choice = {mode, seed, erosion_scale}.
func show_menu(choice: Dictionary) -> void:
	_menu.visible = true
	_progress_box.visible = false
	_seed_edit.text = str(choice.get("seed", 67))
	_mode.selected = 0 if choice.get("mode", "editor") == "editor" else 1
	var scale: float = choice.get("erosion_scale", 0.1)
	_quality.selected = 0 if scale <= 0.15 else (1 if scale <= 0.5 else 2)
	_quality.disabled = _mode.selected == 0


func _on_play() -> void:
	var scales := [0.1, 0.35, 1.0]
	start_requested.emit({"mode": "editor" if _mode.selected == 0 else "seed", "seed": int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 67,
		"erosion_scale": scales[_quality.selected]})


func show_progress() -> void:
	_menu.visible = false
	_progress_box.visible = true
	_started_at = Time.get_ticks_msec()
	_fraction = 0.0
	set_progress("Preparando...", 0.0)


func set_progress(stage: String, fraction: float) -> void:
	_fraction = maxf(_fraction, fraction)
	_stage.text = stage
	_bar.value = _fraction * 100.0
	var elapsed := (Time.get_ticks_msec() - _started_at) / 1000.0
	var text := "%d%%   %.0f s" % [int(_fraction * 100.0), elapsed]
	if _fraction > 0.05 and _fraction < 0.999:
		text += "   (faltan ~%.0f s)" % (elapsed * (1.0 - _fraction) / _fraction)
	_detail.text = text


func _process(delta: float) -> void:
	if not _progress_box.visible:
		return
	_tip_time += delta
	if _tip_time > 6.0:
		_tip_time = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip.text = TIPS[_tip_index]
	# Vista previa: el hilo de la erosion deja una imagen nueva en cada captura.
	if world == null or world.generator == null:
		return
	var builder: TerrainMesh = world.generator.current_builder
	if builder == null:
		return
	var p := builder.get_progress()
	if int(p.get("preview_serial", -1)) == _preview_serial:
		return
	var preview := builder.get_preview()
	_preview_serial = preview["serial"]
	var w: int = preview["width"]
	var h: int = preview["height"]
	var rgb: PackedByteArray = preview["rgb"]
	if w > 0 and rgb.size() == w * h * 3:
		_preview.texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGB8, rgb))
		_preview.visible = true


## Desvanece la pantalla y se elimina.
func finish() -> void:
	set_progress("Listo", 1.0)
	var tween := create_tween()
	for child in get_children():
		if child is CanvasItem:
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
