# WESTSIDE LEGACY Mobile — Propuesta técnica y arquitectura

## Decisión de motor: Godot 4.7 (versión móvil) + Unreal 5.8 (versión PC)

La versión de PC sigue en Unreal Engine 5.8. Para iPhone, la versión móvil se hace en **Godot 4.7** por tres razones:

1. **IPA sin Mac.** Godot puede exportar el proyecto de Xcode desde la línea de comandos y GitHub Actions ofrece máquinas macOS con Xcode. Así se obtiene un IPA sin tener un Mac. Unreal para iOS requiere un Mac (local o remoto con *Remote Build*) con el motor instalado, y no cabe en GitHub Actions.
2. **Tu PC.** El iMac 2013 (GT 755M) no llega a los requisitos del editor de UE5 con soltura. Godot 4.7 funciona bien en ese equipo (si Vulkan da problemas: `--rendering-driver opengl3`).
3. **Rendimiento móvil.** El renderizador *Mobile* de Godot usa Metal en iOS y está pensado para este hardware. El iPhone 16e (A18, 8 GB) va sobrado para el prototipo.

**Coste:** son dos bases de código. Lo que sí se comparte son los recursos: modelos FBX/GLB, texturas, audio, el guion, las misiones (JSON) y el diseño del mapa. Los `.uasset` de Unreal no se pueden reutilizar directamente; hay que exportarlos a FBX/GLB desde Unreal.

## Estructura del proyecto

```
project.godot            Ajustes (renderizador Mobile, horizontal, Jolt Physics)
export_presets.cfg       Preset iOS (solo proyecto de Xcode; se firma después)
scenes/main.tscn         Escena principal (todo se construye por código)
scripts/
  autoload/              EventBus, GameData, GameState, SaveSystem, Settings, Controls
  world/                 CityLayout (trazado), CityBuilder (genera Westbrook), tráfico,
                         peatones, cielo/iluminación, MeshBuilder
  characters/            Humanoid (personajes procedurales), NPC
  player/                Player (Mack a pie), CameraRig (3.ª persona y cinemáticas)
  vehicles/              Car (física VehicleBody3D), CarModel, BusModel
  missions/              MissionRunner (motor de misiones por pasos), IntroCinematic
  ui/                    HUD, radar, mapa, pausa, ajustes, menú principal, controles táctiles
  tools/capture.gd       Recorrido automático que genera capturas
data/                    zonas, bandas, personajes y misiones en JSON
tests/                   Pruebas automáticas (CI)
docs/                    Mapas de referencia, biblia de misiones, fichas de personajes
```

**Principio modular:** el contenido vive en `data/`. Las misiones son listas de pasos (`cutscene`, `dialogue`, `talk`, `goto`, `drive_to`, `scripted_drive`, `checkpoint`, `reward`…). Añadir las misiones 02–80 es sobre todo escribir JSON y crear los lugares que necesitan.

## Cómo se obtiene el IPA

1. Cada `push` a `main` lanza `.github/workflows/build-ios.yml`.
2. **Pruebas (Linux):** Godot importa el proyecto y ejecuta `tests/test_runner.tscn` (datos, desbloqueos, guardado, ciudad, física del coche).
3. **iOS (macOS):** Godot exporta el proyecto de Xcode → `xcodebuild` compila **sin firma** → se empaqueta `WestsideLegacy.ipa` → se sube como *artifact* y como *release* «Última compilación».
4. **Firma e instalación:** con **Sideloadly** en Windows y tu Apple ID (ver `docs/INSTALAR_EN_IPHONE.md`).
   - Apple ID gratuito: la app caduca a los 7 días y hay que volver a firmarla.
   - Apple Developer Program (99 €/año): firma de un año, TestFlight y App Store. Hacen falta un certificado de distribución y un perfil de aprovisionamiento para `com.vantastudio.westsidelegacy`.

**Qué se puede hacer solo con Windows:** todo el desarrollo, las pruebas y la firma con Sideloadly. **Qué necesita macOS:** compilar con Xcode, que lo hace GitHub Actions en remoto.

## Rendimiento (objetivo: 60 FPS estables en iPhone 16e)

- Edificios, palmeras, farolas y coches aparcados en **MultiMesh** (pocas llamadas de dibujo).
- Fachadas con ventanas **por shader**: sin texturas y casi sin memoria.
- Colisiones con cajas simples; tráfico y peatones cinemáticos, sin física.
- Calidad Baja / Media / Alta: escala de render, sombras, MSAA, densidad de tráfico y peatones, límite de 30/60 FPS.
- Texturas en ETC2/ASTC cuando entren los modelos reales.

## Estado por fases

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Arquitectura, motor, estructura, compilación iOS | Hecho (falta confirmar el primer IPA en CI) |
| 2 | Westbrook (South Veyra), Mack, cámara, movimiento, controles táctiles | Hecho (personajes procedurales provisionales) |
| 3 | Coche conducible, entrar y salir | Hecho |
| 4 | Misión 01 completa con diálogos, recompensa y guardado | Hecho |
| 5 | HUD, radar, mapa (barrio y estado), pausa, ajustes | Hecho |
| 6 | Personajes, tráfico, bandas, radio, más contenido | Parcial: 7 personajes y tráfico/peatones; sin radio ni combate |
| 7 | Optimizar, firmar, instalar y probar en iPhone | Pendiente: requiere tu iPhone |
| 8 | IPA final y documentación | Documentación hecha; IPA final pendiente |

## Pendiente y limitaciones honestas

- **Modelos 3D reales:** los personajes y coches son procedurales y siguen las fichas (ropa, colores, accesorios). Para sustituirlos hacen falta GLB con esqueleto humanoide (por ejemplo, exportados de tus FBX).
- **Voces en inglés:** los diálogos están escritos (EN + subtítulos ES), pero no hay audio grabado. Hay un punto de enganche en `main.gd → on_dialogue_line()`.
- **Radio y música:** pendiente de pistas originales o con licencia.
- **Combate y salud:** la barra de salud existe; el combate no está implementado todavía.
- **El resto del estado:** San Cordova, Las Brisas, Northpoint, Bahía Solana y las islas solo existen como datos y en el mapa (bloqueadas por misión).
