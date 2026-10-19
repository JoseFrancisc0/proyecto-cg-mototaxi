class_name GlowZone
extends Area3D
## Zona brillante de recogida o destino (versión provisional del pasajero).
##
## Es un Area3D cilíndrico con un disco luminoso en el suelo y una columna de luz
## alta para verla desde lejos. Todo se construye por código, así no hace falta
## una escena aparte; basta con GlowZone.new() y place().

@export var radius := 4.0
@export var color := Color(1.0, 0.85, 0.2)
@export var beam_height := 60.0
@export var pulse_speed := 3.0

var _disc_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _light: OmniLight3D
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

	# Disco en el suelo: un cilindro bajo, medio enterrado para no flotar en pendientes.
	_disc_mat = _glow_material(0.45)
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 1.2
	disc_mesh.radial_segments = 48
	disc_mesh.material = _disc_mat
	disc.mesh = disc_mesh
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

	# Columna de luz que se adelgaza hacia arriba.
	_beam_mat = _glow_material(0.25)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = radius * 0.3
	beam_mesh.bottom_radius = radius * 0.8
	beam_mesh.height = beam_height
	beam_mesh.radial_segments = 24
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	beam_mesh.material = _beam_mat
	beam.mesh = beam_mesh
	beam.position.y = beam_height * 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.0
	_light.omni_range = radius * 3.0
	_light.position.y = 2.0
	add_child(_light)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var k := 0.5 + 0.5 * sin(_time * pulse_speed)
	_disc_mat.albedo_color.a = lerpf(0.3, 0.6, k)
	_beam_mat.albedo_color.a = lerpf(0.15, 0.35, k)
	_light.light_energy = lerpf(1.2, 2.5, k)


## Coloca la zona sobre el suelo en ground_pos y la activa.
func place(ground_pos: Vector3) -> void:
	global_position = ground_pos
	activate(true)


## Muestra/oculta la zona y enciende/apaga la detección.
func activate(on: bool) -> void:
	visible = on
	set_deferred("monitoring", on)


## true si body está dentro de la zona (por ejemplo, la mototaxi).
func contains(body: Node3D) -> bool:
	return visible and monitoring and overlaps_body(body)


func _glow_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(color, alpha)
	return m
