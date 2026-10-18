extends Node3D

var world: TerrainWorld
var camera: Camera3D
var target := Vector3.ZERO
var yaw := 0.65
var pitch := 0.85
var distance := 320.0
var rotating := false
var panel: PanelContainer
var seed_input: LineEdit
var resolution: OptionButton
var quality: OptionButton
var base_only: CheckBox
var generate_button: Button
var status: Label
var progress: ProgressBar
var stats: Label
var marker_root: Node3D
var _capture_frames := -1
var _generation_started := 0
var _wall_seconds := 0.0

func _ready() -> void:
	world = TerrainWorld.new()
	world.name = "TerrainWorld"
	add_child(world)
	world.generation_progress.connect(_on_progress)
	world.generation_finished.connect(_on_finished)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("9bb9c9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("cfdfec")
	settings.ambient_light_energy = 0.45
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	camera = Camera3D.new()
	camera.far = 6000.0
	camera.current = true
	add_child(camera)
	_make_ui()
	_update_camera()
	_generate()

func _make_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(345, 0)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(key, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "CRAZY MOTOTAXI · TERRENO"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	seed_input = LineEdit.new()
	seed_input.text = "68"
	seed_input.placeholder_text = "Semilla entera"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_input)
	var random_button := Button.new()
	random_button.text = "Otra semilla"
	random_button.pressed.connect(func(): seed_input.text = str(randi_range(1, 999999)))
	seed_row.add_child(random_button)
	resolution = OptionButton.new()
	resolution.add_item("Vista rapida · 256 × 256 celdas", 256)
	resolution.add_item("Entrega S12 · 1024 × 1024 celdas", 1024)
	resolution.add_item("S11 · 256 × 256, una resolucion", 11)
	box.add_child(resolution)
	quality = OptionButton.new()
	quality.add_item("Erosion: vista previa · 3% de iteraciones")
	quality.add_item("Erosion: intermedia · 10% de iteraciones")
	quality.add_item("Erosion: receta completa · puede tardar")
	box.add_child(quality)
	base_only = CheckBox.new()
	base_only.text = "Ver T0 sin erosion ni caminos"
	box.add_child(base_only)
	generate_button = Button.new()
	generate_button.text = "Generar mapa"
	generate_button.pressed.connect(_generate)
	box.add_child(generate_button)
	progress = ProgressBar.new()
	progress.max_value = 1.0
	box.add_child(progress)
	status = Label.new()
	status.text = "Preparando…"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 320
	box.add_child(status)
	stats = Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.custom_minimum_size.x = 320
	box.add_child(stats)
	var export_button := Button.new()
	export_button.text = "Guardar alturas, drenaje y tiempos"
	export_button.pressed.connect(_export_maps)
	box.add_child(export_button)
	var help := Label.new()
	help.text = "Arrastrar con boton derecho: orbitar\nRueda: acercar / alejar · WASD: mover\nMarcadores: crestas, rios y llanuras\nF12: guardar captura"
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)
	var arguments := OS.get_cmdline_user_args()
	if "--full-map" in arguments:
		resolution.select(1)
	if "--paper-iterations" in arguments:
		quality.select(2)
	if "--base" in arguments:
		base_only.button_pressed = true
	if "--s11" in arguments:
		resolution.select(2)

func _generate() -> void:
	if world.busy:
		return
	if not seed_input.text.is_valid_int():
		status.text = "Escribe una semilla entera."
		return
	world.grid_cells = 256 if resolution.get_selected_id() == 11 else resolution.get_selected_id()
	world.erosion_levels = 0 if resolution.get_selected_id() == 11 else 2
	world.iteration_scale = [0.03, 0.10, 1.0][quality.selected]
	world.erosion_enabled = not base_only.button_pressed
	world.retarget_enabled = not base_only.button_pressed
	world.roads_enabled = not base_only.button_pressed
	generate_button.disabled = true
	resolution.disabled = true
	quality.disabled = true
	base_only.disabled = true
	stats.text = "La ventana sigue disponible durante el calculo."
	_generation_started = Time.get_ticks_msec()
	world.generate(int(seed_input.text))

func _on_progress(stage: String, fraction: float) -> void:
	status.text = stage
	progress.value = fraction

func _on_finished(success: bool) -> void:
	generate_button.disabled = false
	resolution.disabled = false
	quality.disabled = false
	base_only.disabled = false
	if not success:
		status.text = "No se pudo generar. Revisa la salida de Godot."
		return
	target = Vector3(0, world.get_height(0, 0), 0)
	distance = world.grid_cells * world.cell_size * 1.48
	_update_camera()
	var times := world.get_timings()
	_wall_seconds = (Time.get_ticks_msec() - _generation_started) / 1000.0
	stats.text = "Semilla %d · %d chunks\nMapa listo en %.2f s · C++ %.2f s\nErosion %.2f s · retargeting %.2f s" % [world.seed_value, world.get_node("Chunks").get_child_count(), _wall_seconds, times.get("total", 0), times.get("erosion", 0), times.get("retarget", 0)]
	_draw_landmarks()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_frames = 8

