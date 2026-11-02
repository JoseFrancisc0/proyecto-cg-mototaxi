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

const MODELS := ["casual", "business", "woman", "worker", "dress", "casual_w"]
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
var _anim: AnimationPlayer
var _timer := 0.0
var _walk_dir := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _free_when_hidden := false


func _ready() -> void:
	_rng.randomize()
	visible = false


## Nuevo pasajero de pie en pos (sobre el suelo), con un modelo al azar (o el indicado).
func wait_at(pos: Vector3, index := -1) -> void:
	_set_model(index if index >= 0 else _rng.randi() % MODELS.size())
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


func _set_model(index: int) -> void:
	index = clampi(index, 0, MODELS.size() - 1)
	if index == model_index and _model:
		return
	if _model:
		_model.queue_free()
	model_index = index
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
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _play(anim_name: String, blend := true) -> void:
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
