class_name PeruHouseAccess
extends RefCounted
## Short, supported flights. Invalid lots are rejected before placing a house.
static func plan(world: TerrainWorld,start: Vector3,entrance: Vector3) -> Dictionary:
	var from:=start
	var horizontal:=Vector3(entrance.x-from.x,0,entrance.z-from.z)
	var run:=horizontal.length()
	if run<.01 or run>9.0:return {}
	var direction:=horizontal/run
	var across:=Vector3(direction.z,0,-direction.x)
	# The existing sidewalk serves the public part of the approach. Build
	# pavers and steps only between its outer edge and the door.
	while run>.20 and not _lot_width_clear(world,from,across):
		var advance:=minf(.15,run-.20)
		from+=direction*advance
		run-=advance
		if advance<.001:break
	from.y=world.get_height(from.x,from.z)+.04
	var rise:=entrance.y-from.y
	if rise<-.18 or rise>3.24:return {}
	if run<=.21 and absf(rise)<=.20:
		return {"blocks":[],"route":[],"steps":0,"landings":0,"rise":rise,"run":run,"riser":0.0,"entrance":entrance}
	# The model already supplies a threshold. The approach can meet it
	# one shallow riser below the door without needing a separate landing.
	var stair_rise:=maxf(0,rise-.12)
	var steps:=ceili(stair_rise/.18)
	var landings:=maxi(0,(steps-1)/12)
	var required:=steps*.29+landings*.90
	if run<required:return {}
	var lead:=run-required if steps else run
	var cursor:=lead
	var levels: Array[Vector3]=[]
	for i in steps:
		if i>0 and i%12==0:
			levels.append(Vector3(cursor,cursor+.90,from.y+stair_rise*i/steps));cursor+=.90
		levels.append(Vector3(cursor,cursor+.29,from.y+stair_rise*(i+1)/steps));cursor+=.29
	var blocks: Array[Transform3D]=[]
	var route: Array[Vector3]=[]
	var yaw:=atan2(direction.x,direction.z)
	for level in levels:
		var span:=level.y-level.x
		if span<.005:continue
		var lo:=INF
		var checks:=maxi(1,ceili(span/.30))
		for i in range(checks+1):
			var p:=from+direction*lerpf(level.x,level.y,float(i)/checks)
			if not _lot_width_clear(world,p,across):return {}
			for side: float in [-.62,.62]:
				var q:=p+across*side
				if world.is_water(q.x,q.z):return {}
				var ground:=world.get_height(q.x,q.z)
				if ground>level.z+.12 or level.z-ground>.85:return {}
				lo=minf(lo,ground-.10)
		var height:=maxf(.10,level.z-lo)
		var center:=from+direction*(level.x+level.y)*.5;center.y=level.z-height*.5
		var basis:=Basis(Vector3.UP,yaw)*Basis.from_scale(Vector3(1.2,height,span+.005))
		blocks.append(Transform3D(basis,center))
		route.append(Vector3(center.x,level.z,center.z))
	return {"blocks":blocks,"route":route,"steps":steps,"landings":landings,"rise":rise,"run":run,"riser":stair_rise/steps if steps else 0.0,"entrance":entrance}

static func _lot_width_clear(world: TerrainWorld,p: Vector3,across: Vector3) -> bool:
	if world.road_layout==null:return true
	for lateral: float in [-.62,0,.62]:
		var q:=p+across*lateral
		q.y=world.get_height(q.x,q.z)
		if world.road_layout.has_walkway(q.x,q.z) or world.road_layout._asphalt_clearance(q)<.06:
			return false
	return true
