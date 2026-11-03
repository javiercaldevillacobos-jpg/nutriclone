# Mapa de reconocimiento: Fitia (iOS)

Alcance: contador de calorías + planificador de comidas para iPhone (iOS 18+, optimizado iPhone 16 Pro). Núcleo: onboarding → objetivos → registro diario (texto, código de barras, foto, voz) → progreso. Planes de comidas, coach IA, ayuno y Apple Health como segunda ola. Apple Watch, visionOS y Android fuera del alcance inicial.
Para: producto propio del usuario (marca nueva, por definir en `/replica-brand`). Nombre de trabajo: **NutriClone**.
Fecha: 2026-11-03

> Reglas: se reconstruye funcionalidad y patrones de UX, no código, logos, textos, recetas, fotos ni la base de datos de Fitia. Fuentes públicas solamente. No se han usado cuentas, APIs privadas ni binarios.

## Fuentes

| # | fuente | URL | notas |
| --- | --- | --- | --- |
| 1 | web (home) | https://fitia.app/es/ | posicionamiento, cifras (20M+ usuarios, 4,9★), integraciones listadas |
| 2 | funcionalidades | https://fitia.app/es/funcionalidades/ | lista completa con etiquetas Gratis/Premium — **fuente de verdad para el gating** |
| 3 | Gratis vs Premium | https://fitia.app/es/premium/ | tabla comparativa, sin precios |
| 4 | centro de ayuda | https://fitia.app/es/ayuda/ | 6 categorías: contador (4), planificador (14), progreso (8), ayuno (1), suscripciones (12), otros (38) |
| 5 | ayuda: suscripciones | https://fitia.app/es/ayuda/categorias/suscripciones-pagos/ | planes, prueba 3 días (solo anual), referidos, cancelación |
| 6 | App Store (US) | https://apps.apple.com/app/fitia-diet-meal-planner/id1448277011 | "Fitia: Calorie Counter & Diet", 4,9★ (24K), iOS 16+, watchOS 10+, visionOS, 216,7 MB, v25.2.4 |
| 7 | pendiente | capturas App Store / vídeos de walkthrough / cuenta propia del usuario | **No se han revisado capturas**: las pantallas de abajo son inferidas. Siguiente paso de recon: que el usuario recorra la app con su propia cuenta y guarde capturas en `replica/screens/` |

Precios IAP (US, App Store): 1 mes 19,99 $ · 3 meses 23,99 $ · 6 meses 35,99 $ · 12 meses 53,99–59,99 $ · Familiar (6 personas) 1 año 89,99 $. Prueba gratis solo en anual y familiar.

## Core loop

Saber cuántas calorías/macros te tocan hoy y registrar lo que comes en segundos (foto, voz, texto, código de barras) para cumplirlo; Premium vende que la app te diga **qué** comer (plan automático + lista de compra).

## Pantallas

Confianza: (h) alta = descrito en varias fuentes · (m) media = una fuente · (g) guess = inferido por convención del sector.

