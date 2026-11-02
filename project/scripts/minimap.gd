class_name Minimap
extends Control
## Minimapa estilo GTA (abajo a la izquierda): gira con la mototaxi (adelante = arriba),
## muestra el relieve, los ríos y las vías, la ruta recomendada por las vías y el punto
## del objetivo. Si el objetivo queda fuera, su punto se pega al borde del mapa.
##
## El fondo (región, sombreado del relieve y ríos) se hornea una vez en una textura;
## las vías y la ruta se dibujan como líneas para que se vean nítidas al acercar.

## Metros que se ven desde la mototaxi hasta el borde superior, parado y a toda velocidad.
@export var view_near := 110.0
@export var view_far := 220.0
@export var far_speed_kmh := 70.0
@export var bake_size := 512

const COLOR_BG := Color(0.07, 0.08, 0.09)
const COLOR_ROAD := Color(0.86, 0.86, 0.82)
const COLOR_FRAME := Color(0, 0, 0, 0.85)
## Colores de región: costa, sierra, selva.
const BIOME_COLORS := [Color(0.72, 0.66, 0.47), Color(0.55, 0.5, 0.43), Color(0.28, 0.45, 0.24)]
const COLOR_RIVER := Color(0.25, 0.48, 0.75)

var world: TerrainWorld
var race: RaceManager
var moto: Mototaxi
var route_color := Color(1.0, 0.85, 0.25)
var target_color := Color(1.0, 0.85, 0.25)

var _tex: ImageTexture
var _half := 0.0
var _size := 0.0
var _roads: Array = []      # [{ "pts": PackedVector2Array, "box": Rect2, "w": float }]
var _view := 110.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = view_near


## Prepara el mapa del mundo (una vez por terreno).
func setup(w: TerrainWorld, r: RaceManager, m: Mototaxi) -> void:
	world = w
	race = r
	moto = m
	_size = world.get_world_size()
	_half = _size * 0.5
	_bake_background()
	_index_roads()


func _process(delta: float) -> void:
	if moto:
		var k := clampf(moto.get_speed_kmh() / far_speed_kmh, 0.0, 1.0)
		_view = lerpf(_view, lerpf(view_near, view_far, k), 1.0 - exp(-2.0 * delta))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if world == null or moto == null:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.62)  # la mototaxi un poco abajo, como en GTA
	var k := center.y / _view                           # píxeles por metro
	var fwd := moto.global_basis.z
	var right := -moto.global_basis.x
	var f := Vector2(fwd.x, fwd.z).normalized()
	var r := Vector2(right.x, right.z).normalized()
	var mp := Vector2(moto.global_position.x, moto.global_position.z)
	# Mundo (x, z) -> pantalla: adelante hacia arriba, derecha hacia la derecha.
	var xc := Vector2(r.x, -f.x) * k
	var yc := Vector2(r.y, -f.y) * k
	var t := Transform2D(xc, yc, center - xc * mp.x - yc * mp.y)

	draw_set_transform_matrix(t)
	if _tex:
		draw_texture_rect(_tex, Rect2(-_half, -_half, _size, _size), false)
	# Vías visibles (solo los tramos cuyo recuadro cae cerca).
	var view_box := Rect2(mp - Vector2.ONE * _view * 1.6, Vector2.ONE * _view * 3.2)
	var px := 1.0 / k  # un píxel en metros
	for road in _roads:
		if view_box.intersects(road["box"]):
			draw_polyline(road["pts"], COLOR_ROAD, maxf(road["w"], 2.5 * px))
	# Ruta recomendada (lo que falta recorrer).
	var showing := race != null and race.state in [RaceManager.State.LIBRE, RaceManager.State.CON_PASAJERO]
	if showing and race.route_line:
		var pts := race.route_line.remaining_points()
		if pts.size() >= 2:
			var flat := PackedVector2Array()
			flat.resize(pts.size() + 1)
			flat[0] = mp
			for i in pts.size():
				flat[i + 1] = Vector2(pts[i].x, pts[i].z)
			draw_polyline(flat, Color(0, 0, 0, 0.6), 7.0 * px)
			draw_polyline(flat, route_color, 4.5 * px)
	draw_set_transform_matrix(Transform2D())

	# Norte (-z) pegado al borde.
	_draw_edge_label("N", t * Vector2(mp.x, mp.y - 10000.0), center, Color.WHITE)
	# Objetivo: punto con borde; en el borde si queda fuera.
	if showing:
		var goal := race.get_target()
		if goal != Vector3.INF:
			var gp := t * Vector2(goal.x, goal.z)
			var inside := Rect2(Vector2.ONE * 10.0, size - Vector2.ONE * 20.0)
			var p := gp if inside.has_point(gp) else _clamp_to_rect(center, gp, inside)
			draw_circle(p, 8.0, Color.BLACK)
			draw_circle(p, 6.0, target_color)
	# Mototaxi: flecha blanca en el centro.
	var tri := PackedVector2Array([center + Vector2(0, -9), center + Vector2(7, 7),
		center + Vector2(0, 3), center + Vector2(-7, 7)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color.BLACK, 1.5, true)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FRAME, false, 3.0)


