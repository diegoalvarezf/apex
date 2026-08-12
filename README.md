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
- **Edad biológica (edad de fitness)** — anclada al VO2max medido: la edad a la que la media poblacional de VO2max (datos normativos HUNT / Loe 2013, n=3.816) iguala tu valor. FC reposo, HRV, IMC, sueño y actividad aplican ajustes menores (a media potencia cuando hay VO2max, por correlación). Delta con 1 decimal.
- **Métricas corporales** — HRV, FC reposo, temperatura de muñeca, luz solar.
- **Actividad** — VO2max, frecuencia respiratoria, SpO2.
- **Composición corporal** — peso, IMC, masa grasa estimada.

### Actividades
- Historial completo de Strava con mapa y zonas cardíacas.
- Récords personales por disciplina.
- Progresión de ejercicios de fuerza.

### Rutina
- Planificación semanal con generación de rutinas por IA (Claude).

### IA Coach
- Análisis personalizado con Claude Sonnet que procesa recuperación, sueño, HRV, carga y actividades recientes para dar recomendaciones accionables.
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
| IA | Anthropic Claude (claude-sonnet-4-6) |
| Widget | WidgetKit + App Groups |
| Watch | watchOS + WatchConnectivity |
| Autenticación | ASWebAuthenticationSession (OAuth 2.0) |
| Persistencia | UserDefaults + App Groups |

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

1. Obtén tu API key en [console.anthropic.com](https://console.anthropic.com).
2. En `Sources/Apex/Services/AIService.swift`:

```swift
enum ClaudeConfig {
    static let apiKey = "TU_API_KEY"
    static let model  = "claude-sonnet-4-6"
}
```

### 4. App Groups (widget)

1. En el [Apple Developer Portal](https://developer.apple.com/account), crea el grupo `group.com.tudominio.forma`.
2. Actívalo en los targets **Apex** y **ApexWidget** en Xcode → Signing & Capabilities → App Groups.
3. Actualiza el identificador en `ApexWidget.swift` y `UserProfileManager.swift`.

### 5. HealthKit

Los permisos se solicitan automáticamente en el primer arranque. Asegúrate de que el target tenga la capability **HealthKit** activada en Xcode.

### 6. Abre en Xcode

```bash
open Apex.xcodeproj
```

Selecciona tu dispositivo (se recomienda dispositivo físico para HealthKit y sensores reales) y pulsa **Run**.

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
│       ├── Health/             # Salud, edad biológica, sueño, composición
│       ├── Activities/         # Historial Strava, récords, progresión
│       ├── Insights/           # IA Coach, Smart Tips
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

### Edad de fitness
`FitnessAgeNorms.fitnessAge(vo2Max:)` invierte la curva normativa de VO2max por edad/sexo del HUNT Study (Loe 2013) para dar la edad a la que la media poblacional iguala tu VO2max. Ecuación de Nes 2011 disponible como estimador no-ejercicio de VO2max.

---

## Requisitos

- iOS 17.0+
- watchOS 10.0+ (para el target Watch)
- Xcode 16+
- Cuenta de desarrollador de Apple (para HealthKit en dispositivo físico)
- Cuenta en Strava API y Anthropic API

---

## Licencia

Proyecto personal — uso privado. No redistribuir sin permiso del autor.
