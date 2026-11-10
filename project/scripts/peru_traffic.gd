class_name PeruTraffic
extends Node3D
## Rutas dirigidas, separación entre vehículos y recuperación de recorridos sin salida.
var world: TerrainWorld
var moto: Mototaxi
var road: PeruRoadLayout
var cars: Array[Dictionary]=[]
var walkers: Array[Dictionary]=[]
var rng:=RandomNumberGenerator.new()
var _clock:=0.0
var recoveries:=0
var night:=false
var _scenes: Array[PackedScene]=[]
const FLEET := ["tico","sedan","coaster","urban_bus"]
const LENGTHS := [3.35,4.5,6.8,9.0]

func setup(w: TerrainWorld,m: Mototaxi) -> void:
	world=w;moto=m;road=w.road_layout;rng.seed=w.world_seed+9876
	for key in FLEET:_scenes.append(load("res://assets/traffic/%s.glb"%key) as PackedScene if ResourceLoader.exists("res://assets/traffic/%s.glb"%key) else null)
	_replenish()

func _flat(p: Vector3) -> Vector2:return Vector2(p.x,p.z)

func _point(a: int,b: int,edge: Dictionary,pedestrian:=false) -> Vector3:
	return road.point_on_lane(a,b,int(edge.road),int(edge.direction),0,pedestrian)

func _valid_walk(p: Vector3) -> bool:
	if not world.is_inside(p.x,p.z) or (world.houses!=null and world.houses.is_blocked(p.x,p.z,.45)):return false
	if road.has_walkway(p.x,p.z):return true
	return world.get_slope(p.x,p.z)<.38 and not world.is_water(p.x,p.z)

func _choices(at: int,previous: int,pedestrian: bool) -> Array:
	var options:=[];var reverse:=[]
	for edge: Dictionary in (road.pedestrian_links[at] if pedestrian else road.links[at]):
		if not pedestrian and road.driveable[int(edge.to)]==0:continue
		var point:=_point(at,int(edge.to),edge,pedestrian)
		if pedestrian and not _valid_walk(point):continue
		if not pedestrian:
			var forward: Vector3=(road.nodes[int(edge.to)]-road.nodes[at]).normalized()
			var side:=Vector3(-forward.z,0,forward.x).normalized()
			# Lane shoulders and tight junctions must support a whole axle, not just a centre point.
			var left:=world.get_height(point.x+side.x*1.1,point.z+side.z*1.1)
			var right:=world.get_height(point.x-side.x*1.1,point.z-side.z*1.1)
			if absf(left-right)>.65:continue
		if int(edge.to)==previous:reverse.append(edge)
		else:options.append(edge)
	return options if not options.is_empty() else reverse

func _replenish() -> void:
	if road==null or road.nodes.is_empty():return
	var candidates:=[]
	for node in range(0,road.nodes.size(),4):
		var d:=_flat(road.nodes[node]-moto.global_position).length()
		if d>32 and d<170 and not road.links[node].is_empty():candidates.append(node)
	if candidates.is_empty():return
	for attempt in 360:
		var is_person:=cars.size()>=8 or attempt%3==0
		if is_person and (walkers.size()>=12 or not GameSettings.get_option("peatones",true)):continue
		if not is_person and (cars.size()>=8 or not GameSettings.get_option("trafico",true)):continue
		var a:=int(candidates[rng.randi_range(0,candidates.size()-1)])
		var choices:=_choices(a,-1,is_person)
		if choices.is_empty():continue
		var edge: Dictionary=choices[rng.randi_range(0,choices.size()-1)]
		var b:=int(edge.to)
		var target:=_point(a,b,edge,is_person)
		var p:=target-(road.nodes[b]-road.nodes[a])
		p.y=world.get_height(p.x,p.z)
		if is_person:
			if not _valid_walk(p):continue
			var route:=_walk_route(a,edge)
			if route.size()<4:continue
			var occupied:=false
			for actor in walkers:
				if actor.body.position.distance_to(p)<6:occupied=true
			if occupied:continue
			var person:=PeruPersonVisual.new();add_child(person)
			person.setup(world.get_biome(p.x,p.z).max_axis_index(),rng.randi()%2);person.position=p;person.play("Walk")
			walkers.append({"body":person,"route":route,"index":1,"step":1,"pause":0.0,"stuck":0.0,"travel":0.0})
		else:
			var kind:=rng.randi()%4
			if _scenes[kind]==null:continue
			if kind>1 and (float(road.roads[int(edge.road)].width)<6.3 or world.get_slope(p.x,p.z)>.20):continue
			var occupied:=false
			for actor in cars:
				if actor.body.position.distance_to(p)<float(LENGTHS[kind])+7:occupied=true
			if occupied:continue
			var body:=CharacterBody3D.new();body.name="Trafico_%s"%FLEET[kind];body.collision_layer=1;body.collision_mask=1;add_child(body)
			# Height is solved from four wheel contacts; sliding against the same ground
			# a second time used to push traffic sideways off its lane on steep banks.
			if is_instance_valid(world._body):body.add_collision_exception_with(world._body)
			for child in road.get_children():
				if child is StaticBody3D:body.add_collision_exception_with(child)
			var visual:=PeruTrafficVehicle.new();body.add_child(visual)
			var model:=_scenes[kind].instantiate() as Node3D;visual.add_child(model)
			if kind!=1 and rng.randf()<.60:_paint(model,kind)
			var box:=Passenger.HeadModel.bounds(model);var factor:=1.0
			# Vehicles and wheel radii are authored in metres; mirrors do not set their scale.
			visual.configure(kind);visual.set_night(night)
			var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(box.size.x*factor*.86,maxf(.6,box.size.y*factor-.25),float(LENGTHS[kind])*.90)
			collision.shape=shape;collision.position.y=shape.size.y*.5+.20;body.add_child(collision)
			body.position=p;body.rotation.y=atan2(target.x-p.x,target.z-p.z)
			cars.append({"body":body,"visual":visual,"from":a,"to":b,"edge":edge,"target":target,"speed":0.0,"stuck":0.0,"travel":0.0,"kind":kind,"length":float(LENGTHS[kind]),"player_blocked":0.0})

