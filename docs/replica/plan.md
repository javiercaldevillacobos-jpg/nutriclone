# Plan Replica: clon nativo iOS de Fitia (nombre de trabajo: NutriClone)

Objetivo: app SwiftUI para iPhone 16 Pro (iOS 18+), con la funcionalidad de Fitia reconstruida desde cero y marca propia.
Base: `replica/recon.md` (28 pantallas, 12 flujos, 15 entidades) y `replica/features.csv` (16 must / 17 should / 10 could / 6 skip).

> **Requisito de hardware:** compilar, firmar y probar en el simulador o en el iPhone requiere **un Mac con Xcode 26**. Esta máquina es Windows: aquí se puede escribir todo el código Swift, el backend y los materiales, pero no compilar. Opciones: un Mac propio, un Mac en la nube (MacinCloud, AWS EC2 Mac) o CI (Xcode Cloud / GitHub Actions macOS) que genere builds para TestFlight.

---

## 1. Recon (`/replica-recon`) — hecho en parte

- [x] Fuentes públicas: web, funcionalidades, premium, ayuda, App Store.
- [x] Inventario de pantallas, flujos, componentes, modelo de datos, matriz.
- [ ] **Pendiente:** capturas de referencia. Tú, con tu propia cuenta de Fitia (si los términos de uso lo permiten), recorres cada pantalla S01–S28 y guardas capturas en `replica/screens/S06-diario.png`, etc. Sin esto, el diseño y el diff de layout trabajan a ciegas.

## 2. Architect (`/replica-architect`)

**Stack iOS**
| capa | elección | por qué |
| --- | --- | --- |
| UI | SwiftUI + Observation (`@Observable`), NavigationStack, TabView | nativo, 120 Hz ProMotion gratis |
| Persistencia local | **SwiftData** (offline-first) | menos código que Core Data, migraciones versionadas |
| Gráficos | Swift Charts | peso, medidas, nutrientes |
| Código de barras | VisionKit `DataScannerViewController` (fallback AVFoundation) | EAN-13/UPC listo, sin modelo propio |
| Foto | 1) Vision + modelo Core ML (Food-101/clasificador propio) para sugerencia rápida en local; 2) **LLM multimodal vía backend** para lista de alimentos + gramos estimados | Core ML solo da clase, no porción |
| Voz | `SpeechAnalyzer`/`SFSpeechRecognizer` on-device (es-ES) → mismo parser que texto | privacidad, sin red para transcribir |
| Parser texto→alimentos | LLM con salida JSON estructurada vía backend; fallback local con reglas (cantidad + unidad + búsqueda) | |
| Salud | HealthKit (leer activeEnergyBurned, steps, workouts, bodyMass; escribir bodyMass, dietaryEnergy y macros) | |
| Pagos | StoreKit 2 + `SubscriptionStoreView` | paywall nativo, sin servidor de recibos obligatorio |
| Widgets / Live Activity | WidgetKit + ActivityKit + App Intents | ayuno en Isla Dinámica del 16 Pro |
| Notificaciones | UserNotifications locales | recordatorios |
| Red | URLSession async/await, sin dependencias | |
| Arquitectura | módulos SPM: `Core` (modelos, cálculo), `FoodDB`, `Logging`, `Plan`, `Progress`, `Coach`, `HealthSync`, `Paywall`, `DesignSystem` | tests aislados |

**Esquema** (SwiftData en local, Postgres en Supabase espejo): User, Goal, Food, Recipe, RecipeIngredient, FoodLog, MealPlan, PlanItem, ShoppingItem, BodyEntry, ProgressPhoto, WaterLog, FastSession, MedLog, CoachMessage. Índices: `Food.barcode` único, `Food.name` trigram (pg_trgm) para búsqueda, `FoodLog(user_id, date)`, `BodyEntry(user_id, date)`. RLS en todas las tablas por `auth.uid()`.

