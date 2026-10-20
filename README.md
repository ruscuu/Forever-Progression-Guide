# WoW Forever Progression Guide

Addon para WoW Forever que guía al jugador del nivel 1 al máximo: qué hacer a continuación, por qué y cómo. Interfaz en español e inglés, sin conexión durante la partida.

## Qué hace ya

| Pestaña | Contenido |
| --- | --- |
| **Progresión** | Lista corta de objetivos (mazmorras para tu nivel, ranuras de equipo débiles, contenido nuevo por explorar) con su motivo y nivel de confianza. Se pueden marcar como hechos, posponer u ocultar. |
| **Mazmorras** | Las 26 mazmorras y bandas clasificadas para tu personaje (*Recomendada*, *Demasiado pronto*, *Opcional*, *Pendiente de verificar*). Cada una tiene una ficha con alas, jefes y procedencia de los datos, un **mapa** de la instancia con los jefes situados, el **botín de tu clase** y **cómo llegar** con punto de ruta. |
| **Equipo** | Equipo actual, nivel de objeto medio y ranuras débiles. |
| **Misiones** | Registro de misiones actual. |
| **Profesiones** | Profesiones y nivel de habilidad. |
| **Buscador** | Mazmorras, alas y jefes, en los dos idiomas. |

Los mapas, los jefes y el botín se leen del propio cliente, así que se mantienen al día con cada parche. Los rangos de nivel vienen de Classic y están marcados como «sin confirmar en Forever» hasta que una fuente autorizada o el juego los verifique. Ver [cómo se actualiza](docs/ACTUALIZACION.md).

Comandos: `/wfg` (o `/guia`) abre la guía; `/wfg es|en|auto` cambia el idioma; `/wfg info` muestra versión y estado; `/wfg errors` lista errores; `/wfg collect off` desactiva las observaciones.

## Instalación

- **Desde una versión publicada:** descarga el `.zip` de *Releases* y descomprímelo en `World of Warcraft\_classic_beta_\Interface\AddOns\`. Con **WowUp** puedes instalarlo desde la URL de este repositorio para recibir las actualizaciones automáticamente.
- **Desde el código:** copia o enlaza la carpeta `WoWForeverGuide/` en la misma ruta.

Si el juego lo marca como desactualizado, activa *Cargar addons desactualizados* en la selección de personaje.

## Documentación

| Documento | Contenido |
| --- | --- |
| [docs/ACTUALIZACION.md](docs/ACTUALIZACION.md) | Cómo se mantienen al día los datos, configuración de GitHub y lista de pruebas en el juego |
| [docs/COBERTURA.md](docs/COBERTURA.md) | Auditoría de fuentes: qué hay, qué falta y qué se puede redistribuir |
| [docs/PLAN.md](docs/PLAN.md) | Plan técnico maestro |

## Estructura

```
WoWForeverGuide/        el addon (Lua 5.1)
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
python pipeline\package.py 0.1.0                # crear release\WoWForeverGuide-0.1.0.zip
```

Para cambiar datos, edita `data-sources/seed/` o añade observaciones, nunca `WoWForeverGuide/Data/`. CI comprueba que los datos generados están al día.

Para publicar a mano una versión, sube una etiqueta: `git tag v0.1.0 && git push origin v0.1.0`.
