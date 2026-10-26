@tool
class_name VegetationAssets
extends RefCounted
## Modelos 3D PROVISIONALES de la vegetacion (S14), hechos con codigo (low poly).
##
## Son placeholders: sirven para ver la distribucion por region, pendiente, altura y
## rios. Para cambiarlos por modelos reales basta poner un Mesh en "mesh_overrides" de
## TerrainVegetation (o en VEGETATION_OVERRIDES de abajo) con el mismo nombre de especie.
## Cada modelo mide lo que mediria la planta real a escala 1 (metros), con la base en y = 0.
##
## Especies (inspiradas en la flora del Peru):
##   costa : huarango (Prosopis pallida, arbol del desierto junto a los rios), cactus columnar
##   sierra: ichu (pasto de puna), queñua (Polylepis, bosques de altura), eucalipto (plantado)
##   selva : arbol de dosel (tipo lupuna), palmera aguaje (zonas humedas), arbusto

## Cambia un placeholder por un modelo real: {"huarango": preload("res://models/huarango.mesh")}.
const VEGETATION_OVERRIDES := {}

static var _cache := {}


## Mesh de la especie (se arma una sola vez y se reutiliza).
static func get_mesh(species: String) -> Mesh:
	if VEGETATION_OVERRIDES.has(species):
		return VEGETATION_OVERRIDES[species]
	if _cache.has(species):
		return _cache[species]
	var b := _Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(species)
	match species:
		"huarango":
			_huarango(b, rng)
		"cactus":
			_cactus(b, rng)
		"ichu":
			_ichu(b, rng)
		"quenua":
			_quenua(b, rng)
		"eucalipto":
			_eucalipto(b, rng)
		"arbol_selva":
			_arbol_selva(b, rng)
		"palmera":
			_palmera(b, rng)
		"arbusto":
			_arbusto(b, rng)
		_:
			_arbusto(b, rng)
	var mesh := b.commit()
	_cache[species] = mesh
	return mesh


static func species_names() -> PackedStringArray:
	return PackedStringArray(["huarango", "cactus", "ichu", "quenua", "eucalipto", "arbol_selva", "palmera", "arbusto"])


# ---------------------------------------------------------------------------
# Especies
# ---------------------------------------------------------------------------

static func _huarango(b: _Builder, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.36, 0.27, 0.19)
	var leaf := Color(0.34, 0.41, 0.19)
	var top := Vector3(0.35, 2.1, 0.1)
	b.tube(Vector3.ZERO, top, 0.24, 0.15, 7, bark)
	# Ramas que se abren hacia los lados: la copa del huarango es ancha y baja.
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
		var tip := top + Vector3(cos(a) * 1.4, rng.randf_range(0.4, 0.8), sin(a) * 1.4)
		b.tube(top, tip, 0.12, 0.06, 5, bark)
		b.blob(tip + Vector3(0, 0.25, 0), Vector3(1.5, 0.55, 1.5), leaf.lerp(Color(0.40, 0.45, 0.22), rng.randf()), rng)
	b.blob(top + Vector3(0, 0.9, 0), Vector3(1.9, 0.6, 1.9), leaf, rng)


static func _cactus(b: _Builder, rng: RandomNumberGenerator) -> void:
	var green := Color(0.36, 0.47, 0.31)
	var height := 2.6
	b.tube(Vector3.ZERO, Vector3(0, height, 0), 0.2, 0.17, 8, green, true)
	for k in 2:
		var a := PI * k + rng.randf_range(-0.4, 0.4)
		var y := rng.randf_range(0.8, 1.4)
		var out := Vector3(cos(a) * 0.55, y + 0.15, sin(a) * 0.55)
		b.tube(Vector3(0, y, 0), out, 0.13, 0.13, 6, green)
		b.tube(out, out + Vector3(0, rng.randf_range(0.7, 1.1), 0), 0.13, 0.11, 6, green, true)


static func _ichu(b: _Builder, rng: RandomNumberGenerator) -> void:
	var base := Color(0.52, 0.46, 0.25)
	var tip := Color(0.82, 0.72, 0.42)
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.2, 0.2)
		var length := rng.randf_range(0.6, 1.0)
		var lean := rng.randf_range(0.25, 0.6)
		var root := Vector3(cos(a), 0, sin(a)) * 0.06
		var mid := root + Vector3(cos(a) * lean * 0.4, length * 0.6, sin(a) * lean * 0.4)
		var end := root + Vector3(cos(a) * lean, length, sin(a) * lean)
		b.blade(root, mid, end, 0.035, base, tip)


static func _quenua(b: _Builder, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.55, 0.30, 0.21)
	var leaf := Color(0.21, 0.31, 0.17)
	var p := Vector3.ZERO
	# Tronco torcido en tramos.
	for k in 3:
		var q := p + Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35))
		b.tube(p, q, 0.2 - k * 0.04, 0.16 - k * 0.04, 6, bark)
		p = q
	for k in 5:
		var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.6), rng.randf_range(-1.0, 1.0))
		b.blob(p + off, Vector3(0.9, 0.6, 0.9) * rng.randf_range(0.8, 1.2), leaf.lerp(Color(0.28, 0.36, 0.20), rng.randf()), rng)


static func _eucalipto(b: _Builder, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.74, 0.71, 0.62)
	var leaf := Color(0.33, 0.44, 0.37)
	var top := Vector3(0.2, 10.0, 0)
	b.tube(Vector3.ZERO, top, 0.28, 0.1, 7, bark)
	for k in 4:
		var y := 6.0 + k * 1.6
		var off := Vector3(rng.randf_range(-0.7, 0.7), y, rng.randf_range(-0.7, 0.7))
		b.blob(off, Vector3(1.3, 1.6, 1.3) * rng.randf_range(0.8, 1.1), leaf, rng)


