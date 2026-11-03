# Arquitectura: NutriClone (reconstrucción de las funciones principales de Fitia)

Fecha: 2026-11-03 · Entrada: `replica/recon.md`, `replica/features.csv`

## Restricción que manda: tú no tienes Mac, compila un amigo

Todo se decide para que tu amigo pueda, en su Mac, hacer esto y nada más:

```bash
brew install xcodegen
```
```bash
xcodegen generate && open NutriClone.xcodeproj
```

y pulsar ▶︎ con el simulador iPhone 16 Pro (o su iPhone/el tuyo conectado).

Consecuencias:
1. **XcodeGen**: el proyecto se describe en `project.yml` (texto legible que puedo escribir y revisar desde Windows). El `.xcodeproj` no se versiona; se genera. Evita el problema de editar a mano un `project.pbxproj`.
2. **Cero dependencias externas en la v1** (sin CocoaPods, sin paquetes SPM obligatorios). Todo con frameworks de Apple. La SDK de Supabase entra solo en el hito de sync, como paquete SPM que Xcode descarga solo.
3. **Modo local por defecto**: sin claves ni backend la app arranca y es usable (BD de alimentos semilla empaquetada, IA simulada con un parser local). Las claves van en `Config.xcconfig` opcional, ignorado por git; `Config.example.xcconfig` documenta qué poner.
4. **Firma**: `DEVELOPMENT_TEAM` vacío en `project.yml`; tu amigo elige su equipo (cuenta Apple gratuita sirve para instalar en un iPhone 7 días; HealthKit y Sign in with Apple **requieren** cuenta de pago de 99 $/año → esas capacidades van detrás de un flag para que la build gratuita compile).
5. **Simulador primero**: cámara, voz, HealthKit y Live Activities se prueban en iPhone real; en simulador hay entradas simuladas (botón "usar foto de ejemplo", "código de ejemplo").
6. Opcional más adelante: GitHub Actions en `macos-15` que compila en cada push → sabes si compila sin molestar a tu amigo.

## Stack