| ID | pantalla | cómo se llega | propósito | componentes clave | estados |
| --- | --- | --- | --- | --- | --- |
| S01 | Bienvenida | primer arranque | propuesta de valor, empezar / iniciar sesión | hero, CTA primario, link login | — (g) |
| S02 | Onboarding: cuestionario | S01 → Empezar | objetivo, sexo, edad, altura, peso, peso meta, actividad, ritmo, dieta, alergias, comidas/día | stepper de preguntas, pickers de número, chips de selección, barra de progreso | validación, atrás (h objetivo / g resto) |
| S03 | Onboarding: resultado | fin de S02 | mostrar kcal y macros calculados, fecha estimada de meta | anillo kcal, barras macro, gráfico de proyección | — (m) |
| S04 | Registro / login | S03 o S01 | crear cuenta (Apple, Google, email) | botones Sign in with Apple/Google, form email | error, cargando (g) |
| S05 | Paywall | tras S04, y en cualquier feature Premium | vender Premium | lista de beneficios, selector de plan, "Canjear código", restaurar | prueba disponible / no (h) |
| S06 | Diario (Hoy) | tab 1 | resumen del día y comidas | selector de fecha, anillo kcal restantes, barras P/C/G, tarjetas por comida (desayuno…cena/snacks), agua, racha | vacío, parcial, superado, día pasado (h) |
| S07 | Añadir alimento (búsqueda) | "+" en tarjeta de comida | buscar en BD, recientes, favoritos, mis alimentos/recetas | barra búsqueda, tabs, lista de resultados con kcal, accesos a foto/voz/escáner | vacío, sin resultados, cargando, offline (h) |
| S08 | Detalle de alimento | tap en resultado | elegir porción y añadir | selector de unidad/cantidad, macros, micronutrientes, puntuación nutricional, comparar | verificado / no (h) |
| S09 | Registro por foto | S07 → cámara | foto → lista de alimentos detectados editable | cámara, overlay de análisis, lista editable con porciones | analizando, sin detección, error, permiso denegado (h) |
| S10 | Registro por voz | S07 → micrófono | dictar comida → alimentos | botón push-to-talk, transcripción en vivo, lista resultante | escuchando, procesando, permiso denegado (h) |
| S11 | Registro por texto (IA) | S07 → escribir | frase libre → alimentos | campo multilinea, lista resultante | ambiguo, error (h) |
| S12 | Escáner de código de barras | S07 → escáner | escanear EAN/UPC | vista cámara con guía, linterna | no encontrado → crear alimento, permiso denegado (h) |
| S13 | Crear alimento / receta | S07 o S12 | alimento propio o receta con ingredientes | formulario de etiqueta nutricional, lista ingredientes, raciones | validación (h) |
| S14 | Plan (semana) | tab 2 | plan automático por día y comida | selector de día, tarjetas de receta con kcal, botón "cambiar", regenerar, PDF | sin plan, generando, Premium bloqueado (h) |
| S15 | Detalle de receta | S14 | ingredientes escalados a tu porción, pasos | foto, macros, ingredientes, pasos, añadir al diario | — (h) |
| S16 | Intercambiar comida | S14 → cambiar | alternativas con kcal similares | lista de sugerencias, filtros | — (m) |
| S17 | Lista de compras | S14 | ingredientes agregados del plan | lista por categoría con checkbox, rango de fechas, compartir | vacía, todo marcado (h) |
| S18 | Progreso | tab 3 | peso y tendencias | gráfico peso (7d/30d/90d/año), meta, ritmo recomendado, historial nutrientes | sin datos, 1 punto (h) |
| S19 | Registrar peso / medidas | S18 → + | peso, % grasa, cintura, cadera, brazos, muslos, pecho | pickers, cálculo automático % grasa | (h) |
| S20 | Fotos de progreso | S18 | galería y comparación lado a lado | grid, comparador antes/después | vacía, permiso (h) |
| S21 | Fitia Coach (chat) | tab o botón flotante | chat IA, análisis de alimento, sugerencias con lo que tienes | lista de mensajes, input, chips de sugerencia | escribiendo, error, límite (h) |
| S22 | Ayuno intermitente | desde Hoy o tab | temporizador 16:8/18:6/20:4/custom | anillo temporizador, selector de protocolo, historial | en ayuno, en ventana, completado (h) |
| S23 | Teams | tab o perfil | equipos, retos, chat de grupo | lista equipos, ranking, chat | sin equipo (m) |
| S24 | Perfil y ajustes | tab 5 | objetivos, metas kcal/macros, comidas/día, unidades, recordatorios, integraciones, suscripción, exportar, cuenta | lista agrupada de ajustes | (h) |
| S25 | Editar metas | S24 | macros personalizados, tipo de dieta | sliders %/g, presets (alto en proteína, keto, low-carb, low-fat) | Premium bloqueado (h) |
| S26 | Integraciones | S24 | Apple Health on/off, permisos | toggles, estado de permisos | denegado (h) |
| S27 | Agua | S06 | registrar vasos, meta personalizada | contador de vasos | (h) |
| S28 | Medicamentos y suplementos | S06 / perfil | dosis, recordatorios, historial (nuevo v25) | lista, form de dosis | (m) |

Widgets (calorías, macros, comidas, ayuno, agua, racha) y Live Activity de ayuno: superficies extra fuera de la app (h).