**API (Supabase Edge Functions)**
- `GET /foods/search?q=&locale=` — BD propia + Open Food Facts + USDA, cacheado.
- `GET /foods/barcode/:ean` — BD propia → Open Food Facts → 404 (crear alimento).
- `POST /ai/parse-meal` {text} → [{food, qty, unit}] (texto y voz).
- `POST /ai/photo-meal` {image} → [{food, grams, confidence}].
- `POST /plans/generate` {goal, days, exclusions} → MealPlan.
- `POST /coach/chat` {messages, day_context} → stream SSE.
- Sync: tablas Postgres directas con RLS + `updated_at` para last-write-wins.

**Orden de construcción (rebanada vertical primero):** onboarding → cálculo → diario → buscar/añadir alimento → peso. Todo lo demás encima.

## 3. Design (`/replica-design`)

- Tokens en `DesignSystem`: `Color` por rol (brand, surface, textPrimary, macroProtein/Carbs/Fat, success, warning, danger) con variantes claro/oscuro en Asset Catalog; tipografía **SF Pro / SF Rounded** con Dynamic Type (`.largeTitle` … `.caption2`), escala de espaciado 4/8/12/16/24/32, radios 8/12/20, materiales `.regularMaterial`.
- Paleta **propia** (no el verde/branding de Fitia); se valida contraste WCAG AA con el checker de la skill.
- Iconos: SF Symbols (fork.knife, barcode.viewfinder, camera.viewfinder, mic.fill, scalemass, drop.fill, timer). Ilustraciones y fotos de recetas propias o generadas.
- Componentes (del recon): ProgressRing, MacroBar, MealCard, FoodRow, PortionPicker, PremiumLock, ChatBubble, WeekDatePicker, NumberWheel, CameraViewport. Cada uno con `#Preview` en todos sus estados.
- Pantallas clave a especificar primero: S06 Diario, S07 Añadir, S09/S10/S12 captura, S14 Plan, S18 Progreso, S24 Perfil.
- HIG: tab bar de 5, sheets con detents para añadir alimento, haptics (`.sensoryFeedback`) al registrar, botones ≥44 pt, soporte VoiceOver y Dynamic Type XXL.

## 4. Build (`/replica-build`)

Sprint 1 — rebanada vertical (must)
1. App shell: TabView, NavigationStack, DesignSystem, SwiftData container.
2. Onboarding S01–S03 + `NutritionCalculator`:
   - BMR Mifflin-St Jeor: H = 10·kg + 6,25·cm − 5·edad + 5; M = … − 161.
   - TDEE = BMR × actividad (1,2 / 1,375 / 1,55 / 1,725 / 1,9).
   - Objetivo: perder −(ritmo kg/sem × 7700 / 7), ganar +250–500, mantener 0; mínimo de seguridad 1200 (M) / 1500 (H).
   - Macros: proteína 1,6–2,2 g/kg según objetivo, grasa 25–30 % kcal, carbos = resto; presets keto/low-carb/low-fat/alto en proteína.
   - Tests unitarios con casos conocidos.
3. Diario S06 + añadir S07/S08 con BD semilla (USDA + OFF subset en SQLite empaquetado).
4. Escáner S12 (VisionKit) → Open Food Facts API pública.
5. Peso S18/S19 con Swift Charts. Agua S27. Recordatorios.

Sprint 2 — captura inteligente (should)
6. Texto libre S11 → `/ai/parse-meal`. 7. Voz S10 (Speech on-device → mismo parser). 8. Foto S09 (Core ML local de sugerencia + `/ai/photo-meal`) con pantalla de revisión obligatoria.

Sprint 3 — plan y progreso
9. Generador de planes: por cada comida, elegir recetas cuya suma se acerque a kcal/macros objetivo (búsqueda greedy + ajuste de raciones; después programación entera si hace falta), respetando exclusiones. S14–S17.
10. Medidas, % grasa (US Navy), fotos de progreso S19–S20. 11. Ajuste dinámico semanal de kcal según tendencia de peso (media móvil 7 días).

Sprint 4 — plataforma
12. HealthKit S26. 13. Ayuno S22 + Live Activity + widgets. 14. Paywall StoreKit 2 S05 (gating por feature según features.csv). 15. Coach S21.

Rendimiento iPhone 16 Pro: listas con `LazyVStack`, imágenes con downsampling, Core ML en Neural Engine (`.cpuAndNeuralEngine`), cámara con formato 4K solo cuando hace falta, animaciones a 120 Hz (`CADisableMinimumFrameDurationOnPhone` = YES en Info.plist).

