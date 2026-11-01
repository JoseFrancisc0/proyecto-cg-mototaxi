class_name LoadingScreen
extends CanvasLayer
## Portada adaptada de Maaack's Menus Template (MIT). Ver ui/vendor/maaack.
signal start_requested(choice: Dictionary)
const Shell = preload("res://scenes/pregame_shell.tscn")
const DisplayFont = preload("res://ui/fonts/Bangers-Regular.ttf")
const MenuPhoto = preload("res://ui/photos/mototaxi_reference.png")
const MenuMusic = preload("res://audio/cumbieton_vs_old_school_dj_juanchii.mp3")
const MENU_TRACK := "Cumbieton vs Reggaeton Old School · DJ Juanchii"
const YELLOW := Color("ffdb38")
const MUTED := Color("a7abb7")
var world: TerrainWorld
var _root: Control
var _home: Control
var _hero: Control
var _navigation: BoxContainer
var _title: Label
var _paper: Label
var _dialog: Control
var _dialog_panel: PanelContainer
var _dialog_title: Label
var _dialog_body: Label
var _dialog_close: Button
var _menu: VBoxContainer
var _options: VBoxContainer
var _notice: Label
var _seed_edit: LineEdit
var _seed_row: VBoxContainer
var _quality_row: VBoxContainer
var _mode: OptionButton
var _quality: OptionButton
var _play: Button
var _help: Button
var _credits: Button
var _progress_box: Control
var _preview: TextureRect
var _preview_placeholder: Label
var _bar: ProgressBar
var _stage: Label
var _detail: Label
var _progress_percent: Label
var _preview_serial := -1
var _preview_source_id := 0
var _preview_updates := 0
var _started_at := 0
var _fraction := 0.0
var _starting := false
var _finishing := false
var _music_player: AudioStreamPlayer
var _music_toggle: Button
var _music_slider: HSlider
var _music_value: Label
var _music_volume := .2
var _music_enabled := true
var _saturated := true
var _custom_music := ""
var _saturation_toggle: CheckButton
var _music_status: Label
var _file_dialog: FileDialog
var _bus_name := ""

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_setup_radio()
	get_viewport().size_changed.connect(_responsive)
	_responsive()

