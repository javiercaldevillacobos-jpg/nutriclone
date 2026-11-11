# Build log

Código en `NutriClone/`. Escrito en Windows, **sin compilar todavía**: la primera compilación la hace un Mac con Xcode 16+ (ver `NutriClone/README.md`). Sin capturas en `replica/clone-screens/` hasta que haya simulador.

Decisión del usuario (2026-11-03): **sin sistema de pago**. Todo funciona como Premium; S05 paywall y referidos pasan a `skip`.

| ID | fecha | estado | falta | notas |
| --- | --- | --- | --- | --- |
| shell | 2026-11-03 | hecho | — | XcodeGen, TabView de 5 pestañas, tokens, SwiftData, carga de 118 alimentos |
| S01 | 2026-11-03 | hecho | — | bienvenida integrada como primer paso del cuestionario |
| S02 | 2026-11-03 | hecho | unidades imperiales | 11 pasos; meta y ritmo se saltan si el objetivo es mantener; valida meta e IMC ≥ 18,5 |
| S03 | 2026-11-03 | hecho | gráfico de proyección | kcal, macros, fecha estimada, gasto, agua, aviso de mínimo de seguridad |
| S04 | — | pendiente | todo | sin cuenta en v0.1 (todo local) |
| S05 | — | skip | — | eliminado a petición |
| S06 | 2026-11-03 | hecho | racha | tira semanal, anillo, macros, comidas 3–5, borrar con deslizar, agua |
| S07 | 2026-11-03 | parcial | búsqueda online (OFF/USDA), accesos a foto/voz/escáner/texto | búsqueda sin tildes, favoritos, recientes, mis alimentos, vacío con "crear" |
| S08 | 2026-11-03 | hecho | micronutrientes extra, puntuación | ración o gramos, cambiar comida, favorito |
| S13 | 2026-11-03 | parcial | recetas con ingredientes | alimento propio con aviso si macros y kcal no cuadran |
| S18 | 2026-11-03 | hecho | medidas, % grasa | gráfico de peso por periodo con meta, calorías 14 días, lista con borrar |
| S19 | 2026-11-03 | parcial | medidas corporales | un registro por día (sustituye) |
| S24 | 2026-11-03 | parcial | recordatorios, exportar, integraciones | metas, comidas/día, datos, borrar todo |
| S25 | 2026-11-03 | parcial | editar gramos a mano | objetivo, ritmo, meta, actividad, dieta con vista previa |
| S27 | 2026-11-03 | hecho | — | vasos de 250 ml dentro del diario |
| S14–S17, S21 | — | stub | todo | pestañas Plan y Coach muestran "Próximamente" |

Riesgo conocido: al no poder compilar aquí, la primera build puede dar errores menores de tipos; se corrigen con el log de Xcode.

Resumen: pantallas 12 de 28 tocadas (8 hechas, 6 parciales); imprescindibles 10 de 15 activos hechos (2 parciales, 3 pendientes: escáner, texto, recordatorios; cuenta pasa al backend).

## v0.2 · 2026-11-03 · BEDCA

| pieza | estado | notas |
| --- | --- | --- |
| CSVParser | hecho | RFC 4180, BOM, CRLF, comillas dobles; recorre escalares Unicode |
| BedcaImporter / BedcaSeeder | hecho | lee bedca_foods.csv por nombre de columna; ENERC kJ→kcal según `ENERC_unit`; g/mg/µg; vacío = nil; filas sin energía se saltan; lectura en segundo plano |
| Food | hecho | `.bedca`, `bedcaID`, grasa saturada, colesterol, Na, K, Ca, Fe, vit. C (opcionales, migración automática); `#Index` en searchKey y sourceRaw |
| Catálogo | hecho | BEDCA principal + foods.json sin duplicados (nombre completo o primer tramo); limpia duplicados de instalaciones anteriores salvo favoritos/usados |
| Atribución | hecho | Perfil > Fuentes de datos y pie del detalle de alimento BEDCA; README |
| Tests | hecho | parser, importador con 2 filas reales, unidades, búsqueda con/sin tildes; 4 tests con el CSV real que solo corren si está en Resources |

CSV incluido en Resources (955 alimentos cargables de 957; 3,3 % con kcal y macros a más del 20 %, el test admite 10 %). Sodio sospechoso en algunos quesos (p. ej. 13,5 g/100 g), compatible con valores declarados por kg. Base por kg de algunos minerales sin resolver (requiere bedca_foodvalues.csv). Licencia BEDCA no comercial: choca con publicar la app en la App Store sin autorización de AESAN.

## v0.3 · 2026-11-03 · Escáner de platos (Gemini)

| pieza | estado | notas |
| --- | --- | --- |
| S09 escáner | hecho | cámara (UIImagePickerController) o galería (PhotosPicker); superposición "Analizando tu plato…" cancelable |
| GeminiService | hecho | actor; generateContent v1beta; `gemini-3.6-flash` por defecto, `gemini-3.5-flash-lite` alternativo; JSON mode; reintentos 429 (2/4/8 s) y 5xx (1); 400/401/403, sin red y timeout mapeados; sesión efímera 30 s |
| KeychainService | hecho | genérico, WhenUnlockedThisDeviceOnly |
| Ajustes | hecho | Perfil > Escáner de platos: SecureField, guardar/borrar, enlace AI Studio, aviso anti-cargos con confirmación obligatoria (`didAcknowledgeFreeTier`), modelo, privacidad |
| Revisión | hecho | gramos editables, cambiar alimento, incluir/excluir, total en vivo; sin coincidencia = sin macros y no se añade |
| Tests | hecho | parser, petición, reintentos, errores, matcher y Llavero con transporte simulado |

Desviaciones del encargo: clave en cabecera `x-goog-api-key` en vez de `?key=` (la documentación actual usa la cabecera y así no queda en la URL); sin `responseJsonSchema` (solo `responseMimeType`) porque la referencia actual no lo confirma de forma literal y un campo erróneo daría 400.
No probado contra la API real (no hay clave ni dispositivo aquí). Riesgo: nombres de modelo o campos camelCase si Google los cambia.

## v0.4 · 2026-11-11 · Código de barras

| pieza | estado | notas |
| --- | --- | --- |
| S12 lector | hecho | VisionKit DataScannerViewController (EAN-13, EAN-8, UPC-E), linterna, entrada manual si no hay cámara o permiso |
| Barcode | hecho | dígito de control GTIN, UPC-E → UPC-A, UPC-A → EAN-13 |
| OpenFoodFactsService | hecho | API v2 sin clave, User-Agent propio, kcal o kJ, números como texto, 404/status 0 = no encontrado |
| Revisión | hecho | CreateFoodView reutilizado con datos precargados; guarda con código y abre el detalle para elegir ración |
| Atribución | hecho | Open Food Facts (ODbL) en detalle y Perfil |
| Tests | hecho | códigos, parser con respuestas reales, petición, 404, sin red |

No probado en dispositivo: el lector solo funciona en iPhone real.