func set_night(value: bool) -> void:
	night=value
	for actor in cars:actor.visual.set_night(value)

func _paint(model: Node3D,kind: int) -> void:
	var colors:=[Color("b3b1a6"),Color("9c2725"),Color("205167"),Color("38634a"),Color("d8bc59")]
	var color: Color=colors[rng.randi()%colors.size()]
	for node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var original:=mesh.get_active_material(surface) as StandardMaterial3D
			if original==null or not original.resource_name.begins_with("PinturaCarroceria"):continue
			var material:=original.duplicate() as StandardMaterial3D
			material.albedo_color=color
			mesh.set_surface_override_material(surface,material)

func _walk_clear(a: Vector3,b: Vector3) -> bool:
	var steps:=maxi(1,ceili(a.distance_to(b)/.65))
	var previous:=a
	var previous_height:=world.get_height(a.x,a.z)
	for i in range(steps+1):
		var point:=a.lerp(b,float(i)/steps)
		if not _valid_walk(point):return false
		var height:=world.get_height(point.x,point.z)
		if i>0 and absf(height-previous_height)>_flat(point-previous).length()*.38+.035:return false
		previous=point;previous_height=height
	return true

func _walk_route(start: int,initial: Dictionary) -> PackedVector3Array:
	var at:=int(initial.to);var previous:=start
	var end:=_point(start,at,initial,true)
	var begin:=end-(road.nodes[at]-road.nodes[start]);begin.y=world.get_height(begin.x,begin.z)
	var route:=PackedVector3Array()
	if not _walk_clear(begin,end):return route
	route.append(begin);route.append(end)
	for step in 45:
		var candidates:=_choices(at,previous,true)
		var best: Dictionary={};var score:=-INF
		var forward: Vector3=(road.nodes[at]-road.nodes[previous]).normalized()
		for edge: Dictionary in candidates:
			if int(edge.to)==previous:continue
			var point:=_point(at,int(edge.to),edge,true)
			if not _walk_clear(route[route.size()-1],point):continue
			var value: float=forward.dot((road.nodes[int(edge.to)]-road.nodes[at]).normalized())+rng.randf_range(-.1,.1)
			if value>score:best=edge;score=value
		if best.is_empty():break
		route.append(_point(at,int(best.to),best,true));previous=at;at=int(best.to)
	return route

func _advance(actor: Dictionary,pedestrian: bool) -> bool:
	var at:=int(actor.to);var previous:=int(actor.from)
	var options:=_choices(at,previous,pedestrian)
	if options.is_empty():return false
	# Prefer continuing along the current road; change routes at intersections.
	var edge: Dictionary=options[rng.randi_range(0,options.size()-1)]
	var forward: Vector3=(road.nodes[at]-road.nodes[previous]).normalized()
	var best:=-INF
	for choice: Dictionary in options:
		var heading: Vector3=(road.nodes[int(choice.to)]-road.nodes[at]).normalized()
		var score:=heading.dot(forward)+rng.randf_range(-.4,.4)
		if score>best:best=score;edge=choice
	actor.from=at;actor.to=int(edge.to);actor.edge=edge;actor.target=_point(at,int(edge.to),edge,pedestrian)
	return true

