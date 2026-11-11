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
var _spawn_clock:=0.0
var _light_clock:=0.0
var _spawn_center:=Vector2.INF
var _spawn_nodes: Array[int]=[]
var _spare_cars: Dictionary={}
var _spare_walkers: Dictionary={}
var recoveries:=0
var night:=false
var _scenes: Array[PackedScene]=[]
const FLEET := ["tico","sedan","coaster","urban_bus"]
const LENGTHS := [3.35,4.5,6.8,9.0]

func setup(w: TerrainWorld,m: Mototaxi) -> void:
	world=w;moto=m;road=w.road_layout;rng.seed=w.world_seed+9876
	for key in FLEET:_scenes.append(load("res://assets/traffic/%s.glb"%key) as PackedScene if ResourceLoader.exists("res://assets/traffic/%s.glb"%key) else null)
	_replenish(360,20)

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

func _replenish(attempt_limit:=12,spawn_limit:=1) -> void:
	if road==null or road.nodes.is_empty():return
	var allow_cars:=bool(GameSettings.get_option("trafico",true))
	var allow_walkers:=bool(GameSettings.get_option("peatones",true))
	if (not allow_cars or cars.size()>=8) and (not allow_walkers or walkers.size()>=12):return
	var observer:=_flat(moto.global_position)
	if observer.distance_squared_to(_spawn_center)>24.0*24.0:
		_spawn_center=observer
		_spawn_nodes.clear()
		for node in range(0,road.nodes.size(),4):
			var d:=_flat(road.nodes[node]).distance_squared_to(observer)
			if d>8.0*8.0 and d<194.0*194.0 and not road.links[node].is_empty():_spawn_nodes.append(node)
	if _spawn_nodes.is_empty():return
	var added:=0
	for attempt in attempt_limit:
		var need_car:=allow_cars and cars.size()<8
		var need_walker:=allow_walkers and walkers.size()<12
		if added>=spawn_limit or not (need_car or need_walker):break
		var is_person:=need_walker and (not need_car or attempt%3==0)
		var a:=_spawn_nodes[rng.randi_range(0,_spawn_nodes.size()-1)]
		var distance:=_flat(road.nodes[a]).distance_squared_to(observer)
		if distance<=32.0*32.0 or distance>=170.0*170.0:continue
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
			var region:=world.get_biome(p.x,p.z).max_axis_index()
			var variant:=rng.randi()%2
			var kind:=region*2+variant
			var spare: Array=_spare_walkers.get(kind,[])
			var person: PeruPersonVisual
			if spare.is_empty():
				person=PeruPersonVisual.new();add_child(person)
				person.setup(region,variant)
			else:
				person=spare.pop_back()
			person.position=p;person.play("Walk")
			person.visible=true;person.process_mode=Node.PROCESS_MODE_INHERIT
			walkers.append({"body":person,"kind":kind,"route":route,"index":1,"step":1,"pause":0.0,"stuck":0.0,"travel":0.0})
		else:
			var kind:=rng.randi()%4
			if _scenes[kind]==null:continue
			if kind>1 and (float(road.roads[int(edge.road)].width)<6.3 or world.get_slope(p.x,p.z)>.20):continue
			var occupied:=false
			for actor in cars:
				if actor.body.position.distance_to(p)<float(LENGTHS[kind])+7:occupied=true
			if occupied:continue
			var spare: Array=_spare_cars.get(kind,[])
			var vehicle: Dictionary=_make_car(kind) if spare.is_empty() else spare.pop_back()
			var body: CharacterBody3D=vehicle.body
			body.position=p;body.rotation=Vector3(0,atan2(target.x-p.x,target.z-p.z),0)
			body.visible=true;body.process_mode=Node.PROCESS_MODE_INHERIT
			vehicle.visual.set_night(night)
			cars.append(vehicle.merged({"from":a,"to":b,"edge":edge,"target":target,"speed":0.0,"stuck":0.0,"travel":0.0,"kind":kind,"length":float(LENGTHS[kind]),"player_blocked":0.0}))
		added+=1

