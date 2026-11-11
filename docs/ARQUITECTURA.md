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

## Misiones, actividades y animación

- **80 misiones** en `data/missions/m01.json` … `m80.json`, escritas a partir de `tools/biblia_80_misiones.json` con el formato de `docs/MISIONES_FORMATO.md` y comprobadas por `tools/validate_missions.py`. `MissionRunner` ejecuta pasos genéricos: escenas de diálogo con cámara al que habla, llamadas, ir/conducir, contrarreloj, robar coche, pelea, defensa por oleadas, sigilo, persecución a pie, recoger pruebas y perder a la policía. Tras cada misión, `main._offer_next_mission()` marca la siguiente.
- **Enemigos** (`scripts/world/hostiles.gd`): pandilleros, matones y guardias con modelos Mixamo; armados o a puños, en alerta o de guardia, o que huyen.
- **Actividades** (`scripts/world/activities.gd`): contrarreloj, reparto, taxi y guerra de bandas.
- **Animación por código** (`Humanoid.animate`): modelo de marcha con cadencia y zancada según la velocidad, rodilla y tobillo por fases, pelvis y hombros en contrarrotación, inclinación al acelerar y girar, reposo con respiración, gestos al hablar, sacudida al recibir daño, agacharse y suavizado de toda la pose. `tests/shot_anim` saca fotogramas de control.
- Las misiones de San Cordova, Las Brisas, Northpoint y las islas ocurren en esas zonas del mapa del estado, que hoy tienen terreno, carreteras y edificios lejanos pero no el detalle de Westbrook.

## Aspecto visual («look» nítido)

- Cielo despejado procedural de día, niebla y niebla volumétrica muy reducidas y perspectiva aérea azulada solo a lo lejos.
- Luz ambiente mezclada (cielo + color neutro) para que las sombras no queden negras; más saturación y contraste; menos viñeta y bloom.
- Resolución interna más alta (90 % en Alta, 77 % en Media, 75 % en Baja) con FSR más nítido, filtro anisotrópico 16x y sesgo de mipmaps negativo.
- Distancia de dibujado de edificios y mobiliario multiplicada por nivel (x2,2 en Alta, x1,5 en Media) y sombras más lejanas.
- Árboles de patios y del terreno con imágenes de modelos reales en planos cruzados (`TreeCards`).
- **Cielo** (`assets/shaders/sky_clouds.gdshader`): nubes volumétricas por ray marching a un cuarto de resolución (14 / 10 / 6 pasos según calidad, `Settings.cloud_steps()`), sol con corona, luna con relieve y halo, y estrellas. El astro es la luz direccional de la escena, así que las sombras coinciden con el sol o la luna.
- **Chalets** (`CityBuilder._build_house_details`): las casas llevan tejado a dos aguas con teja real (Poly Haven), hastiales, chimenea, porche con columnas, puerta y camino; los garajes, portón seccional.
- **Tiendas** (`Interiors._define_shops`): Veyra Threads (ropa), Fade Kings (barbería) e Ink Saints (tatuajes) ocupan locales de edificios comerciales junto al Veyra Mart, con escaparate, interior y servicio. El taller Vargas Auto Works y Pinta y Listo ya existían.
- Estos ajustes cuestan rendimiento: si en el iPhone no llega a 60 FPS, baja `render_scale()` y `view_distance_scale()` en `scripts/autoload/settings.gd`.

## Estado por fases

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Arquitectura, motor, estructura, compilación iOS | Hecho (falta confirmar el primer IPA en CI) |
| 2 | Westbrook (South Veyra), Mack, cámara, movimiento, controles táctiles | Hecho (personajes procedurales provisionales) |
| 3 | Coche conducible, entrar y salir | Hecho |
| 4 | Misión 01 completa con diálogos, recompensa y guardado | Hecho |
| 5 | HUD, radar, mapa (barrio y estado), pausa, ajustes | Hecho |
| 6 | Personajes, tráfico, bandas, radio, más contenido | Parcial: 7 personajes, tráfico/peatones, radio, combate (puños y pistola), policía con estrellas y robo de coches |
| 7 | Optimizar, firmar, instalar y probar en iPhone | Pendiente: requiere tu iPhone |
| 8 | IPA final y documentación | Documentación hecha; IPA final pendiente |

## Pendiente y limitaciones honestas

- **Modelos 3D reales:** los personajes y coches son procedurales y siguen las fichas (ropa, colores, accesorios). Para sustituirlos hacen falta GLB con esqueleto humanoide (por ejemplo, exportados de tus FBX).
- **Voces en inglés:** los diálogos están escritos (EN + subtítulos ES), pero no hay audio grabado. Hay un punto de enganche en `main.gd → on_dialogue_line()`.
- **Radio y música:** pendiente de pistas originales o con licencia.
- **Combate y policía** (`scripts/player/combat.gd`, `scripts/world/police.gd`, `scripts/audio/sfx.gd`): puños y pistola con apuntado automático, peatones que huyen, agentes que llegan en patrulla, detienen con 1 estrella y disparan con 2 o más; las estrellas bajan cuando nadie te ve. Se puede robar cualquier coche del tráfico. **Testigos y reconocimiento** (`scripts/world/crime.gd`): la búsqueda nace de un testigo que llama o de un agente que te ve, con una descripción de ropa y coche; quien no encaja con ella solo es reconocido de cerca. La ropa de Mack se tiñe con `assets/shaders/outfit.gdshader` (5 conjuntos). La misma lógica está portada a Unreal en el plugin `WestsideCrime` del repositorio de PC. Las patrullas persiguen en coche con IA de conducción sobre la misma física que el coche del jugador (`Police._update_pursuits`). Pendiente: más armas, tiendas de munición y animaciones de captura de movimiento para Mack (ahora sus gestos de combate son poses por código).
- **El resto del estado:** San Cordova, Las Brisas, Northpoint, Bahía Solana y las islas solo existen como datos y en el mapa (bloqueadas por misión).