static func _arbol_selva(b: _Builder, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.33, 0.27, 0.2)
	var leaf := Color(0.12, 0.31, 0.10)
	var top := Vector3(0, 8.0, 0)
	b.tube(Vector3.ZERO, top, 0.45, 0.26, 8, bark)
	# Aletas en la base (raices tablares, tipicas de la selva).
	for k in 4:
		var a := TAU * k / 4.0
		b.tube(Vector3(cos(a) * 0.9, 0, sin(a) * 0.9), Vector3(cos(a) * 0.2, 1.4, sin(a) * 0.2), 0.12, 0.08, 4, bark)
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(a) * 2.2, rng.randf_range(-0.6, 0.8), sin(a) * 2.2)
		b.blob(top + off, Vector3(2.6, 1.6, 2.6) * rng.randf_range(0.8, 1.15), leaf.lerp(Color(0.18, 0.38, 0.12), rng.randf()), rng)
	b.blob(top + Vector3(0, 1.6, 0), Vector3(3.0, 1.8, 3.0), leaf, rng)


static func _palmera(b: _Builder, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.43, 0.38, 0.30)
	var leaf := Color(0.20, 0.42, 0.14)
	var p := Vector3.ZERO
	for k in 4:
		var q := p + Vector3(0.12 * k, 2.5, 0.05)
		b.tube(p, q, 0.22 - k * 0.02, 0.2 - k * 0.02, 6, bark)
		p = q
	for k in 11:
		var a := TAU * k / 11.0 + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := p + dir * 1.6 + Vector3(0, 0.5, 0)
		var end := p + dir * 3.2 + Vector3(0, -0.6, 0)
		b.blade(p, mid, end, 0.32, leaf.darkened(0.2), leaf)
	b.blob(p, Vector3(0.45, 0.45, 0.45), leaf.darkened(0.3), rng)


static func _arbusto(b: _Builder, rng: RandomNumberGenerator) -> void:
	var leaf := Color(0.18, 0.40, 0.14)
	for k in 3:
		var off := Vector3(rng.randf_range(-0.5, 0.5), 0.5 + rng.randf_range(0.0, 0.4), rng.randf_range(-0.5, 0.5))
		b.blob(off, Vector3(0.8, 0.6, 0.8) * rng.randf_range(0.8, 1.2), leaf.lerp(Color(0.25, 0.45, 0.16), rng.randf()), rng)


# ---------------------------------------------------------------------------
# Constructor de mallas low poly (caras planas, color por vertice)
# ---------------------------------------------------------------------------

class _Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, n := Vector3.ZERO) -> void:
		var nrm := n if n != Vector3.ZERO else (b - a).cross(c - a).normalized()
		if nrm == Vector3.ZERO:
			return
		verts.append_array([a, b, c])
		norms.append_array([nrm, nrm, nrm])
		cols.append_array([ca, cb, cc])

	## Tronco o rama: cilindro conico de a hasta b.
	func tube(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, color: Color, cap := false) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var other := axis.cross(side)
		var dark := color.darkened(0.12)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := side * cos(a0) + other * sin(a0)
			var d1 := side * cos(a1) + other * sin(a1)
			var c := color if k % 2 == 0 else dark
			tri(a + d0 * r0, b + d0 * r1, a + d1 * r0, c, c, c, (d0 + d1).normalized())
			tri(a + d1 * r0, b + d0 * r1, b + d1 * r1, c, c, c, (d0 + d1).normalized())
			if cap:
				tri(b + d0 * r1, b, b + d1 * r1, c, c, c, axis)

	## Copa de hojas: esfera low poly deformada al azar.
	func blob(center: Vector3, radius: Vector3, color: Color, rng: RandomNumberGenerator) -> void:
		var rings := 4
		var segs := 7
		var pts := []
		for i in rings + 1:
			var row := []
			var phi := PI * i / rings
			for j in segs:
				var theta := TAU * j / segs + (0.3 if i % 2 == 1 else 0.0)
				var jitter := 1.0 + rng.randf_range(-0.15, 0.15) if i > 0 and i < rings else 1.0
				var d := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
				row.append(center + d * radius * jitter)
			pts.append(row)
		for i in rings:
			for j in segs:
				var j1 := (j + 1) % segs
				var p00: Vector3 = pts[i][j]
				var p01: Vector3 = pts[i][j1]
				var p10: Vector3 = pts[i + 1][j]
				var p11: Vector3 = pts[i + 1][j1]
				var shade := color.darkened(0.25 * float(i) / rings)
				_outward_tri(p00, p10, p01, center, shade)
				_outward_tri(p01, p10, p11, center, shade)

	func _outward_tri(a: Vector3, b: Vector3, c: Vector3, center: Vector3, color: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.dot((a + b + c) / 3.0 - center) < 0.0:
			n = -n
		tri(a, b, c, color, color, color, n.normalized())

	## Hoja o brizna: tira de dos tramos que se adelgaza hacia la punta (se ve de los dos lados).
	func blade(root: Vector3, mid: Vector3, tip: Vector3, width: float, base_color: Color, tip_color: Color) -> void:
		var dir := (tip - root)
		dir.y = 0.0
		var side := Vector3(-dir.z, 0, dir.x).normalized() * width if dir.length() > 0.001 else Vector3(width, 0, 0)
		var mid_color := base_color.lerp(tip_color, 0.5)
		var up := Vector3.UP
		tri(root - side, root + side, mid + side * 0.6, base_color, base_color, mid_color, up)
		tri(root - side, mid + side * 0.6, mid - side * 0.6, base_color, mid_color, mid_color, up)
		tri(mid - side * 0.6, mid + side * 0.6, tip, mid_color, mid_color, tip_color, up)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
