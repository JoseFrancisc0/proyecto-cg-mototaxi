class_name VehicleWheelVisuals
extends RefCounted
## El neumático gira sobre su propio eje; solo su pivote delantero dirige.
var wheels: Array[Dictionary] = []

func bind_model(model: Node3D) -> void:
	wheels.clear()
	for pivot: Node in model.find_children("Wheel*Pivot","Node3D",true,false):
		var spin := pivot.get_node_or_null(String(pivot.name).replace("Pivot","Spin")) as Node3D
		if spin == null: continue
		var extras: Dictionary = pivot.get_meta("extras",{})
		wheels.append({"pivot":pivot,"spin":spin,"radius":float(extras.get("wheel_radius",0.25))*model.scale.x,
			"front":pivot.name == &"WheelFrontPivot","angle":0.0})

func update_wheels(delta: float, speed: float, steer: float) -> void:
	for wheel: Dictionary in wheels:
		wheel.angle = wrapf(float(wheel.angle) + speed * delta / maxf(float(wheel.radius),0.05),-PI,PI)
		var spin: Node3D = wheel.spin
		var pivot: Node3D = wheel.pivot
		spin.rotation.x = wheel.angle
		pivot.rotation.y = steer if wheel.front else 0.0
