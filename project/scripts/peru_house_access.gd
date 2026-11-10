class_name PeruHouseAccess
extends RefCounted
## Short, supported flights. Invalid lots are rejected before placing a house.
static func plan(world: TerrainWorld,start: Vector3,entrance: Vector3) -> Dictionary:
	var from:=start;from.y=world.get_height(from.x,from.z)+.04
	var horizontal:=Vector3(entrance.x-from.x,0,entrance.z-from.z)
	var run:=horizontal.length();var rise:=entrance.y-from.y
	if run<.20 or run>9.0 or rise<-.18 or rise>3.24:return {}
	var steps:=ceili(maxf(0,rise)/.18) if rise>.10 else 0
	var landings:=maxi(0,(steps-1)/12)
	var required:=steps*.29+landings*.90+.50 if steps else 0.0
	if run<required:return {}
	var direction:=horizontal/run;var cursor:=0.0;var levels: Array[Vector3]=[]
	var lead:=run-required if steps else run
	if lead>.01:levels.append(Vector3(0,lead,from.y));cursor=lead
	for i in steps:
		if i>0 and i%12==0:
			levels.append(Vector3(cursor,cursor+.90,from.y+rise*i/steps));cursor+=.90
		levels.append(Vector3(cursor,cursor+.29,from.y+rise*(i+1)/steps));cursor+=.29
	if steps:levels.append(Vector3(cursor,run,entrance.y))
	var blocks: Array[Transform3D]=[]
	var route: Array[Vector3]=[]
	var yaw:=atan2(direction.x,direction.z)
	for level in levels:
		var span:=level.y-level.x
		if span<.005:continue
		var lo:=INF
		for t: float in [0.0,.5,1.0]:
			var p:=from+direction*lerpf(level.x,level.y,t)
			for side: float in [-.62,.62]:
				var q:=p+Vector3(direction.z,0,-direction.x)*side
				if world.is_water(q.x,q.z):return {}
				var ground:=world.get_height(q.x,q.z)
				if ground>level.z+.12 or level.z-ground>.85:return {}
				lo=minf(lo,ground-.10)
		var height:=maxf(.10,level.z-lo)
		var center:=from+direction*(level.x+level.y)*.5;center.y=level.z-height*.5
		blocks.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(1.2,height,span+.005)),center))
		route.append(Vector3(center.x,level.z,center.z))
	return {"blocks":blocks,"route":route,"steps":steps,"landings":landings,"rise":rise,"run":run,"riser":rise/steps if steps else 0.0,"entrance":entrance}
