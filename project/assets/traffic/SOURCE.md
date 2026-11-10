# Tráfico

Modelos de Quaternius, licencia **CC0 1.0** (dominio público; igual figuran en Créditos). Descargados en
GLB desde Poly Pizza (2026-11-10). Los usa `RoadTraffic` (`scripts/road_traffic.gd`).

| Archivo | En el juego | Modelo | Poly Pizza |
|---|---|---|---|
| truck.glb | camión (sube lento; más en la sierra) | Truck | https://poly.pizza/m/cXw6oiFtZ8 |
| pickup.glb | camioneta | Pickup Truck | https://poly.pizza/m/qn4grQgHm8 |

Autor: https://quaternius.com

No hay una combi o minivan CC0 en Poly Pizza (las que hay son CC-BY de Poly by Google): la combi se arma
por código en `RoadTraffic.make_combi` (blanca con franja de color, letrero de ruta y parrilla). Las otras
mototaxis usan los modelos del garaje (`VehicleCatalog`). `RoadTraffic` escala cada modelo a su largo real
(`TYPES`) y lo apoya en el suelo; miran hacia +Z.
