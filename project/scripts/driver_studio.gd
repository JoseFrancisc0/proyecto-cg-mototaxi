class_name DriverStudio
extends VBoxContainer
## Selección de foto completa y generación asíncrona del conductor; nunca se recorta a un cuadrado.
var photo_picker: FileDialog
var model_picker: FileDialog
var status_label: Label
var progress: ProgressBar
var photo_preview: TextureRect
var viewport: SubViewport
var preview_root: Node3D
var preview_camera: Camera3D
var generate_button: Button
var use_button: Button
var _pid := -1
var _job_folder := ""
var _draft_path := ""
var _last_stage := ""
var _poll := 0.0
var _angle := -.25

func _ready() -> void:
	add_theme_constant_override("separation",10)
	var title := Label.new()
	title.text = "TU CONDUCTOR · FOTO A PERSONAJE 3D"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color",Color("ffdb38"))
	add_child(title)
	var hint := Label.new()
	hint.text = "Reconstruye cuerpo y vestimenta desde una foto de cuerpo entero. Usa una pose de frente con brazos separados. Las fotos parciales quedan como referencia; esta versión aún no completa esas partes con la misma calidad."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",14)
	add_child(hint)
	var row := HBoxContainer.new()
	add_child(row)
	photo_preview = TextureRect.new()
	photo_preview.custom_minimum_size = Vector2(110,180)
	photo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(photo_preview)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(160,270)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	row.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(480,480)
	viewport.own_world_3d = true
	container.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("151925")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .6
	viewport.add_child(env)
	for rotation_y in [-30,150]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35,rotation_y,0)
		light.light_energy = 1.2
		viewport.add_child(light)
	preview_root = Node3D.new()
	viewport.add_child(preview_root)
	var camera := Camera3D.new()
	camera.position = Vector3(0,1.05,3.05)
	viewport.add_child(camera)
	camera.look_at(Vector3(0,.9,0))
	camera.fov = 39
	camera.current = true
	preview_camera=camera
	var view_buttons := HBoxContainer.new()
	add_child(view_buttons)
	for closeup in [false,true]:
		var view_button := Button.new()
		view_button.text="Ver rostro" if closeup else "Ver cuerpo completo"
		view_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		view_button.pressed.connect(func():
			preview_camera.position=Vector3(0,1.57,.85) if closeup else Vector3(0,1.05,3.05)
			preview_camera.look_at(Vector3(0,1.56,0) if closeup else Vector3(0,.9,0))
			_angle=0)
		view_buttons.add_child(view_button)
	photo_picker = FileDialog.new()
	photo_picker.access = FileDialog.ACCESS_FILESYSTEM
	photo_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	photo_picker.use_native_dialog = true
	photo_picker.filters = PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp ; Fotografía"])
	photo_picker.file_selected.connect(import_photo)
	add_child(photo_picker)
	model_picker = FileDialog.new()
	model_picker.access = FileDialog.ACCESS_FILESYSTEM
	model_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	model_picker.use_native_dialog = true
	model_picker.filters = PackedStringArray(["*.glb ; Personaje 3D articulado"])
	model_picker.file_selected.connect(import_model)
	add_child(model_picker)
	_button("Elegir foto de referencia…",func(): photo_picker.popup_centered_ratio(.8))
	generate_button = _button("Transformar foto en personaje 3D",generate)
	var note := Label.new()
	note.text = "Gratis y local con PIFuHD: no envía la foto ni consume créditos. Reconstruye el volumen de la persona y la ropa. La espalda es estimada. Necesita el generador instalado y tarjeta gráfica."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size",12)
	add_child(note)
	_button("Importar un personaje GLB ya generado…",func(): model_picker.popup_centered_ratio(.8))
	use_button = _button("Usar este conductor",apply_model)
	use_button.disabled = true
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 9
	add_child(progress)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size",14)
	add_child(status_label)
	status_label.text = "El personaje se coloca al volante; no cambia a tus pasajeros."
	if FileAccess.file_exists(DriverAvatar.PHOTO_PATH):
		var image := Image.load_from_file(DriverAvatar.PHOTO_PATH)
		if image: photo_preview.texture = ImageTexture.create_from_image(image)
	else:
		photo_preview.texture = load("res://assets/driver/photo.png")
	var active_model:=DriverAvatar.MODEL_PATH if FileAccess.file_exists(DriverAvatar.MODEL_PATH) else DriverAvatar.DEFAULT_PATH
	if active_model==DriverAvatar.MODEL_PATH and DriverAvatar._is_retired_avatar(active_model):active_model=DriverAvatar.DEFAULT_PATH
	_show_model(active_model)

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	add_child(button)
	return button