## 5. Backend (`/replica-backend`)

Recomendación: **Supabase** (Postgres + Auth + Storage + Edge Functions) — el esquema relacional encaja mejor que Firestore para alimentos/recetas/planes y la búsqueda trigram.
- Auth: Sign in with Apple (obligatorio si hay otro login social) + email OTP.
- Storage: fotos de progreso (bucket privado, cifrado) — o solo en el dispositivo para máxima privacidad.
- Edge Functions con la API de Claude (modelo multimodal) para parse-meal, photo-meal y coach; claves solo en servidor, rate limit por usuario y por plan.
- Coach: prompt de sistema con contexto del día (metas, registrado, restante), avisos de que no es consejo médico, sin diagnósticos; registros de conversación borrables.
- Importación: job que carga USDA FoodData Central y volcado de Open Food Facts (respetar ODbL: atribución y share-alike de la base derivada).
- Checklist de seguridad de la skill: RLS, secretos, borrado de cuenta (obligatorio en App Store), datos de salud nunca para publicidad.

## 6. Test (`/replica-test`)

- Unit tests (Swift Testing): calculadora, parser, generador de planes, conversión de unidades.
- UI tests (XCUITest) para F01–F12 en simulador **iPhone 16 Pro**: happy path + edges del recon (permiso de cámara denegado, sin red, código no encontrado, meta incoherente).
- Dispositivo físico: cámara, escáner, voz, HealthKit, Live Activity (no funcionan bien en simulador).
- Instruments: Time Profiler y Hangs en el Diario con 1 año de datos; objetivo arranque en frío < 400 ms.
- Informes de bug en el formato de la skill.

## 7. Diff (`/replica-diff`)

- Puntuación de paridad desde `features.csv` (must pesa más).
- Diff de layout con tus capturas de `replica/screens/` frente a capturas del simulador (ignora color, así la nueva marca no penaliza).
- Lista de pendientes en orden de construcción.

## 8. Entrepreneur (`/replica-entrepreneur`)

- Leer reseñas públicas reales (App Store, Google Play, Reddit) de Fitia: quejas frecuentes en el sector son precio de Premium, funciones antes gratis ahora de pago, precisión de la foto, anuncios. Se verifica con citas reales en esta fase, no se supone.
- Salida: ángulo de posicionamiento (p. ej. "registro por foto gratis", "privacidad: todo en el dispositivo", "pago único") y fixes priorizados.

## 9. Brand (`/replica-brand`)

- Candidatos de nombre (evitar "Fit-" parecido a Fitia y "NutriTrack", que ya existe en el sector) con comprobación de marca (EUIPO, USPTO, OEPM), dominio, App Store y redes.
- Paleta propia con contraste comprobado, brief de logo, guía de voz en español.
- Barrido del código buscando "Fitia" y restos antes de lanzar.

## 10. Launch (`/replica-launch`)

- Ficha App Store: nombre ≤30, subtítulo ≤30, keywords ≤100 caracteres, descripción; sin mencionar a Fitia (regla anti-copycat 4.1 de Apple).
- Capturas 6,9" (1320×2868) y 6,3" (1206×2622, iPhone 16 Pro) generadas del simulador.
- Política de privacidad (datos de salud, HealthKit, IA de terceros), términos, URL de soporte; etiquetas de privacidad de la App Store.
- Precios frente a los públicos de Fitia (19,99 $/mes, 53,99–59,99 $/año).
- Landing page.

## 11. Deploy (`/replica-deploy`)

- Apple Developer Program (99 $/año), bundle ID, capacidades: HealthKit, Sign in with Apple, In-App Purchase, Push, App Groups (widgets).
- Xcode → Archive → TestFlight → tu iPhone 16 Pro.
- Revisión App Store: puntos sensibles — 1.4.1 (afirmaciones de salud), 5.1.1 (borrado de cuenta, permisos), 5.1.3 (HealthKit: no publicidad ni iCloud de datos de salud), 3.1.1 (IAP), 4.1 (copycat).
- Supabase en producción, monitoreo (Sentry o MetricKit), dominio y email.