func _style(color: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _label(text: String, font_size := 18, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(action)
	return b

func _build_ui() -> void:
	_root = Shell.instantiate()
	add_child(_root)
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_stylebox("normal","Button",_style(Color("181922e8"),Color("62636b")))
	theme.set_stylebox("hover","Button",_style(Color("34303b"),YELLOW))
	theme.set_stylebox("pressed","Button",_style(Color("7a254c"),Color("ff3b8b")))
	theme.set_stylebox("focus","Button",_style(Color("00000000"),YELLOW))
	theme.set_color("font_hover_color","Button",YELLOW)
	theme.set_color("font_focus_color","Button",YELLOW)
	_root.theme = theme
	var photo := _root.get_node("BackgroundTextureRect") as TextureRect
	# The supplied photograph is kept intact; TextureRect crops to the viewport.
	photo.texture = MenuPhoto
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.025,0.045,.67)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_root.move_child(shade,1)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home = _root.get_node("MenuContainer")
	_hero = _home.get_node("TitleMargin")
	_title = _hero.get_node("TitleContainer/TitleLabel")
	_title.text = "CRAZY MOTOTAXI"
	_title.add_theme_font_override("font",DisplayFont)
	_title.add_theme_color_override("font_color",YELLOW)
	_title.add_theme_color_override("font_shadow_color",Color("d92c78"))
	_title.add_theme_constant_override("shadow_offset_x",3)
	_title.add_theme_constant_override("shadow_offset_y",4)
	_home.get_node("SubTitleMargin").hide()
	_navigation = _home.get_node("MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer")
	var actions := [_open_setup,_show_options,_show_controls,_show_credits,func(): get_tree().quit()]
	var names := ["Jugar","Opciones","Controles","Créditos","Salir"]
	for i in range(5):
		var button := _navigation.get_child(i) as Button
		button.text = names[i]
		button.pressed.connect(actions[i])
	_help = _navigation.get_child(2)
	_credits = _navigation.get_child(3)
	_paper = _root.get_node("VersionMargin/VersionContainer/VersionLabel")
	_paper.text = "Schott et al. (2024) · Terrain Amplification using Multi-scale Erosion"
	_paper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper.add_theme_font_size_override("font_size",12)
	_paper.add_theme_color_override("font_color",Color("a7abb7b3"))
	_build_dialog()
	_build_progress()
	_music_toggle = _button("",func(): _set_music(not _music_enabled))
	_root.add_child(_music_toggle)
	_music_toggle.add_theme_font_size_override("font_size",13)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.mp3,*.ogg,*.wav ; Audio"])
	_file_dialog.file_selected.connect(_load_custom_music)
	add_child(_file_dialog)

func _build_dialog() -> void:
	_dialog = Control.new()
	_root.add_child(_dialog)
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,.72)
	_dialog.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog_panel = PanelContainer.new()
	_dialog_panel.add_theme_stylebox_override("panel",_style(Color("171820"),Color("67616a")))
	_dialog.add_child(_dialog_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	_dialog_panel.add_child(layout)
	_dialog_title = _label("Jugar",30,YELLOW)
	layout.add_child(_dialog_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation",14)
	scroll.add_child(contents)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation",12)
	contents.add_child(_menu)
	_menu.add_child(_label("Terreno"))
	_mode = OptionButton.new()
	_mode.add_item("Terreno guardado")
	_mode.add_item("Nuevo terreno")
	_mode.custom_minimum_size.y = 44
	_mode.item_selected.connect(_update_mode)
	_menu.add_child(_mode)
	_seed_row = VBoxContainer.new()
	_menu.add_child(_seed_row)
	_seed_row.add_child(_label("Semilla"))
	var seed_controls := HBoxContainer.new()
	_seed_row.add_child(seed_controls)
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size.y = 44
	seed_controls.add_child(_seed_edit)
	seed_controls.add_child(_button("Aleatoria",func(): _seed_edit.text = str(randi()%2147483647)))
	_quality_row = VBoxContainer.new()
	_menu.add_child(_quality_row)
	_quality_row.add_child(_label("Generación"))
	_quality = OptionButton.new()
	for item in ["Rápida","Normal","Completa"]: _quality.add_item(item)
	_quality.custom_minimum_size.y = 44
	_quality_row.add_child(_quality)
	var note := _label("La misma semilla y los mismos ajustes generan el mismo terreno. La generación completa tarda más.",15,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quality_row.add_child(note)
	_notice = _label("",16,Color("ff839c"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu.add_child(_notice)
	_play = _button("Iniciar",_on_play)
	_menu.add_child(_play)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation",12)
	contents.add_child(_options)
	_options.add_child(_label("Volumen de la música"))
	_music_slider = HSlider.new()
	_music_slider.min_value = 0
	_music_slider.max_value = 100
	_music_slider.step = 1
	_music_slider.custom_minimum_size.y = 32
	_music_slider.value_changed.connect(func(value): _set_music_volume(value/100))
	_options.add_child(_music_slider)
	_music_value = _label("",15,MUTED)
	_options.add_child(_music_value)
	var saturated := CheckButton.new()
	_saturation_toggle = saturated
	saturated.text = "Sonido saturado"
	saturated.button_pressed = true
	saturated.toggled.connect(func(enabled):
		_saturated = enabled
		_apply_saturation()
		_save_radio())
	_options.add_child(saturated)
	_options.add_child(_button("Elegir música…",func(): _file_dialog.popup_centered_ratio(.8)))
	_options.add_child(_button("Restaurar música del menú",func():
		_custom_music = ""
		_set_stream(MenuMusic.duplicate())
		_music_status.text = MENU_TRACK
		_save_radio()))
	_music_status = _label("",15,MUTED)
	_music_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options.add_child(_music_status)
	_dialog_body = _label("",17)
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(_dialog_body)
	_dialog_close = _button("Volver",_close_dialog)
	layout.add_child(_dialog_close)
	_dialog.hide()

func _build_progress() -> void:
	_progress_box = PanelContainer.new()
	_progress_box.add_theme_stylebox_override("panel",_style(Color("101118"),Color("101118")))
	_root.add_child(_progress_box)
	_progress_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	_progress_box.add_child(column)
	_stage = _label("Preparando terreno",24,YELLOW)
	_stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stage)
	var image_area := Control.new()
	image_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(image_area)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_area.add_child(_preview)
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_placeholder = _label("Preparando terreno…",20,MUTED)
	_preview_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	image_area.add_child(_preview_placeholder)
	_preview_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = 12
	_bar.show_percentage = false
	column.add_child(_bar)
	_progress_percent = _label("0 %",20,YELLOW)
	column.add_child(_progress_percent)
	_detail = _label("",14,MUTED)
	column.add_child(_detail)
	_progress_box.hide()

func _open_panel(title: String) -> void:
	_home.hide()
	_dialog_title.text = title
	_menu.hide()
	_options.hide()
	_dialog_body.hide()
	_dialog.show()
	_dialog_close.grab_focus()
	_responsive()

func _open_setup() -> void:
	_open_panel("Jugar")
	_menu.show()
	_play.grab_focus()

func _show_options() -> void:
	_open_panel("Opciones")
	_options.show()

func _show_dialog(title: String, text: String) -> void:
	_open_panel(title)
	_dialog_body.text = text
	_dialog_body.show()

func _close_dialog() -> void:
	_dialog.hide()
	_home.show()
	_navigation.get_child(0).grab_focus()

func _show_controls() -> void:
	_show_dialog("Controles","W / ↑ — Acelerar\nS / ↓ — Frenar y retroceder\nA, D / ←, → — Girar\nEspacio — Freno de mano\nR — Enderezar la mototaxi\n\nRecoge al pasajero en la zona amarilla y llévalo a la zona verde.")

func _show_credits() -> void:
	_show_dialog("Créditos","Rodrigo Felix Meza Gavilan\nJosep Ratzinger Castro Ferrer\nJose Francisco Wong Orrillo\nJose Joaquin Osnayo Matos\n\nComputación Gráfica · UTEC · 2026-II\n\nMenú: Maaack's Menus Template\nMarek Belski · MIT\nFotografía: referencia aportada al proyecto.\nMúsica: Cumbieton vs Reggaeton Old School (2020)\nDJ Pirata, Maxi Gen, El Kaio y DJ Juanchii\nDescarga publicada por DJ Juanchii en su canal.\nTipografía Bangers: Vernon Adams · SIL OFL\nTexturas: ambientCG · CC0\n\nTerreno: Schott et al. (2024), Terrain Amplification using Multi-scale Erosion.")

func _responsive() -> void:
	if not is_instance_valid(_root): return
	var v := get_viewport().get_visible_rect().size
	var short := v.y < 500
	_title.add_theme_font_size_override("font_size",44 if short else int(clampf(v.x*.08,46,100)))
	_title.text = "CRAZY\nMOTOTAXI" if v.x < 500 and not short else "CRAZY MOTOTAXI"
	_title.offset_bottom = 136 if v.x < 500 and not short else 110
	_hero.add_theme_constant_override("margin_top",14 if short else int(v.y*.07))
	_home.get_node("MenuButtonsMargin").add_theme_constant_override("margin_top",76 if short else 160)
	_home.get_node("MenuButtonsMargin").add_theme_constant_override("margin_bottom",40)
	_navigation.add_theme_constant_override("separation",4 if short else 10)
	var row_height := 36 if short else 48
	for button in _navigation.get_children():
		button.custom_minimum_size = Vector2(210,row_height)
		button.add_theme_font_size_override("font_size",17 if short else 21)
	_navigation.offset_left = -110
	_navigation.offset_right = 110
	_navigation.offset_top = -(row_height*5 + (4 if short else 10)*4)/2.0
	_navigation.offset_bottom = -_navigation.offset_top
	_paper.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_paper.offset_left = 8
	_paper.offset_right = -125
	_paper.offset_top = -38
	_paper.offset_bottom = 0
	_music_toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_music_toggle.offset_left = -126
	_music_toggle.offset_right = -12
	_music_toggle.offset_top = -52
	_music_toggle.offset_bottom = -12
	var w := minf(540,v.x-28)
	var h := minf(620,v.y-36)
	_dialog_panel.position = (v-Vector2(w,h))/2
	_dialog_panel.size = Vector2(w,h)
	_progress_box.offset_left = 20
	_progress_box.offset_top = 20
	_progress_box.offset_right = -20
	_progress_box.offset_bottom = -72

func _update_mode(_index := 0) -> void:
	_seed_row.visible = _mode.selected == 1
	_quality_row.visible = _mode.selected == 1

func show_menu(choice: Dictionary) -> void:
	_starting = false
	_finishing = false
	_home.show()
	_navigation.show()
	_hero.show()
	_progress_box.hide()
	_dialog.hide()
	_seed_edit.text = str(choice.get("seed",67))
	_mode.select(0 if choice.get("mode","editor") == "editor" else 1)
	var scale: float = choice.get("erosion_scale",.1)
	_quality.select(0 if scale <= .15 else (1 if scale <= .5 else 2))
	_notice.hide()
	_play.disabled = false
	_update_mode()
	_responsive()
	_navigation.get_child(0).grab_focus()

func _on_play() -> void:
	if _starting: return
	var seed_text := _seed_edit.text.strip_edges()
	if _mode.selected == 1 and (not seed_text.is_valid_int() or int(seed_text)<0 or int(seed_text)>2147483647):
		_notice.text = "Ingresa una semilla entre 0 y 2147483647."
		_notice.show()
		return
	_starting = true
	_play.disabled = true
	start_requested.emit({"mode":"editor" if _mode.selected == 0 else "seed","seed":int(seed_text) if seed_text.is_valid_int() else 67,"erosion_scale":[.1,.35,1.0][_quality.selected]})

func show_progress() -> void:
	_home.hide()
	_navigation.hide()
	_hero.hide()
	_dialog.hide()
	_progress_box.show()
	_preview.texture = null
	_preview.hide()
	_preview_placeholder.show()
	_preview_serial = -1
	_preview_source_id = 0
	_preview_updates = 0
	_fraction = 0
	_started_at = Time.get_ticks_msec()
	set_progress("Preparando terreno",0)

func set_progress(stage: String, fraction: float) -> void:
	if is_finite(fraction): _fraction = maxf(_fraction,clampf(fraction,0,1))
	_stage.text = stage
	_bar.value = _fraction*100
	_progress_percent.text = "%d %%" % int(_fraction*100)

func show_error(message := "No se pudo preparar el terreno. Intenta de nuevo.") -> void:
	show_menu({"mode":"editor" if _mode.selected == 0 else "seed","seed":int(_seed_edit.text),"erosion_scale":[.1,.35,1.0][_quality.selected]})
	_open_setup()
	_notice.text = message
	_notice.show()

func _process(_delta: float) -> void:
	if not is_instance_valid(_progress_box) or not _progress_box.visible or _finishing: return
	var elapsed := int((Time.get_ticks_msec()-_started_at)/1000)
	_detail.text = "%02d:%02d" % [elapsed/60,elapsed%60]
	if world == null or world.generator == null: return
	var builder: TerrainMesh = world.generator.current_builder
	if builder == null: return
	var source_id := builder.get_instance_id()
	if source_id != _preview_source_id:
		_preview_source_id = source_id
		_preview_serial = -1
	var progress := builder.get_progress()
	if int(progress.get("preview_serial",-1)) == _preview_serial: return
	var preview := builder.get_preview()
	_preview_serial = int(preview["serial"])
	var width: int = preview["width"]
	var height: int = preview["height"]
	var rgb: PackedByteArray = preview["rgb"]
	if width > 0 and height > 0 and rgb.size() == width*height*3:
		_preview.texture = ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RGB8,rgb))
		_preview.visible = true
		_preview_placeholder.visible = false
		_preview_updates += 1

func finish() -> void:
	if _finishing: return
	_finishing = true
	set_progress("Listo",1)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root,"modulate:a",0.0,.35)
	tween.parallel().tween_property(_music_player,"volume_db",-60.0,.35)
	tween.tween_callback(queue_free)

func _setup_radio() -> void:
	var saved := ConfigFile.new()
	if saved.load("user://pregame_audio.cfg") == OK:
		_music_enabled = bool(saved.get_value("radio","enabled",true))
		_music_volume = clampf(float(saved.get_value("radio","volume",.2)),0,1)
		_custom_music = str(saved.get_value("radio","file",""))
		_saturated = bool(saved.get_value("radio","saturated",true))
	_saturation_toggle.set_pressed_no_signal(_saturated)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_bus_name = "MenuRadio_%d" % get_instance_id()
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,_bus_name)
	var distortion := AudioEffectDistortion.new()
	distortion.mode = AudioEffectDistortion.MODE_OVERDRIVE
	distortion.drive = .4
	distortion.pre_gain = 3
	distortion.post_gain = -6
	AudioServer.add_bus_effect(index,distortion)
	_music_player.bus = _bus_name
	_apply_saturation()
	_set_stream(MenuMusic.duplicate())
	_music_status.text = MENU_TRACK
	if not _custom_music.is_empty() and FileAccess.file_exists(_custom_music): _load_custom_music(_custom_music,false)
	_music_slider.set_value_no_signal(_music_volume*100)
	_set_music_volume(_music_volume,false)
	_set_music(_music_enabled,false)

