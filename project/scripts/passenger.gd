class_name Passenger
extends Node3D
## Pasajero visible (S13): persona animada que espera junto a la vía, hace señas, sube y baja.
##
## Modelos de Quaternius (CC0, ver res://assets/characters/SOURCE.md). Todos comparten el
## esqueleto y las animaciones, así que cualquiera sirve para cualquier pasajero.
##
## Ciclo, lo maneja RaceManager:
##   wait_at()  -> espera de pie; mira a la mototaxi y la llama con la mano al acercarse.
##   board()    -> camina hacia la mototaxi y "sube" (se oculta).
##   get_off()  -> aparece junto a la mototaxi, paga o reclama según el ánimo, se va caminando y
##                 se borra (RaceManager crea otro Passenger para el siguiente viaje).
## No tiene colisión: la recogida se detecta con la zona de RaceManager.

const HeadModel := preload("res://scripts/passenger_head.gd")
const PORTRAIT_PATH := "user://passenger_portrait.png"
const PORTRAIT_SHADER := preload("res://shaders/passenger_portrait.gdshader")
const PORTRAIT_MODEL := 0  # Casual2: coordenadas de rostro en el espacio de la malla.
const MODELS := ["casual", "business", "woman", "worker", "dress", "casual_w"]
# Tonos de ropa por clima. Se conserva la variedad de piel y pelo de los modelos.
const CLOTHING := ["Suit", "Red_Dark", "Pink", "Worker_Vest", "Red", "Orange"]
const REGIONAL_CLOTHING := [
	[Color("4d7486"), Color("c06443"), Color("bf5a62")],
	[Color("593a57"), Color("8a3d42"), Color("4d6364")],
	[Color("3d7760"), Color("39727d"), Color("b2853e")],
]
const ANIM := "CharacterArmature|"

enum Mode { HIDDEN, WAITING, BOARDING, GETTING_OFF, LEAVING }

@export var wave_distance := 45.0   ## Desde esta distancia hace señas a la mototaxi.
@export var walk_speed := 1.5       ## m/s caminando.
@export var board_time := 1.8       ## Máximo de segundos caminando hacia la mototaxi.
@export var leave_time := 5.0       ## Segundos alejándose antes de desaparecer.

var world: TerrainWorld
var moto: Node3D
var mode := Mode.HIDDEN
var model_index := -1

var _model: Node3D
var _outfit := Color.WHITE
var _portrait: Texture2D
var _custom_head := false
var _anim: AnimationPlayer
var _timer := 0.0
var _walk_dir := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _free_when_hidden := false


func _ready() -> void:
	_rng.randomize()
	visible = false


## Nuevo pasajero de pie en pos (sobre el suelo), con un modelo al azar (o el indicado).
func wait_at(pos: Vector3, index := -1, portrait: Texture2D = null, head_model: Node3D = null) -> void:
	var region := world.get_biome(pos.x, pos.z).max_axis_index() if world else 0
	var palette: Array = REGIONAL_CLOTHING[region]
	var chosen := index if index >= 0 else _rng.randi() % MODELS.size()
	if portrait==null and head_model==null:chosen=region*2+posmod(chosen,2)
	_set_model(PORTRAIT_MODEL if portrait or head_model else chosen, palette[_rng.randi_range(0, palette.size() - 1)], portrait, head_model)
	_place(pos)
	if moto:
		_face(moto.global_position, 1.0)
	mode = Mode.WAITING
	visible = true
	_play("Idle")


## Camina hacia la mototaxi y se sube.
func board() -> void:
	if mode == Mode.HIDDEN:
		return
	mode = Mode.BOARDING
	_timer = board_time
	_play("Walk")


## Baja en pos y se aleja en dirección away. happy: paga contento; si no, reclama.
func get_off(pos: Vector3, away: Vector3, happy: bool) -> void:
	if model_index < 0:
		_set_model(_rng.randi() % MODELS.size())
	_place(pos)
	visible = true
	away.y = 0.0
	_walk_dir = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	if moto:
		_face(moto.global_position, 1.0)
	mode = Mode.GETTING_OFF
	_free_when_hidden = true
	var reaction := "Interact" if happy else "HitRecieve"
	_play(reaction, false)
	_timer = _anim.get_animation(ANIM + reaction).length if _anim else 1.0


func hide_now() -> void:
	mode = Mode.HIDDEN
	visible = false
	if _free_when_hidden:
		queue_free()


