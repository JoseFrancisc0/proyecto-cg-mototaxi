class_name GlowZone
extends Area3D
## Zona de recogida o destino.
##
## Es un Area3D cilíndrico (solo para detectar la mototaxi). Si marker_enabled, se ve un
## anillo plano pintado sobre el suelo, que sigue el relieve (como el marcador de destino
## de GTA). Sin columna de luz ni disco: la guía principal es el minimapa del HUD.
## Todo se construye por código: basta con GlowZone.new() y place().

@export var radius := 4.0
@export var color := Color(1.0, 0.85, 0.2)
@export var pulse_speed := 3.0
## Anillo en el suelo; en la recogida se apaga porque la persona ya marca el lugar.
@export var marker_enabled := true
@export var ring_width := 0.45
@export var ring_lift := 0.12      ## Altura sobre el suelo (m), para no hundirse.

## Si está, el anillo copia la altura del terreno en cada punto.
var terrain: TerrainWorld

var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	monitoring = true
	monitorable = false

	# Volumen de detección: alto para tolerar el desnivel del terreno.
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 8.0
	shape.shape = cyl
	add_child(shape)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(color, 0.8)
	_ring = MeshInstance3D.new()
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = marker_enabled
	add_child(_ring)


func _process(delta: float) -> void:
	if not visible or not marker_enabled:
		return
	_time += delta
	_mat.albedo_color.a = lerpf(0.55, 0.95, 0.5 + 0.5 * sin(_time * pulse_speed))


## Coloca la zona sobre el suelo en ground_pos y la activa.
func place(ground_pos: Vector3) -> void:
	global_position = ground_pos
	if marker_enabled:
		_build_ring()
	activate(true)


## Muestra/oculta la zona y enciende/apaga la detección.
func activate(on: bool) -> void:
	visible = on
	set_deferred("monitoring", on)


## true si body está dentro de la zona (por ejemplo, la mototaxi).
func contains(body: Node3D) -> bool:
	return visible and monitoring and overlaps_body(body)


## Anillo como cinta de triángulos; cada vértice a la altura del terreno en su punto.
func _build_ring() -> void:
	const SEGMENTS := 56
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var c := global_position
	for i in SEGMENTS + 1:
		var a := TAU * i / SEGMENTS
		var dir := Vector3(cos(a), 0.0, sin(a))
		for r: float in [radius - ring_width, radius]:
			var p := dir * r
			var y := ring_lift
			if terrain:
				y += terrain.get_height(c.x + p.x, c.z + p.z) - c.y
			verts.append(Vector3(p.x, y, p.z))
		if i > 0:
			var v := i * 2
			idx.append_array([v - 2, v - 1, v, v - 1, v + 1, v])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ring.mesh = m