func _make_car(kind: int) -> Dictionary:
	var body:=CharacterBody3D.new()
	body.name="Trafico_%s"%FLEET[kind]
	body.collision_layer=1;body.collision_mask=1
	add_child(body)
	if is_instance_valid(world._body):body.add_collision_exception_with(world._body)
	for child in road.get_children():
		if child is StaticBody3D:body.add_collision_exception_with(child)
	var visual:=PeruTrafficVehicle.new();body.add_child(visual)
	var model:=_scenes[kind].instantiate() as Node3D;visual.add_child(model)
	if kind!=1 and rng.randf()<.60:_paint(model,kind)
	var box:=Passenger.HeadModel.bounds(model)
	visual.configure(kind)
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(box.size.x*.86,maxf(.6,box.size.y-.25),float(LENGTHS[kind])*.90)
	collision.shape=shape;collision.position.y=shape.size.y*.5+.20
	body.add_child(collision)
	return {"body":body,"visual":visual,"half_width":shape.size.x*.5}

func _retire(actor: Dictionary,pedestrian: bool) -> void:
	var pool:=_spare_walkers if pedestrian else _spare_cars
	var kind:=int(actor.kind)
	var spare: Array=pool.get(kind,[])
	if spare.size()>=2:
		actor.body.queue_free()
		return
	actor.body.visible=false
	actor.body.process_mode=Node.PROCESS_MODE_DISABLED
	if pedestrian:
		spare.append(actor.body)
	else:
		actor.visual.horn.stop()
		actor.visual.voice.stop()
		spare.append({"body":actor.body,"visual":actor.visual,"half_width":actor.half_width})
	pool[kind]=spare

func set_night(value: bool) -> void:
	if night==value:return
	night=value
	for actor in cars:actor.visual.set_night(value)
	_sync_headlights()

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
	if _clock>1:
		_clock=0
		for list in [cars,walkers]:
			for i in range(list.size()-1,-1,-1):
				var actor: Dictionary=list[i]
				var distance: float=actor.body.global_position.distance_to(moto.global_position)
				if distance>250 or (float(actor.stuck)>12 and distance>55):
					_retire(actor,actor.body is PeruPersonVisual);list.remove_at(i);recoveries+=1
	_spawn_clock+=delta
	if _spawn_clock>.25:
		_spawn_clock=0
		_replenish()
	for actor: Dictionary in cars:
		actor["age"]=float(actor.get("age",0))+delta
		_move_car(actor,delta)
	for actor: Dictionary in walkers:
		actor["age"]=float(actor.get("age",0))+delta
		_move_walker(actor,delta)
	if night:
		_light_clock+=delta
		if _light_clock>.075:
			_light_clock=0
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
	var bypass := float(actor.get("bypass",0))
	for step in 6:
		var along := _flat(road.nodes[int(actor.to)]-road.nodes[int(actor.from)]).normalized()
		if (offset.length()>=1.35 and absf(bypass)<.05) or (absf(bypass)>=.05 and _flat(offset).dot(along)>=1.35):break
		if not _advance(actor,false):actor.stuck+=delta;return
		offset=actor.target-body.position;offset.y=0
	var tangent := _flat(road.nodes[int(actor.to)]-road.nodes[int(actor.from)]).normalized()
	var side := Vector2(-tangent.y,tangent.x)
	actor["avoid_timer"] = float(actor.get("avoid_timer",0))-delta
	if float(actor.avoid_timer)<=0:
		actor.avoid_timer = rng.randf_range(.14,.23)
		actor["avoid_offset"] = _obstacle_offset(actor,tangent,side)
	bypass = move_toward(bypass,float(actor.get("avoid_offset",0)),delta*1.8)
	actor["bypass"] = bypass
	if absf(bypass)>=.05:
		var lateral := _flat(offset).dot(side)+bypass
		var aim := tangent*4.5+side*lateral
		offset = Vector3(aim.x,0,aim.y)
	var direction:=offset.normalized()
	var speed:=7.5 if int(actor.kind)<2 else 5.6
	if absf(bypass)>=.05:speed=minf(speed,4.2)
	var stopping_room:=float(actor.get("solid_stop_distance",INF))
	if is_finite(stopping_room):
		speed=minf(speed,sqrt(7.0*maxf(0,stopping_room)))
		actor.solid_stop_distance=stopping_room-float(actor.speed)*delta
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