func _process(delta: float) -> void:
	match mode:
		Mode.WAITING:
			if moto == null:
				return
			var d := global_position.distance_to(moto.global_position)
			_face(moto.global_position, delta * 4.0)
			_play("Wave" if d < wave_distance else "Idle")
		Mode.BOARDING:
			_timer -= delta
			if moto == null or _timer <= 0.0:
				hide_now()
				return
			var to := moto.global_position - global_position
			to.y = 0.0
			if to.length() < 1.4:
				hide_now()
				return
			_face(moto.global_position, delta * 8.0)
			_step(to.normalized() * walk_speed * 1.3 * delta)
		Mode.GETTING_OFF:
			_timer -= delta
			if _timer <= 0.0:
				mode = Mode.LEAVING
				_timer = leave_time
				_play("Walk")
		Mode.LEAVING:
			_timer -= delta
			_face(global_position + _walk_dir, delta * 6.0)
			_step(_walk_dir * walk_speed * delta)
			if _timer <= 0.0:
				hide_now()


func _set_model(index: int, outfit := Color.WHITE, portrait: Texture2D = null, head_model: Node3D = null) -> void:
	index = clampi(index, 0, MODELS.size() - 1)
	if index == model_index and outfit == _outfit and portrait == _portrait and _model and not _custom_head and head_model == null:
		return
	if _model:
		_model.queue_free()
	model_index = index
	_outfit = outfit
	_portrait = portrait
	if portrait==null and head_model==null:
		var person:=PeruPersonVisual.new()
		person.name="Model"
		add_child(person)
		person.setup(index/2,index%2)
		_model=person
		_anim=null
		_custom_head=false
		return
	var scene: PackedScene = load("res://assets/characters/passenger_%s.glb" % MODELS[index])
	_model = scene.instantiate()
	_model.name = "Model"
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		# Las animaciones importadas no vienen en bucle; las que se repiten se marcan aquí.
		for loop_name in ["Idle", "Wave", "Walk"]:
			if _anim.has_animation(ANIM + loop_name):
				_anim.get_animation(ANIM + loop_name).loop_mode = Animation.LOOP_LINEAR
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in part.get_surface_override_material_count():
			var source := part.get_active_material(surface) as StandardMaterial3D
			if source and source.resource_name == CLOTHING[index] and outfit != Color.WHITE:
				var cloth := source.duplicate() as StandardMaterial3D
				cloth.albedo_color = outfit
				part.set_surface_override_material(surface, cloth)

	_custom_head = false
	if head_model:
		_custom_head = HeadModel.attach(_model, head_model)
		if not _custom_head:
			head_model.free()
	if portrait and not _custom_head:
		_apply_portrait(portrait)


static func load_portrait() -> Texture2D:
	if not FileAccess.file_exists(PORTRAIT_PATH):
		return null
	var photo := Image.new()
	if photo.load(PORTRAIT_PATH) != OK:
		return null
	photo.generate_mipmaps()
	return ImageTexture.create_from_image(photo)


func _apply_portrait(portrait: Texture2D) -> void:
	var head := _model.find_child("Casual2_Head", true, false) as MeshInstance3D
	if head == null or head.mesh == null:
		return
	var original := head.mesh as ArrayMesh
	if original == null:
		return
	var personalized := ArrayMesh.new()
	for surface in original.get_surface_count():
		var source := original.surface_get_material(surface) as StandardMaterial3D
		var part := source.resource_name if source else ""
		if part == "Eye" or part == "Eyebrows":
			continue
		var arrays := original.surface_get_arrays(surface)
		var material: Material = source
		if part == "Skin" or part == "Skin_Darker":
			# UV frontal en reposo. Se conservan índices, huesos y pesos de la cabeza.
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv := PackedVector2Array()
			var mask := PackedColorArray()
			for v in vertices:
				uv.append(Vector2(0.5 + v.x / 0.00205, 0.5 - (v.z - 0.01681) / 0.00247))
				mask.append(Color(1, 1, 1, smoothstep(0.00074, 0.00139, -v.y)))
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_COLOR] = mask
			var projection := ShaderMaterial.new()
			projection.shader = PORTRAIT_SHADER
			projection.set_shader_parameter("portrait", portrait)
			projection.set_shader_parameter("skin_tone", source.albedo_color)
			material = projection
		var flags: int = original.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		personalized.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		personalized.surface_set_material(personalized.get_surface_count() - 1, material)
	head.mesh = personalized


func _play(anim_name: String, blend := true) -> void:
	if _model is PeruPersonVisual:
		_model.play(anim_name)
		return
	if _anim == null or not _anim.has_animation(ANIM + anim_name):
		return
	if _anim.current_animation == ANIM + anim_name:
		return
	_anim.play(ANIM + anim_name, 0.25 if blend else 0.1)


func _place(pos: Vector3) -> void:
	if world:
		pos.y = world.get_height(pos.x, pos.z)
	global_position = pos


func _step(offset: Vector3) -> void:
	_place(global_position + offset)


## Gira hacia target (solo en horizontal). weight 1 = de golpe.
func _face(target: Vector3, weight: float) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	var yaw := atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(weight, 0.0, 1.0))
