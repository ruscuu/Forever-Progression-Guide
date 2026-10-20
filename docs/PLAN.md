# Plan técnico maestro: WoW Forever Progression Guide

Documento de planificación · Versión 1.0 · 20 de octubre de 2026

> Copia de referencia del plan original. Las conclusiones de la auditoría de
> fuentes que lo matizan están en [`COBERTURA.md`](COBERTURA.md); cuando ambos
> documentos discrepen, prevalece `COBERTURA.md` porque recoge lo comprobado.

El objetivo es construir un addon que acompañe al jugador desde el nivel inicial hasta el máximo nivel disponible, con todas las clases desde la primera versión, interfaz en español e inglés y datos incluidos localmente para funcionar sin conexión.

La arquitectura recomendada es Lua para el addon, datos locales generados automáticamente y herramientas gratuitas en Windows para preparar y validar esos datos. No hace falta crear una aplicación web ni mantener un servidor propio.

Hay una decisión de diseño especialmente importante: la guía debe recomendar qué hacer, no solo mostrar una enciclopedia de objetos. Debe explicar cuál es el siguiente objetivo, por qué merece la pena y cómo alcanzarlo.

## 1. Estado de las fuentes y decisiones iniciales

| Recurso | Papel previsto | Notas del plan original |
| --- | --- | --- |
| [Forever Companion](https://forevercompanion.io/developers) | Fuente principal gratuita | JSON de mazmorras, misiones, objetos, zonas, reputaciones y misiones de clase; sin clave según su documentación; recomienda caché. |
| [ForeverDB](https://foreverdb.net/developers) | Complemento | Objetos, vendedores, hechizos, misiones, clases y mazmorras. Requiere solicitar API key y atribuir la fuente. |
| [WoW-Addons de Atraeau](https://github.com/Atraeau/WoW-Addons) | Fuente técnica | Entorno de desarrollo, herramientas Lua y referencia de la API del cliente (interfaz 16001). |

### Decisión sobre las fuentes

- Fuente de datos principal: Forever Companion.
- Fuente secundaria: ForeverDB, si aprueban el acceso y sus condiciones permiten el uso previsto.
- Fuente técnica: documentación del cliente de WoW Forever y pruebas realizadas dentro del juego.
- Datos comunitarios: solo como complemento y con su procedencia registrada.

Ninguna fuente externa debe ser considerada automáticamente correcta para todos los objetos. Se distinguen datos verificados en el juego, heredados de Classic y anunciados pero no disponibles.

## 2. Arquitectura general

Dos partes: el addon que se ejecuta en el juego y un sistema de preparación de datos que se ejecuta en el PC Windows (no tiene que estar activo al jugar).

```
Fuentes públicas y datos comprobados
  Forever Companion · ForeverDB opcional · verificación en el cliente · datos comunitarios autorizados
        │
Pipeline de datos en Windows
  Importación → normalización → traducción → validación → generación
        │
Paquete de datos del addon
  Archivos Lua estáticos, versionados y distribuidos junto con el addon
        │
WoW Forever
  Interfaz bilingüe · recomendaciones · seguimiento · búsqueda offline
```

### Reglas arquitectónicas

1. El addon nunca necesita llamar a una API externa.
2. El addon no contiene claves secretas ni credenciales.
3. Los datos se actualizan mediante nuevas versiones del paquete o de la distribución.
4. La interfaz y las reglas de recomendación se mantienen separadas de los datos.
5. Una fuente que falle no debe impedir que el addon cargue.
6. Los datos desconocidos no se sustituyen por valores inventados.
7. El progreso del jugador se guarda localmente mediante las funciones permitidas por el cliente.

## 3. Estructura de módulos

```
WoWForeverGuide/
  Core/          Inicialización, eventos, configuración, registro de errores, compatibilidad
  Data/          Mazmorras, misiones, objetos, zonas, clases, profesiones, recetas, recompensas, botín
  Engine/        Motor de progresión, cálculo de mejoras, filtros por clase, próximos objetivos
  UI/            Ventana principal, buscador, fichas, comparador de equipo, panel de objetivos
  Localization/  Textos en español e inglés
  Profile/       Objetivos completados, preferencias, filtros, datos guardados
  Tests/         Integridad de datos, reglas de recomendación, traducciones, compatibilidad
```

Herramientas fuera del addon:

- `data-sources/`: documentación, fuentes originales y condiciones de uso.
- `pipeline/`: importación, normalización y generación de datos.
- `translations/`: traducciones revisadas.
- `validation/`: informes de datos incompletos y contradictorios.
- `release/`: paquete final preparado para distribuir.

### Herramientas gratuitas previstas

| Herramienta | Función |
| --- | --- |
| Visual Studio Code | Editar Lua y las herramientas auxiliares |
| Lua Language Server | Autocompletado y análisis del código |
| Git | Historial, ramas y versiones |
| Luacheck | Detectar errores y problemas de estilo en Lua |
| PowerShell | Ejecutar las herramientas de Windows |
| Python 3 | Importar, validar y generar datos |
| WoW Forever | Pruebas reales dentro del cliente |

## 4. Modelo de datos

| Entidad | Información que debe guardar |
| --- | --- |
| `Dungeon` | ID, nombre, zona, nivel recomendado, jefes, requisitos y facción |
| `Quest` | ID, nivel, dador, objetivos, requisitos previos, recompensa y experiencia |
| `Item` | ID del juego, ranura, estadísticas, nivel requerido, clase y calidad |
| `ItemSource` | Objeto, jefe, misión, vendedor, profesión o cofre del que procede |
| `Zone` | Zona, niveles adecuados, facción y contenido disponible |
| `ClassProfile` | Clase, especialización, función y restricciones de equipamiento |
| `Profession` | Profesión, recetas, materiales, nivel de habilidad y productos |
| `Recipe` | Receta, materiales, requisito de habilidad y objeto producido |
| `Objective` | Acción recomendada, requisitos, prioridad y condición de finalización |
| `Localization` | Textos propios de la interfaz en español e inglés |
| `SourceRecord` | Fuente, fecha, versión, nivel de confianza y estado de verificación |

### Reglas de integridad

- Los IDs del juego son la referencia principal para enlazar objetos y misiones.
- Los nombres no se usan como identificadores únicos.
- Las misiones deben poder relacionarse con sus requisitos previos.
- Las recetas deben relacionarse con sus materiales y productos.
- Las recomendaciones deben enlazar con las fuentes de obtención de cada objeto.
- Cada registro se identifica como verificado, heredado, anunciado o desconocido.
- Los datos de Classic no se mezclan silenciosamente con los confirmados de Forever.

Los registros presentes en varias fuentes se fusionan por ID, conservando diferencias y procedencia.

## 5. Fuentes de datos gratuitas por función

| Categoría | Fuente principal prevista | Qué falta comprobar |
| --- | --- | --- |
| Mazmorras y jefes | Forever Companion | Completitud y cambios de la beta |
| Misiones y cadenas | Forever Companion | Requisitos y recompensas sin verificar |
| Objetos y botín | Forever Companion | Estadísticas específicas de Forever |
| Zonas y niveles | Forever Companion | Rutas óptimas entre zonas |
| Reputaciones | Forever Companion | Cambios y disponibilidad de recompensas |
| Habilidades de clase | Datos de clase y cliente | Especializaciones y requisitos actualizados |
| Profesiones y recetas | ForeverDB, cliente y fuentes comunitarias | Cobertura de recetas, materiales y niveles |
| Mejores objetos por clase | Motor propio de recomendaciones | Pesos de estadísticas y pruebas reales |
| Traducciones | Datos del juego y traducción revisada | Nombres propios, objetos y términos técnicos |

### Cómo completar los huecos de información

1. Consultar si los datos están disponibles en el cliente.
2. Comprobarlos dentro del juego.
3. Consultar una fuente comunitaria cuya reutilización esté permitida.
4. Registrar el dato manualmente, indicando quién lo verificó y cuándo.
5. Mantenerlo como desconocido si no puede confirmarse.

No se extraen ni redistribuyen bases de datos de terceros sin comprobar sus condiciones de uso.

## 6. Motor de progresión

### 6.1. Recomendación de mazmorras

Evalúa nivel frente a rango, nivel de enemigos, misiones y requisitos, equipo para el rol, recompensas que sean mejora real, tiempo aproximado, facción y acceso. Categorías de salida: *Demasiado pronto*, *Recomendada*, *Recomendada por recompensa*, *Opcional*, *Pendiente de verificar*. Sin reglas rígidas de «nivel X».

### 6.2. Mejor equipo disponible

Tres conceptos: mejor equipo teórico, mejor mejora accesible y mejor objetivo futuro. Para cada ranura: objeto actual, alternativa, motivo, nivel requerido, fuente, requisitos, dificultad/incertidumbre, fecha y confianza. Las ponderaciones dependen de la especialización y del objetivo (daño, supervivencia, PvP); no basta con sumar estadísticas.

### 6.3. Misiones y cadenas de requisitos

Grafo de dependencias: qué se puede hacer ya, qué está bloqueado y qué paso desbloquea más contenido. Prioridades: desbloqueo de mazmorras, mejoras de equipo, experiencia útil, cadenas de clase y agrupación por zona. Nunca asumir disponibilidad solo por nivel.

### 6.4. Profesiones y fabricación

Qué profesión desarrollar para un objetivo, qué receta produce un objeto útil, habilidad requerida, dónde se aprende, materiales y su origen, comparación con alternativas, desbloqueos por vendedor/misión/reputación y dependencias entre profesiones. No asumir que la profesión óptima en Classic lo es en Forever.

### 6.5. Generador de objetivos

Lista corta de objetivos ordenados por utilidad, cada uno con su explicación. El jugador puede completarlos, posponerlos o descartarlos.

## 7. Idiomas: español e inglés

Textos de interfaz en archivos de localización; nombres oficiales según idioma y datos disponibles; IDs independientes del idioma; datos técnicos compartidos; nombres sin traducción confirmada en idioma original. Selector ES/EN independiente del cliente con opción automática. Pruebas: textos sin traducir, etiquetas largas, duplicados, caracteres.

## 8. Datos locales, tamaño y funcionamiento offline

1. Descargar datos autorizados durante la preparación.
2. Normalizar y resolver relaciones.
3. Generar archivos estáticos del addon.
4. Dividirlos por categoría y, si hace falta, por zona o rango de nivel.
5. Incluirlos todos en el paquete.
6. Cargar de forma controlada.

Progreso en SavedVariables (si se confirma su comportamiento). Sin escritura libre a disco ni HTTP en partida.

## 9. Diseño de la interfaz

Ventana principal con cabecera (personaje · nivel · clase · especialización · objetivo actual, selector ES/EN) y seis secciones: Progresión, Mazmorras, Equipo, Misiones, Profesiones, Buscador. Compacta, redimensionable si el cliente lo permite. Sin mapas interactivos ni navegación automática en la primera versión.

## 10. Fases de desarrollo y criterios de aceptación

| Fase | Contenido | Aceptación |
| --- | --- | --- |
| 01 · Investigación y especificación (puerta de decisión) | Cliente, API, fuentes gratuitas, condiciones de reutilización, cobertura de profesiones | Documento de fuentes con cobertura, limitaciones y plan alternativo por categoría |
| 02 · Modelo de datos y pipeline | Importación, normalización, traducciones, generación | Sin IDs duplicados sin resolver, relaciones rotas conocidas ni datos de origen ocultos |
| 03 · Núcleo e interfaz | Ventana, buscador, filtros, fichas, bilingüe | Carga en el cliente correcto, sin Internet, sin errores bloqueantes |
| 04 · Mazmorras y misiones | Niveles, requisitos, jefes, recompensas, cadenas | Respeta facción, nivel y requisitos registrados |
| 05 · Equipo y profesiones | Evaluación, rutas de fabricación, explicaciones | Cada recomendación con motivo, fuente e indicador de confianza |
| 06 · Validación y publicación | Clases, localizaciones, rendimiento, persistencia, instalación limpia | Versión reproducible, documentación, atribuciones y limitaciones conocidas |

No se fija fecha de entrega hasta medir el volumen real de datos.

## 11. Riesgos y cómo reducirlos

| Riesgo | Medida preventiva |
| --- | --- |
| API gratuita incompleta o caída | Conservar importaciones válidas y generación independiente |
| Datos de Classic incorrectos para Forever | Procedencia y estado de verificación por registro |
| Cambios de interfaz o de API | Fijar el build compatible y probar tras cada actualización |
| Recomendaciones de equipo engañosas | Separar teoría, accesibilidad y confianza; validar por especialización |
| Profesiones sin datos completos | Inventario de cobertura y huecos completados de forma verificable |
| Paquete demasiado grande | Medir tamaño y tiempo de carga antes de decidir la granularidad |
| Traducciones inconsistentes | IDs estables y glosario bilingüe |
| Datos protegidos por licencias | Revisar condiciones y atribuir cada fuente |
| Pérdida del progreso | Probar SavedVariables, migraciones y valores predeterminados |
| Errores que afectan a todo el addon | Aislar módulos; una categoría incompleta no bloquea las demás |

## 12. Plan de pruebas

- **A. Datos:** IDs válidos y únicos, objetos sin fuente, requisitos inexistentes, recetas sin materiales o producto, referencias rotas, traducciones y estados de verificación, dependencias del paquete.
- **B. Motor:** equipo utilizable por la clase, no recomendar peores piezas, misiones bloqueadas no disponibles, recetas con requisitos satisfacibles, cambio con especialización/nivel/objetivo, baja confianza ante datos insuficientes.
- **C. En el cliente:** instalación limpia, ventanas, sin conexión, cambio ES/EN, varias clases y niveles, seguimiento de objetivos, persistencia, detección de funciones no disponibles.
- **D. Regresión:** comparar cada actualización de datos con la anterior y generar informe de cambios.

## 13. Primera versión publicable (definición de terminado)

1. Todas las clases disponibles en los filtros.
2. Interfaz completa en español e inglés.
3. Datos locales y funcionamiento sin conexión.
4. Mazmorras con rangos de nivel y requisitos.
5. Fichas de misiones, jefes y recompensas conocidas.
6. Buscador de objetos y fuentes de obtención.
7. Recomendaciones de equipo por clase y especialización.
8. Rutas de fabricación con recetas verificadas.
9. Seguimiento de objetivos guardado localmente.
10. Indicadores de confianza y procedencia.
11. Documentación, pruebas y atribución de todas las fuentes.

## 14. Decisiones técnicas

| Decisión | Recomendación |
| --- | --- |
| Lenguaje del addon | Lua |
| Cliente de referencia | WoW Forever; verificar el build instalado |
| Entorno de desarrollo | Windows + VS Code + Git |
| Fuentes iniciales | Forever Companion y fuentes complementarias autorizadas |
| API de pago | No necesaria |
| Funcionamiento durante el juego | Totalmente offline |
| Distribución de datos | Archivos estáticos incluidos en el paquete |
| Localización | Español e inglés desde el comienzo |
| Arquitectura | Módulos independientes; datos separados de la lógica |
| Recomendaciones | Motor propio con reglas explícitas y datos verificados |
| Actualización | Pipeline externo que genera una nueva versión del paquete |
| Publicación | Repositorio y plataforma de addons, según licencias |

### Recomendación final

No empezar por la ventana del addon sino por una auditoría de datos. El primer entregable es un documento de cobertura que responda:

1. ¿Qué datos proporciona cada fuente?
2. ¿Qué datos están confirmados en WoW Forever?
3. ¿Qué información de profesiones falta?
4. ¿Qué podemos redistribuir legalmente dentro del addon?
5. ¿Qué reglas de recomendación podemos implementar con suficiente confianza?
