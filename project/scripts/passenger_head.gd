extends RefCounted

const PATH := "user://passenger_head.glb"
const MAX_BYTES := 32 * 1024 * 1024


static func load_model(path: String = PATH) -> Node3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 20 or file.get_length() > MAX_BYTES:
		return null
	if file.get_32() != 0x46546C67:  # Cabecera glTF binaria.
		return null
	file.seek(0)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(file.get_buffer(file.get_length()), "", state) != OK:
		return null
	var model := document.generate_scene(state) as Node3D
	if model:
		var box := bounds(model)
		if not box.is_finite() or not box.has_volume():
			model.free()
			return null
	return model


static func bounds(node: Node, parent := Transform3D.IDENTITY) -> AABB:
	var pose := parent
	if node is Node3D:
		pose = parent * node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh:
		result = pose * node.get_aabb()
	for child in node.get_children():
		var box := bounds(child, pose)
		if box.has_volume():
			result = result.merge(box) if result.has_volume() else box
	return result


static func attach(body: Node3D, model: Node3D) -> bool:
	var original := body.find_child("Casual2_Head", true, false) as MeshInstance3D
	if original == null:
		return false
	var skeleton := original.get_parent() as Skeleton3D
	if skeleton == null:
		return false
	var index := skeleton.find_bone("Head")
	if index < 0:
		return false
	var box := bounds(model)
	var center := box.get_center()
	var fit := 0.00345 / box.size.y
	# El GLB mira a +Z con Y arriba. El rig Casual2 usa -Y como frente y Z arriba.
	var axes := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN).scaled(Vector3.ONE * fit)
	var neck := Vector3(0, -0.00055, 0.01525)
	var bind := Transform3D(axes, neck - axes * Vector3(center.x, box.position.y, center.z))
	var anchor := BoneAttachment3D.new()
	anchor.name = "CabezaPersonalizada"
	anchor.bone_name = "Head"
	skeleton.add_child(anchor)
	var pivot := Node3D.new()
	pivot.transform = skeleton.get_bone_global_rest(index).affine_inverse() * bind
	anchor.add_child(pivot)
	pivot.add_child(model)
	original.hide()
	return true