## Flujos

```
F01 Nuevo usuario obtiene sus metas
    S01 -> S02 (≈10 preguntas) -> S03 -> S04 -> S05 (cerrar) -> S06
    happy path: ~14 taps
    edge: meta incoherente (peso meta < IMC 18,5), menor de edad, unidades imperiales

F02 Registrar comida por texto/búsqueda (núcleo)
    S06 -> "+" en Comida -> S07 -> buscar -> S08 -> Añadir -> S06
    happy path: 4 taps + escribir
    edge: sin resultados, unidad rara (taza, porción), offline

F03 Registrar por código de barras
    S06 -> + -> S07 -> S12 -> (encontrado) S08 -> Añadir
    happy path: 4 taps
    edge: no está en BD -> S13 crear; permiso cámara denegado; código ilegible

F04 Registrar por foto (Premium)
    S06 -> + -> S07 -> S09 -> foto -> revisar lista -> Confirmar
    happy path: 4 taps
    edge: plato mixto, detección errónea, sin red (IA en la nube)

F05 Registrar por voz (Premium)
    S06 -> + -> S07 -> S10 -> hablar -> revisar -> Confirmar
    happy path: 4 taps
    edge: ruido, idioma, cantidades vagas ("un poco de arroz")

F06 Generar y seguir un plan (Premium)
    S14 -> Generar -> S15 -> "Comí esto" -> S06 ; S14 -> S16 cambiar
    edge: alergias/exclusiones, sin recetas que cuadren, día ya parcialmente registrado

F07 Lista de compras
    S14 -> S17 -> marcar -> compartir

F08 Registrar peso y ver progreso
    S18 -> + -> S19 -> Guardar -> S18 (gráfico actualizado + ajuste dinámico de kcal)

F09 Ayuno
    S22 -> elegir 16:8 -> Empezar -> (Live Activity) -> Terminar

F10 Preguntar al Coach
    S21 -> escribir/chip -> respuesta con contexto del día

F11 Conectar Apple Health
    S24 -> S26 -> toggle -> hoja de permisos HealthKit -> kcal activas suman al presupuesto

F12 Suscribirse
    feature bloqueada -> S05 -> plan -> StoreKit -> desbloqueado
    edge: restaurar compras, prueba ya usada, código promocional
```

## Componentes

| componente | variantes | estados | usado en |
| --- | --- | --- | --- |
| Anillo de progreso | kcal, ayuno, agua | <meta, =meta, >meta | S03, S06, S22 |
| Barra de macro | proteína, carbs, grasa | normal, superada | S03, S06, S08, S15 |
| Tarjeta de comida | desayuno, almuerzo, cena, snack, extra | vacía, con items | S06, S14 |
| Fila de alimento | buscar, registrado, plan | verificado, favorito, swipe-borrar | S07, S06, S14 |
| Selector de porción | gramos, unidad, taza, ración | — | S08, S09–S11 |
| Botón | primario, secundario, ghost, destructivo | normal, pressed, disabled, loading | todas |
| Chip / pill | selección simple, múltiple, filtro | on/off | S02, S16, S21, S25 |
| Picker numérico | altura, peso, edad, medidas | métrico/imperial | S02, S19 |
| Gráfico de línea | peso, medida, kcal | vacío, 1 punto, serie | S03, S18 |
| Hoja inferior (sheet) | añadir, porción, confirmar IA | — | S07–S12 |
| Candado Premium | inline, overlay | — | todas las Premium |
| Burbuja de chat | usuario, coach, tarjeta rica | escribiendo | S21, S23 |
| Visor de cámara | foto, barcode | permiso denegado | S09, S12, S20 |
| Selector de fecha (semana) | diario, plan | hoy, pasado, futuro | S06, S14 |
| Lista con checkbox | compras | marcado | S17 |
| Tab bar | 5 tabs (Hoy, Plan, Progreso, Coach, Perfil) — inferido | badge | global |

## Modelo de datos inferido

