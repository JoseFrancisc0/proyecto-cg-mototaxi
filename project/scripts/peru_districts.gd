class_name PeruDistricts
extends RefCounted
## Barrios coherentes por sectores: la zona depende del lugar, no de cada casa al azar.
static func at(world: TerrainWorld,p: Vector3) -> Dictionary:
	var region:=world.get_biome(p.x,p.z).max_axis_index()
	var distance:=INF
	var nearest:=Vector3.ZERO
	for town in world.get_town_centers():
		var d:=Vector2(p.x-town.x,p.z-town.z).length()
		if d<distance:distance=d;nearest=town
	var sector:=posmod(int(floor((atan2(p.z-nearest.z,p.x-nearest.x)+PI)/TAU*4))+world.world_seed,4)
	var zone: String
	var patch_distance:=INF;var patch_zone:=""
	for patch: Dictionary in world._district_patches:
		if int(patch.region)!=region:continue
		var d:=Vector2(p.x-patch.center.x,p.z-patch.center.z).length()
		if d<float(patch.radius) and d<patch_distance:patch_distance=d;patch_zone=patch.zone
	if not patch_zone.is_empty():zone=patch_zone
	elif region==0 and world.get_slope(p.x,p.z)>.14 and distance<650:zone="ladera"
	elif region==1 and world.get_slope(p.x,p.z)>.22 and distance<500:zone="ladera"
	elif distance>320:zone="rural"
	elif region==0:
		zone=["popular","tradicional","residencial","moderna"][sector]
	elif region==1:zone=["popular","tradicional","residencial","moderna"][sector]
	else:
		zone=["popular","tradicional","residencial","moderna"][sector]
		if world.get_drainage(p.x,p.z)>20000 and sector==0:zone="ribereno"
	return {"region":region,"zone":zone,"dense":zone in ["popular","tradicional","ladera"],"green":.05 if zone in ["popular","ladera"] else .90 if zone in ["moderna","residencial"] else .35,"litter":zone in ["popular","ladera"]}
