<p align="center"><img src="docs/logo/logo-512.png" alt="Logo de Forever Progression Guide" width="160"></p>

# Forever Progression Guide

Addon para WoW Forever que guía al jugador del nivel 1 al máximo: qué hacer a continuación, por qué y cómo. Interfaz en español e inglés, sin conexión durante la partida.

## Qué hace ya

| Pestaña | Contenido |
| --- | --- |
| **Progresión** | Objetivos con su motivo y nivel de confianza: mazmorras para tu nivel (o la próxima), misiones que recoger antes de entrar, misiones de clase, zona recomendada y ranuras de equipo débiles. Se pueden marcar como hechos, posponer u ocultar. |
| **Mazmorras** | 42 mazmorras y bandas, incluidas las nuevas de Forever, clasificadas para tu personaje. Cada ficha tiene **Información** (entrada, cambios en Forever, jefes), **Misiones** (requisitos, recompensas, experiencia y si ya las hiciste), **Botín** (iconos, calidad, filtrado por lo que tu clase puede usar y mejoras frente a tu equipo) y **Mapa**. |
| **Equipo** | Equipo actual, nivel de objeto medio y ranuras débiles. |
| **Misiones** | Misiones de mazmorra y de élite disponibles para tu nivel, y tu registro actual. |
| **Profesiones** | Profesiones y nivel de habilidad. |
| **Buscador** | Mazmorras, jefes, misiones y objetos, en los dos idiomas. |
| **Opciones** | Idioma, icono del minimapa, registro de observaciones y restablecer objetivos o ventana. También están en *Opciones → AddOns* del juego. |

En la cabecera se elige la **clase y especialización** que se consulta. Por defecto son las de tu personaje, y las listas salen del propio cliente, así que solo aparecen las de Forever.

**Datos:** mazmorras (incluidas las nuevas de Forever), misiones con requisitos y recompensas, objetos con icono y calidad, zonas, misiones de clase y raros vienen de [Forever Companion](https://forevercompanion.io), que reúne ForeverChanges, Wowhead y Zockify. Se actualizan solos cada 6 horas.

Los mapas de las mazmorras se leen del propio cliente cuando los tiene. Los rangos de nivel y el resto de datos indican su procedencia: vistos en Forever, heredados de Classic, anunciados o verificados por jugadores. Ver [cómo se actualiza](docs/ACTUALIZACION.md).

**Icono en el minimapa:** clic izquierdo abre la guía, clic derecho abre las opciones y se puede arrastrar alrededor del minimapa.

Comandos: `/wfg` (o `/guia`) abre la guía; `/wfg opciones` abre las opciones; `/wfg minimapa` muestra u oculta el icono; `/wfg es|en|auto` cambia el idioma; `/wfg info` muestra versión y estado; `/wfg test` hace una autoprueba y muestra un informe; `/wfg traducir` recoge del juego los nombres de objetos y misiones en tu idioma; `/wfg errors` lista errores; `/wfg collect off` desactiva las observaciones.

## Instalación

- **Desde una versión publicada:** descarga el `.zip` de *Releases* y descomprímelo en `World of Warcraft\_classic_beta_\Interface\AddOns\`. Con **WowUp** puedes instalarlo desde la URL de este repositorio para recibir las actualizaciones automáticamente.
- **Desde el código:** copia o enlaza la carpeta `ForeverProgressionGuide/` en la misma ruta.

Si el juego lo marca como desactualizado, activa *Cargar addons desactualizados* en la selección de personaje.

## Documentación

| Documento | Contenido |
| --- | --- |
| [docs/ACTUALIZACION.md](docs/ACTUALIZACION.md) | Cómo se mantienen al día los datos, configuración de GitHub y lista de pruebas en el juego |
| [docs/COBERTURA.md](docs/COBERTURA.md) | Auditoría de fuentes: qué hay, qué falta y qué se puede redistribuir |
| [docs/PLAN.md](docs/PLAN.md) | Plan técnico maestro |

## Estructura

```
ForeverProgressionGuide/ el addon (Lua 5.1)
  Core/                 arranque, eventos aislados, compatibilidad con la API
  Data/                 GENERADO por pipeline/build_data.py: no editar
  Engine/               recomendación, diario del cliente, equipo, objetivos
  Profile/              observaciones en juego
  Localization/         español e inglés
  UI/                   ventana, mapa y pestañas
data-sources/           semilla, fuentes, observaciones y datos normalizados
pipeline/               sondeo de fuentes, importación, generación, empaquetado
tests/                  pruebas del addon en Lua 5.1 con la API simulada
.github/workflows/      CI, actualización automática de datos y publicación
```

## Desarrollo

Requiere Python 3. Las pruebas del addon usan `lupa`, que ejecuta Lua 5.1, la misma versión que WoW.

```powershell
pip install lupa==2.8
python -m unittest discover -s pipeline\tests   # pipeline
python -m unittest discover -s tests            # addon
python pipeline\build_data.py                   # regenerar datos tras cambiar data-sources\
python pipeline\package.py 0.1.0                # crear release\ForeverProgressionGuide-0.1.0.zip
```

Para cambiar datos, edita `data-sources/seed/` o añade observaciones, nunca `ForeverProgressionGuide/Data/`. CI comprueba que los datos generados están al día.

Para publicar a mano una versión, sube una etiqueta: `git tag v0.1.0 && git push origin v0.1.0`.
