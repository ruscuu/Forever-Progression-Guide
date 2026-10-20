# WoW Forever Progression Guide

Addon para WoW Forever (en Lua) que guía al jugador de nivel 1 al máximo: qué hacer a continuación, por qué y cómo. Interfaz en español e inglés y datos incluidos en el paquete para jugar sin conexión.

**Estado: fase 01, auditoría de fuentes.** Todavía no hay código del addon, a propósito: el plan exige confirmar antes qué datos fiables y redistribuibles existen.

| Documento | Contenido |
| --- | --- |
| [docs/PLAN.md](docs/PLAN.md) | Plan técnico maestro |
| [docs/COBERTURA.md](docs/COBERTURA.md) | Auditoría de fuentes (v0), hallazgos y acciones pendientes |
| [data-sources/sources.json](data-sources/sources.json) | Inventario de fuentes y endpoints |

## Sondeo de cobertura

Requiere Python 3 y solo usa la biblioteca estándar.

```powershell
# Solo para fuentes con clave (nunca se guarda en el repositorio)
setx FOREVERDB_API_KEY "<clave>"

python pipeline\probe_sources.py            # descarga en data-sources\raw\ y genera validation\coverage-<fecha>.md
python pipeline\probe_sources.py --offline  # vuelve a analizar la última descarga
python -m unittest discover -s pipeline\tests
```

El informe muestra, por fuente y categoría, el número de registros, los IDs duplicados o ausentes, el porcentaje de registros que trae cada campo y los valores de los campos de verificación (`status`, `verified`, `source`…).