func _draw_landmarks() -> void:
	if marker_root != null:
		marker_root.queue_free()
	marker_root = Node3D.new()
	add_child(marker_root)
	for landmark: Dictionary in world.get_landmarks():
		var marker := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.25
		shape.bottom_radius = 1.0
		shape.height = 8.0
		marker.mesh = shape
		marker.position = landmark.position + Vector3.UP * 4
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("f7cf68") if landmark.type == "cresta" else (Color("5fd3ed") if landmark.type == "rio" else Color("9cde85"))
		marker.material_override = material
		marker_root.add_child(marker)
		var label := Label3D.new()
		label.text = landmark.type
		label.position = marker.position + Vector3.UP * 6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		marker_root.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rotating = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(15.0, distance * 0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(3000.0, distance * 1.1)
	if event is InputEventMouseMotion and rotating:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch + event.relative.y * 0.005, 0.15, 1.5)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_capture_frames = 2
	_update_camera()

func _process(delta: float) -> void:
	if not seed_input.has_focus():
		var movement := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): movement.z -= 1
		if Input.is_physical_key_pressed(KEY_S): movement.z += 1
		if Input.is_physical_key_pressed(KEY_A): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_D): movement.x += 1
		target += movement.rotated(Vector3.UP, yaw) * delta * distance * 0.4
		_update_camera()
	if _capture_frames > 0:
		_capture_frames -= 1
	elif _capture_frames == 0:
		_capture_frames = -1
		_save_screenshot()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target, Vector3.UP)

func _export_maps() -> void:
	if world.busy or world.field == null:
		return
	var folder := ProjectSettings.globalize_path("res://../output/terrain_seed_%d_%d_%s" % [world.seed_value, world.grid_cells, "t0" if not world.erosion_enabled else str(world.iteration_scale)])
	DirAccess.make_dir_recursive_absolute(folder)
	var side := world.grid_cells + 1
	var before := world.field.get_initial_heights()
	var after := world.field.get_heights()
	var drainage := world.field.get_drainage_map()
	Image.create_from_data(side, side, false, Image.FORMAT_RF, before.to_byte_array()).save_exr(folder + "/t0.exr", true)
	Image.create_from_data(side, side, false, Image.FORMAT_RF, after.to_byte_array()).save_exr(folder + "/final.exr", true)
	Image.create_from_data(side, side, false, Image.FORMAT_RF, drainage.to_byte_array()).save_exr(folder + "/drainage.exr", true)
	var maps := world.field.get_regional_maps()
	Image.create_from_data(side, side, false, Image.FORMAT_RF, maps.hardness.to_byte_array()).save_exr(folder + "/hardness.exr", true)
	Image.create_from_data(side, side, false, Image.FORMAT_RF, maps.talus.to_byte_array()).save_exr(folder + "/talus.exr", true)
	var metadata := {"seed": world.seed_value, "grid_cells": world.grid_cells, "samples_per_side": side, "cell_size": world.cell_size, "levels": world.erosion_levels, "iteration_scale": world.iteration_scale, "erosion_enabled": world.erosion_enabled, "wall_seconds": _wall_seconds, "timings_seconds": world.get_timings()}
	var file := FileAccess.open(folder + "/metadata.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata, "\t"))
	var table := FileAccess.open(folder + "/timings.csv", FileAccess.WRITE)
	if table != null:
		table.store_csv_line(PackedStringArray(["celdas", "fluvial_s", "termica_s", "deposicion_s"]))
		for cells: int in [64, 128, 256, 512, 1024]:
			var key := "cells_%d" % cells
			if world.get_timings().has(key):
				var level: Dictionary = world.get_timings()[key]
				table.store_csv_line(PackedStringArray([str(cells), str(level.fluvial), str(level.thermal), str(level.deposition)]))
	status.text = "Mapas guardados en output/"
	var low := before[0]
	var high := before[0]
	for height: float in before:
		low = minf(low, height)
		high = maxf(high, height)
	for name: String in ["t0", "final"]:
		var values := before if name == "t0" else after
		var image := Image.create(side, side, false, Image.FORMAT_RGB8)
		for z in range(side):
			for x in range(side):
				var shade: float = clampf((values[z * side + x] - low) / maxf(high - low, 0.001), 0, 1)
				image.set_pixel(x, z, Color(shade, shade, shade))
		image.save_png(folder + "/" + name + ".png")

func _save_screenshot() -> void:
	var folder := ProjectSettings.globalize_path("res://../output")
	DirAccess.make_dir_recursive_absolute(folder)
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(folder + "/terrain_view.png")
	screenshot.save_png(folder + "/terrain_%d_%s.png" % [world.grid_cells, "t0" if not world.erosion_enabled else str(world.iteration_scale)])
	if "--capture" in OS.get_cmdline_user_args():
		_export_maps()
		get_tree().quit()
