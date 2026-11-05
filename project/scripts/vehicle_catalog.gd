class_name VehicleCatalog
extends RefCounted
const MODEL_SCALE := 1.2
const SOUND_STYLES := ["Eléctrico · turbo iónico", "Deportivo 2T · turbo flutter", "Diésel pesado · descarga de aire", "Bicilíndrico · compresor mecánico", "Motor suave · turbo silbante", "Monocilíndrico viejo · turbo traqueteante"]
## "price": soles de ahorro para comprarla en el garaje (CareerSave); la inicial es gratis.
## Las barras se derivan de los ajustes usados por la física, no son decorativas.
const VEHICLES := [
	{"id":"neon_thunder", "price":85.0, "name":"Neon Thunder", "role":"VELOCIDAD / ASFALTO", "description":"Ligera y rápida. Domina las rectas con su turbo de alta potencia.", "speed":78.0, "force":740.0, "grip":2.8, "offroad":0.52, "turbo":2.3, "color":Color("ffdb38")},
	{"id":"faketaxi_drift", "price":65.0, "name":"Faketaxi Drift", "role":"DERRAPE / AGILIDAD", "description":"Giro rápido y agarre suelto para enlazar curvas con el freno de mano.", "speed":72.0, "force":710.0, "grip":2.35, "offroad":0.55, "turbo":2.15, "color":Color("ff3b8b")},
	{"id":"neon_shadow", "price":0.0, "name":"Neon Shadow", "role":"EQUILIBRIO / CONTROL", "description":"Respuesta equilibrada para llevar pasajeros entre regiones.", "speed":68.0, "force":730.0, "grip":3.2, "offroad":0.61, "turbo":2.1, "color":Color("42ded9")},
	{"id":"silver_guardian", "price":50.0, "name":"Silver Guardian", "role":"AGARRE / SIERRA", "description":"Tracción firme y fuerza de subida. Ideal para las rutas de montaña.", "speed":64.0, "force":850.0, "grip":3.5, "offroad":0.67, "turbo":2.2, "color":Color("b4caff")},
	{"id":"midnight_camper", "price":30.0, "name":"Midnight Camper", "role":"ESTABILIDAD / VIAJE", "description":"Dirección tranquila y buena tracción para viajes largos.", "speed":60.0, "force":800.0, "grip":3.6, "offroad":0.65, "turbo":2.0, "color":Color("b89cff")},
	{"id":"dusty", "price":40.0, "name":"Dusty", "role":"TIERRA / RESISTENCIA", "description":"La más capaz fuera de la pista, aunque la tierra siempre reduce el ritmo.", "speed":62.0, "force":830.0, "grip":3.3, "offroad":0.72, "turbo":2.1, "color":Color("efb878")},
]

static func entry(index: int) -> Dictionary:
	return VEHICLES[clampi(index, 0, VEHICLES.size()-1)]

static func create_model(index: int) -> Node3D:
	var data := entry(index)
	var scene := load("res://assets/vehicles/%s.glb" % data.id) as PackedScene
	var model := scene.instantiate() as Node3D if scene else null
	if model: model.scale = Vector3.ONE * MODEL_SCALE
	return model

static func bars(index: int) -> Dictionary:
	var v := entry(index)
	return {"Velocidad":float(v.speed)/85.0, "Aceleración":float(v.force)/950.0,
		"Agarre":float(v.grip)/4.0, "Todoterreno":float(v.offroad)/0.85,
		"Turbo":float(v.turbo)/2.6}