func import_photo(path: String) -> void:
	if _pid>0 and OS.is_process_running(_pid): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>12*1024*1024:
		status_label.text = "Usa una imagen de hasta 12 MB."
		return
	var image := Image.load_from_file(path)
	if image==null or mini(image.get_width(),image.get_height())<80:
		status_label.text = "No se pudo leer la foto o es demasiado pequeña."
		return
	if maxi(image.get_width(),image.get_height())>3072:
		var factor := 3072.0/maxi(image.get_width(),image.get_height())
		image.resize(roundi(image.get_width()*factor),roundi(image.get_height()*factor),Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DriverAvatar.FOLDER))
	if image.save_png(DriverAvatar.PHOTO_PATH)!=OK:
		status_label.text = "No se pudo guardar la referencia."
		return
	photo_preview.texture = ImageTexture.create_from_image(image)
	status_label.text = "Foto completa cargada. Genera el personaje para conservar rostro y vestimenta."
	use_button.disabled = true

func generate() -> void:
	if not FileAccess.file_exists(DriverAvatar.PHOTO_PATH):
		import_photo(ProjectSettings.globalize_path("res://assets/driver/photo.png"))
		if not FileAccess.file_exists(DriverAvatar.PHOTO_PATH): return
	var helper := ProjectSettings.globalize_path("res://../tools/create_driver.mjs")
	if not FileAccess.file_exists(helper):
		status_label.text = "Esta instalación no incluye el generador. Puedes importar el personaje GLB."
		return
	_job_folder = ProjectSettings.globalize_path(DriverAvatar.FOLDER+"generation_%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_job_folder)
	_pid = OS.create_process("node",PackedStringArray([helper,ProjectSettings.globalize_path(DriverAvatar.PHOTO_PATH),_job_folder]),false)
	if _pid<0:
		status_label.text = "No se pudo iniciar el generador local. Revisa que Node y Blender estén instalados."
		return
	generate_button.disabled = true
	status_label.text = "Iniciando generación; puedes dejar este panel abierto."

func import_model(path: String) -> void:
	if _pid>0 and OS.is_process_running(_pid): return
	if not _show_model(path):
		status_label.text = "Ese archivo no contiene un personaje 3D válido."
		return
	_draft_path = path
	use_button.disabled = false
	status_label.text = "Personaje cargado. Comprueba el rostro y la ropa antes de usarlo."

func _show_model(path: String) -> bool:
	var source := DriverAvatar.load_avatar(path)
	if source == null: return false
	for old in preview_root.get_children():
		preview_root.remove_child(old)
		old.queue_free()
	var driver := DriverAvatar.new()
	preview_root.add_child(driver)
	if not driver.setup(2,source,false):
		driver.queue_free()
		return false
	return true

func apply_model() -> void:
	if _draft_path.is_empty(): return
	var probe := DriverAvatar.new()
	add_child(probe)
	var source := DriverAvatar.load_avatar(_draft_path)
	var valid := probe.setup(2,source,true) if source else false
	probe.queue_free()
	if not valid:
		status_label.text = "El modelo necesita un esqueleto humano para poder sentarse al volante."
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DriverAvatar.FOLDER))
	if _draft_path != ProjectSettings.globalize_path(DriverAvatar.MODEL_PATH) and _draft_path != DriverAvatar.MODEL_PATH:
		if DirAccess.copy_absolute(_draft_path,ProjectSettings.globalize_path(DriverAvatar.MODEL_PATH))!=OK:
			status_label.text = "No se pudo guardar el personaje."
			return
	status_label.text = "Conductor guardado. Se usará en la próxima partida."

func _process(delta: float) -> void:
	if not is_instance_valid(viewport): return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if is_visible_in_tree():
		_angle += delta*.18
		preview_root.rotation.y = _angle
	if _pid<=0: return
	_poll += delta
	if _poll<.5: return
	_poll = 0
	var path := _job_folder.path_join("status.json")
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			progress.value = float(data.get("progress",0))*100
			status_label.text = str(data.get("error",data.get("stage","Preparando personaje")))
			if data.get("done",false):
				_pid = -1
				generate_button.disabled = false
				if data.has("model"): import_model(str(data.model))
	if _pid>0 and not OS.is_process_running(_pid):
		_pid = -1
		generate_button.disabled = false
		status_label.text = "El generador local terminó sin resultado. Revisa su instalación."
