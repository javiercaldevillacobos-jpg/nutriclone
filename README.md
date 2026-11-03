# NutriClone

App de nutrición para iPhone (SwiftUI, iOS 18+). Esta es la versión 0.1: funciona entera en el
iPhone, sin servidor ni cuenta, y con todas las funciones desbloqueadas.

## Para quien compila (necesitas un Mac)

Requisitos: macOS 15 o posterior, **Xcode 16 o posterior** (App Store) y Homebrew (https://brew.sh).

1. Copia la carpeta `NutriClone` al Mac.
2. Abre Terminal dentro de esa carpeta e instala XcodeGen (solo la primera vez):

   ```bash
   brew install xcodegen
   ```

3. Genera el proyecto y ábrelo:

   ```bash
   xcodegen generate && open NutriClone.xcodeproj
   ```

4. Arriba en Xcode elige el destino **iPhone 16 Pro** (simulador) y pulsa ▶︎ (Cmd+R).

### Instalarlo en un iPhone de verdad

1. Conecta el iPhone por cable y desbloquéalo. En el iPhone: Ajustes > Privacidad y seguridad >
   **Modo de desarrollador** > activar (se reinicia).
2. En Xcode: clic en el proyecto `NutriClone` > target `NutriClone` > **Signing & Capabilities** >
   *Team*: elige tu Apple ID (Add Account… si no aparece). Una cuenta gratuita vale.
3. Si sale un error de *bundle identifier*, cambia `com.nutriclone.app` por algo único
   (por ejemplo `com.tunombre.nutriclone`).
4. Elige el iPhone como destino y pulsa ▶︎. La primera vez, en el iPhone: Ajustes > General >
   VPN y gestión de dispositivos > confía en tu certificado.

Con una cuenta gratuita la app caduca a los **7 días**; basta con volver a pulsar ▶︎.

### Tests

Cmd+U en Xcode, o:

```bash
xcodebuild test -scheme NutriClone -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Si algo no compila

Copia el error completo de Xcode (panel de la izquierda, icono del triángulo rojo) y mándaselo
a quien hizo el código. No hace falta tocar nada más.

## Qué hay en esta versión

- Cuestionario inicial y cálculo de calorías y macros (Mifflin-St Jeor + nivel de actividad + objetivo).
- Diario por día y por comida, con anillo de calorías, barras de macros y agua.
- Buscador sobre la base española BEDCA (955 alimentos, CSV incluido) más una base
  de genéricos y platos incluida (valores aproximados basados en USDA FoodData Central, dominio
  público), recientes, favoritos y alimentos propios. Sin tildes ni mayúsculas.
- Vitaminas y minerales (sodio, potasio, calcio, hierro, vitamina C, colesterol) en los alimentos BEDCA.
- Detalle de alimento con ración en gramos o en unidades.
- Peso con gráfico, historial de calorías de 14 días.
- Perfil con cambio de objetivo y recálculo de metas.

- Escáner de platos con foto (Gemini, nivel gratuito, con tu propia clave). Ver abajo.

Pendiente (siguientes hitos): escáner de código de barras, registro por texto y voz,
planes de comidas y lista de compras, medidas y fotos de progreso, ayuno, Apple Health,
widgets, coach y sincronización en la nube.

## Base de alimentos BEDCA (opcional, recomendado)

La app usa como fuente principal la **BEDCA** (Base de Datos Española de Composición de Alimentos,
AESAN). El CSV ya viene en `Resources/bedca_foods.csv` (descargado el 2026-11-03 de la rama main del
repositorio; SHA-256 c4e37b7e25e3e96765f777c0b9939bb7e8707f94940aecb8c7338bffbdc101b1). Para actualizarlo:

1. Descarga el dataset "BEDCA Food Composition Dataset 2026" de Zenodo
   (https://doi.org/10.5281/zenodo.22017001, zip de unos 4,5 MB) o directamente el fichero
   `output/bedca_foods.csv` del repositorio https://github.com/TerjeRu/bedca-database.
2. Copia `bedca_foods.csv` (tal cual, sin abrirlo ni guardarlo con Excel) en `Resources/`:

   ```
   NutriClone/Resources/bedca_foods.csv
   ```

3. Vuelve a generar el proyecto para que entre en el bundle:

   ```bash
   xcodegen generate
   ```

Al arrancar, la app lee el CSV en segundo plano (955 de sus 957 filas; 2 no tienen energía), convierte la energía de
kJ a kcal cuando hace falta y guarda los valores por 100 g de porción comestible. Los genéricos de
`foods.json` que ya están en BEDCA (por ejemplo "Manzana" o "Pan blanco") no se cargan; si ya estaban
de una versión anterior, se borran salvo que sean favoritos o se hayan usado. Sin el CSV, la app
funciona igual con `foods.json`.

### Licencia y atribución

Los datos de BEDCA permiten uso **personal, educativo y no comercial** citando la fuente:

> AESAN/BEDCA Base de Datos Española de Composición de Alimentos v1.0 (2010)

La app muestra esta atribución en Perfil > Fuentes de datos y al pie de cada alimento BEDCA. Los
valores no se modifican (solo se convierten de unidad). **Si la app se publica o se cobra, hace falta
autorización expresa de AESAN/BEDCA** o quitar el CSV. AESAN y BEDCA no se responsabilizan del uso de
los datos. Errores en los datos: bedca.adm@gmail.com.

Limitación conocida: el CSV ancho no indica la base de cada valor. Según `bedca_units.csv`, algunos
minerales (Ca, Fe, K, Mg, Na, P, Cu, Zn) pueden venir declarados "por kg" en ciertos alimentos; en
esos casos el valor por 100 g saldría 10 veces mayor. Calorías y macronutrientes no se ven afectados.
Para resolverlo habría que leer también `bedca_foodvalues.csv`, que sí indica la base de cada valor.

## Escáner de platos (Gemini, nivel gratuito)

En *Añadir alimento* > **Escanear plato**: haces una foto (o eliges una de la galería), Google Gemini
estima qué alimentos hay y cuántos gramos, la app los cruza con BEDCA y tu catálogo, y tú revisas y
corriges antes de añadirlos al diario. Nada se guarda sin pasar por la revisión.

Configuración (una vez):

1. Entra en https://aistudio.google.com/apikey con tu cuenta de Google y crea una clave. No pide tarjeta.
2. En la app: Perfil > **Escáner de platos**, marca el aviso de coste, pega la clave y pulsa *Guardar clave*.
   Se guarda en el Llavero del iPhone (solo este dispositivo, sin iCloud).

Coste 0 € — qué hace la app y qué depende de ti:

- La app no lleva ninguna clave ni pide datos de pago, y no tiene ningún camino hacia un plan de pago.
- Si se agota la cuota gratuita, Google responde "429": la app espera 2, 4 y 8 s, y si sigue igual te
  pide que esperes. Las peticiones rechazadas por límite no se cobran.
- **Lo único que puede generar un cargo es vincular una cuenta de facturación al proyecto de Google
  de esa clave.** La app no puede ver ni impedir eso: no lo hagas mientras la uses. Los límites
  diarios (se reinician a medianoche hora del Pacífico) se ven en https://aistudio.google.com/rate-limit.
- Modelo por defecto: `gemini-3.6-flash`; alternativa `gemini-3.5-flash-lite` (en ajustes). Ambos
  tenían nivel gratuito el 2026-11-03. Si Google cambia los nombres, se editan en
  `Core/Services/Scan/GeminiService.swift` (`GeminiModel`).

Privacidad: en el nivel gratuito Google puede usar lo que envías para mejorar sus productos. Envía
solo fotos de comida. La foto se reduce a 1024 px antes de enviarla y la clave viaja en la cabecera
`x-goog-api-key`, nunca en la URL.

La cámara solo funciona en un iPhone real; en el simulador usa "Elegir de la galería".

## Estructura

```
project.yml      definición del proyecto (XcodeGen genera NutriClone.xcodeproj)
App/             arranque y pestañas
Core/            modelos SwiftData, cálculo nutricional, carga de alimentos (BEDCA, foods.json, CSV)
DesignSystem/    colores, espaciados y componentes
Features/        una carpeta por pantalla
Resources/       foods.json y, si lo añades, bedca_foods.csv
Tests/           tests unitarios (los del CSV real solo corren si está en Resources)
```

Aviso: NutriClone ofrece estimaciones generales y no sustituye el consejo de un profesional sanitario.
