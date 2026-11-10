extends Control
@export var individual_houses:=false
## Inspect the reference beside the actual three-dimensional neighbourhood.
var _entries: Array=[]
var _viewport: SubViewport
var _camera: Camera3D
var _block: PeruReferenceBlocks
var _photo: TextureRect
var _status: Label
var _picker: OptionButton
var _aspect: AspectRatioContainer
var _target:=Vector3.ZERO
var _yaw:=0.0
var _pitch:=.35
var _radius:=60.0
var _changing:=false

func _ready() -> void:
	_entries=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference_photos/catalog.json"))
	if individual_houses:_entries=_house_entries()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop:=ColorRect.new();backdrop.color=Color("111820");backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(backdrop)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(margin)
	for key in ["margin_left","margin_top","margin_right","margin_bottom"]:margin.add_theme_constant_override(key,16)
	var layout:=VBoxContainer.new();layout.add_theme_constant_override("separation",12);margin.add_child(layout)
	var bar:=HBoxContainer.new();bar.add_theme_constant_override("separation",18);layout.add_child(bar)
	var back:=Button.new();back.text="← Volver al menú";back.pressed.connect(_back);bar.add_child(back)
	var title:=Label.new();title.text="Revisar casas" if individual_houses else "Comparar barrios";title.add_theme_font_size_override("font_size",25);bar.add_child(title)
	var picker:=OptionButton.new();picker.name="ElegirBarrio";picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_picker=picker
	for item: Dictionary in _entries:picker.add_item(str(item.title))
	bar.add_child(picker);picker.item_selected.connect(_select)
	if individual_houses:
		var views:=HBoxContainer.new();layout.add_child(views)
		for item: Array in [["Frente",0.0,.08],["Costado izquierdo",-PI*.5,.12],["Costado derecho",PI*.5,.12],["Parte trasera",PI,.12],["Desde arriba",.6,1.1]]:
			var button:=Button.new();button.text=item[0];views.add_child(button)
			button.pressed.connect(_set_view.bind(float(item[1]),float(item[2])))
	var split:=HSplitContainer.new();split.split_offset=0;split.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(split)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=360;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(left)
	var label:=Label.new();label.text="REFERENCIA INDIVIDUAL" if individual_houses else "FOTO REAL";label.add_theme_font_size_override("font_size",18);left.add_child(label)
	_photo=TextureRect.new();_photo.name="FotoReal";_photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_photo.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(_photo)
	_status=Label.new();_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.add_theme_color_override("font_color",Color("e9bd70"));left.add_child(_status)
	var note:=Label.new();note.text="Se muestra el edificio completo utilizado por el juego. Comprueba también laterales, espalda y cubierta. El parecido se revisa por separado de sus cierres y apoyos." if individual_houses else "La distribución de estas muestras se preparó para comparar las fotos. Los edificios también se usan en el mapa generado.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_color_override("font_color",Color("aebac4"));left.add_child(note)
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.custom_minimum_size.x=360;split.add_child(right)
	var help:=Label.new();help.text="MODELO 3D · Arrastra para girar · Rueda para acercar · Botón derecho para desplazar";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(help)
	_aspect=AspectRatioContainer.new();_aspect.ratio=1.7;_aspect.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(_aspect)
	var container:=SubViewportContainer.new();container.stretch=true;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_aspect.add_child(container);container.gui_input.connect(_orbit_input)
	_viewport=SubViewport.new();_viewport.name="Vista3D";_viewport.own_world_3d=true;_viewport.size=Vector2i(900,700);_viewport.msaa_3d=Viewport.MSAA_4X;_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(_viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b3c8cf");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.28;_viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,-25,0);sun.light_energy=.68;sun.shadow_enabled=true;_viewport.add_child(sun)
	_camera=Camera3D.new();_camera.current=true;_camera.far=4000;_camera.keep_aspect=Camera3D.KEEP_WIDTH;_viewport.add_child(_camera)
	_select(0)

func _select(index: int) -> void:
	if _changing:return
	_changing=true
	if _block:
		_viewport.remove_child(_block);_block.queue_free()
	var item: Dictionary=_entries[index]
	_block=PeruReferenceBlocks.new();_viewport.add_child(_block)
	if individual_houses:_block.build_house(item.model)
	else:_block.build_reference(str(item.key))
	_target=_block.camera_target;var offset:=_block.camera_position-_target;_radius=offset.length();_yaw=atan2(offset.x,offset.z);_pitch=asin(offset.y/_radius);_camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(_block.camera_fov)*.5)*1.6))
	_photo.texture=load(str(item.photo)) if not str(item.photo).is_empty() else null
	_picker.select(index)
	if _photo.texture:_aspect.ratio=float(_photo.texture.get_width())/_photo.texture.get_height()
	if individual_houses:_aspect.ratio=1.35
	_status.text=str(item.status).to_upper()+" · "+str(item.note)+"\nNo aprobado como casi idéntico."
	_update_camera();_changing=false

