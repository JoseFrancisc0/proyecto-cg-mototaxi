class_name RouteLine
extends MeshInstance3D
## Ruta recomendada (S12, J-B): guarda la ruta y la recorta a medida que la mototaxi
## avanza. El minimapa la dibuja; opcionalmente también se ve como cinta con flechas sobre
## el suelo (RaceManager.show_route_in_world).

@export var width := 1.6
@export var lift := 0.35            ## Altura sobre el suelo (m), para no hundirse en el terreno.
@export var max_step := 2.0         ## Subdivide tramos más largos para seguir el relieve.
@export var color := Color(1.0, 0.85, 0.2):
	set(v):
		color = v
		if _mat:
			_mat.set_shader_parameter("tint", v)

var terrain: TerrainWorld

var _points := PackedVector3Array()  # ruta subdividida
var _dist := PackedFloat32Array()    # distancia acumulada de cada punto
var _from := 0                       # primer punto dibujado
var _mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.2, 1.0);
void fragment() {
	// UV.x = metros a lo largo de la ruta; UV.y = 0..1 a lo ancho.
	float across = abs(UV.y - 0.5) * 2.0;
	float chevron = fract(UV.x / 3.0 - across * 0.35 - TIME * 0.9);
	float arrow = step(chevron, 0.4);
	float edge = smoothstep(1.0, 0.8, across);
	ALBEDO = mix(tint.rgb * 0.75, vec3(1.0), arrow * 0.55);
	ALPHA = edge * mix(0.55, 0.95, arrow);
}
"""


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("tint", color)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Cambia la ruta mostrada (vacía = ocultar).
func set_route(route: PackedVector3Array) -> void:
	_points = PackedVector3Array()
	_dist = PackedFloat32Array()
	_from = 0
	for i in route.size():
		if i > 0:
			var a := route[i - 1]
			var b := route[i]
			var steps := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / max_step))
			for s in range(1, steps):
				_append(a.lerp(b, float(s) / steps))
		_append(route[i])
	_rebuild()


## Índice del punto de la ruta más cercano a p, buscando hacia adelante desde el último.
## Recorta lo ya recorrido. Devuelve la distancia (m, en planta) de p a la ruta.
func advance(p: Vector3) -> float:
	if _points.size() < 2:
		return 0.0
	var best := _from
	var best_d := INF
	for i in range(_from, mini(_points.size(), _from + 80)):
		var d := Vector2(_points[i].x - p.x, _points[i].z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	if best > _from + 2:
		_from = best
		_rebuild()
	return best_d


## Punto de la ruta a 'ahead' metros por delante del avance actual (para la flecha del HUD).
func point_ahead(ahead: float) -> Vector3:
	if _points.is_empty():
		return Vector3.INF
	var goal := _dist[_from] + ahead
	for i in range(_from, _points.size()):
		if _dist[i] >= goal:
			return _points[i]
	return _points[-1]


## Puntos de la ruta que faltan recorrer (para el minimapa).
func remaining_points() -> PackedVector3Array:
	return _points.slice(_from) if _points.size() - _from >= 2 else PackedVector3Array()


func remaining_length() -> float:
	return 0.0 if _points.is_empty() else _dist[-1] - _dist[_from]


func _append(p: Vector3) -> void:
	if terrain:
		p.y = maxf(p.y, terrain.get_height(p.x, p.z))
	if not _points.is_empty():
		var last := _points[-1]
		var step := Vector2(p.x - last.x, p.z - last.z).length()
		if step < 0.05:
			return
		_dist.append(_dist[-1] + step)
	else:
		_dist.append(0.0)
	_points.append(p)


func _rebuild() -> void:
	var n := _points.size() - _from
	if n < 2:
		mesh = null
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in n:
		var i := _from + k
		var a := _points[maxi(i - 1, _from)]
		var b := _points[mini(i + 1, _points.size() - 1)]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.001:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(Vector3.UP) * (width * 0.5)
		var c := _points[i] + Vector3.UP * lift
		verts.append(c - side)
		verts.append(c + side)
		uvs.append(Vector2(_dist[i], 0.0))
		uvs.append(Vector2(_dist[i], 1.0))
		if k > 0:
			var v := k * 2
			idx.append_array([v - 2, v - 1, v, v - 1, v + 1, v])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