| capa | elección | por qué |
| --- | --- | --- |
| lenguaje / UI | Swift 6, SwiftUI, Observation (`@Observable`) | nativo, 120 Hz ProMotion, lo que pediste |
| mínimo | iOS 18.0, iPhone | SwiftData maduro, `MeshGradient`, widgets interactivos; el 16 Pro trae iOS 18+ |
| proyecto | XcodeGen (`project.yml`) | generable en cualquier Mac, editable desde Windows |
| persistencia | SwiftData (offline-first) | menos código que Core Data, sin dependencias |
| BD de alimentos semilla | SQLite de solo lectura empaquetado (`foods.sqlite`, ~3–5 MB) leído con la API C de SQLite3 | 5–10k alimentos genéricos USDA + traducción; búsqueda instantánea offline |
| código de barras | VisionKit `DataScannerViewController` | EAN/UPC sin modelo propio |
| foto | `PhotosPicker`/cámara → Edge Function `photo-meal` (Claude multimodal); fallback local Vision `VNClassifyImageRequest` para sugerir nombres | Core ML solo da clase, no gramos |
| voz | Speech (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`) | transcripción local en es-ES |
| texto → alimentos | `MealParser` local (cantidad + unidad + búsqueda) y, si hay backend, `parse-meal` con LLM | funciona sin red |
| gráficos | Swift Charts | peso, medidas, nutrientes |
| salud | HealthKit (flag `HEALTHKIT_ENABLED`) | leer energía activa/pasos/peso, escribir peso y nutrición |
| pagos | **ninguno** — decisión del usuario (2026-11-03): sin paywall, todo desbloqueado | se quitan StoreKit, `subscriptions` y el webhook de App Store |
| widgets / ayuno | WidgetKit + ActivityKit (target extensión, hito 4) | Isla Dinámica del 16 Pro |
| notificaciones | UserNotifications locales | recordatorios sin servidor |
| backend | Supabase: Postgres + Auth + Storage + Edge Functions (Deno/TS) | un solo proveedor, SQL relacional para alimentos/planes, gratis al empezar |
| IA | API de Claude desde Edge Functions (clave solo en servidor) | parse, foto, coach, plan |
| BD externa de alimentos | Open Food Facts API pública (barcode) + USDA FoodData Central (semilla) | licencias abiertas (ODbL / dominio público) |
| tests | Swift Testing (unit) + XCUITest (flujos) | incluido en Xcode |

Una sola base de datos en la nube, sin microservicios. La app es la fuente de verdad local; la nube es copia y sync.

## Estructura del proyecto

```
NutriClone/
  project.yml                    XcodeGen
  Config.example.xcconfig        SUPABASE_URL, SUPABASE_ANON_KEY (opcionales)
  README.md                      instrucciones para tu amigo, paso a paso
  App/
    NutriCloneApp.swift          @main, ModelContainer, entorno
    RootView.swift               onboarding o TabView
  Core/
    Models/                      @Model SwiftData (espejo de schema.sql)
    Nutrition/                   NutritionCalculator, MacroPreset, BodyFat
    Services/                    FoodRepository, MealParser, AIService (protocolo + Mock + Supabase),
                                 BarcodeService (OFF), HealthService, StoreService, ReminderService
  DesignSystem/                  Tokens (Color, Font, Spacing), componentes (ProgressRing, MacroBar…)
  Features/
    Onboarding/  Diary/  AddFood/  Capture/ (Photo, Voice, Text, Barcode)
    Plan/  Progress/  Coach/  Fasting/  Profile/  Paywall/
  Resources/
    foods.sqlite  recipes.json  Assets.xcassets  Localizable.xcstrings  NutriClone.storekit
  Tests/  UITests/
  Widgets/                       (hito 4)
supabase/
  migrations/0001_init.sql       = replica/schema.sql
  functions/ parse-meal  photo-meal  coach-chat  generate-plan  barcode  app-store-notifications
```

Cada `AIService`/`BarcodeService` es un protocolo con implementación `Mock` (por defecto) y `Supabase`. Se inyecta por entorno; así todo compila y se previsualiza sin red.

## Esquema

Tablas: **18** (`profiles, goals, foods, recipes, recipe_ingredients, favorites, food_logs, water_logs, meal_plans, plan_items, shopping_items, body_entries, progress_photos, fast_sessions, activity_days, coach_messages, ai_usage, subscriptions` — `profiles` cuelga de `auth.users`). Acceso: **Row Level Security** en todas; el catálogo público (`user_id is null`) es de solo lectura; `ai_usage` y `subscriptions` solo las escriben Edge Functions con service role.

SQL completo: [`replica/schema.sql`](schema.sql). Decisiones clave:
- `food_logs` guarda un **snapshot** de nombre y macros: el diario no cambia si se corrige o borra el alimento.
- Días como `date` local (`log_date`), instantes como `timestamptz` UTC.
- IDs generados en el cliente (UUID) → reintentos de sync idempotentes.
- `deleted_at` (borrado lógico) en tablas sincronizadas para propagar borrados.
- Índice único parcial: **un solo ayuno abierto** por usuario; un código de barras público único.
- Búsqueda: `pg_trgm` sobre `lower(name)` + función `search_foods`.

En local, los `@Model` de SwiftData replican estas entidades con los mismos nombres de campo y añaden `syncState` (`pending|synced`).

## API

Todo pasa por Supabase. Las lecturas/escrituras CRUD van directas a tablas con RLS (cliente PostgREST); solo lo que necesita secretos o lógica va en Edge Functions.

| método ruta | hace | quién | entrada | salida | flujo |
| --- | --- | --- | --- | --- | --- |
| Auth `signInWithIdToken` (Apple) | login con Sign in with Apple | anónimo | identity token | sesión | F01 |
| Auth OTP email | login por email | anónimo | email, código | sesión | F01 |
| `rpc search_foods` | buscar alimentos | usuario | q, lim | foods[] | F02 |
| `GET /functions/v1/barcode?ean=` | BD propia → Open Food Facts → normaliza y cachea en `foods` | usuario | ean | food \| 404 | F03 |
| `POST /functions/v1/parse-meal` | texto/voz → alimentos con gramos (salida JSON estructurada), cruza con `foods` | usuario, cuota | {text, locale} | [{name, grams, food_id?, kcal…, confidence}] | F05, S11 |
| `POST /functions/v1/photo-meal` | imagen (≤1 MB, JPEG 1024 px) → alimentos y gramos | usuario Premium, cuota | {image_base64} | igual que arriba | F04 |
| `POST /functions/v1/generate-plan` | genera plan N días con recetas que cuadren kcal/macros/exclusiones | usuario Premium | {start_date, days} | meal_plan + items + shopping | F06, F07 |
| `POST /functions/v1/coach-chat` | coach IA con contexto (meta, día, últimos 7 días), streaming SSE | usuario Premium, cuota | {messages[]} | stream texto | F10 |
| tablas `food_logs, water_logs, body_entries, …` upsert por `id` | sync | usuario (RLS) | filas con `updated_at` | filas | todos |
| `GET` tablas `?updated_at=gt.{cursor}` | pull de cambios | usuario | cursor | filas | sync |
| Storage `progress-photos/{uid}/…` | fotos de progreso privadas | usuario | jpeg | path | F08 |
| `POST /functions/v1/delete-account` | borra usuario y datos (requisito App Store 5.1.1) | usuario | — | 204 | S24 |

Webhooks de entrada: **App Store Server Notifications v2** → `app-store-notifications` (verifica JWS firmado por Apple, actualiza `subscriptions`; idempotente por `notificationUUID`).
Webhooks de salida: ninguno.
Jobs:
- `ajuste-dinamico` (cron Supabase, semanal, lunes 04:00 UTC): con ≥2 semanas de peso, compara tendencia real con la esperada y propone nuevo `kcal` (la app lo muestra como sugerencia; no cambia sin confirmar).
- `limpieza-ia` (diario): borra `ai_usage` > 90 días.
- Recordatorios: **locales** en el iPhone, sin job de servidor.

Solo APIs oficiales y públicas con tus propias claves (Supabase, Anthropic, Open Food Facts, USDA). Nunca endpoints privados de Fitia.

## Las partes que muerden

- **Zonas horarias:** el "día" de un registro es el día local del usuario al registrar; se guarda `log_date` explícito. Viajar no mueve registros pasados. Ayuno con instantes UTC.
- **Idempotencia:** UUID de cliente en cada fila; upsert por `id`. Notificaciones de App Store deduplicadas por `notificationUUID`.
- **Conflictos de sync:** last-write-wins por `updated_at` por fila; suficiente para datos de un solo usuario. Borrados con `deleted_at`.
- **Carreras:** dos ayunos abiertos → índice único parcial. Marcar "comido" un item del plan dos veces → `eaten_log_id` único por item.
- **Límites y coste de IA:** cuota diaria por usuario y tipo en `ai_usage` (p. ej. gratis 5 parse/día, Premium 50 fotos/día), imágenes reducidas a 1024 px antes de subir, timeout 20 s, respuesta siempre editable por el usuario.
- **Precisión de la IA:** la foto y la voz **nunca** registran directo: siempre hay pantalla de revisión con gramos editables.
- **Búsqueda:** offline en `foods.sqlite` (FTS5 con `unicode61 remove_diacritics`) + online `search_foods`; se fusionan resultados.
- **Offline:** todo el núcleo funciona sin red; la cola de sync se vacía al recuperar conexión.
- **Tamaño de ficheros:** fotos de progreso comprimidas HEIC/JPEG ≤ 1 MB.
- **Permisos:** cámara, micrófono, voz, fotos, HealthKit, notificaciones: textos en Info.plist (en `project.yml`) y estados de "permiso denegado" con botón a Ajustes.
- **Datos de salud / RGPD:** datos de salud = categoría especial. Consentimiento explícito, borrado de cuenta en la app, exportación de datos, nada de HealthKit a publicidad ni a terceros (regla 5.1.3 de Apple), IA de terceros declarada en la política.
- **Contenido médico:** el coach no diagnostica; mínimo de kcal de seguridad (1200 M / 1500 H) y aviso para menores, embarazo y TCA.
- **Licencia ODbL de Open Food Facts:** atribución visible y la base derivada de OFF se comparte con la misma licencia.
- **Firma sin cuenta de pago:** HealthKit y Sign in with Apple no se pueden firmar con cuenta gratuita → flags en `project.yml` para desactivarlos.

## Orden de construcción

1. **Rebanada vertical** (fea pero completa, solo local, sin backend)
   Pantallas: S02 onboarding → S03 resultado → S06 diario → S07 buscar → S08 detalle → S18/S19 peso.
   Datos: `Profile, Goal, Food (semilla), FoodLog, BodyEntry` en SwiftData.
   Prueba que tu amigo puede generar, compilar y abrir en el simulador del iPhone 16 Pro. **Este es el primer entregable.**
2. **Imprescindibles** (`must` de features.csv)
   S01 bienvenida, S12 escáner + `barcode` (OFF directo desde la app primero), S11 texto con `MealParser` local, S13 crear alimento/receta, recientes y favoritos, S27 agua, recordatorios, S24 perfil, S05 paywall StoreKit 2 con `.storekit` local, comidas por día.
3. **Importantes** (`should`)
   3a. Backend: `schema.sql`, Auth, sync, `parse-meal`, `photo-meal` → S09 foto, S10 voz.
   3b. Plan: recetas propias (`recipes.json`), `generate-plan`, S14–S17.
   3c. Progreso: medidas, % grasa US Navy, fotos S20, historial de nutrientes, ajuste dinámico.
   3d. Plataforma: HealthKit S26, ayuno S22 + Live Activity, widgets, coach S21.
4. **Opcionales** (`could`) y después los arreglos que salgan de `/replica-entrepreneur`.

Riesgos principales: (1) la calidad de la BD de alimentos en español sin la de Fitia; (2) coste y precisión de la foto con IA; (3) compilar a distancia: cada iteración depende de tu amigo → conviene montar GitHub Actions en macOS pronto.
