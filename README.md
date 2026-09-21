# (Nombre WIP) Crazy Mototaxi

Este nombre no es el final, porque viene con copyright. Más adelante se le va a poner un mejor nombre.

*Integrantes*:
- Rodrigo Félix Meza Gavilán
- Josep Ratzinger Castro Ferrer
- Jose Francisco Wong Orrillo
- Jose Joaquín Osnayo Matos

*Curso*: CS4016 - Computación Gráfica

*Ciclo*: 2026 - 2

*Universidad*: UTEC

*In memoriam Daniel Casquino*

---

El presente repositorio contiene todos los archivos utilizados para el desarrollo del proyecto final del curso. Este fue creado a partir de un template de Godot para que pueda funcionar con C++. Nativamente, Godot trabaja con archivos `.gd` para la construcción de scripts. 

Sin embargo, ya que este proyecto va a requerir de matemática y cálculos pesados, la mejor manera de agilizarlo fue su integración con C++ mediante GDExtension.

Básicamente, este template va a agarrar los archivos `.h` y `.cpp` que contengan el código principal del proyecto, que tenga que ver con la generación procedural de terreno y esas cosas. De ahí, los va a compilar en librerías `.dll` que las va a poder leer Godot y los archivos `.gd` para la construcción del juego. 

La ventaja de hacer esto es que el compilado del proyecto se vuelve rapidísimo, el código al que le importa los evaluadores del proyecto se vuelve más legible, queda mejor dividido cuál es la implementación propia del curso, y el rendimiento del producto final se vuelve más estable.

#### Requisitos de instalación

Se necesitan los siguientes programas:

- Godot Engine 4 (instálalo desde Steam)
- Visual Studio Build Tools (No es necesario que se traigan el IDE entero, solo las build tools)
- Python 3 (para pipear el sconstruct)
- SConstruct (`pip install scons`)
- Git (versionado)

#### Dónde va cada cosa

En este repo las cosas se trabajan de la siquiente manera:

- **`src/`**

Aquí, van los archivos C++ del tópico de nuestro proyecto. Por el momento, solo van una generación básica de ruido del terreno, construcción de caminos mediante A*, y el ensamblado del mesh que leerá Godot para el mapa de juego. 

**IMPORTANTE**: aunque tanto `register_types.h` como `register_types.cpp` vengan del template original, son esenciales para el compilado del proyecto. NO LOS VAYAN A ELIMINAR. LAS INSTRUCCIONES DE CUÁNDO MODIFICAR ESTOS ARCHIVOS SE ENCUENTRAN MÁS ADELANTE.

- **`project/`**

Este realmente es el directorio del proyecto Godot. Desde el editor, es lo único que el motor va a ver. El único código que van a tocar de acá es el `scripts/chunk_mesh.gd`, donde se encuentra el script que genera la escena `terrain_demo.tscn` con el mesh de terreno generado.

Algo adicional, `project.godot` es a donde tiene que apuntar el editor cuando abran el proyecto por primera vez. Para que la integración con C++, se pueda linkear correctamente, pueden consultar `bin/example.gdextension` (no creo que tengan que tocar este archivo, debería funcionar así nomás).

- **Y el resto del proyecto?**

No lo tocan, eso es de la magia del template. Yo no lo he tocado y me ha funcionado de maravilla. Cualquier error que se produzca, se encuentran en los archivos mencionados anteriormente.

---

### CÓMO EJECUTAR ESTE PROYECTO

1. Instalan los requisitos.
2. Asumiendo que su compu es 64 bits, abren **x64 Native Tools Command Prompt for VS**
3. Se dirigen a la ubicación del repo del proyecto
4. En el root (no en las subcarpetas `project`, ni `src`, ni `godot-cpp`, ninguna de esas), hacen esto: 

```
git submodule update --init --recursive
```

y luego esto

```
scons api_version=4.7 -j8
```
Eso debería compilar los archivos C++ que necesita el proyecto. LA PRIMERA VEZ que hagan esto va a demorar. Las siguientes veces va a ser mas rápido.

5. Abren Godot Engine, y hacen click en "Import Project" o "Importar Proyecto"
6. Van a la ubicación del repo, entran a `project`, y hacen click en `project.godot`
7. Aceptan el mensajito, les va a abrir el repo
8. Les va a cargar ahí nomas el terrenito generado de la escena.

### DESDE EL EDITOR GODOT

* Si es que no se les abre la escena, hacen doble click en `terrain_demo.tscn` para que les abra. Debe estar abierta desde la vista "3D" de la barrita de arriba.

* En esa barrita van a ver algo que se llama "Script". Ahí van a ver el script que está ejecutando el Godot: `chunk_mesh.gd`.

* Si quieren hacer cambios desde el editor, pueden modificar el script, y le dan a guardar script con click derecho sobre este. Otra alternativa es que desde la vista de jerarquía de la izquierda, van a poder seleccionar el objeto "Terrain". En las propiedades bajo la sección "chunk_mesh.gd", van a poder configurar el tamaño del grid, la semilla (si quieren generar un mapita diferente), como cositas de la red de caminos. 

* Cualquier modificación les va a pedir luego que guarden la escena con "Save Scene". Una vez guardada, van a "Scene/Reload Saved Scene". Se esperan un ratito, hasta que le carguen los cambios.

### CUANDO LES TOQUE EDITAR

1. Se van al root del repo.
2. Entran al `src/`.
3. Hacen sus cambios respectivos del C++. 
4. Si crean una nueva clase, TIENEN QUE REGISTRARLA:
  a. En `register_types.cpp`, agregan el `#Include "tu_clase.h"`.
  b. Tambienmodifican esta parte del código:

```cpp
void initialize_gdextension_types(ModuleInitializationLevel p_level)
{
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(TerrainNoise);
	GDREGISTER_CLASS(RoadNetwork);
	GDREGISTER_CLASS(TerrainMesh);

  // Para registrar tu clase
  GDREGISTER_CLASS(TuClase);
}
```

5. Vuelven al root del proyecto y recompilan los dlls:

```
scons api_version=4.7 -j8
```

6. Entran al Godot y abren el proyecto

7. Hacen los cambios respectivos dentro de los scripts `.gd` (puede que sea `scripts/chunk_mesh.gd`). 

8. Guardan la escena.

9. `Scene/Reload Saved Scene`

10. Y ya estaría.