func _apply_saturation() -> void:
	var index := AudioServer.get_bus_index(_bus_name)
	if index >= 0: AudioServer.set_bus_effect_enabled(index,0,_saturated)

func _set_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis: stream.loop = true
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
	_music_player.stream = stream
	_music_player.play()
	_music_player.stream_paused = not _music_enabled

func _load_custom_music(path: String, persist := true) -> void:
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			stream = mp3
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
	if stream == null or stream.get_length() <= 0:
		_music_status.text = "No se pudo abrir ese archivo."
		return
	_custom_music = path
	_set_stream(stream)
	_music_status.text = path.get_file()
	if persist: _save_radio()

func _set_music(enabled: bool, persist := true) -> void:
	_music_enabled = enabled
	_music_player.stream_paused = not enabled
	_music_toggle.text = "Música: sí" if enabled else "Música: no"
	if persist: _save_radio()

func _set_music_volume(volume: float, persist := true) -> void:
	_music_volume = clampf(volume,0,1)
	_music_player.volume_db = linear_to_db(maxf(.0001,_music_volume))
	_music_value.text = "%d %%" % roundi(_music_volume*100)
	if persist: _save_radio()

func _save_radio() -> void:
	var saved := ConfigFile.new()
	saved.set_value("radio","enabled",_music_enabled)
	saved.set_value("radio","volume",_music_volume)
	saved.set_value("radio","file",_custom_music)
	saved.set_value("radio","saturated",_saturated)
	saved.save("user://pregame_audio.cfg")

func _exit_tree() -> void:
	if is_instance_valid(_music_player): _music_player.stop()
	var index := AudioServer.get_bus_index(_bus_name)
	if index > 0: AudioServer.remove_bus(index)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _dialog.visible:
		_close_dialog()
		get_viewport().set_input_as_handled()
