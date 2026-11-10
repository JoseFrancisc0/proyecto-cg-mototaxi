class_name PeruPersonVisual
extends Node3D
## Personas reconstruidas con su vestimenta completa y animación sobre el esqueleto.
const PEOPLE := ["coast_man","coast_woman","highlands_man","highlands_woman","amazon_man","amazon_woman"]
var skeleton: Skeleton3D
var animation := "Idle"
var phase := 0.0
var _rest := {}
var _body: Node3D
var _base_y:=0.0

func setup(region: int,variant: int) -> void:
	var key: String=PEOPLE[clampi(region,0,2)*2+posmod(variant,2)]
	var packed:=load("res://assets/people/%s.glb"%key) as PackedScene
	if packed==null:return
	_body=packed.instantiate();add_child(_body)
	var bounds:=Passenger.HeadModel.bounds(_body)
	var factor:=1.70/maxf(.01,bounds.size.y)
	_body.scale*=factor
	_body.position-=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	_base_y=_body.position.y
	for node in _body.find_children("*","Skeleton3D",true,false):skeleton=node;break
	if skeleton:
		for i in skeleton.get_bone_count():_rest[i]=skeleton.get_bone_pose_rotation(i)

func play(value: String) -> void:
	animation=value

func _rotate(bone: String,x: float,z:=0.0) -> void:
	var index:=skeleton.find_bone(bone)
	if index>=0:skeleton.set_bone_pose_rotation(index,(_rest[index] as Quaternion)*Quaternion.from_euler(Vector3(x,0,z)))

func _process(delta: float) -> void:
	if skeleton==null:return
	phase+=delta*7.5
	for index: int in _rest:skeleton.set_bone_pose_rotation(index,_rest[index])
	var stride:=sin(phase)*.33 if animation=="Walk" else 0.0
	_rotate("LeftUpLeg",stride);_rotate("RightUpLeg",-stride)
	_rotate("LeftLeg",maxf(0,-sin(phase))*.45 if animation=="Walk" else 0.0)
	_rotate("RightLeg",maxf(0,sin(phase))*.45 if animation=="Walk" else 0.0)
	_rotate("LeftArm",-stride*.65,.10);_rotate("RightArm",stride*.65,-.10)
	if animation=="Wave":
		_rotate("RightArm",-.25,-1.9)
		_rotate("RightForeArm",-.35,sin(phase)*.3)
	_body.position.y=_base_y+(absf(sin(phase))*.018 if animation=="Walk" else sin(phase*.3)*.003)
