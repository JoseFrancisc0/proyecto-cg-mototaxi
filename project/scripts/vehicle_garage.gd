class_name VehicleGarage
extends VBoxContainer
## Garaje (menú principal y fin de cada día): ver las mototaxis, comprar las que faltan con
## los ahorros de la partida en curso y elegir cuál se usa (CareerSave). Lo comprado se queda
## aunque se pierda la partida; solo se juega con una mototaxi propia.

signal ownership_changed
## Cambió la mototaxi en uso (comprada o elegida con "Usar esta").
signal active_changed(index: int)

var selected := 2
var _model_root: Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _view: SubViewportContainer
var _hero: BoxContainer
var _name_label: Label
var _role: Label
var _description: Label
var _stats: VBoxContainer
var _dragging := false
var _yaw := -0.6
var _wallet: Label
var _buy: Button

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = "GARAJE  /  ELIGE TU MOTOTAXI"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color("ffdb38"))
	add_child(heading)
	_hero = BoxContainer.new()
	_hero.add_theme_constant_override("separation", 24)
	add_child(_hero)
	_view = SubViewportContainer.new()
	_view.custom_minimum_size = Vector2(0, 280)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.stretch = true
	_hero.add_child(_view)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640,320)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_view.add_child(_viewport)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("10131f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d9ff")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	_viewport.add_child(environment)
	for angle in [Vector3(-45,-30,0), Vector3(-25,140,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angle
		light.light_energy = 1.5 if angle.y < 0 else 0.8
		_viewport.add_child(light)
	var platform := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.9
	cylinder.bottom_radius = 1.9
	cylinder.height = 0.10
	platform.mesh = cylinder
	platform.position.y = -0.07
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("34394d")
	material.metallic = 0.5
	material.roughness = 0.4
	platform.material_override = material
	_viewport.add_child(platform)
	_model_root = Node3D.new()
	_viewport.add_child(_model_root)
	_camera = Camera3D.new()
	_camera.position = Vector3(3.0,1.9,3.4)
	_viewport.add_child(_camera)
	_camera.look_at(Vector3(0,0.7,0))
	_camera.fov = 40
	_camera.current = true
	_view.gui_input.connect(_on_view_input)
	_view.resized.connect(func():
		if is_instance_valid(_model_root) and _model_root.get_child_count()>0:
			_frame_model(_model_root.get_child(0)))
	_stats = VBoxContainer.new()
	_stats.custom_minimum_size.x = 220
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_theme_constant_override("separation", 8)
	_hero.add_child(_stats)
	var nav := HBoxContainer.new()
	add_child(nav)
	var previous := Button.new()
	previous.text = "❮"
	previous.custom_minimum_size = Vector2(48,44)
	previous.pressed.connect(func(): select_vehicle(posmod(selected-1,6)))
	nav.add_child(previous)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size",26)
	nav.add_child(_name_label)
	var next := Button.new()
	next.text = "❯"
	next.custom_minimum_size = Vector2(48,44)
	next.pressed.connect(func(): select_vehicle(posmod(selected+1,6)))
	nav.add_child(next)
	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 12)
	add_child(shop)
	_wallet = Label.new()
	_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet.add_theme_font_size_override("font_size", 16)
	shop.add_child(_wallet)
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(190, 40)
	_buy.pressed.connect(_on_shop_button)
	shop.add_child(_buy)
	var hint := Label.new()
	hint.text = "Arrastra para girar · Rueda para acercar · Shift / X del mando: turbo"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",13)
	hint.add_theme_color_override("font_color",Color("a7abb7"))
	add_child(hint)
	resized.connect(_responsive)
	selected = CareerSave.get_active()
	select_vehicle(selected)
	_responsive()

## Vuelve a mostrar la mototaxi en uso y el dinero actual (al abrir el garaje).
func refresh() -> void:
	select_vehicle(CareerSave.get_active())

func select_vehicle(index: int) -> void:
	selected = clampi(index,0,5)
	if not is_instance_valid(_model_root): return
	for child in _model_root.get_children():
		_model_root.remove_child(child)
		child.queue_free()
	var model := VehicleCatalog.create_model(selected)
	if model:
		_model_root.add_child(model)
		_frame_model(model)
	var v := VehicleCatalog.entry(selected)
	var owned := CareerSave.is_owned(selected)
	_name_label.text = ("%02d / %s" if owned else "🔒 %02d / %s") % [selected+1,v.name]
	if owned and selected == CareerSave.get_active():
		_name_label.text += "  ·  EN USO"
	_update_shop()
	_name_label.add_theme_color_override("font_color",v.color)
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	_role = Label.new()
	_role.text = v.role
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_role.add_theme_color_override("font_color",v.color)
	_role.add_theme_font_size_override("font_size",15)
	_stats.add_child(_role)
	_description = Label.new()
	_description.text = v.description
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size",14)
	_stats.add_child(_description)
	var sound_style := Label.new()
	sound_style.text = VehicleCatalog.SOUND_STYLES[selected]
	sound_style.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sound_style.add_theme_font_size_override("font_size",13)
	sound_style.add_theme_color_override("font_color",Color("a7abb7"))
	_stats.add_child(sound_style)
	var bars := VehicleCatalog.bars(selected)
	for stat: String in bars:
		var label := Label.new()
		label.text = stat + ("  ·  %d km/h" % v.speed if stat == "Velocidad" else "")
		label.add_theme_font_size_override("font_size",14)
		_stats.add_child(label)
		var bar := ProgressBar.new()
		bar.value = bars[stat] * 100.0
		bar.show_percentage = false
		bar.custom_minimum_size.y = 7
		var fill := StyleBoxFlat.new()
		fill.bg_color = v.color
		bar.add_theme_stylebox_override("fill",fill)
		var back := StyleBoxFlat.new()
		back.bg_color = Color("303342")
		bar.add_theme_stylebox_override("background",back)
		_stats.add_child(bar)

func is_selected_owned() -> bool:
	return CareerSave.is_owned(selected)


func _update_shop() -> void:
	if _wallet == null:
		return
	var savings := CareerSave.get_savings()
	var best := CareerSave.get_best_day()
	var money := ("Ahorros de la partida: S/ %.2f" % savings) if CareerSave.has_game() else "Sin partida en curso"
	_wallet.text = money + (("   ·   Mejor jornada: día %d" % best) if best > 0 else "")
	var owned := CareerSave.is_owned(selected)
	var price := float(VehicleCatalog.entry(selected).get("price", 0.0))
	if not owned:
		_buy.text = "Comprar · S/ %.2f" % price
		_buy.disabled = savings < price
	elif selected == CareerSave.get_active():
		_buy.text = "En uso"
		_buy.disabled = true
	else:
		_buy.text = "Usar esta"
		_buy.disabled = false


func _on_shop_button() -> void:
	if CareerSave.is_owned(selected):
		_on_use()
	else:
		_on_buy()


func _on_buy() -> void:
	if CareerSave.buy(selected):
		select_vehicle(selected)
		ownership_changed.emit()
		active_changed.emit(selected)


func _on_use() -> void:
	if CareerSave.set_active(selected):
		select_vehicle(selected)
		active_changed.emit(selected)


func _responsive() -> void:
	_hero.vertical = size.x < 650
	_view.custom_minimum_size.y = 230 if _hero.vertical else 290
	_name_label.add_theme_font_size_override("font_size",18 if size.x < 450 else 26)
	if _model_root.get_child_count() > 0:
		_frame_model(_model_root.get_child(0))

func _frame_model(model: Node3D) -> void:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var transform_to_model := _model_root.global_transform.affine_inverse() * mesh.global_transform
		var box := transform_to_model * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first: return
	var aspect := maxf(_view.size.x / maxf(_view.size.y,1.0),1.0)
	var radius := Vector2(bounds.size.x,bounds.size.z).length()*0.5
	var distance := maxf(radius/(aspect*tan(deg_to_rad(17.0))),bounds.size.y*0.64/tan(deg_to_rad(17.0)))*1.12
	var center := bounds.get_center()
	_camera.fov = 34
	_camera.position = center + Vector3(0.66,0.27,0.75).normalized()*distance
	_camera.look_at(center)

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.fov = clampf(_camera.fov + (-2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2),28,55)
	if event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.012

func _process(delta: float) -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree(): return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _dragging = false
	if not _dragging: _yaw += delta * 0.22
	_model_root.rotation.y = _yaw
