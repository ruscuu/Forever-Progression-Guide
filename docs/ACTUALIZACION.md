# Cómo se mantiene actualizada la guía

El addon no puede conectarse a Internet durante la partida (lo impide el
cliente, y así lo exige el plan), así que no puede «descargar» datos nuevos
mientras juegas. La guía se mantiene al día con tres capas, de la más rápida a
la más lenta.

```
 ┌─────────────────────────────┐   cada vez que abres la guía
 │ 1. Datos del propio cliente │   diario de mazmorras, mapas, jefes,
 │    (en tiempo real)         │   entradas, botín por clase, equipo
 └──────────────┬──────────────┘
                │ lo que el cliente no sabe
 ┌──────────────▼──────────────┐   cada 6 horas, automático
 │ 2. Paquete de datos         │   GitHub Actions descarga las fuentes,
 │    (versión del addon)      │   regenera, prueba y publica
 └──────────────┬──────────────┘
                │ lo que ninguna fuente confirma
 ┌──────────────▼──────────────┐   cada vez que juegas
 │ 3. Observaciones en juego   │   instancias, mapas, entradas, jefes
 │    (SavedVariables)         │   y misiones; vuelven como «verificado»
 └─────────────────────────────┘
```

## 1. Datos del cliente: siempre al día

Todo lo que el motor del juego ya sabe se pide en tiempo real y nunca se
copia al paquete (`Engine/Journal.lua`):

| Qué | API del cliente |
| --- | --- |
| Lista de mazmorras y bandas, descripción | `EJ_GetInstanceByIndex` |
| Jefes (traducidos al idioma del cliente) | `EJ_GetEncounterInfoByIndex` |
| Mapa de la mazmorra, por plantas | `C_Map.GetMapArtLayerTextures`, `C_Map.GetMapGroupMembersInfo` |
| Posición de los jefes en el mapa | `C_EncounterJournal.GetEncountersOnMap` |
| Entrada en el mapa del mundo y punto de ruta | `C_EncounterJournal.GetDungeonEntrancesForMap`, `C_Map.SetUserWaypoint` |
| Botín filtrado por tu clase | `EJ_SetLootFilter`, `C_EncounterJournal.GetLootInfoByIndex` |
| Equipo y nivel de objeto | `GetInventoryItemLink`, `C_Item.GetDetailedItemLevelInfo` |

Cuando un parche de Forever cambia un jefe, un mapa o el botín, la guía lo
muestra al momento, sin actualizar nada. Si Blizzard añade una mazmorra nueva
al diario, aparece en la lista como «Pendiente de verificar» y en Progresión
como objetivo «Explora…».