```
User        id, email, name, sex, birthdate, height_cm, units, locale,
            created_at, premium_until, referral_code
            evidence: S02, S04, ayuda suscripciones · confidence: high

Goal        user_id, type (lose|gain|maintain), target_weight_kg, pace_kg_week,
            activity_level, diet_type (balanced|high_protein|low_carb|keto|low_fat|smart),
            kcal, protein_g, carbs_g, fat_g, meals_per_day, dynamic_adjust (bool),
            allergies[], conditions[]
            evidence: S02, S03, S25, funcionalidades · confidence: high

Food        id, name, brand, barcode, source (verified|user|ai), serving_units[],
            per_100g {kcal, protein, carbs, fat, fiber, sugar, sat_fat, sodium, …20+},
            nutrition_score
            evidence: S07, S08, S12, App Store "20+ nutrientes" · confidence: high

Recipe      id, name, author (system|user), servings, steps[], image,
            ingredients[] (food_id, qty, unit), tags (diet types), prep_min
            evidence: S13, S15 · confidence: high

FoodLog     id, user_id, date, meal_slot, food_id | recipe_id, qty, unit,
            kcal…(snapshot), method (search|barcode|photo|voice|text|plan)
            evidence: S06, F02–F05 · confidence: high (method: guess)

MealPlan    id, user_id, start_date, days[] -> PlanItem(date, meal_slot, recipe_id, servings, eaten bool)
            shared_with[] (familia)
            evidence: S14, S16, "sincronizar con familia" · confidence: medium

ShoppingItem plan_id, food_id, qty, unit, category, checked
            evidence: S17 · confidence: medium

BodyEntry   user_id, date, weight_kg, body_fat_pct, waist, hip, arm, thigh, chest
ProgressPhoto user_id, date, image_ref, pose
            evidence: S18–S20 · confidence: high

WaterLog    user_id, date, ml               · high
FastSession user_id, protocol, start_at, end_at, target_h   · high
MedLog      user_id, name, dose, schedule, taken_at   · medium (feature v25)
CoachMessage user_id, role, content, created_at, context_snapshot   · medium
Team        id, name, challenge, members[]; TeamMessage   · medium
Subscription user_id, product_id, platform, expires_at, trial_used   · high
ActivityImport user_id, date, active_kcal, steps, source (healthkit)   · high
```

Relaciones: User 1-1 Goal, User 1-n FoodLog, Food 1-n FoodLog, Recipe n-n Food, User 1-n MealPlan 1-n PlanItem, MealPlan 1-n ShoppingItem, User 1-n BodyEntry/WaterLog/FastSession/ProgressPhoto, Team n-n User.

## Matriz de funcionalidades

Ver `features.csv`. Must: 16, should: 17, could: 10, skip: 6.

## Fuera de alcance (no se puede o no se debe clonar)

- La base de datos de 10M+ alimentos verificados por nutricionistas de Fitia y sus 20.000+ recetas → se sustituye por **Open Food Facts** (ODbL, códigos de barras), **USDA FoodData Central** (dominio público, genéricos) y **BEDCA/tablas nacionales** si la licencia lo permite, más recetas propias.
- Marca, logo, nombre "Fitia", "Fitia Coach", "Fitia Teams", textos, ilustraciones, fotos de recetas.
- La comunidad de 20M usuarios (Teams depende de tener red).
- Integraciones directas con Strava/Garmin/Oura/WHOOP vía acuerdos: se cubre todo vía HealthKit.
- Asesoría nutricional/médica certificada: el coach IA debe ir con avisos y sin prometer resultados clínicos.
- Apple Watch y visionOS: posible, pero fuera de la primera versión.

## Tamaño

Pantallas 28, flujos 12, entidades 15. Partes difíciles:
1. **Reconocimiento de comida por foto con estimación de porción** — un modelo Core ML local reconoce clases pero no gramos; calidad tipo Fitia exige un LLM multimodal en la nube (coste por uso).
2. **Base de datos de alimentos** buena en español y por país — es el foso real de Fitia.
3. **Generador de planes** que cuadre kcal + macros + preferencias/alergias con recetas reales (optimización, no solo filtro).
4. Sync offline-first entre dispositivos + StoreKit 2 + HealthKit.

Tamaño: **L** (un trimestre para un dev con experiencia iOS) para el alcance must+should. El núcleo (must) es **M**.
