class_name FullMap
extends CanvasLayer
## Mapa completo (tecla M o Back del mando), como el mapa de pausa de GTA: norte arriba,
## todo el mundo con relieve, ríos y vías, la ruta recomendada, el objetivo, los lugares con
## nombre y la mototaxi. Rueda o +/-: acercar; arrastrar: mover; C: volver a la mototaxi.
## Main pausa el juego mientras está abierto. Reutiliza el fondo horneado del Minimap.

const ACTION := &"game_map"
const COLOR_BG := Color(0.05, 0.06, 0.07, 0.96)
const COLOR_ROAD := Color(0.86, 0.86, 0.82)
const COLOR_PLACE := Color(1, 1, 1, 0.9)

@export var min_view := 150.0   ## Metros visibles (alto de la pantalla) con el zoom máximo.

var minimap: Minimap
var race: RaceManager
var moto: Mototaxi
var route_color := Color(1.0, 0.85, 0.25)

var _canvas: Control
var _help: Label
var _center := Vector2.ZERO   # punto del mundo (x, z) en el centro de la pantalla
var _zoom := 1.0              # píxeles por metro
var _dragging := false


static func ensure_action() -> void:
	Mototaxi._add_action(ACTION, [KEY_M], [], [JOY_BUTTON_BACK])


func _ready() -> void:
	layer = 17
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	ensure_action()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_input)
	add_child(_canvas)
	_help = Label.new()
	_help.text = "MAPA   ·   M / Esc: cerrar   ·   Rueda o +/-: acercar   ·   Arrastrar: mover   ·   C: centrar"
	_help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_help.offset_top = -44
	_help.offset_bottom = -14
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_theme_font_size_override("font_size", 18)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 6)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help)


func open() -> void:
	if minimap == null or minimap.world == null:
		return
	visible = true
	_center_on_moto()
	# Arranca mostrando ~1.6 km de alto (o el mundo entero si es más chico).
	_zoom = _canvas.size.y / minf(1600.0, minimap.world.get_world_size())
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	_dragging = false


func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_C:
		_center_on_moto()
	elif k in [KEY_EQUAL, KEY_KP_ADD]:
		_zoom_at(1.25, _canvas.size * 0.5)
	elif k in [KEY_MINUS, KEY_KP_SUBTRACT]:
		_zoom_at(0.8, _canvas.size * 0.5)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.15, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		_center -= (event as InputEventMouseMotion).relative / _zoom
		_clamp_center()


## Acerca o aleja dejando fijo el punto del mundo que está bajo el cursor.
func _zoom_at(factor: float, screen_p: Vector2) -> void:
	var world_size := minimap.world.get_world_size()
	var before := _to_world(screen_p)
	var min_zoom := _canvas.size.y / (world_size * 1.1)
	var max_zoom := _canvas.size.y / min_view
	_zoom = clampf(_zoom * factor, min_zoom, max_zoom)
	_center += before - _to_world(screen_p)
	_clamp_center()


func _center_on_moto() -> void:
	if moto:
		_center = Vector2(moto.global_position.x, moto.global_position.z)


func _clamp_center() -> void:
	var half := minimap.world.get_world_size() * 0.5
	_center = _center.clamp(Vector2.ONE * -half, Vector2.ONE * half)


func _to_world(screen_p: Vector2) -> Vector2:
	return _center + (screen_p - _canvas.size * 0.5) / _zoom


func _to_screen(p: Vector2) -> Vector2:
	return _canvas.size * 0.5 + (p - _center) * _zoom


func _draw_map() -> void:
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), COLOR_BG)
	if minimap == null or minimap.world == null:
		return
	var world := minimap.world
	var size := world.get_world_size()
	var half := size * 0.5
	# Norte (-z) arriba: mundo (x, z) -> pantalla con una escala y un desplazamiento.
	var t := Transform2D(Vector2(_zoom, 0), Vector2(0, _zoom), c.size * 0.5 - _center * _zoom)
	c.draw_set_transform_matrix(t)
	var tex := minimap.get_background()
	if tex:
		c.draw_texture_rect(tex, Rect2(-half, -half, size, size), false)
	var view := Rect2(_to_world(Vector2.ZERO), c.size / _zoom)
	var px := 1.0 / _zoom
	for road in minimap.get_road_pieces():
		if view.intersects(road["box"]):
			c.draw_polyline(road["pts"], COLOR_ROAD, maxf(road["w"], 2.0 * px))
	var showing := race != null and race.state in [RaceManager.State.LIBRE, RaceManager.State.CON_PASAJERO]
	if showing and race.route_line:
		var pts := race.route_line.remaining_points()
		if pts.size() >= 2:
			var flat := PackedVector2Array()
			flat.append(Vector2(moto.global_position.x, moto.global_position.z))
			for p in pts:
				flat.append(Vector2(p.x, p.z))
			c.draw_polyline(flat, Color(0, 0, 0, 0.6), 8.0 * px)
			c.draw_polyline(flat, route_color, 5.0 * px)
	c.draw_set_transform_matrix(Transform2D())

	# Lugares con nombre (miradores, confluencias, caletas, pueblos).
	var font := c.get_theme_default_font()
	for lm in world.get_landmarks():
		var label := str(lm.get("label", ""))
		if label.is_empty():
			continue
		var sp := _to_screen(Vector2(lm["position"].x, lm["position"].z))
		if not Rect2(Vector2.ZERO, c.size).has_point(sp):
			continue
		c.draw_circle(sp, 4.0, Color.BLACK)
		c.draw_circle(sp, 2.5, COLOR_PLACE)
		c.draw_string_outline(font, sp + Vector2(7, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		c.draw_string(font, sp + Vector2(7, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_PLACE)

	if showing:
		var goal := race.get_target()
		if goal != Vector3.INF:
			var gp := _to_screen(Vector2(goal.x, goal.z))
			c.draw_circle(gp, 11.0, Color.BLACK)
			c.draw_circle(gp, 8.0, route_color)
	# Mototaxi: flecha que apunta hacia donde mira.
	var mp := _to_screen(Vector2(moto.global_position.x, moto.global_position.z))
	var f := Vector2(moto.global_basis.z.x, moto.global_basis.z.z)
	var ang := f.angle() + PI * 0.5 if f.length() > 0.01 else 0.0
	var tri := PackedVector2Array([Vector2(0, -12), Vector2(9, 9), Vector2(0, 4), Vector2(-9, 9)])
	for i in tri.size():
		tri[i] = mp + tri[i].rotated(ang)
	c.draw_colored_polygon(tri, Color.WHITE)
	c.draw_polyline(tri + PackedVector2Array([tri[0]]), Color.BLACK, 2.0, true)
	# Norte.
	c.draw_string_outline(font, Vector2(c.size.x - 48, 48), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color.BLACK)
	c.draw_string(font, Vector2(c.size.x - 48, 48), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
