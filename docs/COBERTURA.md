# Documento de cobertura de fuentes · v0

Fase 01 del [plan](PLAN.md) · 20 de octubre de 2026 · Estado: **borrador, puerta de decisión abierta**

Este documento responde a las cinco preguntas con las que cierra el plan. Es una
primera versión hecha con investigación remota: desde el entorno en que se
redactó **no se pudo abrir** `forevercompanion.io`, `foreverdb.net`,
`theforeverera.com` ni `foreverchanges.pro` (bloqueo de red), así que lo que se
dice de esas fuentes procede de sus páginas indexadas por buscadores y no de
su documentación técnica. Cada afirmación lleva su nivel de confianza:

- **Confirmado**: leído directamente en la fuente.
- **Indirecto**: visto en resultados de búsqueda o en descripciones de terceros.
- **Sin confirmar**: lo afirma el plan, pero no se ha podido comprobar.

Para cerrar la fase hay que completar la [lista de acciones](#7-acciones-para-cerrar-la-fase-01)
desde tu PC con la herramienta `pipeline/probe_sources.py`.

---

## 1. Hallazgos que cambian el plan

### H1 · Forever Companion probablemente no es una fuente primaria *(crítico)*

- La web `forevercompanion.io` se presenta como **«WoW Forever Leveling Planner»**,
  un planificador gratuito. *(Indirecto)*
- Según su propia portada, contrasta compilaciones beta y datos en vivo con
  **tres sitios de datos de Forever** y las notas de parche de Blizzard, y revisa
  a mano los cambios grandes. Su página de feedback dice que los datos del juego
  **vienen de sitios independientes**. *(Indirecto)*
- La búsqueda no encontró ninguna documentación indexada de su página
  `/developers`: ni endpoints, ni uso sin clave, ni recomendación de caché.
  Puede existir y no estar indexada, pero hoy esas características del plan
  están **sin confirmar**.
- Hay confusión de nombres: existen un addon de CurseForge llamado
  *Forever Companion* (misiones, botín y recetas) y un repositorio de GitHub
  `darksolis/ForeverCompanion` (un compañero animado). Ninguno de los dos es
  el sitio web ni ofrece una API de datos.

**Consecuencia:** si Forever Companion agrega datos de otros sitios, su API
(si existe) hereda las condiciones de uso de esos sitios. No puede ser la
fuente principal hasta saber **de dónde vienen sus datos** y **si permite
redistribuirlos dentro de un addon**. Además, depender de un agregador añade
una capa de retraso y de posibles errores.

### H2 · ForeverDB es hoy la fuente técnica más sólida, pero con barrera de acceso

- La API se anunció el **18-10-2026**, hace dos días. Devuelve JSON con API key y
  el acceso se solicita en su página. *(Indirecto, en su portada)*
- Categorías anunciadas: objetos, hechizos, misiones, vendedores, mazmorras,
  clases y conjuntos de objetos, además de artículos y publicaciones de Blizzard.
  Un listado de terceros menciona capacidades de tipo *Item*, *Dungeon(s)*,
  *Bis* y *Sim*. *(Indirecto)*
- Sus datos se **extraen del cliente beta** (*datamining*), así que las cifras
  pueden cambiar. *(Indirecto)*
- Tiene páginas de profesiones con recuentos y diferencias con Classic, por
  ejemplo Cocina: 132 recetas (44 nuevas, 1 modificada) y Alquimia: 196
  (72 nuevas, 11 modificadas). *(Indirecto)*
- **No aparece «recetas» entre las categorías de la API.** Puede que las recetas
  solo se consulten en la web o a través de *spells*; hay que confirmarlo en
  la documentación.
- No se han encontrado condiciones de uso, límites de peticiones ni requisitos
  de atribución. *(Sin confirmar)*

### H3 · Las fuentes de profesiones no coinciden entre sí

| Dato | The Forever Era | ForeverChanges | ForeverDB |
| --- | --- | --- | --- |
| Total de recetas | 2.209 en 13 profesiones | — | — |
| Herrería | 441 | 437 (197 nuevas) | — |
| Cocina | — | — | 132 |
| Alquimia | — | — | 196 |

*(Todo indirecto.)* La diferencia es pequeña (cuatro recetas en Herrería),
pero demuestra que **ninguna fuente única es fiable**. Las recetas necesitan
fusionarse por ID de hechizo o de objeto y conservar las discrepancias, tal
como prevé el plan. Ninguna de estas webs muestra una API o una licencia de
reutilización en lo indexado.

### H4 · El cliente es moderno y puede ser la fuente más fiable *(oportunidad)*

Confirmado en el [repositorio de Atraeau](https://github.com/Atraeau/WoW-Addons):

- Producto `wow_classic_beta`, nombre en clave **Camelot**, interfaz **16001**
  (parche 1.60.1), motor moderno **basado en 12.0**.
- Los archivos TOC siguen el patrón `<Addon>_Camelot.toc`; carpeta de flavor `_classic_beta_`.
- Build en vivo: `/dump select(4, GetBuildInfo())`.
- Volcado de la API del cliente: **6.577 funciones, 1.802 eventos y 792 tipos**,
  regenerable con el addon `/apiexport`. `/btpcheck` comprueba qué APIs existen.
- El README **no declara licencia** para el repositorio (solo el BlizzThreatPlates
  incluido, con licencia MIT). Puede usarse como referencia, pero no conviene
  copiar su código ni sus definiciones sin permiso del autor.

**Consecuencias:**

1. Un motor 12.0 trae las APIs `C_*` modernas (`C_Item`, `C_QuestLog`,
   `C_TradeSkillUI`…). El addon podría **pedir al cliente** nombres, calidad, nivel y
   estadísticas de objetos en tiempo real, sin incluirlos en el paquete. Así se
   reduce el tamaño y los datos salen directamente de Forever, no de Classic.
2. Esos nombres llegan **en el idioma del cliente**. Para cumplir el requisito de
   «ES/EN independiente del cliente», los nombres en el otro idioma tendrían que
   seguir incluidos en el paquete. Hay que decidir si ese requisito se aplica a
   los nombres del juego o solo a la interfaz del addon.
3. Hay que verificar si las restricciones a addons introducidas en 12.0 (en
   combate y con valores protegidos) están activas en Forever. A una guía que
   se usa sobre todo fuera de combate le afectaría poco, pero debe comprobarse
   con `/btpcheck` o con el volcado de la API.

---

## 2. ¿Qué datos proporciona cada fuente?

| Categoría | Forever Companion | ForeverDB API | Webs comunitarias | Cliente (runtime) |
| --- | --- | --- | --- | --- |
| Mazmorras y jefes | Sin confirmar | Anunciado | Sí (web) | Parcial (diario de mazmorras, si existe) |
| Misiones y cadenas | Sin confirmar | Anunciado | Sí (web) | Solo estado del jugador (completadas, activas) |
| Objetos y estadísticas | Sin confirmar | Anunciado | Sí (web) | **Sí**, por ID |
| Fuentes de botín | Sin confirmar | Probable (mazmorras) | Sí (web) | No |
| Vendedores | — | Anunciado | Parcial | Solo al abrir el vendedor |
| Zonas y niveles | Sin confirmar | — | Sí (web) | Parcial |
| Reputaciones | Sin confirmar | — | Parcial | Estado del jugador |
| Clases y hechizos | Sin confirmar | Anunciado | Sí (web) | **Sí** |
| Profesiones y recetas | — | Web sí; API sin confirmar | Sí (web, cifras discrepantes) | Solo recetas que el jugador conoce |
| BiS / simulación | — | Indicios (*Bis*, *Sim*) | Addons como ForeverBiS | No |

## 3. ¿Qué datos están confirmados en WoW Forever?

Desde aquí solo se ha podido confirmar la parte técnica del cliente (H4).
Ningún conjunto de datos de juego se ha verificado todavía. ForeverDB declara
que sus datos se extraen del cliente beta: eso es mejor que heredar datos de
Classic, pero un dato presente en los archivos del cliente no siempre está
disponible en el juego.

**Propuesta de estados de verificación** para el campo `SourceRecord`:

| Estado | Significado |
| --- | --- |
| `verified_ingame` | Comprobado en el cliente por una persona o por el addon (con fecha y build) |
| `datamined` | Extraído de los archivos del cliente Forever, pero sin comprobar en el juego |
| `classic_inherited` | Procede de Classic y no se ha comprobado en Forever |
| `announced` | Anunciado, pero no presente en el cliente |
| `unknown` | Sin dato fiable |

El plan solo preveía cuatro estados. Se añade `datamined` porque será el
estado más habitual en la fuente con más cobertura.

## 4. ¿Qué información de profesiones falta?

1. **Fuente redistribuible**: ninguna web de profesiones encontrada muestra una
   API o una licencia de reutilización.
2. **Relación receta → hechizo → objeto producido**: necesaria para fusionar
   fuentes por ID y no por nombre.
3. **Dónde se aprende cada receta** (entrenador, vendedor, botín, reputación) y
   el **origen de los materiales**. Las webs muestran entrenadores, pero no se ha
   comprobado que la cobertura sea completa.
4. **Número de profesiones**: una fuente cuenta 13. Hay que confirmar la lista
   exacta, incluidas las nuevas de Forever, si las hay.
5. **Consistencia**: cifras distintas para la misma profesión (H3).

**Plan B:** el cliente puede leer las recetas que el jugador conoce mediante la
API de profesiones al abrir la ventana del oficio. Un modo opcional de
«contribución» podría ir registrando recetas verificadas en SavedVariables para
completar el paquete en futuras versiones, siempre a partir de datos del
propio jugador.

## 5. ¿Qué podemos redistribuir legalmente dentro del addon?

| Material | Situación | Acción |
| --- | --- | --- |
| Datos de Forever Companion | Desconocida; posiblemente datos de terceros | Pedir por escrito su origen y permiso de redistribución |
| Datos de ForeverDB | Desconocida hasta leer sus condiciones | Solicitar la key y preguntar expresamente por el uso dentro de un addon distribuido |
| The Forever Era, ForeverChanges | Sin licencia visible | No usar automáticamente; solo para contrastar a mano |
| Datos leídos del cliente en tiempo real | No se redistribuyen: los consulta el addon al jugador | Vía preferente para nombres y estadísticas |
| Código y definiciones de Atraeau | Sin licencia declarada | Solo referencia; pedir licencia si se quiere reutilizar |
| Datos que verifiquemos nosotros | Propios | Registrar quién verificó, cuándo y en qué build |

Hasta que haya respuesta, los datos descargados se guardan solo en local
(`data-sources/raw/` está en `.gitignore`) y **no se publican en el repositorio**.

## 6. ¿Qué reglas de recomendación podemos implementar con confianza?

| Regla | Confianza | Depende de |
| --- | --- | --- |
| Filtrar equipo por clase, armadura y arma utilizables | Alta | Reglas de clase y APIs del cliente |
| Ocultar objetos por encima del nivel del personaje (o marcarlos como «futuros») | Alta | Nivel requerido, consultable en el cliente |
| Clasificar mazmorras por rango de nivel y facción | Media | Rangos de nivel de una fuente fiable |
| Marcar misiones disponibles o bloqueadas | Media-baja | Grafo de requisitos previos completo, aún sin fuente confirmada |
| Mejor mejora accesible por ranura | Baja | Pesos de estadísticas por especialización en Forever, sin fuente ni validación |
| Rutas de fabricación | Baja | Datos de recetas y materiales (sección 4) |

Conviene empezar por las de confianza alta y media y mostrar las demás como
*Pendiente de verificar*, tal como prevé el apartado 6.1 del plan.

---

## 7. Acciones para cerrar la fase 01

Desde tu PC con Windows (donde sí hay acceso a esas webs):

- [ ] Abrir `https://forevercompanion.io/developers` y confirmar si existe la API. Si existe, copiar sus rutas en
      `data-sources/sources.json` → `forevercompanion.endpoints` y anotar `terms_url`.
- [ ] Preguntar al autor de Forever Companion de qué sitios proceden sus datos y si permite redistribuirlos en un addon.
- [ ] Solicitar la API key de ForeverDB indicando el uso previsto: un addon gratuito, offline y con atribución.
      Preguntar por las recetas y por la redistribución.
- [ ] Con la key: `setx FOREVERDB_API_KEY "<clave>"` en PowerShell, abrir una terminal nueva, rellenar los endpoints y ejecutar
      `python pipeline\probe_sources.py`. El informe se genera en `validation\coverage-<fecha>.md`.
- [ ] En el juego: `/dump select(4, GetBuildInfo())` y anotar el build.
- [ ] Instalar el addon de volcado de Atraeau, ejecutar `/apiexport` y comprobar que existen `C_Item`, `C_QuestLog`,
      `C_TradeSkillUI` y `C_EncounterJournal`, y si hay restricciones de 12.0.
- [ ] Decidir si «ES/EN independiente del cliente» se aplica también a los nombres de objetos y misiones (ver H4.2).

Cuando estén hechas, se actualiza este documento a v1 y se cierra la puerta de
decisión: se fija la fuente principal y el alcance de la versión 1.

## Referencias consultadas

- [Atraeau/WoW-Addons](https://github.com/Atraeau/WoW-Addons) (leído directamente)
- [Forever Companion](https://forevercompanion.io/), [feedback](https://forevercompanion.io/feedback?from=%2F), [privacidad](https://forevercompanion.io/privacy) (vía buscador)
- [ForeverDB](https://foreverdb.net/), [Cocina](https://foreverdb.net/profession/cooking), [Alquimia](https://foreverdb.net/profession/alchemy) (vía buscador)
- [ForeverDB en Firecrawl](https://www.firecrawl.dev/alexandria/foreverdb-net) (vía buscador)
- [The Forever Era · recetas](https://theforeverera.com/en/recipes/) (vía buscador)
- [ForeverChanges · profesiones](https://foreverchanges.pro/professions) (vía buscador)
- [Forever Companion en CurseForge](https://www.curseforge.com/wow/addons/forever-companion), [darksolis/ForeverCompanion](https://github.com/darksolis/ForeverCompanion) (homónimos, no son la fuente)