func _draw_edge_label(text: String, screen_p: Vector2, center: Vector2, c: Color) -> void:
	var inside := Rect2(Vector2.ONE * 12.0, size - Vector2.ONE * 24.0)
	var p := _clamp_to_rect(center, screen_p, inside)
	var font := get_theme_default_font()
	draw_circle(p, 10.0, Color(0, 0, 0, 0.7))
	draw_string(font, p + Vector2(-5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)


## Punto donde la recta center→p sale del rectángulo (o p si está dentro).
static func _clamp_to_rect(center: Vector2, p: Vector2, box: Rect2) -> Vector2:
	if box.has_point(p):
		return p
	var d := p - center
	var s := INF
	if d.x > 0.0:
		s = minf(s, (box.end.x - center.x) / d.x)
	elif d.x < 0.0:
		s = minf(s, (box.position.x - center.x) / d.x)
	if d.y > 0.0:
		s = minf(s, (box.end.y - center.y) / d.y)
	elif d.y < 0.0:
		s = minf(s, (box.position.y - center.y) / d.y)
	return center + d * clampf(s, 0.0, 1.0)


## Fondo del mapa: color de la región, sombreado del relieve (luz del noroeste), ríos y
## lagos. Las alturas y el drenaje se leen de las grillas del terreno (sin llamadas por punto).
func _bake_background() -> void:
	var t0 := Time.get_ticks_msec()
	var n := bake_size
	var step := _size / (n - 1)
	# Región a baja resolución (llamada a C++ por punto), luego se agranda suavizada.
	var low := 64
	var col := Image.create(low, low, false, Image.FORMAT_RGB8)
	for j in low:
		for i in low:
			var b := world.get_biome(-_half + i * _size / (low - 1), -_half + j * _size / (low - 1))
			var s := maxf(b.x + b.y + b.z, 0.001)
			col.set_pixel(i, j, BIOME_COLORS[0] * (b.x / s) + BIOME_COLORS[1] * (b.y / s) + BIOME_COLORS[2] * (b.z / s))
	col.resize(n, n, Image.INTERPOLATE_BILINEAR)

	var hs: PackedFloat32Array = world._heights
	var hn: int = world._n
	var acc := PackedFloat64Array()
	var lakes := PackedInt32Array()
	var dn := 0
	var river_area := 60000.0
	if world._surface:
		var hydro: Dictionary = world._surface.get_hydrology_data()
		dn = hydro.get("samples", 0)
		acc = hydro.get("accumulation", PackedFloat64Array())
		lakes = hydro.get("lakes", PackedInt32Array())
		if acc.size() != dn * dn:
			dn = 0
	if world.generator and world.generator.get("river_catchment") != null:
		river_area = world.generator.river_catchment

	var light := Vector3(-1.0, 1.4, -1.0).normalized()
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var hrow := PackedFloat32Array()
	hrow.resize(n * n)
	for j in n:
		var gj := roundi(float(j) * (hn - 1) / (n - 1))
		for i in n:
			hrow[j * n + i] = hs[gj * hn + roundi(float(i) * (hn - 1) / (n - 1))] if hs.size() == hn * hn else 0.0
	for j in n:
		var dj := roundi(float(j) * (dn - 1) / (n - 1)) if dn > 1 else 0
		for i in n:
			var hx := hrow[j * n + mini(i + 1, n - 1)] - hrow[j * n + maxi(i - 1, 0)]
			var hz := hrow[mini(j + 1, n - 1) * n + i] - hrow[maxi(j - 1, 0) * n + i]
			var nrm := Vector3(-hx / (2.0 * step), 1.0, -hz / (2.0 * step)).normalized()
			var shade := clampf(0.55 + 0.6 * (nrm.dot(light) - 0.6), 0.45, 1.15)
			var c := col.get_pixel(i, j) * shade
			if dn > 1:
				var k := dj * dn + roundi(float(i) * (dn - 1) / (n - 1))
				if acc[k] >= river_area or (lakes.size() == acc.size() and lakes[k] != 0):
					c = COLOR_RIVER
			c.a = 1.0
			img.set_pixel(i, j, c.darkened(0.15))
	_tex = ImageTexture.create_from_image(img)
	print("Minimap: fondo %dx%d en %d ms" % [n, n, Time.get_ticks_msec() - t0])


## Parte las vías en tramos cortos con su recuadro, para dibujar solo las cercanas.
func _index_roads() -> void:
	_roads.clear()
	const PIECE := 24
	for road in world.get_roads():
		var path: PackedVector3Array = road["path"]
		var w: float = road.get("width", 4.0)
		var start := 0
		while start < path.size() - 1:
			var end := mini(start + PIECE, path.size() - 1)
			var pts := PackedVector2Array()
			var box := Rect2(Vector2(path[start].x, path[start].z), Vector2.ZERO)
			for i in range(start, end + 1):
				var p := Vector2(path[i].x, path[i].z)
				pts.append(p)
				box = box.expand(p)
			_roads.append({"pts": pts, "box": box, "w": w})
			start = end
