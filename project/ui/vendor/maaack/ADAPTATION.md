# Base utilizada: Maaack's Menus Template

Original: https://github.com/Maaack/Godot-Menus-Template
Commit consultado: `1b7578ae48224bd301d0f196997d7def93a15096`.
Archivo: `addons/maaacks_menus_template/base/nodes/menus/main_menu/main_menu.tscn`.
Autor: Marek Belski / Maaack. Licencia MIT adjunta.

`main_menu.tscn.upstream.txt` conserva la escena descargada sin cambios.
`scenes/pregame_shell.tscn` es una adaptación real de esa escena: conserva BackgroundTextureRect,
MenuContainer, TitleMargin/TitleContainer/TitleLabel, MenuButtonsMargin/MenuButtonsContainer,
la lista vertical de botones y VersionMargin/VersionContainer/VersionLabel.
Se retiraron scripts/autoloads del paquete y su confirmación de salida para conectarlos
al cargador TerrainWorld existente. Se añadió el botón Controles. No se instaló el plugin completo.
La distribución portada + lista vertical + submenús reproduce la base; colores, fotografía,
texto y tamaños adaptables son cambios del proyecto. El antiguo dibujo de taxi no se utiliza.
