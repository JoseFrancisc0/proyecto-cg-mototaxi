class_name DriverAvatar
extends Node3D
## Avatar completo: conserva rostro y ropa del GLB; el retrato nunca se proyecta al pasajero.
const FOLDER := "user://driver_avatar/"
const MODEL_PATH := FOLDER + "driver.glb"
const PHOTO_PATH := FOLDER + "reference.png"
const STATUS_PATH := FOLDER + "status.json"
const DEFAULT_PATH := "res://assets/driver/driver.glb"
const MAX_MODEL_BYTES := 48*1024*1024
const SEATS := [Vector3(0,.62,.23),Vector3(0,.57,.16),Vector3(0,.59,.22),Vector3(0,.59,.10),Vector3(0,.60,.12),Vector3(0,.60,.15)]
const GRIPS := [Vector3(.25,.87,.61),Vector3(.21,.86,.58),Vector3(.22,.90,.59),Vector3(.21,.88,.59),Vector3(.22,.89,.59),Vector3(.21,.86,.61)]
const RIDING_LEAN := [.14,.18,.13,.29,.27,.26]
var model: Node3D
var skeleton: Skeleton3D
var model_height := 1.75
var seat := Vector3.ZERO
var _neck_bone := -1
var _vehicle_index := 0

static func load_avatar(model_path := "") -> Node3D:
	var file_path := model_path
	if file_path.is_empty():
		file_path = MODEL_PATH if FileAccess.file_exists(MODEL_PATH) else DEFAULT_PATH
		if file_path==MODEL_PATH and _is_retired_avatar(file_path):file_path=DEFAULT_PATH
	if not FileAccess.file_exists(file_path): return null
	if file_path.begins_with("res://"):
		var packed := load(file_path) as PackedScene
		return packed.instantiate() as Node3D if packed else null
	var f := FileAccess.open(file_path,FileAccess.READ)
	if f == null or f.get_length()<20 or f.get_length()>MAX_MODEL_BYTES: return null
	if f.get_32()!=0x46546c67: return null
	f.seek(0)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(f.get_buffer(f.get_length()),"",state)!=OK: return null
	return document.generate_scene(state) as Node3D

static func _is_retired_avatar(path: String) -> bool:
	# Keep the old file, but retire only the exact mannequin format produced by this project.
	var stream:=FileAccess.open(path,FileAccess.READ)
	if stream==null or stream.get_length()<24:return false
	if stream.get_32()!=0x46546c67:return false
	stream.seek(12)
	var length:=stream.get_32()
	if stream.get_32()!=0x4e4f534a or length>2*1024*1024:return false
	var metadata:=stream.get_buffer(length).get_string_from_utf8()
	return metadata.contains("Chaqueta y camiseta") and metadata.contains("Rostro de la fotograf")

func setup(vehicle_index: int, source: Node3D = null, seated := true) -> bool:
	_vehicle_index=clampi(vehicle_index,0,5)
	model = source if source else load_avatar()
	if model == null: return false
	add_child(model)
	if model is PeruPersonVisual:model.set_process(false)
	for visual in model.find_children("*","PeruPersonVisual",true,false):visual.set_process(false)
	var bounds := Passenger.HeadModel.bounds(model)
	if not bounds.has_volume():
		model.queue_free()
		return false
	var factor := model_height/bounds.size.y
	model.scale *= factor
	model.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	skeleton = model.find_child("*",true,false) as Skeleton3D
	for child in model.find_children("*","Skeleton3D",true,false):
		skeleton = child
		break
	for player in model.find_children("*","AnimationPlayer",true,false):
		player.stop()
		player.active=false
	seat = SEATS[clampi(vehicle_index,0,5)] * VehicleCatalog.MODEL_SCALE
	if seated and skeleton:
		if _bone(["Hips","Pelvis","rootpelvis"])<0:
			model.visible=false
			return false
		_seat_pose()
	elif seated:
		# Un modelo sin articulaciones se deja en la vista previa, nunca de pie dentro de la moto.
		model.visible = false
		return false
	return true

