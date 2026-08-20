# APEX

App iOS nativa de seguimiento de rendimiento deportivo. Integra Strava, Apple HealthKit y un coach de IA basado en Claude para darte una visión completa de tu recuperación, carga de entrenamiento y salud diaria.

> **Trabajo de Fin de Máster** — Máster en Desarrollo de Software e Inteligencia Artificial.
> Autor: Diego Álvarez. Repositorio: https://github.com/diegoalvarezf/apex

---

## Características

### Dashboard
- **Body Battery** — energía acumulada día a día al estilo Garmin/Firstbeat: solo recarga durmiendo (aditiva sobre la batería con la que te acostaste, no anclada al Recovery); el ejercicio drena según su carga; despierto, nunca sube.
- **Recuperación** — score 0–100 tipo *readiness* (Whoop/Oura/Garmin): 45% HRV + 15% FC en reposo + 25% sueño + 15% carga (ACWR), con HRV y FC como z-score contra tu baseline de 60 días.
- **Esfuerzo** — TRIMP de Banister continuo acumulado en el día (actividades + FC de fondo elevada), con curva saturante a 0–100.
- **Estrés** — media diaria del estrés fisiológico horario: (FC − FC reposo) / reserva cardíaca.
- **Carga de entrenamiento (ACWR)** — ATL/CTL con 180 días de historial. Barra de 4 colores: azul (<0.8), verde (0.8–1.3), amarillo (1.3–1.5), rojo (>1.5).
- **Sueño** — duración, sueño profundo, score y tendencia semanal.
- **Smart Tips** — alertas locales instantáneas basadas en recuperación, HRV, carga acumulada y déficit de sueño.
- **Calendario** — desde la cabecera "Hoy": el mes con el valor de cada día (Body Battery, estrés o recuperación) y, al entrar en un día, sus métricas, la curva horaria de batería, el sueño y las actividades de esa jornada.

### Pestaña Salud
- **Edad Apex** — edad de fitness anclada al VO2max: la edad a la que la media poblacional de VO2max (datos normativos HUNT / Loe 2013, n=3.816) iguala tu valor. FC reposo, HRV, IMC, sueño y actividad aplican ajustes menores (a media potencia cuando hay VO2max, por correlación). Delta con 1 decimal.
- **Métricas corporales** — HRV, FC reposo, temperatura de muñeca, luz solar.
- **Actividad** — VO2max, frecuencia respiratoria, SpO2.
- **Composición corporal** — peso, IMC, masa grasa estimada.

### Actividades
- Historial completo de Strava con mapa y zonas cardíacas.
- Récords personales por disciplina.
- Progresión de ejercicios de fuerza.

### Rutina
- Planificación semanal con generación de rutinas por IA, que usa tu progresión
  registrada, los grupos trabajados esta semana y tus métricas de recuperación.
- Una rutina **activa** a la vez; las demás quedan archivadas y no alimentan a la IA.

### Apex IA
- Análisis personalizado que procesa recuperación, sueño, HRV, carga y actividades recientes para dar recomendaciones accionables.
- Alertas diarias, resumen semanal y análisis por métrica, cacheados para no repetir llamadas.
- Chat con el coach usando tus datos como contexto.
- Sonnet para los análisis del día a día; Opus para diseñar una rutina y para cambiar
  un ejercicio suelto, que son las tareas que más razonamiento exigen.
- Notificaciones diarias a las 8:30 con tu estado de recuperación.
- Catálogo cerrado en el servidor: el cliente pide un análisis por nombre y manda los
  datos ya calculados, nunca un prompt. El servidor decide qué se le pregunta al
  modelo y con qué formato — así se corrige sin publicar versión nueva de la app.