func _set_view(yaw: float,pitch: float) -> void:
	_yaw=yaw;_pitch=pitch;_update_camera()

func _house_entries() -> Array:
	var sources: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/house_studies/catalog.json"))
	var known: Dictionary={}
	for source: Dictionary in sources:known[str(source.id)]=source
	var entries: Array=[]
	var prior: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference_photos/catalog.json"))
	var building_photos: Dictionary={}
	for source: Dictionary in prior:building_photos[str(source.key)]=source
	for model: Dictionary in TerrainHouses.MODELS:
		var file:=str(model.file);var style:=str(model.style);var variant:=int(file.get_basename().right(1));var ref: Dictionary={}
		if style=="casa_moderna":ref=known.get(["porton_madera","casa_angosta","casa_tropical","casa_esquina"][variant],{})
		elif style=="andina_actual":ref=known.get(["kinsawasi","larapa","zarumilla","enaco"][variant],{})
		elif style=="barranco":ref=known.get("sucre",{})
		var photo:="res://assets/house_studies/"+str(ref.photo) if ref.has("photo") else ""
		var old_key: String={"jardin":"0_residencial","valle_sagrado":"1_residencial","san_blas":"1_tradicional","tropical_actual":"2_moderna","iquitos":"2_tradicional"}.get(style,"")
		if ref.is_empty() and building_photos.has(old_key):
			ref=building_photos[old_key];photo=str(ref.photo)
		var status:="Avance parcial" if style in ["casa_moderna","andina_actual"] else "Por mal camino" if style=="barranco" else "Sin referencia individual asignada"
		if not photo.is_empty() and status=="Sin referencia individual asignada":status="Referencia de tipo; parecido pendiente"
		var note:="Referencia: "+str(ref.get("title","pendiente"))+". Revisar proporciones, materiales y detalles; no aprobado como réplica."
		if photo.is_empty():note="Pendiente de una referencia individual adecuada; no se sustituye por una fotografía general de barrio."
		entries.append({"key":file.get_file().get_basename(),"model":model,"title":StopNames.REGIONS[int(model.region)]+" · "+style.replace("_"," ")+" · "+str(variant+1),"photo":photo,"status":status,"note":note})
	return entries

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:_radius=maxf(4,_radius*.90)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:_radius=minf(1200,_radius*1.10)
	if event is InputEventMouseMotion:
		if event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			_yaw-=event.relative.x*.005;_pitch=clampf(_pitch+event.relative.y*.005,-.05,1.45)
		elif event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
			_target+=(_camera.global_basis.x*-event.relative.x+_camera.global_basis.y*event.relative.y)*_radius*.0015
	_update_camera()

func _update_camera() -> void:
	_camera.position=_target+Vector3(sin(_yaw)*cos(_pitch),sin(_pitch),cos(_yaw)*cos(_pitch))*_radius;_camera.look_at(_target)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):_back()

func _back() -> void:get_tree().change_scene_to_file("res://main.tscn")
