class_name StopNames
extends RefCounted
## Nombres y tipos de las paradas (landmarks) según la región: costa, sierra o selva.
##
## assign() recorre los landmarks de TerrainWorld y les agrega:
##   "region": 0 costa, 1 sierra, 2 selva (la que domina en ese punto)
##   "kind":   tipo de parada ("plaza", "mercado", "paradero", "colegio", ...); "via" = sin nombre
##   "label":  nombre a mostrar ("Mercado Santa Rosa"), salvo en las paradas "via"
## Los centros de pueblo son plaza o mercado; los rasgos del terreno, mirador, confluencia o
## playa; y algunos puntos de vía separados entre sí (named_spacing) reciben un tipo y un
## nombre al azar. Todo sale de la semilla del mundo: el mismo mapa da los mismos nombres.
## El tipo de parada servirá para ambientarla (puestos de mercado, paradero techado, ...).

const REGIONS := ["costa", "sierra", "selva"]

## Nombres propios por región (se combinan con el tipo de parada).
const NAMES := [
	[  # costa
		"San Martín", "Santa Rosa", "Los Pescadores", "Las Dunas", "El Huarango", "La Punta",
		"Miramar", "San Pedro", "Los Algarrobos", "Brisas del Mar", "El Sol", "Las Gaviotas",
		"La Caleta", "Los Pelícanos", "Santa María", "El Carrizal", "Las Salinas", "Villa del Mar",
	],
	[  # sierra
		"Santa Ana", "Los Andes", "San Cristóbal", "Las Retamas", "Huaynapata", "Los Eucaliptos",
		"Cruz Pata", "San Jerónimo", "Inti Raymi", "Las Vicuñas", "Kantu", "Señor de los Milagros",
		"Wiracocha", "Pumacahua", "Qollana", "Chachacomo", "Los Quinuales", "San Isidro",
	],
	[  # selva
		"El Aguajal", "Las Palmeras", "Río Verde", "San Juan", "La Cocha", "Los Shapajas",
		"El Huito", "Las Orquídeas", "Bellavista", "Las Lupunas", "Tres Esquinas", "Puerto Nuevo",
		"Los Camu Camu", "La Cascada", "El Paiche", "Las Bromelias", "Santa Clotilde", "Nuevo Edén",
	],
]

## Plantilla del nombre de cada tipo de parada, por región ("%s" = nombre propio).
const TEMPLATES := {
	"plaza": ["Plaza %s", "Plaza de Armas %s", "Plaza %s"],
	"mercado": ["Mercado %s", "Mercado de Abastos %s", "Mercado %s"],
	"paradero": ["Paradero %s", "Paradero %s", "Paradero %s"],
	"colegio": ["Colegio %s", "Colegio %s", "Colegio %s"],
	"posta": ["Posta de Salud %s", "Posta %s", "Posta de Salud %s"],
	"grifo": ["Grifo %s", "Grifo %s", "Grifo %s"],
	"chacra": ["Fundo %s", "Chacra %s", "Chacra %s"],
	"especial": ["Huaca %s", "Comunidad %s", "Embarcadero %s"],
	"mirador": ["Mirador %s", "Mirador %s", "Mirador %s"],
	"confluencia": ["Confluencia %s", "Puente %s", "Confluencia %s"],
	"playa": ["Playa %s", "Playa %s", "Playa %s"],
}

## Tipos de las paradas de vía con nombre y su peso al sortear.
const ROAD_KINDS := {"paradero": 3.0, "chacra": 2.0, "colegio": 1.5, "posta": 1.0, "grifo": 1.0, "especial": 1.0}
## Rasgo del terreno -> tipo de parada.
const FEATURE_KINDS := {"pico": "mirador", "confluencia": "confluencia", "costa": "playa"}

## Color del tablero del cartel por tipo.
const KIND_COLORS := {
	"plaza": Color("175442"), "mercado": Color("7a3b22"), "paradero": Color("1f4f8a"),
	"colegio": Color("8a6d12"), "posta": Color("a33a3a"), "grifo": Color("3d3d3d"),
	"chacra": Color("4f6b23"), "especial": Color("6b3f7a"), "mirador": Color(0.85, 0.45, 0.15),
	"confluencia": Color(0.15, 0.45, 0.85), "playa": Color(0.95, 0.80, 0.30),
}


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, Color("514941"))


## Agrega "region", "kind" y "label" a cada landmark. region_of(p: Vector3) -> int.
## Las paradas de vía con nombre quedan a por lo menos named_spacing metros entre sí y de
## los pueblos y rasgos.
static func assign(landmarks: Array[Dictionary], world_seed: int, region_of: Callable, named_spacing := 220.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "paradas"])
	var pools: Array = [[], [], []]
	var used := {}
	var named: Array[Vector3] = []
	var town_count := [0, 0, 0]

	for lm in landmarks:
		var region: int = clampi(region_of.call(lm["position"]), 0, 2)
		lm["region"] = region
		var type: String = lm["type"]
		if type == "pueblo":
			# El primer pueblo de cada región tiene la plaza; los demás, alternan.
			lm["kind"] = "plaza" if town_count[region] % 2 == 0 else "mercado"
			town_count[region] += 1
		elif FEATURE_KINDS.has(type):
			lm["kind"] = FEATURE_KINDS[type]
		else:
			lm["kind"] = "via"
			lm.erase("label")
			continue
		lm["label"] = _make_label(lm["kind"], region, rng, pools, used)
		named.append(lm["position"])

	# Paradas de vía con nombre, en orden al azar para que no se agrupen por vía.
	var order := range(landmarks.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i: int in order:
		var lm := landmarks[i]
		if lm["kind"] != "via":
			continue
		var p: Vector3 = lm["position"]
		if named.any(func(q: Vector3) -> bool: return Vector2(q.x - p.x, q.z - p.z).length() < named_spacing):
			continue
		lm["kind"] = _pick_kind(rng)
		lm["label"] = _make_label(lm["kind"], lm["region"], rng, pools, used)
		named.append(p)


static func _pick_kind(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for w: float in ROAD_KINDS.values():
		total += w
	var r := rng.randf() * total
	for k: String in ROAD_KINDS:
		r -= ROAD_KINDS[k]
		if r <= 0.0:
			return k
	return "paradero"


## Nombre que no se repite: cada nombre propio sale una vez por región antes de volver a usarse.
static func _make_label(kind: String, region: int, rng: RandomNumberGenerator, pools: Array, used: Dictionary) -> String:
	var template: String = TEMPLATES[kind][region]
	for attempt in 60:
		if pools[region].is_empty():
			var fresh: Array = NAMES[region].duplicate()
			for i in range(fresh.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = fresh[i]
				fresh[i] = fresh[j]
				fresh[j] = tmp
			pools[region] = fresh
		var label := template % pools[region].pop_back()
		if not used.has(label):
			used[label] = true
			return label
	var fallback := template % ("%s %d" % [NAMES[region][0], used.size()])
	used[fallback] = true
	return fallback
