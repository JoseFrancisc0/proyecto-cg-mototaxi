extends SceneTree
var failures:=0
func check(value: bool,label: String) -> void:
	print("OK " if value else "FAIL ",label)
	if not value:failures+=1
func _initialize() -> void:
	var streets:=PeruRegionalSettlements.town_streets(Vector3(13,20,-7),.035,-.02)
	var connected:=true
	for road: Dictionary in streets:
		var path: PackedVector3Array=road.path
		for end: Vector3 in [path[0],path[-1]]:
			var joined:=false
			for other: Dictionary in streets:
				if other==road:continue
				var points: PackedVector3Array=other.path
				var closest:=Geometry3D.get_closest_point_to_segment(end,points[0],points[-1])
				if closest.distance_to(end)<.0001:joined=true
			connected=connected and joined
	check(connected,"Cada extremo termina en otra calle, sin prolongaciones aisladas")
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.grid_size=64;world.cell_size=1
	var layout:=PeruRoadLayout.new();layout.world=world
	layout._cutout_n=257;layout._cutout_step=.25
	layout._cutout.resize(257*257*2);layout._cutout.fill(-1000)
	# A 12.6 m avenue meets a 6.4 m transverse street. Its asphalt must
	# stay inside the latter's outer edge, even with overlapping capsules.
	for x in range(-20,20,2):
		layout._raster_cutout(Vector3(x,0,0),Vector3(x+2,0,0),6.3,false,3.2+x+20,3.2+20-(x+2))
	var outside:=int((0+32)/.25)*257+int((24+32)/.25)
	var inside:=int((0+32)/.25)*257+int((22+32)/.25)
	check(layout._cutout[outside*2]<0,"La avenida no sobresale del borde de la calle transversal")
	check(layout._cutout[inside*2]>0,"El remate mantiene asfalto continuo dentro del cruce")
	layout.free();world.free()
	print("TOWN_ROAD_ENDINGS_RESULT ",failures)
	quit(failures)