func _physics_process(delta: float) -> void:
	if road==null:return
	_clock+=delta
	if _clock>5:
		_clock=0
		for list in [cars,walkers]:
			for i in range(list.size()-1,-1,-1):
				var actor: Dictionary=list[i]
				var distance: float=actor.body.global_position.distance_to(moto.global_position)
				if distance>250 or (float(actor.stuck)>12 and distance>55):
					actor.body.queue_free();list.remove_at(i);recoveries+=1
		_replenish()
	for actor: Dictionary in cars:
		actor["age"]=float(actor.get("age",0))+delta
		_move_car(actor,delta)
	for actor: Dictionary in walkers:
		actor["age"]=float(actor.get("age",0))+delta
		_move_walker(actor,delta)
	_sync_headlights()

func _sync_headlights() -> void:
	var material:=world.generator.material_override as ShaderMaterial
	if material==null:return
	if not night:material.set_shader_parameter("traffic_light_count",0);return
	var origins:=PackedVector4Array();var directions:=PackedVector4Array();origins.resize(16);directions.resize(16)
	var count:=0
	var camera:=get_viewport().get_camera_3d()
	var observer:=camera.global_position if camera else moto.global_position
	for actor in cars:
		if count>=8 or actor.body.global_position.distance_to(observer)>115:continue
		var lamp: SpotLight3D=actor.visual.lamps[0]
		var p:=world.generator.to_local(lamp.global_position)
		var d: Vector3=world.generator.global_basis.inverse()*-lamp.global_basis.z
		origins[count]=Vector4(p.x,p.y,p.z,lamp.spot_range);directions[count]=Vector4(d.x,d.y,d.z,cos(deg_to_rad(lamp.spot_angle)));count+=1
	var parent:=get_parent() as PeruWorldLife
	if parent:
		for lamp in parent._lamps:
			if count>=16:break
			if not lamp.visible or lamp.global_position.distance_to(observer)>65:continue
			var p:=world.generator.to_local(lamp.global_position)
			origins[count]=Vector4(p.x,p.y,p.z,lamp.omni_range);directions[count]=Vector4(0,-1,0,-1);count+=1
	material.set_shader_parameter("traffic_light_origins",origins);material.set_shader_parameter("traffic_light_directions",directions);material.set_shader_parameter("traffic_light_count",count)

func _move_car(actor: Dictionary,delta: float) -> void:
	var body: CharacterBody3D=actor.body
	var offset: Vector3=actor.target-body.position;offset.y=0
	for step in 6:
		if offset.length()>=1.35:break
		if not _advance(actor,false):actor.stuck+=delta;return
		offset=actor.target-body.position;offset.y=0
	var direction:=offset.normalized()
	var speed:=7.5 if int(actor.kind)<2 else 5.6
	var previous_speed:=float(actor.speed)
	# Bumper gap and right-of-way avoid the sensor seeing adjacent-lane traffic as a wall.
	for other in cars:
		if other==actor:continue
		var relative: Vector3=other.body.position-body.position;relative.y=0
		var along:=relative.dot(direction)
		if along>0 and along<(float(actor.length)+float(other.length))*.5+3.5 and absf(relative.cross(direction).y)<1.25:speed=0
	var ray:=PhysicsRayQueryParameters3D.create(body.position+Vector3.UP*.85,body.position+Vector3.UP*.85+direction*(float(actor.length)*.5+3))
	var excludes: Array[RID]=[body.get_rid()]
	if is_instance_valid(world._body):excludes.append(world._body.get_rid())
	if is_instance_valid(world._bridge_body):excludes.append(world._bridge_body.get_rid())
	excludes.append_array(road.ground_bodies);ray.exclude=excludes
	var obstacle:=get_world_3d().direct_space_state.intersect_ray(ray)
	if not obstacle.is_empty():speed=0
	var player_near:=_flat(moto.global_position-body.position).length()<float(actor.length)*.5+4.5
	actor.player_blocked=float(actor.player_blocked)+delta if speed==0 and player_near else 0.0
	if float(actor.player_blocked)>1.5:actor.visual.complain(float(actor.player_blocked)>4,int(actor.get("age",0))+int(actor.kind))
	actor.speed=move_toward(float(actor.speed),speed,delta*3.5)
	var before:=body.position
	body.velocity=direction*float(actor.speed);body.move_and_slide()
	var yaw:=lerp_angle(body.rotation.y,atan2(direction.x,direction.z),minf(1,delta*4))
	_align_chassis(actor,yaw,delta)
	var distance:=before.distance_to(body.position)
	actor.travel+=distance;actor.stuck=float(actor.stuck)+delta if distance<.005 else 0.0
	actor.visual.animate_motion(_flat(body.position-before).length(),wrapf(atan2(direction.x,direction.z)-yaw,-PI,PI),float(actor.speed)<previous_speed-.02,delta)
	if float(actor.stuck)>5 and speed>0:_advance(actor,false)

