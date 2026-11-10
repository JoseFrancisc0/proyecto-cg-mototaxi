class_name PeruWorldLife
extends Node3D
## Ambientación local, sin escribir alturas ni modificar el generador de terreno.
var traffic: PeruTraffic
var world: TerrainWorld
var moto: Mototaxi
var session: GameSession
var _rng := RandomNumberGenerator.new()
var _cars: Array[Dictionary] = []
var _walkers: Array[Dictionary] = []
var _lamps: Array[OmniLight3D] = []
var _time := 0.0
var _clock := 0.0
var _horn_cool := 0.0
var _horn: AudioStreamPlayer3D
var shops := 0
var hillside_houses := 0
var _materials := {}

func setup(w: TerrainWorld, m: Mototaxi, s: GameSession) -> void:
	world=w
	moto=m
	session=s
	_rng.seed=hash("vida-%d"%world.world_seed)
	_build_neighborhood_details()
	var neighborhood:=PeruNeighborhoodDetails.new();add_child(neighborhood);neighborhood.build(world)
	traffic=PeruTraffic.new()
	add_child(traffic)
	traffic.setup(world,moto)
	_cars=traffic.cars
	_walkers=traffic.walkers
	_horn=AudioStreamPlayer3D.new()
	_horn.stream=load("res://audio/world/horn.wav")
	_horn.volume_db=-12
	_horn.max_distance=70
	add_child(_horn)

func _build_neighborhood_details() -> void:
	if not GameSettings.get_option("barrios",true):return
	var signs:=["BODEGA MARISOL","MENÚ DEL DÍA","FERRETERÍA EL SOL","TALLER DE MOTOS","PANADERÍA SAN JOSÉ"]
	if world.houses:
		for house: Dictionary in world.houses.houses:
			if str(house.zone)!="pueblo" or _rng.randf()>.18:continue
			var xf:=Transform3D(Basis(Vector3.UP,float(house.yaw)),house.position)
			var sign:=Node3D.new();add_child(sign);sign.transform=xf
			var size: Vector3=house.size
			_box(sign,Vector3(minf(4.5,size.x*.8),.48,.07),Vector3(0,2.52,size.z*.5+.06),Color("742f26"))
			_text(sign,signs[shops%signs.size()],Vector3(0,2.52,size.z*.5+.11),Color("fff0ca"),.0035)
			shops+=1
	for road: Dictionary in world.get_roads():
		if int(road.kind)<2:continue
		var path: PackedVector3Array=road.path
		var spacing:=60.0
		for i in range(1,path.size()):
			spacing+=path[i].distance_to(path[i-1])
			if spacing<55 or _lamps.size()>=180:continue
			spacing=0
			var side:=(path[i]-path[i-1]).cross(Vector3.UP).normalized()
			var p:=path[i]+side*(float(road.width)*.5+.65)
			if world.road_layout._crossing(p,int(road.id)):continue
			if world.is_water(p.x,p.z) or (world.houses and world.houses.is_blocked(p.x,p.z,.25)):continue
			p.y=world.get_height(p.x,p.z)
			var pole:=Node3D.new();add_child(pole);pole.position=p
			_lamp(pole,Vector3.ZERO)

func _material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if _materials.has(key): return _materials[key]
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.82
	_materials[key]=mat
	return mat

func _box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var shape:=BoxMesh.new()
	shape.size=size
	mesh.mesh=shape
	mesh.material_override=_material(color)
	mesh.position=position
	mesh.visibility_range_end=180
	parent.add_child(mesh)
	return mesh

func _text(parent: Node3D, text: String, position: Vector3, color:=Color.WHITE, pixels:=.007) -> void:
	var label:=Label3D.new()
	label.text=text
	label.position=position
	label.font_size=48
	label.pixel_size=pixels
	label.modulate=color
	label.outline_size=5
	label.visibility_range_begin=1.5
	label.visibility_range_end=90
	parent.add_child(label)

func _lamp(parent: Node3D, offset: Vector3) -> void:
	_box(parent,Vector3(.10,4,.10),offset+Vector3.UP*2,Color("555b60"))
	_box(parent,Vector3(.55,.12,.45),offset+Vector3.UP*4,Color("fff0ba"))
	var lamp:=OmniLight3D.new()
	lamp.position=offset+Vector3.UP*3.8
	lamp.light_color=Color("ffd797")
	lamp.omni_range=12
	lamp.light_energy=1.1
	lamp.shadow_enabled=false
	parent.add_child(lamp)
	_lamps.append(lamp)

func _physics_process(delta: float) -> void:
	if world==null: return
	_horn_cool=maxf(0,_horn_cool-delta)
	if Input.is_physical_key_pressed(KEY_H) and _horn_cool<=0:
		_horn_cool=.8
		_horn.global_position=moto.global_position
		_horn.play()
func _process(delta: float) -> void:
	if world==null: return
	_time+=delta
	_clock+=delta
	if _clock<1.0 or not bool(GameSettings.get_option("dia_noche",true)): return
	_clock=0
	var hour:=fmod(7+_time/25,24) if session.free_mode else session.get_clock_minutes()/60
	var angle:=(hour-6)/12*PI
	var daylight:=clampf(sin(angle),0,1)
	traffic.set_night(daylight<.28)
	var direction:=Vector3(cos(angle)*.7,maxf(-.15,sin(angle)),.4).normalized()
	var sun:=get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.global_basis=Basis.looking_at(-direction,Vector3.UP)
		sun.light_energy=lerpf(.09,1.10,daylight)
		sun.light_color=Color("ffc799").lerp(Color("fff5e7"),daylight)
	var mat:=world.generator.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("sun_direction",direction)
		mat.set_shader_parameter("sun_intensity",lerpf(.05,2.0,daylight))
		mat.set_shader_parameter("ambient_intensity",lerpf(.18,.55,daylight))
		mat.set_shader_parameter("sky_color",Color("111d38").lerp(Color("87a8c9"),daylight))
		mat.set_shader_parameter("fog_color",Color("111a2c").lerp(Color("d0c3ae"),daylight))
		TerrainVegetation.sync_lighting(mat,direction)
	var environment:=get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment and environment.environment:
		environment.environment.ambient_light_energy=lerpf(.28,.50,daylight)
		var sky: ProceduralSkyMaterial=environment.environment.sky.sky_material as ProceduralSkyMaterial if environment.environment.sky else null
		if sky:
			sky.sky_top_color=Color("0b142a").lerp(Color("668fb9"),daylight)
			sky.sky_horizon_color=Color("1a233d").lerp(Color("d8bd97"),daylight)
	for lamp in _lamps: lamp.visible=daylight<.3 and lamp.global_position.distance_to(moto.global_position)<65
