class_name PeruTrafficVehicle
extends Node3D
var wheels: Array[Dictionary]=[]
var lamps: Array[Light3D]=[]
var lenses: Array[MeshInstance3D]=[]
var horn: AudioStreamPlayer3D
var voice: AudioStreamPlayer3D
var message: Label3D
var kind:=0
var night:=false
var _complaint_cool:=0.0
var _message_time:=0.0

func configure(index: int) -> void:
	kind=index
	for tag in ["FL","FR","RL","RR"]:
		var pivot:=find_child("Wheel"+tag,true,false) as Node3D
		if pivot:
			var spin:=pivot.find_child("*Spin",true,false) as Node3D
			var radius:=float(pivot.get_meta("wheel_radius",pivot.get_meta("extras",{}).get("wheel_radius",.28)))
			wheels.append({"pivot":pivot,"spin":spin,"radius":radius,"front":tag.begins_with("F"),"point":to_local(pivot.global_position)})
	var length: float=PeruTraffic.LENGTHS[kind]
	var width: float=[1.45,1.70,2.05,2.48][kind]
	var height: float=[1.55,1.48,2.65,3.1][kind]
	for side in [-1,1]:
		var head:=SpotLight3D.new();head.position=Vector3(side*width*.34,height*.38,length*.49);head.rotation.y=PI
		head.light_color=Color("ffecc5");head.light_energy=2.6;head.spot_range=35;head.spot_angle=36;head.spot_attenuation=1.2;head.shadow_enabled=false
		add_child(head);lamps.append(head)
		var tail:=OmniLight3D.new();tail.position=Vector3(side*width*.37,height*.31,-length*.48);tail.light_color=Color("ff2414");tail.omni_range=2;tail.light_energy=.45
		add_child(tail);lamps.append(tail)
		for rear in [false,true]:
			var lens:=MeshInstance3D.new();var shape:=SphereMesh.new();shape.radius=width*.045;shape.height=shape.radius*2;shape.radial_segments=12;shape.rings=6;lens.mesh=shape
			lens.position=Vector3(side*width*.34,height*(.31 if rear else .38),length*(-.51 if rear else .51));lens.scale=Vector3(1,.7,.3)
			var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("ff3020") if rear else Color("fff1c9");material.emission_enabled=true;material.emission=material.albedo_color;material.emission_energy_multiplier=1.5;lens.material_override=material;add_child(lens);lenses.append(lens)
	horn=AudioStreamPlayer3D.new();horn.stream=load("res://audio/world/horn.wav");horn.volume_db=-4 if kind<2 else 0;horn.pitch_scale=.9 if kind<2 else .62;horn.max_distance=65;add_child(horn)
	voice=AudioStreamPlayer3D.new();voice.volume_db=-10;voice.max_distance=38;add_child(voice)
	message=Label3D.new();message.position=Vector3(0,height+.5,0);message.billboard=BaseMaterial3D.BILLBOARD_ENABLED;message.font_size=42;message.pixel_size=.008;message.outline_size=7;message.visible=false;add_child(message)
	var route_anchor:=find_child("RouteAnchor",true,false) as Node3D
	if route_anchor:
		var route:=Label3D.new();route.text="CENTRO · TERMINAL" if kind==3 else "CENTRO · MERCADO";route.position=to_local(route_anchor.global_position)+Vector3(0,0,.025);route.font_size=52;route.pixel_size=.0019;route.modulate=Color("1b2022");route.outline_size=0;route.visibility_range_end=60;add_child(route)
	set_night(false)

func set_night(value: bool) -> void:
	night=value
	for light in lamps:light.visible=value
	for lens in lenses:lens.visible=value

func animate_motion(distance: float,steer: float,braking: bool,delta: float) -> void:
	_complaint_cool=maxf(0,_complaint_cool-delta);_message_time=maxf(0,_message_time-delta)
	message.visible=_message_time>0
	for wheel in wheels:
		if wheel.spin:wheel.spin.rotation.x+=distance/maxf(.01,float(wheel.radius))
		if wheel.front:wheel.pivot.rotation.y=lerp_angle(wheel.pivot.rotation.y,clampf(steer,-.42,.42),minf(1,delta*8))
	for i in lamps.size():
		if i%2==1:lamps[i].visible=night or braking;lamps[i].light_energy=1.0 if braking else .45
	for i in lenses.size():lenses[i].visible=night or (i%2==1 and braking)

func complain(angry: bool,variant: int) -> void:
	if _complaint_cool>0:return
	_complaint_cool=5.5;horn.play()
	if angry:
		var lines:=["¡Avanza, pe!","¡Deja pasar!","¡Muévete, carajo!","¡No te quedes ahí!"]
		var choice:=posmod(variant,lines.size());message.text=lines[choice];_message_time=2.8
		var path:="res://audio/traffic/driver_%d.wav"%choice
		if ResourceLoader.exists(path):voice.stream=load(path);voice.play()
