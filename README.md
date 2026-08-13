# APEX

App iOS nativa de seguimiento de rendimiento deportivo. Integra Strava, Apple HealthKit y un coach de IA basado en Claude para darte una visión completa de tu recuperación, carga de entrenamiento y salud diaria.

> **Trabajo de Fin de Máster** — Máster en Desarrollo de Software e Inteligencia Artificial.
> Autor: Diego Álvarez. Repositorio: https://github.com/diegoalvarezf/apex

---

## Características

### Dashboard
- **Body Battery** — energía acumulada day-over-day siguiendo la metodología de PeakWatch: el sueño carga por encima del recovery score, el ejercicio intenso depleciona, el reposo apenas consume.
- **Recuperación** — score 0–100 calculado con z-score de HRV (70%) y FC en reposo (30%) contra tu baseline de 60 días. Calibrado para que "en tu media" = ~75 pts, no 50.
- **Esfuerzo** — TRIMP de Banister continuo acumulado en el día (actividades + FC de fondo elevada), con curva saturante a 0–100.
- **Estrés** — media diaria del estrés fisiológico horario: (FC − FC reposo) / reserva cardíaca.
- **Carga de entrenamiento (ACWR)** — ATL/CTL con 180 días de historial. Barra de 4 colores: azul (<0.8), verde (0.8–1.3), amarillo (1.3–1.5), rojo (>1.5).
- **Sueño** — duración, sueño profundo, score y tendencia semanal.
- **Smart Tips** — alertas locales instantáneas basadas en recuperación, HRV, carga acumulada y déficit de sueño.

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
- Sonnet para los análisis y Opus para diseñar rutinas, que es la tarea que más razonamiento exige.
- Notificaciones diarias a las 8:30 con tu estado de recuperación.

### Widget
- **Body Battery** (small) — anillo con valor actual.
- **Forma · Resumen** (medium) — 4 barras: Body Battery, Recuperación, Esfuerzo, Sueño.
- **Forma · Detalle** (large) — igual con valores grandes y barras con degradado.

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
| IA | Anthropic Claude (Sonnet para análisis, Opus para rutinas) |
| Widget | WidgetKit + App Groups |
| Watch | watchOS + WatchConnectivity |
| Autenticación | ASWebAuthenticationSession (OAuth 2.0) |
| Persistencia | UserDefaults + App Groups · **Keychain** para credenciales |

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
3. En `Sources/Apex/Services/StravaAuth.swift` rellena:

```swift
enum StravaConfig {
    static let clientID     = "TU_CLIENT_ID"
    static let clientSecret = "TU_CLIENT_SECRET"
    static let redirectURI  = "apex-strava://localhost/oauth"
}
```

4. En Xcode, añade el URL Scheme `apex-strava` en `Info.plist` → URL Types.

### 3. Anthropic API

La clave la introduce cada usuario desde la propia app: **Perfil → Apex IA**. Se
valida contra la API antes de guardarla y se almacena en el **Keychain** del
dispositivo, no en el binario ni en UserDefaults. Cada uno usa su clave y su
consumo se factura a su cuenta.

1. Crea una clave en [console.anthropic.com](https://console.anthropic.com/settings/keys).
2. Ábrela en la app en Perfil → Apex IA y pulsa "Comprobar y guardar".

Sin clave, el resto de la app funciona igual: solo se desactivan los análisis de IA.

> Para desarrollo puedes dejarla en `StravaSecrets.plist` (bajo `AnthropicAPIKey`),
> que está en `.gitignore`. La del Keychain tiene prioridad sobre esa.

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
└── ApexWatch/                  # App de Apple Watch
```

---

## Métricas y algoritmos

> 📚 La base científica completa de cada métrica, con referencias a la literatura, está en
> [`docs/METRICS_SOURCES.md`](docs/METRICS_SOURCES.md). Ahí se marcan también las únicas tres
> calibraciones de producto (sin fuente pública).

### Body Battery
Modelo acumulativo day-over-day. Principio de Garmin/Firstbeat: el ejercicio drena según su
**carga (EPOC/TRIMP)**, no según el promedio de FC (que se diluye en el gimnasio). Arranca
del recovery del día (+ bonus de sueño) y solo recarga durmiendo:
- **Entreno (Strava)**: drena `65·(1−e^(−TRIMP/45))` pts repartidos en sus horas
- **Vida diaria (HRR <0.25, sin actividad)**: -0.6 a -1.2 pts/hora
- **Sueño**: carga hasta `recovery + (horas - 6) × 4`

### Recovery Score
`HRV (70%) + FC_reposo (30%)`

Z-score contra baseline de 60 días (calibrado vs PeakWatch con datos reales):
- z = 0 (en tu media) → 50 pts
- z = +1 (HRV elevada) → 70 pts
- z = -1 (HRV baja) → 30 pts

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

APEX está construida para uso personal: todo ocurre en el dispositivo y no hay
servidor. Eso mantiene el proyecto simple y sin coste, pero pone tres límites que
conviene declarar antes que disimular.

### 1. El `client_secret` de Strava viaja en la app

El flujo OAuth de Strava exige el `client_secret` para canjear el código por el
token, y no admite PKCE, que es el mecanismo pensado para que las apps móviles no
tengan que llevar secretos. Sin un servidor intermedio no hay forma correcta de
hacerlo: el secreto acaba dentro del binario, de donde se puede extraer.

No permite entrar en la cuenta de nadie —identifica a la aplicación, no al
usuario—, pero sí suplantar a APEX ante Strava o agotar su cuota de peticiones,
que es por aplicación. Con la app sin distribuir el riesgo es teórico; dejaría de
serlo al publicarla.

Los tokens que devuelve Strava, esos sí credenciales del usuario, se guardan en el
**Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), igual que la clave de
la API de IA.

### 2. Distribuir la app exige un backend

Publicarla obligaría a montar un servidor intermedio, y no principalmente por
seguridad:

- El `client_secret` y la clave de IA dejarían de estar en el dispositivo, y podrían
  rotarse sin publicar una actualización.
- Se podría limitar el consumo por usuario. Hoy cada uno pone su clave de Anthropic
  precisamente porque no hay forma de repartir ese coste.
- Permitiría un modelo de suscripción, que en iOS debe pasar por In-App Purchase.

Tiene contrapartida: hoy los datos de salud van del dispositivo directos a la API de
Anthropic, mientras que con backend pasarían por un servidor propio. Se gana control
sobre las claves a cambio de custodiar datos de salud ajenos, lo que en la UE es más
responsabilidad, no menos.

### 3. Salir al mercado es un proyecto distinto

Además del backend, distribuir la app en la UE implicaría cumplir el **RGPD** con
datos de categoría especial (art. 9): HRV, sueño y frecuencia cardíaca lo son. Eso
exige consentimiento explícito y granular, política de privacidad real, finalidad
limitada, plazos de conservación y derecho de acceso y borrado. También habría que
declarar a Anthropic como encargado del tratamiento, firmar el acuerdo
correspondiente y advertir de forma clara que los análisis no son consejo médico.

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
