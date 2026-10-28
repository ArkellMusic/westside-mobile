# WESTSIDE LEGACY Mobile

*Respect Is Earned. Legacy Is Taken.* — Vanta Studio

Versión para iPhone del juego de mundo abierto WESTSIDE LEGACY, hecha en **Godot 4.7**. El prototipo actual empieza en Westbrook (South Veyra) con la cinemática de apertura y la misión 01 «Back to Westbrook».

- Arquitectura, decisiones y estado por fases: [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md)
- Instalar el IPA en el iPhone desde Windows: [`docs/INSTALAR_EN_IPHONE.md`](docs/INSTALAR_EN_IPHONE.md)
- Controles: [`docs/CONTROLES.md`](docs/CONTROLES.md)
- Biblia de misiones, mapas y fichas de personajes: [`docs/`](docs)

## Abrir el proyecto en el PC

1. Descarga Godot 4.7.2 (estándar, no .NET) desde godotengine.org.
2. Abre Godot → *Importar* → elige `project.godot` de esta carpeta.
3. Pulsa F5 para jugar. Si la gráfica da problemas con Vulkan, abre Godot con `--rendering-driver opengl3`.

## Compilación del IPA

Cada push a `main` ejecuta las pruebas y compila el IPA sin firmar en GitHub Actions (pestaña **Actions** → *Compilar IPA iOS*). El IPA también se publica en la release **Última compilación**.

## Pruebas

```
godot --headless --path . res://tests/test_runner.tscn
```

## Capturas automáticas

```
godot --path . --resolution 1560x720 -- --capture=/ruta/de/salida
```
