# Formato de misión (data/missions/mNN.json)

Cada misión es un JSON con cabecera y una lista de pasos que `MissionRunner` ejecuta en orden.
La fuente de diseño es `tools/biblia_80_misiones.json` (la biblia: premisa, mecánicas y 7 fases).

```json
{
  "id": "m02", "number": 2, "title": "OLD KEYS", "title_es": "Llaves viejas", "act": "ACTO I",
  "start": "mack_door",
  "steps": [ ... ]
}
```

## Puntos (campos `at`, `target`, `start`)

- Nombre de lugar de Westbrook: `terminal`, `veyra_mart`, `mack_door`, `mack_house_curb`, `vargas_front`,
  `loco`, `dre_corner`, `keisha`, `viper`, `pinta_listo`, `comisaria`, `hospital`, `beach`, `pier`, `bridge`.
- `"player"`: donde esté el jugador.
- `[x, z]` dentro de Westbrook (x de -240 a 300, z de -240 a 240). Se ajusta solo a la acera o al cruce más cercano.
  Referencias: playa y muelle al oeste (x ≈ -290), puente al este (x ≈ 330), casa de Mack (-100, 15),
  esquina de Dre (-59, 108), taller Vargas (100, -110), Redline Kings / Viper (159, -192), terminal (100, -24),
  comisaría (122, -117), hospital (176, -120), Veyra Mart (-20, -20).
- `{"zone": "<zona>", "dx": m, "dz": m}` con dx y dz entre -180 y 180, para las otras ciudades:
  `san_cordova` (misiones 23+), `las_brisas` (43+), `northpoint` (63+), `bahia_solana` (70+),
  `isla_brava` (71+), `isla_coral` (73+), `isla_nacar` (75+). `westbrook` siempre vale.
  Las otras ciudades están a 2-4 km: como mucho UN viaje entre ciudades por misión.

## Pasos

| type | campos | qué hace |
|---|---|---|
| `phase` | `n` (1-7) | marca la fase de la biblia |
| `scene` | `at`, `cast` [ids], `lines`, opcional `title_card`, `hour` | cinemática de diálogo: el reparto en corro, cámara al que habla |
| `call` | `lines`, opcional `objective` | llamada o voz en off (solo subtítulos, sin cortar el juego) |
| `goto` | `target`, `objective`, opcional `hint`, `radius` | ir a pie o en coche |
| `drive_to` | `target`, `objective`, opcional `stop` | llegar EN vehículo |
| `timed_drive` | `target`, `objective`, opcional `time` (s) | llegar en vehículo contrarreloj |
| `steal` | `objective` | conseguir un vehículo |
| `fight` | `at`, `count` (1-6), `objective`, opcional `faction`, `armed`, `waves` (1-3) | acabar con todos |
| `defend` | `at`, `count`, `waves`, `time` (s), `objective` | aguantar oleadas |
| `sneak` | `target`, `guards` (1-5), `objective`, opcional `label` | llegar sin que te vean (si te ven, pelea) |
| `chase` | `at`, `objective`, opcional `toast` | alcanzar a alguien que huye a pie |
| `collect` | `at`, `count` (1-5), `label`, `objective`, opcional `hint` | recoger / examinar / fotografiar cosas |
| `lose_cops` | `stars` (1-4), `objective` | la policía te busca: piérdela |
| `give` | `ammo`, `money`, opcional `toast` | dar munición o dinero |
| `time` | `hour` (0-24) | cambia la hora del día |
| `toast` | `title`, `subtitle` | aviso en pantalla |
| `checkpoint` | — | guarda (tras las fases 2, 4 y 6) |
| `reward` | `money`, `reputation` {banda: n}, `toast` | recompensa |
| `complete` | `next_objective` | cierra la misión (siempre el último paso) |

`faction`: `redline_kings`, `midnight_locos`, `the_syndicate`, `guards`. Reputación: además `westbrook_saints`.

## Diálogos

Cada línea: `{"speaker": "Dre", "en": "...", "es": "...", "t": 3.5}` (voz en inglés, subtítulo en español;
`t` = segundos, unos 0,07 por carácter del inglés, mínimo 2).

- `cast` usa ids: `big_ray`, `dre`, `ghost`, `loco`, `keisha`, `viper`, `okafor`. Cualquier otro texto crea un
  secundario con ese nombre (p. ej. `"Nina Cho"`, `"Evelyn Cross"`, `"Detective Hale"`). Mack siempre está.
- `speaker` en escenas: `Mack`, `Big Ray`, `Dre`, `Ghost`, `Loco`, `K` (Keisha), `Viper`, `Okafor`, o el nombre
  exacto de un secundario del `cast`. En `call` puede ser cualquiera.

## Estructura obligatoria

1. `phase 1` y una `scene` de apertura con `"title_card": true` (10-16 líneas): los personajes hablan entre ellos
   antes de la acción, con tono de drama criminal de barrio: seco, tenso, con jerga y amenazas creíbles.
2. Las 7 fases de la biblia, cada una con su `phase` y 1-3 pasos jugables; varias `call`/`scene` intermedias.
3. `checkpoint` al acabar las fases 2, 4 y 6.
4. Una `scene` de cierre (6-12 líneas) con la consecuencia, luego `reward` y `complete`.
5. Entre 22 y 34 pasos por misión.

Validar: `python3 tools/validate_missions.py`
