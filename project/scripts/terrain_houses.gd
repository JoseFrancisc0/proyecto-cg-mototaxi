class_name TerrainHouses
extends Node3D
## Viviendas del mapa según la región (pendiente 10, fase 4): que se note que vive gente.
##   Pueblos: casas en fila a los dos lados de las calles (kind 3), frente a la vía.
##   Cerca del pueblo: casas más separadas en avenidas y carreteras.
##   Campo: alguna casa suelta junto a las carreteras y trochas, y la casa de la chacra al final de
##   cada trocha sin salida.
## Modelos importados (assets/houses, ver SOURCE.md), escalados a un tamaño real. Cada casa es sólida
## (una caja de colisión) y se apoya en el suelo: si el terreno baja, un zócalo de piedra la sostiene
## (no flota). Nunca sobre una vía, un río, una parada, un cartel u otra casa; quita los árboles de
## adentro (TerrainVegetation). Todo sale de la semilla del mundo: mismo mapa, mismas casas.

const DIR := "res://assets/houses/"
## file, region (0 costa, 1 sierra, 2 selva), height (alto real en m), yaw (giro para que la puerta
## mire hacia +Z).
const MODELS := [
	{"file": "peru/costa_invasion_0.glb", "region": 0, "height": 3.3899998664855957, "yaw": 0.0, "style": "invasion", "zones": ["ladera"], "frontage": 5.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_invasion_1.glb", "region": 0, "height": 6.960000038146973, "yaw": 0.0, "style": "invasion", "zones": ["ladera"], "frontage": 6.1, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_invasion_2.glb", "region": 0, "height": 3.3899998664855957, "yaw": 0.0, "style": "invasion", "zones": ["ladera"], "frontage": 7.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 5, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_invasion_3.glb", "region": 0, "height": 9.660000801086426, "yaw": 0.0, "style": "invasion", "zones": ["ladera"], "frontage": 8.3, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 27, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_barrio_0.glb", "region": 0, "height": 8.140000343322754, "yaw": 0.0, "style": "barrio", "zones": ["popular"], "frontage": 9.2, "roof": "flat", "entrance": [-3.5880000591278076, 0.1400001049041748, 3.430000066757202], "foundation_size": [9.2, 6.2], "envelope": {"openings": 17, "sealed_panels": 23, "ground_doors": 1}},
	{"file": "peru/costa_barrio_1.glb", "region": 0, "height": 5.78000020980835, "yaw": 0.0, "style": "barrio", "zones": ["popular"], "frontage": 5.3, "roof": "flat", "entrance": [1.1660000085830688, 0.1400001049041748, 3.6549999713897705], "foundation_size": [5.3, 6.65], "envelope": {"openings": 8, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_barrio_2.glb", "region": 0, "height": 5.78000020980835, "yaw": 0.0, "style": "barrio", "zones": ["popular"], "frontage": 5.7, "roof": "flat", "entrance": [1.253999948501587, 0.1400001049041748, 3.880000114440918], "foundation_size": [5.7, 7.1000000000000005], "envelope": {"openings": 8, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_barrio_3.glb", "region": 0, "height": 3.0299999713897705, "yaw": 0.0, "style": "barrio", "zones": ["popular"], "frontage": 6.0, "roof": "flat", "entrance": [1.3200000524520874, 0.1400001049041748, 4.105000019073486], "foundation_size": [6.0, 7.550000000000001], "envelope": {"openings": 8, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_barranco_0.glb", "region": 0, "height": 2.9800000190734863, "yaw": 0.0, "style": "barranco", "zones": ["tradicional"], "frontage": 5.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/costa_barranco_1.glb", "region": 0, "height": 6.289999961853027, "yaw": 0.0, "style": "barranco", "zones": ["tradicional"], "frontage": 6.1, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 4, "ground_doors": 1}},
	{"file": "peru/costa_barranco_2.glb", "region": 0, "height": 5.680000305175781, "yaw": 0.0, "style": "barranco", "zones": ["tradicional"], "frontage": 7.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 21, "sealed_panels": 3, "ground_doors": 1}},
	{"file": "peru/costa_barranco_3.glb", "region": 0, "height": 2.9800000190734863, "yaw": 0.0, "style": "barranco", "zones": ["tradicional"], "frontage": 8.3, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 9, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_jardin_0.glb", "region": 0, "height": 8.041095733642578, "yaw": 0.0, "style": "jardin", "zones": ["residencial"], "frontage": 7.2, "roof": "pitched", "entrance": [-1.944000005722046, 0.15999996662139893, 4.550000190734863], "foundation_size": [7.2, 8.4], "envelope": {"openings": 5, "sealed_panels": 7, "ground_doors": 1}},
	{"file": "peru/costa_jardin_1.glb", "region": 0, "height": 8.015929222106934, "yaw": 0.0, "style": "jardin", "zones": ["residencial"], "frontage": 6.4, "roof": "pitched", "entrance": [-1.7280000448226929, 0.15999996662139893, 4.550000190734863], "foundation_size": [6.4, 8.4], "envelope": {"openings": 5, "sealed_panels": 7, "ground_doors": 1}},
	{"file": "peru/costa_jardin_2.glb", "region": 0, "height": 8.02939224243164, "yaw": 0.0, "style": "jardin", "zones": ["residencial"], "frontage": 6.8, "roof": "pitched", "entrance": [-1.8359999656677246, 0.15999996662139893, 4.550000190734863], "foundation_size": [6.8, 8.4], "envelope": {"openings": 5, "sealed_panels": 7, "ground_doors": 1}},
	{"file": "peru/costa_jardin_3.glb", "region": 0, "height": 8.004579544067383, "yaw": 0.0, "style": "jardin", "zones": ["residencial"], "frontage": 6.1, "roof": "pitched", "entrance": [-1.6469999551773071, 0.15999996662139893, 4.550000190734863], "foundation_size": [6.1, 8.4], "envelope": {"openings": 5, "sealed_panels": 7, "ground_doors": 1}},
	{"file": "peru/costa_miraflores_0.glb", "region": 0, "height": 26.3799991607666, "yaw": 0.0, "style": "miraflores", "zones": ["moderna"], "frontage": 15.0, "roof": "flat", "entrance": [0.0, 0.1799999475479126, 6.900000095367432], "foundation_size": [15.0, 13.0], "envelope": {"openings": 1, "sealed_panels": 140, "ground_doors": 1}},
	{"file": "peru/costa_miraflores_1.glb", "region": 0, "height": 35.53000259399414, "yaw": 0.0, "style": "miraflores", "zones": ["moderna"], "frontage": 18.0, "roof": "flat", "entrance": [0.0, 0.1799999475479126, 7.150000095367432], "foundation_size": [18.0, 13.5], "envelope": {"openings": 1, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_miraflores_2.glb", "region": 0, "height": 47.730003356933594, "yaw": 0.0, "style": "miraflores", "zones": ["moderna"], "frontage": 12.0, "roof": "flat", "entrance": [0.0, 0.1799999475479126, 5.400000095367432], "foundation_size": [12.0, 10.0], "envelope": {"openings": 1, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_miraflores_3.glb", "region": 0, "height": 59.93000030517578, "yaw": 0.0, "style": "miraflores", "zones": ["moderna"], "frontage": 22.0, "roof": "flat", "entrance": [0.0, 0.1799999475479126, 8.899999618530273], "foundation_size": [22.0, 17.0], "envelope": {"openings": 1, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_valle_0.glb", "region": 0, "height": 2.9800000190734863, "yaw": 0.0, "style": "valle", "zones": ["rural"], "frontage": 5.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/costa_valle_1.glb", "region": 0, "height": 5.680000305175781, "yaw": 0.0, "style": "valle", "zones": ["rural"], "frontage": 6.1, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/costa_valle_2.glb", "region": 0, "height": 2.9800000190734863, "yaw": 0.0, "style": "valle", "zones": ["rural"], "frontage": 7.2, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 5, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/costa_valle_3.glb", "region": 0, "height": 5.680000305175781, "yaw": 0.0, "style": "valle", "zones": ["rural"], "frontage": 8.3, "roof": "flat", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 18, "sealed_panels": 5, "ground_doors": 1}},
	{"file": "peru/costa_casa_moderna_0.glb", "region": 0, "height": 7.699999809265137, "yaw": 0.0, "style": "casa_moderna", "zones": ["residencial", "moderna"], "frontage": 9.6, "roof": "flat", "entrance": [-2.496000051498413, 0.15999996662139893, 5.340000152587891], "foundation_size": [9.6, 10.0], "envelope": {"openings": 12, "sealed_panels": 8, "ground_doors": 1}},
	{"file": "peru/costa_casa_moderna_1.glb", "region": 0, "height": 6.99399995803833, "yaw": 0.0, "style": "casa_moderna", "zones": ["residencial", "moderna"], "frontage": 6.4, "roof": "flat", "entrance": [-0.8320000171661377, 0.15999996662139893, 4.340000152587891], "foundation_size": [6.4, 8.0], "envelope": {"openings": 14, "sealed_panels": 4, "ground_doors": 1}},
	{"file": "peru/costa_casa_moderna_2.glb", "region": 0, "height": 6.800000190734863, "yaw": 0.0, "style": "casa_moderna", "zones": ["residencial", "moderna"], "frontage": 10.0, "roof": "flat", "entrance": [-0.5, 0.12000000476837158, 7.130000114440918], "foundation_size": [10.0, 10.0], "envelope": {"openings": 16, "sealed_panels": 4, "ground_doors": 2}},
	{"file": "peru/costa_casa_moderna_3.glb", "region": 0, "height": 8.199999809265137, "yaw": 0.0, "style": "casa_moderna", "zones": ["residencial", "moderna"], "frontage": 16.0, "roof": "flat", "entrance": [-4.639999866485596, 0.1400001049041748, 6.980000019073486], "foundation_size": [16.0, 12.0], "envelope": {"openings": 14, "sealed_panels": 4, "ground_doors": 1}},
	{"file": "peru/sierra_andina_urbana_0.glb", "region": 1, "height": 4.578444480895996, "yaw": 0.0, "style": "andina_urbana", "zones": ["popular"], "frontage": 5.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_urbana_1.glb", "region": 1, "height": 7.440727710723877, "yaw": 0.0, "style": "andina_urbana", "zones": ["popular"], "frontage": 6.1, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_urbana_2.glb", "region": 1, "height": 10.316205024719238, "yaw": 0.0, "style": "andina_urbana", "zones": ["popular"], "frontage": 7.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 13, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_urbana_3.glb", "region": 1, "height": 5.541606426239014, "yaw": 0.0, "style": "andina_urbana", "zones": ["popular"], "frontage": 8.3, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_san_blas_0.glb", "region": 1, "height": 4.578444480895996, "yaw": 0.0, "style": "san_blas", "zones": ["tradicional"], "frontage": 5.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_san_blas_1.glb", "region": 1, "height": 7.440727710723877, "yaw": 0.0, "style": "san_blas", "zones": ["tradicional"], "frontage": 6.1, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 3, "ground_doors": 1}},
	{"file": "peru/sierra_san_blas_2.glb", "region": 1, "height": 10.316205024719238, "yaw": 0.0, "style": "san_blas", "zones": ["tradicional"], "frontage": 7.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 13, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_san_blas_3.glb", "region": 1, "height": 5.541606426239014, "yaw": 0.0, "style": "san_blas", "zones": ["tradicional"], "frontage": 8.3, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 19, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_valle_sagrado_0.glb", "region": 1, "height": 5.890363693237305, "yaw": 0.0, "style": "valle_sagrado", "zones": ["residencial"], "frontage": 14.8, "roof": "pitched", "entrance": [1.7760000228881836, 0.2200000286102295, 4.400000095367432], "foundation_size": [14.8, 8.1], "envelope": {"openings": 14, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_valle_sagrado_1.glb", "region": 1, "height": 6.047396659851074, "yaw": 0.0, "style": "valle_sagrado", "zones": ["residencial"], "frontage": 13.0, "roof": "pitched", "entrance": [1.559999942779541, 0.2200000286102295, 4.400000095367432], "foundation_size": [13.0, 8.1], "envelope": {"openings": 13, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_valle_sagrado_2.glb", "region": 1, "height": 6.194744110107422, "yaw": 0.0, "style": "valle_sagrado", "zones": ["residencial"], "frontage": 16.0, "roof": "pitched", "entrance": [1.9199999570846558, 0.2200000286102295, 4.400000095367432], "foundation_size": [16.0, 8.1], "envelope": {"openings": 13, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_valle_sagrado_3.glb", "region": 1, "height": 6.3323869705200195, "yaw": 0.0, "style": "valle_sagrado", "zones": ["residencial"], "frontage": 12.5, "roof": "pitched", "entrance": [1.5, 0.2200000286102295, 4.400000095367432], "foundation_size": [12.5, 8.1], "envelope": {"openings": 13, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_actual_0.glb", "region": 1, "height": 7.374821186065674, "yaw": 0.0, "style": "andina_actual", "zones": ["moderna"], "frontage": 8.5, "roof": "flat", "entrance": [-2.2950000762939453, 0.15999996662139893, 4.360000133514404], "foundation_size": [8.5, 8.0], "envelope": {"openings": 14, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/sierra_andina_actual_1.glb", "region": 1, "height": 6.490000247955322, "yaw": 0.0, "style": "andina_actual", "zones": ["moderna"], "frontage": 10.0, "roof": "flat", "entrance": [-0.800000011920929, 0.15999996662139893, 4.860000133514404], "foundation_size": [10.0, 9.0], "envelope": {"openings": 14, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/sierra_andina_actual_2.glb", "region": 1, "height": 17.809999465942383, "yaw": 0.0, "style": "andina_actual", "zones": ["moderna"], "frontage": 12.6, "roof": "flat", "entrance": [2.3940000534057617, 0.15999996662139893, 5.349999904632568], "foundation_size": [12.6, 10.0], "envelope": {"openings": 53, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/sierra_andina_actual_3.glb", "region": 1, "height": 24.309999465942383, "yaw": 0.0, "style": "andina_actual", "zones": ["moderna"], "frontage": 10.2, "roof": "flat", "entrance": [0.0, 0.15999996662139893, 5.460000038146973], "foundation_size": [10.2, 10.2], "envelope": {"openings": 50, "sealed_panels": 84, "ground_doors": 1}},
	{"file": "peru/sierra_adobe_0.glb", "region": 1, "height": 4.578444480895996, "yaw": 0.0, "style": "adobe", "zones": ["rural"], "frontage": 5.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_adobe_1.glb", "region": 1, "height": 4.890727519989014, "yaw": 0.0, "style": "adobe", "zones": ["rural"], "frontage": 6.1, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 5, "sealed_panels": 3, "ground_doors": 1}},
	{"file": "peru/sierra_adobe_2.glb", "region": 1, "height": 5.216205596923828, "yaw": 0.0, "style": "adobe", "zones": ["rural"], "frontage": 7.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 5, "sealed_panels": 3, "ground_doors": 1}},
	{"file": "peru/sierra_adobe_3.glb", "region": 1, "height": 8.091606140136719, "yaw": 0.0, "style": "adobe", "zones": ["rural"], "frontage": 8.3, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 18, "sealed_panels": 8, "ground_doors": 1}},
	{"file": "peru/sierra_andina_ladera_0.glb", "region": 1, "height": 4.251367568969727, "yaw": 0.0, "style": "andina_ladera", "zones": ["ladera"], "frontage": 6.0, "roof": "pitched", "entrance": [1.440000057220459, 0.13999998569488525, 3.5799999237060547], "foundation_size": [6.0, 6.6], "envelope": {"openings": 3, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_ladera_1.glb", "region": 1, "height": 4.272198677062988, "yaw": 0.0, "style": "andina_ladera", "zones": ["ladera"], "frontage": 7.0, "roof": "pitched", "entrance": [-1.75, 0.13999998569488525, 3.5799999237060547], "foundation_size": [7.0, 6.6], "envelope": {"openings": 3, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_ladera_2.glb", "region": 1, "height": 6.537233352661133, "yaw": 0.0, "style": "andina_ladera", "zones": ["ladera"], "frontage": 5.5, "roof": "pitched", "entrance": [1.3200000524520874, 0.13999998569488525, 3.5799999237060547], "foundation_size": [5.5, 6.6], "envelope": {"openings": 5, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/sierra_andina_ladera_3.glb", "region": 1, "height": 4.292093276977539, "yaw": 0.0, "style": "andina_ladera", "zones": ["ladera"], "frontage": 8.5, "roof": "pitched", "entrance": [-2.125, 0.13999998569488525, 3.5799999237060547], "foundation_size": [8.5, 6.6], "envelope": {"openings": 3, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/selva_pucallpa_0.glb", "region": 2, "height": 4.620991230010986, "yaw": 0.0, "style": "pucallpa", "zones": ["popular"], "frontage": 5.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/selva_pucallpa_1.glb", "region": 2, "height": 7.606750011444092, "yaw": 0.0, "style": "pucallpa", "zones": ["popular"], "frontage": 6.1, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 4, "ground_doors": 1}},
	{"file": "peru/selva_pucallpa_2.glb", "region": 2, "height": 10.601876258850098, "yaw": 0.0, "style": "pucallpa", "zones": ["popular"], "frontage": 7.2, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 13, "sealed_panels": 6, "ground_doors": 1}},
	{"file": "peru/selva_pucallpa_3.glb", "region": 2, "height": 5.496976375579834, "yaw": 0.0, "style": "pucallpa", "zones": ["popular"], "frontage": 8.3, "roof": "pitched", "entrance": [0.0, 0.1400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 9, "sealed_panels": 5, "ground_doors": 1}},
	{"file": "peru/selva_iquitos_0.glb", "region": 2, "height": 7.430000305175781, "yaw": 0.0, "style": "iquitos", "zones": ["tradicional"], "frontage": 10.8, "roof": "flat", "entrance": [-3.806999921798706, 0.13999998569488525, 3.4800000190734863], "foundation_size": [10.8, 6.2], "envelope": {"openings": 24, "sealed_panels": 13, "ground_doors": 4}},
	{"file": "peru/selva_iquitos_1.glb", "region": 2, "height": 9.20674991607666, "yaw": 0.0, "style": "iquitos", "zones": ["tradicional"], "frontage": 6.1, "roof": "pitched", "entrance": [0.0, 0.13999998569488525, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 6, "ground_doors": 1}},
	{"file": "peru/selva_iquitos_2.glb", "region": 2, "height": 13.001875877380371, "yaw": 0.0, "style": "iquitos", "zones": ["tradicional"], "frontage": 7.2, "roof": "pitched", "entrance": [0.0, 0.13999998569488525, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 29, "sealed_panels": 9, "ground_doors": 1}},
	{"file": "peru/selva_iquitos_3.glb", "region": 2, "height": 6.296976566314697, "yaw": 0.0, "style": "iquitos", "zones": ["tradicional"], "frontage": 8.3, "roof": "pitched", "entrance": [0.0, 0.13999998569488525, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/selva_tarapoto_0.glb", "region": 2, "height": 3.41104793548584, "yaw": 0.0, "style": "tarapoto", "zones": ["residencial"], "frontage": 3.6, "roof": "flat", "entrance": [0.7919999957084656, 0.13999998569488525, 3.700000047683716], "foundation_size": [3.6, 6.8], "envelope": {"openings": 3, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/selva_tarapoto_1.glb", "region": 2, "height": 3.41104793548584, "yaw": 0.0, "style": "tarapoto", "zones": ["residencial"], "frontage": 4.0, "roof": "flat", "entrance": [0.8799999952316284, 0.13999998569488525, 3.700000047683716], "foundation_size": [4.0, 6.8], "envelope": {"openings": 3, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/selva_tarapoto_2.glb", "region": 2, "height": 3.41104793548584, "yaw": 0.0, "style": "tarapoto", "zones": ["residencial"], "frontage": 4.2, "roof": "flat", "entrance": [0.9240000247955322, 0.13999998569488525, 3.700000047683716], "foundation_size": [4.2, 6.8], "envelope": {"openings": 3, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/selva_tarapoto_3.glb", "region": 2, "height": 3.41104793548584, "yaw": 0.0, "style": "tarapoto", "zones": ["residencial"], "frontage": 3.4, "roof": "flat", "entrance": [0.7480000257492065, 0.13999998569488525, 3.700000047683716], "foundation_size": [3.4, 6.8], "envelope": {"openings": 3, "sealed_panels": 0, "ground_doors": 1}},
	{"file": "peru/selva_tropical_actual_0.glb", "region": 2, "height": 6.346958637237549, "yaw": 0.0, "style": "tropical_actual", "zones": ["moderna"], "frontage": 8.6, "roof": "pitched", "entrance": [0.0, 0.12000000476837158, 5.199999809265137], "foundation_size": [8.6, 7.0], "envelope": {"openings": 8, "sealed_panels": 0, "ground_doors": 2}},
	{"file": "peru/selva_tropical_actual_1.glb", "region": 2, "height": 7.6663594245910645, "yaw": 0.0, "style": "tropical_actual", "zones": ["moderna"], "frontage": 9.0, "roof": "pitched", "entrance": [0.0, 0.18000006675720215, 4.059999942779541], "foundation_size": [9.0, 7.5], "envelope": {"openings": 7, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/selva_tropical_actual_2.glb", "region": 2, "height": 6.399409294128418, "yaw": 0.0, "style": "tropical_actual", "zones": ["moderna"], "frontage": 10.1, "roof": "pitched", "entrance": [0.0, 0.12000000476837158, 5.900000095367432], "foundation_size": [10.1, 8.4], "envelope": {"openings": 8, "sealed_panels": 0, "ground_doors": 2}},
	{"file": "peru/selva_tropical_actual_3.glb", "region": 2, "height": 7.64548921585083, "yaw": 0.0, "style": "tropical_actual", "zones": ["moderna"], "frontage": 7.6, "roof": "pitched", "entrance": [0.0, 0.18000006675720215, 3.859999895095825], "foundation_size": [7.6, 7.1], "envelope": {"openings": 7, "sealed_panels": 2, "ground_doors": 1}},
	{"file": "peru/selva_comunidad_0.glb", "region": 2, "height": 6.075738906860352, "yaw": 0.0, "style": "comunidad", "zones": ["rural"], "frontage": 5.2, "roof": "pitched", "supports": [[-2.236, 0, 2.666], [-2.236, 0, 0], [-2.236, 0, -2.666], [0, 0, 2.666], [0, 0, 0], [0, 0, -2.666], [2.236, 0, 2.666], [2.236, 0, 0], [2.236, 0, -2.666]], "entrance": [0.0, 0.6400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}, "approach": [0, 0.06, 4.470000000000001]},
	{"file": "peru/selva_comunidad_1.glb", "region": 2, "height": 6.413207530975342, "yaw": 0.0, "style": "comunidad", "zones": ["rural"], "frontage": 6.1, "roof": "pitched", "supports": [[-2.6229999999999998, 0, 2.8595], [-2.6229999999999998, 0, 0], [-2.6229999999999998, 0, -2.8595], [0, 0, 2.8595], [0, 0, 0], [0, 0, -2.8595], [2.6229999999999998, 0, 2.8595], [2.6229999999999998, 0, 0], [2.6229999999999998, 0, -2.8595]], "entrance": [0.0, 0.6400001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 5, "sealed_panels": 3, "ground_doors": 1}, "approach": [0, 0.06, 4.695]},
	{"file": "peru/selva_comunidad_2.glb", "region": 2, "height": 6.785853385925293, "yaw": 0.0, "style": "comunidad", "zones": ["rural"], "frontage": 7.2, "roof": "pitched", "supports": [[-3.096, 0, 3.0530000000000004], [-3.096, 0, 0], [-3.096, 0, -3.0530000000000004], [0, 0, 3.0530000000000004], [0, 0, 0], [0, 0, -3.0530000000000004], [3.096, 0, 3.0530000000000004], [3.096, 0, 0], [3.096, 0, -3.0530000000000004]], "entrance": [0.0, 0.6400001049041748, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 5, "sealed_panels": 3, "ground_doors": 1}, "approach": [0, 0.06, 4.92]},
	{"file": "peru/selva_comunidad_3.glb", "region": 2, "height": 9.847015380859375, "yaw": 0.0, "style": "comunidad", "zones": ["rural"], "frontage": 8.3, "roof": "pitched", "supports": [[-3.5690000000000004, 0, 3.2465], [-3.5690000000000004, 0, 0], [-3.5690000000000004, 0, -3.2465], [0, 0, 3.2465], [0, 0, 0], [0, 0, -3.2465], [3.5690000000000004, 0, 3.2465], [3.5690000000000004, 0, 0], [3.5690000000000004, 0, -3.2465]], "entrance": [0.0, 0.6400001049041748, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 18, "sealed_panels": 8, "ground_doors": 1}, "approach": [0, 0.06, 5.1450000000000005]},
	{"file": "peru/selva_belen_0.glb", "region": 2, "height": 6.1209917068481445, "yaw": 0.0, "style": "belen", "zones": ["ribereno"], "frontage": 5.2, "roof": "pitched", "supports": [[-2.236, 0, 2.666], [-2.236, 0, 0], [-2.236, 0, -2.666], [0, 0, 2.666], [0, 0, 0], [0, 0, -2.666], [2.236, 0, 2.666], [2.236, 0, 0], [2.236, 0, -2.666]], "entrance": [0.0, 1.6400001049041748, 3.5], "foundation_size": [5.2, 6.2], "envelope": {"openings": 9, "sealed_panels": 2, "ground_doors": 1}, "approach": [0, 0.06, 6.15]},
	{"file": "peru/selva_belen_1.glb", "region": 2, "height": 9.35675048828125, "yaw": 0.0, "style": "belen", "zones": ["ribereno"], "frontage": 6.1, "roof": "pitched", "supports": [[-2.6229999999999998, 0, 2.8595], [-2.6229999999999998, 0, 0], [-2.6229999999999998, 0, -2.8595], [0, 0, 2.8595], [0, 0, 0], [0, 0, -2.8595], [2.6229999999999998, 0, 2.8595], [2.6229999999999998, 0, 0], [2.6229999999999998, 0, -2.8595]], "entrance": [0.0, 1.8900001049041748, 3.7249999046325684], "foundation_size": [6.1, 6.65], "envelope": {"openings": 10, "sealed_panels": 4, "ground_doors": 1}, "approach": [0, 0.06, 6.655]},
	{"file": "peru/selva_belen_2.glb", "region": 2, "height": 7.201876640319824, "yaw": 0.0, "style": "belen", "zones": ["ribereno"], "frontage": 7.2, "roof": "pitched", "supports": [[-3.096, 0, 3.0530000000000004], [-3.096, 0, 0], [-3.096, 0, -3.0530000000000004], [0, 0, 3.0530000000000004], [0, 0, 0], [0, 0, -3.0530000000000004], [3.096, 0, 3.0530000000000004], [3.096, 0, 0], [3.096, 0, -3.0530000000000004]], "entrance": [0.0, 2.140000104904175, 3.950000047683716], "foundation_size": [7.2, 7.1000000000000005], "envelope": {"openings": 5, "sealed_panels": 4, "ground_doors": 1}, "approach": [0, 0.06, 7.16]},
	{"file": "peru/selva_belen_3.glb", "region": 2, "height": 10.446976661682129, "yaw": 0.0, "style": "belen", "zones": ["ribereno"], "frontage": 8.3, "roof": "pitched", "supports": [[-3.5690000000000004, 0, 3.2465], [-3.5690000000000004, 0, 0], [-3.5690000000000004, 0, -3.2465], [0, 0, 3.2465], [0, 0, 0], [0, 0, -3.2465], [3.5690000000000004, 0, 3.2465], [3.5690000000000004, 0, 0], [3.5690000000000004, 0, -3.2465]], "entrance": [0.0, 2.390000104904175, 4.175000190734863], "foundation_size": [8.3, 7.550000000000001], "envelope": {"openings": 18, "sealed_panels": 7, "ground_doors": 1}, "approach": [0, 0.06, 7.945]},
]

const SETBACK := 2.0          ## Distancia (m) del borde de la vía al frente de la casa.
const MAX_STEP := .85        ## Reject a lot before producing a huge retaining pedestal.
const STOP_CLEARANCE := 4.0   ## Distancia mínima a una parada (el pasajero espera ahí).
const SIGN_CLEARANCE := 2.5
const GRID := 32.0
const TILE := 256.0           ## Las casas se dibujan por baldosas (MultiMesh) para poder recortarlas.
const VIEW_DISTANCE := 900.0
const TOWN_RADIUS := 260.0    ## Radio alrededor de un pueblo con casas en avenidas y carreteras.

## [{ "model", "region", "position" (centro en el suelo), "yaw", "size" (ancho, alto, fondo), "zone" }]
## zone: "pueblo" (calles), "afueras" (cerca del pueblo), "campo", "chacra".
var houses: Array[Dictionary] = []
var counts := {}             ## región -> cantidad
var _grid := {}              # Vector2i -> índices de houses
var _rng := RandomNumberGenerator.new()
var _world: TerrainWorld
var _models: Array[Dictionary] = []
var _stops: Array[Vector3] = []
var _signs: Array[Vector3] = []
var _catchment := 60000.0

static var _cache := {}


## Carga un modelo: { "parts": [[Mesh, Transform3D], ...] escaladas al alto real, centradas y
## apoyadas en y = 0, "size": Vector3 }.
static func load_model(model: Dictionary) -> Dictionary:
	if _cache.has(model["file"]):
		return _cache[model["file"]]
	var scene: PackedScene = load(DIR + model["file"])
	var root := scene.instantiate()
	var raw: Array = []
	_collect(root, Transform3D.IDENTITY, raw)
	root.free()
	var box := AABB()
	var first := true
	for part: Array in raw:
		var b: AABB = part[1] * (part[0] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s: float = model["height"] / maxf(box.size.y, 0.001)
	var center := box.get_center()
	var fix := Transform3D(Basis(Vector3.UP, model["yaw"]).scaled(Vector3.ONE * s), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -Vector3(center.x, box.position.y, center.z))
	var parts: Array = []
	for part: Array in raw:
		parts.append([part[0], fix * part[1]])
	var size := (Basis(Vector3.UP, model["yaw"]).get_rotation_quaternion() * (box.size * s)).abs()
	var info := {"parts": parts, "size": Vector3(size.x, model["height"], size.z)}
	var entrance: Array=model.get("approach",model.get("entrance",[0,.14,box.size.z*.5]))
	info["entrance"]=fix*Vector3(float(entrance[0]),float(entrance[1]),float(entrance[2]))
	var foundation: Array=model.get("foundation_size",[box.size.x,box.size.z])
	info["foundation_size"]=Vector2(float(foundation[0])*s,float(foundation[1])*s)
	info["foundation_center"]=fix*Vector3.ZERO
	var supports: Array[Vector3]=[]
	for point: Array in model.get("supports",[]):supports.append(fix*Vector3(float(point[0]),float(point[1]),float(point[2])))
	info["supports"]=supports
	_cache[model["file"]] = info
	return info


static func _collect(node: Node, xf: Transform3D, out: Array) -> void:
	var t := xf * (node as Node3D).transform if node is Node3D else xf
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([(node as MeshInstance3D).mesh, t])
	for c in node.get_children():
		_collect(c, t, out)


func clear() -> void:
	houses.clear()
	counts.clear()
	_grid.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()  # Diferido: puede haber cuerpos en medio de un paso de física.


## Reparte las casas sobre el mapa de world.
func build(world: TerrainWorld, world_seed: int, density := 1.0) -> void:
	clear()
	if density <= 0.0:
		return
	_world = world
	_rng.seed = hash("casas-%d" % world_seed)
	_models.clear()
	for m in MODELS:
		var info := load_model(m)
		_models.append({"model": m, "size": info["size"]})
	_stops.clear()
	for lm in world.get_landmarks():
		_stops.append(lm["position"])
	_signs = world.get_sign_positions()
	if world.generator != null and world.generator.get("river_catchment") != null:
		_catchment = float(world.generator.get("river_catchment"))
	var towns := world.get_town_centers()
	var near_town := func(p: Vector3) -> bool:
		for t in towns:
			if Vector2(p.x - t.x, p.z - t.z).length() < TOWN_RADIUS:
				return true
		return false
	var roads := world.get_roads()
	# Primero las calles del pueblo (fila continua), luego afueras y campo.
	for road in roads:
		if road["kind"] == 3:
			_line(road, "pueblo", Vector2(0.4, 2.5) / density, near_town)
	for road in roads:
		if road["kind"] == 1 or road["kind"] == 2:
			_line(road, "afueras", Vector2(6.0, 22.0) / density, near_town)
			_line(road, "campo", Vector2(140.0, 420.0) / density, near_town)
		elif road["kind"] == 0:
			_line(road, "campo", Vector2(90.0, 260.0) / density, near_town)
			_farm(road)
	_hillsides()
	_commit()

func _hillsides() -> void:
	var choices:=_models.filter(func(item):return int(item.model.region)==0 and "ladera" in item.model.zones)
	if choices.is_empty():return
	var placed:=0
	for road: Dictionary in _world.get_roads():
		var path: PackedVector3Array=road.path
		for i in range(2,path.size()-2,3):
			if placed>=70:return
			var p:=path[i]
			if _world.get_biome(p.x,p.z).max_axis_index()!=0:continue
			var direction: Vector3=(path[i+1]-path[i-1]).normalized();direction.y=0
			var side:=direction.cross(Vector3.UP).normalized()
			for sign in [-1.0,1.0]:
				for setback in [10.0,13.0,16.0]:
					var center: Vector3=p+side*sign*setback
					if not _world.is_inside(center.x,center.z) or _world.get_biome(center.x,center.z).max_axis_index()!=0:continue
					var ground:=_world.get_height(center.x,center.z)
					if ground-p.y<.65 or ground-p.y>4.0 or _world.is_water(center.x,center.z):continue
					var m: Dictionary=choices[_rng.randi()%choices.size()];var size: Vector3=m.size
					var yaw:=atan2(-side.x*sign,-side.z*sign)
					# Terrace footprints must still fit the bank; access is on foot via stairs.
					var lo:=INF;var hi:=-INF;var valid:=true
					for q in _corners(center,yaw,size,.5):
						if not _world.is_inside(q.x,q.y) or _world.get_offroad_amount(q.x,q.y)<.99 or _world.is_water(q.x,q.y):valid=false;break
						var h:=_world.get_height(q.x,q.y);lo=minf(lo,h);hi=maxf(hi,h)
					if not valid or hi-lo>1.20:continue
					# Match the actual lot rectangles rather than a large clearance
					# circle, which left artificial gaps between hillside neighbours.
					var footprint:=_corners(center,yaw,size,.06);var occupied:=false
					for neighbor: int in _near(center,24):
						var other: Dictionary=houses[neighbor]
						if not Geometry2D.intersect_polygons(footprint,_corners(other.position,other.yaw,other.size,.06)).is_empty():occupied=true;break
					if occupied:continue
					var position:=Vector3(center.x,hi+.08,center.z)
					var entry: Vector3=Transform3D(Basis(Vector3.UP,yaw),position)*load_model(m.model).entrance
					var access:=PeruHouseAccess.plan(_world,p+side*sign*(float(road.width)*.5+.30),entry)
					if access.is_empty():continue
					_add({"model":_models.find(m),"region":0,"position":position,"yaw":yaw,"size":size,"zone":"ladera","district":"ladera","radius":Vector2(size.x,size.z).length()*.5,"access":access})
					placed+=1


## Casas a los dos lados de una vía, separadas por gap (m, rango al azar).
func _line(road: Dictionary,zone: String,gap: Vector2,near_town: Callable) -> void:
	var path: PackedVector3Array=road.path
	var cumulative:=PackedFloat32Array([0.0])
	for i in range(1,path.size()):cumulative.append(cumulative[i-1]+path[i-1].distance_to(path[i]))
	if cumulative.size()<2:return
	for side in [-1.0,1.0]:
		var cursor:=5.0;var previous_s:=-INF;var previous_width:=0.0
		var pending: Dictionary={}
		while cursor<cumulative[cumulative.size()-1]-4:
			var index:=1
			while index<cumulative.size()-1 and cumulative[index]<cursor:index+=1
			var t:=clampf((cursor-cumulative[index-1])/maxf(.01,cumulative[index]-cumulative[index-1]),0,1)
			var p:=path[index-1].lerp(path[index],t)
			var urban: bool=near_town.call(p)
			if (zone=="afueras" and not urban) or (zone=="campo" and urban):cursor+=6;continue
			var candidates:=_choices(p,zone)
			if candidates.is_empty():cursor+=5;continue
			if pending.is_empty() or not candidates.has(pending):pending=candidates[_rng.randi()%candidates.size()]
			var model: Dictionary=pending
			var district:=PeruDistricts.at(_world,p)
			var dense:=bool(district.dense) and urban
			var separation:=.06 if dense else _rng.randf_range(.8,3.0) if urban else _rng.randf_range(gap.x,gap.y)
			var required:=previous_s+previous_width*.5+float(model.size.x)*.5+separation
			if cursor<required:cursor=required;continue
			var direction: Vector3=(path[index]-path[index-1]).normalized()
			var local:=PackedVector3Array([p-direction,p,p+direction])
			var placed:=_try_house(local,1,side,float(road.width)*.5,zone,model)
			if placed.is_empty():
				# A large tower that cannot fit this lot must not prevent every
				# smaller compatible building from being considered along the street.
				pending={};cursor+=1.5;continue
			previous_s=cursor;previous_width=float(model.size.x)
			cursor+=previous_width*.5+2.5+separation
			pending={}

func _choices(p: Vector3,zone: String) -> Array:
	var district:=PeruDistricts.at(_world,p)
	var selected:=str(district.zone) if zone not in ["campo","chacra"] else "rural"
	return _models.filter(func(item):return int(item.model.region)==int(district.region) and selected in item.model.get("zones",["rural"]))

## La casa de la chacra al final de una trocha sin salida.
func _farm(road: Dictionary) -> void:
	var path: PackedVector3Array = road["path"]
	if path.size() < 4:
		return
	for i in [path.size() - 2, 1]:
		if _world.get_offroad_amount(path[i].x, path[i].z) < 0.5 and not _try_house(path, i, 1.0 if _rng.randf() < 0.5 else -1.0, road["width"] * 0.5, "chacra").is_empty():
			return


func _try_house(path: PackedVector3Array, i: int, side: float, half: float, zone: String,preferred: Dictionary={}) -> Dictionary:
	var p := path[i]
	var a := path[maxi(i - 2, 0)]
	var b := path[mini(i + 2, path.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < 0.5:
		return {}
	dir = dir.normalized()
	var out := Vector3(-dir.z, 0.0, dir.x) * side  # Hacia afuera de la vía.
	var region := _world.get_biome(p.x, p.z).max_axis_index()
	var choices:=_choices(p,zone)
	if choices.is_empty():return {}
	var m: Dictionary=preferred if not preferred.is_empty() else choices[_rng.randi()%choices.size()]
	var size: Vector3 = m["size"]
	# El frente (+Z del modelo) mira a la vía: el ancho va a lo largo de la vía.
	var center := p + out * (half + SETBACK + size.z * 0.5)
	var yaw := atan2(-out.x, -out.z)
	if _world.get_biome(center.x, center.z).max_axis_index() != region:
		return {}  # En el borde entre regiones.
	var ground := _fits(center, yaw, size)
	if is_nan(ground):
		return {}
	var position:=Vector3(center.x,ground,center.z)
	var entry: Vector3=Transform3D(Basis(Vector3.UP,yaw),position)*load_model(m.model).entrance
	var access:=PeruHouseAccess.plan(_world,p+out*(half+.30),entry)
	if access.is_empty():return {}
	var h := {"model": _models.find(m), "region": region, "position": Vector3(center.x, ground, center.z),
		"yaw": yaw, "size": size, "zone": zone, "district":"rural" if zone in ["campo","chacra"] else PeruDistricts.at(_world,p).zone, "radius": Vector2(size.x, size.z).length() * 0.5}
	h["access"]=access
	_add(h)
	return h


## Altura del piso de la casa (lo más alto del suelo bajo ella: nada queda enterrado; el zócalo
## cubre el desnivel) o NAN si no cabe ahí.
func _fits(center: Vector3, yaw: float, size: Vector3,max_step:=MAX_STEP) -> float:
	if not _world.is_inside(center.x, center.z):
		return NAN
	var basis := Basis(Vector3.UP, yaw)
	# Descarte rápido: centro y esquinas libres.
	for c: Vector3 in [Vector3.ZERO, Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		var q := center + basis * (c * Vector3(size.x, 0.0, size.z))
		if not _world.is_inside(q.x, q.z) or _world.get_offroad_amount(q.x, q.z) < 0.99 or _world.get_reach_id(q.x, q.z) < 0:
			return NAN
	var radius := Vector2(size.x, size.z).length() * 0.5
	var mine := _corners(center, yaw, size, 0.015)
	for k in _near(center, radius + 12.0):
		var o: Dictionary = houses[k]
		var reach: float = radius + o["radius"] + 1.0
		if Vector2(o["position"].x - center.x, o["position"].z - center.z).length_squared() > reach * reach:
			continue
		if not Geometry2D.intersect_polygons(mine, _corners(o["position"], o["yaw"], o["size"], 0.015)).is_empty():
			return NAN
	var lo := INF
	var hi := -INF
	var margin := 0.6
	# A fixed 4x4 test could miss a narrow road between samples under a large
	# tower. Keep sample spacing below the narrowest street's width.
	var nx:=maxi(4,ceili((size.x+margin)/2.0)+1)
	var nz:=maxi(4,ceili((size.z+margin)/2.0)+1)
	for ix in nx:
		for iz in nz:
			var local := Vector3((float(ix) / (nx-1) - 0.5) * (size.x + margin), 0.0, (float(iz) / (nz-1) - 0.5) * (size.z + margin))
			var q := center + basis * local
			if not _world.is_inside(q.x, q.z) or _world.get_offroad_amount(q.x, q.z) < 0.99:
				return NAN
			if _world.get_reach_id(q.x, q.z) < 0:
				return NAN
			if _world.is_water(q.x,q.z):return NAN
			var y := _world.get_height(q.x, q.z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo > max_step:
		return NAN
	# Lejos del agua: los cauces son angostos, se revisa más tupido y con 3 m de margen.
	for ix in 5:
		for iz in 5:
			var q := center + basis * Vector3((ix / 4.0 - 0.5) * (size.x + 6.0), 0.0, (iz / 4.0 - 0.5) * (size.z + 6.0))
			if _world.is_water(q.x,q.z) or _world.get_drainage(q.x, q.z) >= _catchment * 0.3:
				return NAN
	lo = hi
	for s in _stops:
		if Vector2(s.x - center.x, s.z - center.z).length() < radius + STOP_CLEARANCE:
			# Solo si la parada cae de verdad cerca del rectángulo (no de su círculo).
			if _rect_distance(center, yaw, size, s) < STOP_CLEARANCE:
				return NAN
	for s in _signs:
		if _rect_distance(center, yaw, size, s) < SIGN_CLEARANCE:
			return NAN
	return lo + 0.08


func _rect_distance(center: Vector3, yaw: float, size: Vector3, q: Vector3) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * Vector3(q.x - center.x, 0.0, q.z - center.z)
	var dx := maxf(absf(local.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - size.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


static func _corners(center: Vector3, yaw: float, size: Vector3, grow := 0.0) -> PackedVector2Array:
	var basis := Basis(Vector3.UP, yaw)
	var out := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := center + basis * Vector3(c.x * (size.x * 0.5 + grow), 0.0, c.y * (size.z * 0.5 + grow))
		out.append(Vector2(q.x, q.z))
	return out


func _add(h: Dictionary) -> void:
	var k := houses.size()
	houses.append(h)
	counts[StopNames.REGIONS[h["region"]]] = counts.get(StopNames.REGIONS[h["region"]], 0) + 1
	var key := Vector2i(floori(h["position"].x / GRID), floori(h["position"].z / GRID))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(k)


## Índices de casas con centro a menos de r de p (aprox., por celdas).
func _near(p: Vector3, r: float) -> Array:
	var out := []
	var n := ceili(r / GRID)
	var c0 := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			out.append_array(_grid.get(c0 + Vector2i(dx, dz), []))
	return out


## true si el punto (x, z) cae dentro de una casa (agrandada en grow m).
func is_blocked(x: float, z: float, grow := 0.0) -> bool:
	var q := Vector3(x, 0.0, z)
	for k in _near(q, 20.0):
		var h: Dictionary = houses[k]
		if _rect_distance(h["position"], h["yaw"], h["size"], q) <= grow:
			return true
	return false


## Círculos [x, z, radio] que cubren cada casa (para quitar los árboles de adentro).
func blockers() -> Array:
	var out := []
	for h in houses:
		out.append([h["position"].x, h["position"].z, Vector2(h["size"].x, h["size"].z).length() * 0.5 + 1.0])
	return out


# --- Dibujo y colisión ----------------------------------------------------------------

const PLINTH_COLOR := Color(0.46, 0.43, 0.39)

func _commit() -> void:
	# Por baldosa y por pieza de modelo: un MultiMesh con todas las casas de ese modelo.
	var tiles := {}  # Vector2i -> { [modelo, pieza]: Array[Transform3D] }
	var plinths := {}  # Vector2i -> Array[Transform3D] (cajas unitarias)
	var foundations: Dictionary={}
	var foundation_tiles: Dictionary={}
	var railings: Array=[]
	var bodies := Node3D.new()
	bodies.name = "Colision"
	add_child(bodies)
	for h in houses:
		var key := Vector2i(floori(h["position"].x / TILE), floori(h["position"].z / TILE))
		if not tiles.has(key):
			tiles[key] = {}
			plinths[key] = []
			var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);foundations[key]=surface
		var xf := Transform3D(Basis(Vector3.UP, h["yaw"]), h["position"])
		var info := load_model(_models[h["model"]]["model"])
		for k in info["parts"].size():
			var id := Vector2i(h["model"], k)
			if not tiles[key].has(id):
				tiles[key][id] = []
			tiles[key][id].append(xf * (info["parts"][k][1] as Transform3D))
		var size: Vector3 = h["size"]
		if h.has("access"):
			plinths[key].append_array(h.access.blocks)
			if float(h.access.rise)>.55:
				var route: Array=h.access.route
				for j in range(1,route.size()):
					var a: Vector3=route[j-1];var b: Vector3=route[j]
					var side:=(b-a).cross(Vector3.UP).normalized()*.63
					for sign: float in [-1,1]:
						var p:=a+side*sign+Vector3.UP*.95;var q:=b+side*sign+Vector3.UP*.95
						var direction:=q-p
						if direction.length()>.001:railings.append(Transform3D(Basis.looking_at(direction.normalized(),Vector3.UP).scaled(Vector3(.045,.045,direction.length())),(p+q)*.5))
						if j%3==1:railings.append(Transform3D(Basis.from_scale(Vector3(.045,.95,.045)),a+side*sign+Vector3.UP*.475))
		# Zócalo de piedra desde 0.3 m bajo el punto más bajo hasta el piso de la casa.
		var drop: float = h["position"].y - _lowest_under(h) + 0.3
		var plinth_h := maxf(drop, 0.0) + 0.25
		if not info.get("supports",[]).is_empty():
			for support: Vector3 in info.supports:
				var top: Vector3=xf*support
				var bottom:=_world.get_height(top.x,top.z)-.15
				var height:=maxf(.15,top.y-bottom)
				plinths[key].append(Transform3D(Basis.from_scale(Vector3(.24,height,.24)),Vector3(top.x,top.y-height*.5,top.z)))
		else:
			_append_foundation(foundations[key],xf,info)
			foundation_tiles[key]=true
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x * 0.92, size.y, size.z * 0.92)
		shape.shape = box
		body.transform = xf
		shape.position.y = size.y * 0.5
		body.add_child(shape)
		bodies.add_child(body)
	var plinth_mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLINTH_COLOR
	mat.albedo_texture=load("res://assets/houses/peru/materials/sierra/rustic_stone_wall.jpg")
	mat.albedo_color=Color.WHITE
	mat.uv1_triplanar=true;mat.uv1_world_triplanar=true;mat.uv1_scale=Vector3.ONE*.5
	mat.roughness = 0.95
	plinth_mesh.material = mat
	for key: Vector2i in tiles:
		for id: Vector2i in tiles[key]:
			var part: Array = load_model(_models[id.x]["model"])["parts"][id.y]
			_multimesh("Casas_%d_%d_%d_%d" % [key.x, key.y, id.x, id.y], part[0], tiles[key][id])
		_multimesh("Zocalos_%d_%d" % [key.x, key.y], plinth_mesh, plinths[key])
		if not foundation_tiles.has(key):continue
		var surface: SurfaceTool=foundations[key]
		surface.generate_normals();var mesh:=surface.commit()
		if mesh:
			mesh.surface_set_material(0,mat)
			var instance:=MeshInstance3D.new();instance.name="CimentacionAjustada_%d_%d"%[key.x,key.y];instance.mesh=mesh;add_child(instance)
	var rail_mesh:=BoxMesh.new();var rail_material:=StandardMaterial3D.new();rail_material.albedo_color=Color("3b4140").srgb_to_linear();rail_material.metallic=.5;rail_mesh.material=rail_material
	_multimesh("PasamanosDeAccesos",rail_mesh,railings)

func _append_foundation(surface: SurfaceTool,xf: Transform3D,info: Dictionary) -> void:
	var size: Vector2=info.foundation_size
	var center: Vector3=info.foundation_center
	var corners: Array[Vector3]=[]
	for c in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		corners.append(xf*(center+Vector3(c.x*size.x*.5,.035,c.y*size.y*.5)))
	for i in 4:
		var a: Vector3=corners[i];var b: Vector3=corners[(i+1)%4]
		var count:=maxi(1,ceili(a.distance_to(b)/.65))
		for j in count:
			var p:=a.lerp(b,float(j)/count);var q:=a.lerp(b,float(j+1)/count)
			var low_p:=Vector3(p.x,_world.get_height(p.x,p.z)-.15,p.z)
			var low_q:=Vector3(q.x,_world.get_height(q.x,q.z)-.15,q.z)
			for point: Vector3 in [p,low_p,low_q,p,low_q,q]:
				surface.set_uv(Vector2(point.x+point.z,point.y)*.5);surface.add_vertex(point)


## Altura más baja del suelo bajo una casa (esquinas y centro).
func _lowest_under(h: Dictionary) -> float:
	var lo: float = h["position"].y
	for c in _corners(h["position"], h["yaw"], h["size"], 0.1):
		lo = minf(lo, _world.get_height(c.x, c.y))
	return lo


func _multimesh(node_name: String, mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_end = VIEW_DISTANCE
	mmi.visibility_range_end_margin = 40.0
	add_child(mmi)
