class_name PeruWallPaint
extends RefCounted
## Brush strokes lie directly on plaster. No rectangular billboard or white backing.
const LETTERS={
"A":[[Vector2(0,0),Vector2(.4,1),Vector2(.8,0)],[Vector2(.17,.4),Vector2(.65,.4)]],
"B":[[Vector2(0,0),Vector2(.1,1),Vector2(.55,1),Vector2(.75,.8),Vector2(.45,.52),Vector2(.75,.3),Vector2(.55,.03),Vector2(0,0)]],
"C":[[Vector2(.75,.85),Vector2(.35,1),Vector2(.04,.7),Vector2(.05,.25),Vector2(.35,0),Vector2(.8,.15)]],
"I":[[Vector2(.2,0),Vector2(.38,1)]],
"L":[[Vector2(.1,1),Vector2(0,.05),Vector2(.7,0)]],
"M":[[Vector2(0,0),Vector2(.1,1),Vector2(.45,.3),Vector2(.72,1),Vector2(.85,0)]],
"O":[[Vector2(.4,0),Vector2(.02,.2),Vector2(0,.7),Vector2(.3,1),Vector2(.7,.85),Vector2(.85,.4),Vector2(.65,0),Vector2(.4,0)]],
"R":[[Vector2(0,0),Vector2(.06,1),Vector2(.55,.95),Vector2(.75,.70),Vector2(.08,.50),Vector2(.85,0)]],
"S":[[Vector2(.85,.85),Vector2(.4,1),Vector2(.05,.65),Vector2(.7,.4),Vector2(.7,.05),Vector2(0,0)]],
"U":[[Vector2(.05,1),Vector2(0,.25),Vector2(.3,0),Vector2(.6,.15),Vector2(.8,1)]]}

static func _stroke(st: SurfaceTool,a: Vector2,b: Vector2,width: float,color: Color,depth: float) -> void:
	if a.distance_squared_to(b)<.000001:return
	var side:=(b-a).orthogonal().normalized()*width
	for p: Vector2 in [a-side,b-side,b+side,a-side,b+side,a+side]:
		st.set_color(color);st.set_normal(Vector3.FORWARD);st.add_vertex(Vector3(p.x,p.y,depth))

static func add(parent: Node3D,p: Vector3,size: Vector2,seed_value: int) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var words: Array=["SUR","LIMA","CALLAO","BARRIO"]
	for layer in 3:
		var word: String=words[rng.randi()%words.size()]
		var unit:=size.x/(word.length()+.5)
		var origin:=Vector2(-size.x*.46,-size.y*.36+layer*size.y*.23)
		var colors: Array[Color]=[Color("343432"),Color("9c493b"),Color("37606a"),Color("496750")]
		var color: Color=colors[(layer+seed_value)%colors.size()];color.a=.62+layer*.10
		for letter_index in word.length():
			var paths: Array=LETTERS.get(word[letter_index],[])
			for path: Array in paths:
				for i in range(1,path.size()):
					var a: Vector2=path[i-1];var b: Vector2=path[i]
					a=origin+Vector2((a.x+letter_index+a.y*.18)*unit,a.y*size.y*.47)
					b=origin+Vector2((b.x+letter_index+b.y*.18)*unit,b.y*size.y*.47)
					_stroke(st,a,b,rng.randf_range(.009,.022),color,.004+layer*.002)
			if rng.randf()<.35:
				var a:=origin+Vector2((letter_index+.35)*unit,size.y*.22)
				_stroke(st,a,a-Vector2(0,rng.randf_range(.12,.32)),.004,color,.012)
	var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=1
	var node:=MeshInstance3D.new();node.name="PintadasSobreMuro";node.mesh=st.commit();node.material_override=material;node.position=p;node.visibility_range_end=90;parent.add_child(node)