func _bone(aliases: Array) -> int:
	if skeleton == null: return -1
	for i in skeleton.get_bone_count():
		var key := String(skeleton.get_bone_name(i)).to_lower().replace("mixamorig:","").replace("_","").replace(".","")
		for alias: String in aliases:
			if key == alias.to_lower().replace("_","").replace(".",""): return i
	return -1

func _aim(parent_bone: int, child_bone: int, direction: Vector3) -> void:
	if parent_bone<0 or child_bone<0: return
	var pose := skeleton.get_bone_global_pose(parent_bone)
	var child_pose := skeleton.get_bone_global_pose(child_bone)
	var from := child_pose.origin-pose.origin
	if from.length()<.000001: return
	var local_direction := skeleton.global_basis.inverse()*global_basis*direction
	pose.basis = Basis(Quaternion(from.normalized(),local_direction.normalized()))*pose.basis
	skeleton.set_bone_global_pose(parent_bone,pose)

func _seat_pose() -> void:
	var hips := _bone(["Hips","Pelvis","rootpelvis"])
	if hips>=0:
		var hip_position := global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(hips).origin
		model.position += seat-hip_position
	var spine:=_bone(["Spine","Abdomen"])
	if spine>=0:
		_tilt(spine,RIDING_LEAN[_vehicle_index])
		_tilt(_bone(["Neck"]),-RIDING_LEAN[_vehicle_index])
	for side in ["Left","Right"]:
		var short := "L" if side=="Left" else "R"
		var thigh := _bone([side+"UpLeg",side+"Thigh","thigh"+short,"upperleg"+short])
		var knee := _bone([side+"Leg",side+"Calf","calf"+short,"lowerleg"+short])
		var foot := _bone([side+"Foot","foot"+short])
		_aim(thigh,knee,Vector3(0,-.12,1))
		_aim(knee,foot,Vector3(0,-1,.12))
		var upper := _bone([side+"Arm",side+"UpperArm","upperarm"+short])
		var elbow := _bone([side+"ForeArm",side+"LowerArm","forearm"+short,"lowerarm"+short])
		var hand := _bone([side+"Hand","hand"+short,"wrist"+short])
		_fit_arm(upper,elbow,hand,1.0 if side=="Left" else -1.0)
	_neck_bone = _bone(["Head","head"])

func _tilt(index: int,angle: float) -> void:
	if index<0:return
	var pose:=skeleton.get_bone_global_pose(index)
	var axis:=skeleton.global_basis.inverse()*global_basis*Vector3.RIGHT
	pose.basis=Basis(axis.normalized(),angle)*pose.basis
	skeleton.set_bone_global_pose(index,pose)

func _joint_position(index: int) -> Vector3:
	return global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(index).origin

func _fit_arm(upper: int,elbow: int,hand: int,side: float) -> void:
	if mini(upper,mini(elbow,hand))<0: return
	var shoulder := _joint_position(upper)
	var a := shoulder.distance_to(_joint_position(elbow))
	var b := _joint_position(elbow).distance_to(_joint_position(hand))
	var target: Vector3=GRIPS[_vehicle_index]*VehicleCatalog.MODEL_SCALE
	target.x*=side
	var axis := (target-shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target),absf(a-b)+.001,a+b-.001)
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var bend := Vector3(side*.5,-1,-.1)
	bend=(bend-axis*bend.dot(axis)).normalized()
	var elbow_target := shoulder+axis*along+bend*sqrt(maxf(0,a*a-along*along))
	_aim(upper,elbow,elbow_target-shoulder)
	_aim(elbow,hand,shoulder+axis*distance-_joint_position(elbow))

func follow_vehicle(steer: float) -> void:
	rotation.z = -steer*.025

static func generation_status() -> Dictionary:
	if not FileAccess.file_exists(STATUS_PATH): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(STATUS_PATH))
	return data if data is Dictionary else {}