func _align_chassis(actor: Dictionary,yaw: float,delta: float) -> void:
	var body: CharacterBody3D=actor.body
	var visual: PeruTrafficVehicle=actor.visual
	var a: Vector3=road.nodes[int(actor.from)];var b: Vector3=road.nodes[int(actor.to)]
	var d:=Vector2(b.x-a.x,b.z-a.z)
	var t:=clampf(Vector2(body.position.x-a.x,body.position.z-a.z).dot(d)/maxf(.01,d.length_squared()),0,1)
	var expected:=lerpf(a.y,b.y,t)
	var rotation:=Basis(Vector3.UP,yaw)
	var contacts: Array[Vector3]=[]
	var excludes: Array[RID]=[body.get_rid(),moto.get_rid()]
	for other in cars:
		if other!=actor:excludes.append(other.body.get_rid())
	for wheel in visual.wheels:
		var local: Vector3=wheel.point
		var p:=body.position+rotation*Vector3(local.x,0,local.z)
		var query:=PhysicsRayQueryParameters3D.create(Vector3(p.x,expected+1.8,p.z),Vector3(p.x,expected-5,p.z))
		query.exclude=excludes
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():p.y=world._sample_height(p.x,p.z)
		else:p=hit.position
		contacts.append(p)
	if contacts.size()!=4:return
	var normal: Vector3=((contacts[1]+contacts[3]-contacts[0]-contacts[2])*.5).cross((contacts[2]+contacts[3]-contacts[0]-contacts[1])*.5).normalized()
	if normal.y<0:normal=-normal
	if normal.y<.45:normal=Vector3.UP
	var forward:=Vector3(sin(yaw),0,cos(yaw)).slide(normal).normalized()
	var target:=Basis.looking_at(-forward,normal)
	body.basis=Basis(body.basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(),minf(1,delta*12)))
	var height:=0.0
	for i in contacts.size():
		var point: Vector3=visual.wheels[i].point
		height+=contacts[i].y-(body.basis*Vector3(point.x,0,point.z)).y
	body.position.y=height/contacts.size()
	var error:=0.0
	for i in contacts.size():
		var wheel: Dictionary=visual.wheels[i]
		var center:=visual.to_global(wheel.point)
		var foot:=center-body.basis.y*float(wheel.radius)
		var correction:=clampf((contacts[i]-foot).dot(body.basis.y),-.45,.45)
		wheel.pivot.global_position=center+body.basis.y*correction
		error=maxf(error,absf((wheel.pivot.global_position-body.basis.y*float(wheel.radius)).y-contacts[i].y))
	actor["contact_error"]=error

func _move_walker(actor: Dictionary,delta: float) -> void:
	var body: PeruPersonVisual=actor.body
	if float(actor.pause)>0:
		actor.pause=maxf(0,float(actor.pause)-delta);body.play("Idle");return
	var route: PackedVector3Array=actor.route
	var target:=route[int(actor.index)]
	var offset:=target-body.position;offset.y=0
	if offset.length()<.10:
		var index:=int(actor.index)+int(actor.step)
		if index<0 or index>=route.size():
			actor.step=-int(actor.step);index=int(actor.index)+int(actor.step);actor.pause=.6
		actor.index=index;return
	var next:=body.position+offset.normalized()*minf(offset.length(),delta*1.15)
	next.y=world.get_height(next.x,next.z)
	actor.travel+=body.position.distance_to(next);actor.stuck=0.0
	body.position=next;body.rotation.y=lerp_angle(body.rotation.y,atan2(offset.x,offset.z),minf(1,delta*6));body.play("Walk")