### Apex Pro
Cuotas ampliadas (100 análisis/día en vez de 20, 4 rutinas/mes en vez de 1, 30
cambios de ejercicio en vez de 5) tras canjear un código. La suscripción real por
compra dentro de la app exige cuenta de desarrollador de pago, así que mientras
tanto Pro se activa por código: da el mismo plan que daría la suscripción, no una
simulación. Emisión, canje y revocación de códigos, documentados en
[`backend/README.md`](backend/README.md#apex-pro).

### Widget
- **Body Battery** (small) — anillo con valor actual.
- **Apex · Resumen** (medium) — 4 barras: Body Battery, Recuperación, Esfuerzo, Sueño.
- **Apex · Detalle** (large) — igual con valores grandes y barras con degradado.

### Apple Watch
- Dashboard en muñeca con Battery, Recovery, HRV, sueño, historial de actividades.
- Sincronización en tiempo real vía WatchConnectivity.

---

## Stack técnico

| Capa | Tecnología |
|---|---|
| UI | SwiftUI |
| Datos de salud | HealthKit |
| Actividades | Strava API v3 |
| IA | Anthropic Claude (Sonnet para análisis, Opus para rutinas y cambios de ejercicio) |
| Widget | WidgetKit + App Groups |
| Watch | watchOS + WatchConnectivity |
| Autenticación | ASWebAuthenticationSession (OAuth 2.0) |
| Persistencia | UserDefaults + App Groups · **Keychain** para credenciales |
| Backend | Node + TypeScript (Fastify, Drizzle, Postgres) en Railway |

---

## Configuración

### 1. Clona el repositorio

```bash
git clone https://github.com/diegoalvarezf/apex.git
cd apex
```

### 2. Strava API

1. Crea una aplicación en [strava.com/settings/api](https://www.strava.com/settings/api).
2. Anota tu **Client ID** y **Client Secret**.
3. El **Client ID** va en `StravaConfig` (`Sources/Apex/Services/StravaAuth.swift`).
   No es secreto: viaja en la URL de autorización, a la vista de cualquiera.
4. El **Client Secret** va en el backend, como variable de entorno. Nunca en la app:
   ahí acabaría dentro del binario, de donde se extrae descomprimiendo el `.ipa`.
5. En Xcode, añade el URL Scheme `apex-strava` en `Info.plist` → URL Types.

### 3. Backend

La app no habla directamente con Anthropic ni canjea tokens de Strava: ambas cosas
pasan por un servidor propio, que custodia las credenciales y aplica las cuotas.
Está en [`backend/`](backend/) y tiene su propio README.

En el primer arranque la app se registra contra él y guarda un token de dispositivo
en el Keychain; a partir de ahí manda **el tipo de análisis y los datos**, nunca un
prompt. Así, ni el `client_secret` de Strava ni la clave de Anthropic viajan dentro
del `.ipa`.

Para apuntar a tu propio despliegue, cambia `BackendConfig.baseURL` en
`Sources/Apex/Services/BackendClient.swift`.

### 4. App Groups (widget)

1. En el [Apple Developer Portal](https://developer.apple.com/account), crea el grupo `group.com.tudominio.apex`.
2. Actívalo en los targets **Apex** y **ApexWidget** en Xcode → Signing & Capabilities → App Groups.
3. Actualiza el identificador en `ApexWidget.swift` y `UserProfileManager.swift`.

### 5. HealthKit

Los permisos se solicitan automáticamente en el primer arranque. Asegúrate de que el target tenga la capability **HealthKit** activada en Xcode.

### 6. Abre en Xcode

```bash
open Apex.xcodeproj
```

Selecciona tu dispositivo (se recomienda dispositivo físico para HealthKit y sensores reales) y pulsa **Run**.

### 7. Tests

Los algoritmos de carga de entrenamiento están cubiertos por tests unitarios
(Swift Testing). Los valores esperados salen de aplicar a mano las ecuaciones
publicadas, no de la propia implementación:

```bash
xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17'
```

> Si añades ficheros nuevos, regenera el proyecto con `xcodegen generate` antes de compilar.

---

## Arquitectura

```
Sources/
├── Apex/
│   ├── App/                    # Punto de entrada, entitlements
│   ├── Models/                 # Activity, HealthData, AIInsight, Routine
│   ├── Services/
│   │   ├── HealthKitManager    # Lectura de todos los datos de salud
│   │   ├── BodyBatteryStore    # Cálculo acumulativo de Body Battery
│   │   ├── AIService           # Cliente de la API de Claude
│   │   ├── StravaAPI/Auth      # OAuth y fetching de actividades
│   │   └── NotificationManager
│   ├── ViewModels/
│   │   ├── DashboardViewModel  # Carga de actividades, TRIMP, ATL/CTL
│   │   └── RoutineViewModel
│   └── Views/
│       ├── Dashboard/          # Inicio, cards de métricas, detalle
│       ├── Health/             # Salud, Edad Apex, sueño, composición
│       ├── Activities/         # Historial Strava, récords, progresión
│       ├── Insights/           # Apex IA, alertas
│       ├── Routine/
│       └── Shared/             # Componentes reutilizables
├── ApexWidget/                 # Widget de iOS (WidgetKit)
├── ApexWatch/                  # App de Apple Watch
└── Shared/                     # Colores de métricas: los usan app, widget y reloj
```

---

## Métricas y algoritmos

> 📚 La base científica completa de cada métrica, con referencias a la literatura, está en
> [`docs/METRICS_SOURCES.md`](docs/METRICS_SOURCES.md). Ahí se marcan también las únicas tres
> calibraciones de producto (sin fuente pública).

### Body Battery
Modelo acumulativo día-a-día. Principio de Garmin/Firstbeat: el ejercicio drena según su
**carga (EPOC/TRIMP)**, no según el promedio de FC (que se diluye en el gimnasio). Solo
recarga durmiendo; despierto, la batería solo baja:
- **Entreno (Strava)**: drena `65·(1−e^(−TRIMP/45))` pts repartidos en sus horas.
- **Vida diaria** (sin actividad): reposo ~1 pt/h, vida normal ~1.8 pt/h, esfuerzo sin
  registrar como actividad hasta `HRr²·38`.
- **Sueño**: aditiva sobre la batería con la que te acostaste —no anclada al Recovery—,
  `calidad × factor autonómico (HRV de esa noche) × horas × 6.5`, repartida **por hora**
  para que una noche que cruza medianoche se reparta bien entre los dos días naturales.

Detalle completo, con las constantes y por qué cambiaron, en
[`docs/METRICS_SOURCES.md`](docs/METRICS_SOURCES.md) §8.

### Recovery Score
Modelo tipo *readiness* (Whoop/Oura/Garmin), no HRV+RHR puro: el HRV manda, pero
dormir poco o la carga aguda templan el score aunque el HRV esté alto.

```
score = 0.45 · HRV_score + 0.15 · RHR_score + 0.25 · sueño + 0.15 · carga (ACWR)
```

HRV y RHR son z-scores contra el baseline de 60 días (calibrado vs PeakWatch con
datos reales): z = 0 (en tu media) → 50 pts, ±1 SD ≈ ±17.

### ACWR (Carga de entrenamiento)
- ATL: EMA 7 días (k ≈ 0.134)
- CTL: EMA 42 días (k ≈ 0.0235)
- ACWR = ATL / CTL
- 180 días de historial para convergencia del CTL

### Carga por sesión (ATL/CTL)
TRIMP de Banister (1991) en unidades reales:
`t_min × HRr × 0.64 × e^(1.92·HRr)` (hombres) / `t_min × HRr × 0.86 × e^(1.67·HRr)` (mujeres)

Para ciclismo con potencia usa TSS: `(segundos × NP × IF) / (FTP × 3600) × 100`, con FTP estimado como 95% de la mejor NP en salidas ≥20 min.

### Esfuerzo diario (tile)
TRIMP de Banister continuo acumulado en el día: cada actividad + cada hora de fondo con FC elevada (HRr>0.20) aporta `t·HRr·a·e^(b·HRr)`. Curva saturante `score = 100·(1−e^(−TRIMP/90))`. Se cambió desde Edwards por zonas porque su corte al 50% daba 0 en días sin entreno intenso.

### Sueño
Score anclado a normas AASM / National Sleep Foundation: duración 40% (óptimo 7–9h), sueño profundo N3 20% (≥16% del total), REM 20% (≥20%), eficiencia 20% (≥85%). Eficiencia = tiempo dormido / tiempo en cama (definición AASM).

### Edad Apex (edad de fitness)
`FitnessAgeNorms.fitnessAge(vo2Max:)` invierte la curva normativa de VO2max por edad/sexo del HUNT Study (Loe 2013) para dar la edad a la que la media poblacional iguala tu VO2max.

**Prioridad del VO2max**: medido y vigente (HealthKit, ≤14 días) → estimado con tus
carreras → cociente FCmáx/FCreposo. Cuando no procede de una medición, la app lo
etiqueta como estimado e indica el método en la propia tarjeta.

La estimación con carreras sigue la misma idea que Garmin o Suunto —qué ritmo
sostienes a qué frecuencia cardíaca— pero con ecuaciones publicadas, ya que sus
algoritmos son propietarios: coste de oxígeno por la ecuación de carrera del **ACSM**
y extrapolación al máximo por reserva de FC (**Swain & Leutholtz 1997**). Se toma la
mediana de 90 días descartando series, cuestas y rodajes cortos. Detalle y filtros en
[`docs/METRICS_SOURCES.md`](docs/METRICS_SOURCES.md) §12.

---

## Limitaciones conocidas y trabajo futuro

APEX tiene un servidor propio ([`backend/`](backend/)) que custodia las credenciales
y aplica las cuotas. Lo que sigue son los límites que quedan, declarados antes que
disimulados.

### 1. Resuelto: los secretos ya no viajan en la app

Durante buena parte del desarrollo la app llevaba dentro el `client_secret` de
Strava y una clave de Anthropic. El de Strava no tenía arreglo posible en el
cliente: su OAuth lo exige para canjear el código por el token y no admite PKCE,
que es el mecanismo pensado para que las apps móviles no lleven secretos.

Hoy ambos viven solo en el servidor. La app manda **el tipo de análisis y los
datos**, nunca un prompt ni una credencial, y el canje de Strava pasa por el
backend. Comprobado con `strings` sobre una compilación limpia, fichero por
fichero: ningún secreto aparece en el bundle.

Los tokens que devuelve Strava —esos sí credenciales del usuario— y el token de
dispositivo se guardan en el **Keychain**
(`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). El servidor **no** guarda los
tokens de Strava de nadie: los devuelve y los custodia la app, para no convertirse
en un depósito de credenciales ajenas.

### 2. La identidad del dispositivo no está atestiguada

No hay cuentas: en el primer arranque la app se registra y recibe un token. Para
saber a quién aplicarle la cuota basta, pero **nada impide registrar dispositivos
nuevos en bucle** para renovarla. Lo que acota el gasto son los topes por
dispositivo, no la identidad.

Cerrarlo de verdad requiere **App Attest**, que exige cuenta de desarrollador de
pago (99 $/año) — la misma que falta para la suscripción real por compra dentro
de la app: sin ella no hay productos en App Store Connect ni recibos que validar.
Mientras tanto, Apex Pro funciona igual pero se activa **por código** en vez de
por compra (ver arriba); el día que haya cuenta de pago, validar el recibo llama
a la misma función que ya concede Pro y no cambia nada más.

Como techo aparte —no depende de identificar a nadie—, el servidor tiene un
**límite de gasto diario** para toda la instalación: se mira antes de cada
llamada y corta si se supera, así que un abuso de este agujero tiene tope aunque
no se pueda cerrar del todo.

### 3. Salir al mercado es un proyecto distinto

Distribuir la app en la UE implicaría cumplir el **RGPD** con datos de categoría
especial (art. 9): HRV, sueño y frecuencia cardíaca lo son. Eso exige
consentimiento explícito y granular, política de privacidad real, finalidad
limitada, plazos de conservación y derecho de acceso y borrado. También habría que
declarar a Anthropic como encargado del tratamiento, firmar el acuerdo
correspondiente y advertir de forma clara que los análisis no son consejo médico.

Y hay una contrapartida que el backend introduce: antes los datos de salud iban del
dispositivo directos a la API de Anthropic; ahora pasan por un servidor propio. Se
gana control sobre las claves a cambio de custodiar datos ajenos, lo que en la UE es
más responsabilidad, no menos.

### 4. El histórico vive solo en el dispositivo

La app guarda una foto diaria de las métricas calculadas (`DailySnapshotStore`) para
que consultar un día pasado devuelva lo que se vio aquel día y no un recálculo con
los parámetros actuales. Esas fotos, como el resto del estado, viven en UserDefaults:
unos 100 KB para 90 días.

El registro lo dispara tanto abrir la app como una tarea de `BGAppRefreshTask`, que
pide a iOS despertar la app cada pocas horas para no depender de que el usuario la
abra. Los datos están en HealthKit, en el dispositivo, así que no hay forma de
calcularlos desde fuera; y iOS concede esas ejecuciones según el uso de la app, de
modo que **mejora la cobertura pero no garantiza un registro diario**.

Eso significa además que **el histórico se pierde al borrar la app y no viaja a un
móvil nuevo**. La solución sin backend es `NSUbiquitousKeyValueStore` (iCloud clave-valor),
donde cabría holgadamente —su límite es 1 MB—, pero iCloud es un entitlement que
requiere cuenta de desarrollador de pago, así que queda pendiente junto con lo
anterior.

### Mejoras identificadas

- **Recuperar los datos por RAG** en la generación de rutinas: hoy el modelo diseña
  con su conocimiento interno guiado por los principios del prompt (documentados en
  `METRICS_SOURCES.md`). Una base documental con contraindicaciones por lesión y
  técnica de ejercicios daría respuestas más precisas y trazables.
- **Tipo de dominio propio para las actividades.** Las vistas consumen
  `StravaActivity`, el DTO del proveedor. Mientras Strava sea la única fuente no
  molesta; con una segunda haría falta un `Workout` propio al que ambas mapeen.
- **Inversión de dependencias.** La app usa MVVM pragmático sin protocolos: SwiftUI
  ya inyecta con `@EnvironmentObject` y el valor está en la validez de las métricas,
  no en las capas. Abstraer los servicios permitiría testear también las vistas.

## Requisitos

- iOS 17.0+
- watchOS 10.0+ (para el target Watch)
- Xcode 16+
- Cuenta de desarrollador de Apple (para HealthKit en dispositivo físico)
- Cuenta en Strava API y Anthropic API

---

## Licencia

Proyecto personal — uso privado. No redistribuir sin permiso del autor.