Cada llamada se comprueba antes de hacerse (`Core/Compat.lua`): si Forever no
tiene alguna de estas funciones, esa parte se desactiva y el resto sigue
funcionando. **Está por confirmar en el cliente real** qué partes del diario
tiene Forever rellenas (ver [lista de pruebas](#lista-de-pruebas-en-el-juego)).

## 2. Paquete de datos: actualización automática

Lo que el cliente no ofrece (rangos de nivel recomendados, procedencia y
confianza de cada dato) viaja en `ForeverProgressionGuide/Data/`, generado por
`pipeline/build_data.py`. El flujo `.github/workflows/update-data.yml`:

1. Se ejecuta **cada 6 horas**, a mano desde la pestaña *Actions*, o cuando se
   suben observaciones nuevas a `data-sources/contributions/`.
2. Descarga las fuentes configuradas en `data-sources/sources.json`.
3. Fusiona campo a campo: un dato solo sustituye a otro de igual o menor
   confianza (`verified_ingame` > `datamined` > `classic_inherited` > `announced`).
4. Valida (IDs duplicados, rangos imposibles, referencias rotas) y ejecuta
   todas las pruebas.
5. Si nada ha cambiado, termina sin hacer nada. Si algo cambió, abre un pull
   request con el informe de cambios (`validation/changes-latest.md`).
6. Con la variable de repositorio `AUTO_MERGE_DATA = true`, lo fusiona solo
   (salvo que el informe elimine registros, que siempre requiere revisión) y
   llama a `release.yml`, que publica una versión nueva.

### Cómo le llega al jugador

`release.yml` crea un **GitHub Release** con el `.zip` y, si está configurado,
lo sube a **CurseForge**. Los gestores de addons actualizan solos:

- **CurseForge app**: cuando el proyecto exista en CurseForge.
- **WowUp**: instalando desde la URL del repositorio de GitHub, sin necesidad de CurseForge.

Además, el addon compara el build del cliente con el último build para el que
se comprobaron los datos y avisa en Progresión si tu cliente es más nuevo.

### Configuración en GitHub (una sola vez)

| Dónde (*Settings*) | Nombre | Para qué |
| --- | --- | --- |
| Secrets → Actions | `FOREVERDB_API_KEY` | Descargar ForeverDB cuando concedan la clave |
| Secrets → Actions | `DATA_BOT_TOKEN` (opcional) | Token personal con permiso de *contents* y *pull requests*: hace que los PR automáticos también pasen CI |
| Variables → Actions | `AUTO_MERGE_DATA` = `true` (opcional) | Publicar sin revisión manual |
| Secrets → Actions | `CF_API_KEY` | Subir a CurseForge |
| Variables → Actions | `CF_PROJECT_ID`, `CF_GAME_VERSION_IDS` | ID del proyecto en CurseForge e IDs de versión de juego (separados por comas) |
| Actions → General | *Allow GitHub Actions to create and approve pull requests* | Necesario para el paso 5 |

### Conectar una fuente nueva

Cuando una fuente autorice por escrito el uso de sus datos dentro de un addon:

1. En `sources.json`, rellena `endpoints` con las rutas reales y pon
   `redistribution_allowed: true`.
2. Añade en `imports` cómo se traduce cada campo. Hay un ejemplo en
   `_example_import`: `instanceID` es obligatorio y sirve para enlazar.
3. Ejecuta `python pipeline/probe_sources.py` y `python pipeline/build_data.py`
   y revisa el informe de cambios.

Sin `redistribution_allowed`, el pipeline descarga y analiza la fuente, pero
no la incluye en el addon.

## 3. Observaciones en juego: los datos que faltan

`Profile/Collector.lua` anota, mientras juegas y sin datos personales:

- Instancias en las que entras: ID, nombre en tu idioma, tipo, tamaño, mapas
  (plantas) y nivel con el que entras.
- Entrada aproximada: tu última posición en exteriores antes de entrar.
- Jefes derrotados (solo victorias).
- Misiones aceptadas y entregadas: nivel, zona y experiencia.

Para incorporarlas a la guía:

```powershell
python pipeline\import_contributions.py --wow "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
python pipeline\build_data.py
git add data-sources\contributions ForeverProgressionGuide\Data data-sources\generated
git commit -m "Observaciones en juego"
git push
```

El resultado:

- Las mazmorras que has visitado pasan a «En Forever: verificado en el juego».
- Su mapa funciona aunque el diario no lo tenga.
- «Cómo llegar» usa la entrada anotada.
- Las instancias que no estaban en ningún dato aparecen como nuevas.

Entrar en una mazmorra **no** verifica su rango de niveles: eso sigue
necesitando una fuente o una comprobación manual.

Se puede desactivar con `/wfg collect off`.

## Lista de pruebas en el juego

Esto no se ha podido probar sin el cliente. Las pruebas automáticas usan Lua
5.1 real con una API simulada, pero falta confirmar en Forever:

- [ ] El addon carga (`/wfg`) y `/wfg errors` no muestra errores.
- [ ] `/wfg info` indica «diario: sí». Si dice «no», Forever no expone el
      diario de mazmorras y la guía usa solo los datos incluidos.
- [ ] Mazmorras → Las Minas de la Muerte → **Mapa** dibuja el mapa y los jefes.
- [ ] **Botín de clase** muestra objetos (el diario tiene botín en Forever).
- [ ] **Cómo llegar** coloca un punto de ruta en el mapa del mundo.
- [ ] Al entrar y salir de una mazmorra, `/wfg info` cuenta una instancia observada.
- [ ] Cambiar de idioma con el botón de la cabecera y con `/wfg en`.
- [ ] Los datos se conservan después de `/reload` y al cerrar el juego.

Si algo falla, el texto de `/wfg errors` basta para corregirlo.