func _obstacle_offset(actor: Dictionary,forward: Vector2,side: Vector2) -> float:
	actor["solid_stop_distance"]=INF
	if not is_instance_valid(world.obstacles) or forward.is_zero_approx():return 0.0
	var body: CharacterBody3D=actor.body
	var base := _flat(actor.target)
	var position := _flat(body.position)
	var solids := world.obstacles.solids_near(body.position,18.0)
	var half_width := float(actor.get("half_width",1.05))
	var front := float(actor.length)*.5
	var blockers: Array[Vector3]=[]
	var blocked:=false
	var first:=INF
	for solid: Array in solids:
		var point:=Vector2(solid[0],solid[1])
		var along:=forward.dot(point-position)
		if along < -front-1.0 or along > 17.0:continue
		var lateral:=side.dot(point-base)
		var clearance:=float(solid[2])+half_width+.25
		blockers.append(Vector3(lateral,along,clearance))
		if absf(lateral)<clearance:
			blocked=true
			first=minf(first,along)
	if not blocked:return 0.0
	var candidates: Array[float]=[]
	for obstacle in blockers:
		candidates.append(obstacle.x-obstacle.z-.08)
		candidates.append(obstacle.x+obstacle.z+.08)
	candidates.sort_custom(func(a: float,b: float) -> bool:return absf(a)<absf(b))
	for candidate in candidates:
		if absf(candidate)>5.0:continue
		var clear:=true
		for obstacle in blockers:
			if absf(obstacle.x-candidate)<obstacle.z:clear=false;break
		if not clear:continue
		for along: float in [maxf(1.5,first),maxf(4.0,first+front)]:
			var center:=position+forward*along+side*(candidate+side.dot(base-position))
			var probe:=Vector3(center.x,body.position.y,center.y)
			if road._asphalt_clearance(probe)>-half_width-.12:clear=false;break
		if not clear:continue
		for other in cars:
			if other==actor:continue
			var other_position:=_flat(other.body.position)
			var ahead:=forward.dot(other_position-position)
			if ahead>-front and ahead<maxf(12.0,first+8) and absf(side.dot(other_position-base)-candidate)<half_width+float(other.get("half_width",1.05))+.35:
				clear=false;break
		var player:=_flat(moto.global_position)
		var player_ahead:=forward.dot(player-position)
		if player_ahead>-front and player_ahead<maxf(12.0,first+6) and absf(side.dot(player-base)-candidate)<half_width+1.0:
			clear=false
		if clear:return candidate
	actor.solid_stop_distance=first-front-1.2
	return float(actor.get("bypass",0))

func _align_chassis(actor: Dictionary,yaw: float,delta: float) -> void:
	var body: CharacterBody3D=actor.body
	var visual: PeruTrafficVehicle=actor.visual
	var rotation:=Basis(Vector3.UP,yaw)
	var contacts: Array[Vector3]=[]
	for wheel in visual.wheels:
		var local: Vector3=wheel.point
		var p:=body.position+rotation*Vector3(local.x,0,local.z)
		# Sample only drivable surfaces. The forward sensor handles obstacles;
		# they must not lift a wheel before the vehicle has passed them.
		p.y=world.get_height(p.x,p.z)
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
