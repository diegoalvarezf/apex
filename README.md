# Forma

App iOS nativa de seguimiento de rendimiento deportivo. Integra Strava, Apple HealthKit y un coach de IA basado en Claude para darte una visión completa de tu recuperación, carga de entrenamiento y salud diaria.

---

## Características

### Dashboard
- **Body Battery** — energía acumulada day-over-day siguiendo la metodología de PeakWatch: el sueño carga por encima del recovery score, el ejercicio intenso depleciona, el reposo apenas consume.
- **Recuperación** — score 0–100 calculado con z-score de HRV (70%) y FC en reposo (30%) contra tu baseline de 60 días. Calibrado para que "en tu media" = ~75 pts, no 50.
- **Esfuerzo** — TRIMP de Banister del día escalado a 0–100. Usa TSS para ciclismo con datos de potencia.
- **Estrés** — inverso de recuperación, con gráfica horaria de FC.
- **Carga de entrenamiento (ACWR)** — ATL/CTL con 180 días de historial. Barra de 4 colores: azul (<0.8), verde (0.8–1.3), amarillo (1.3–1.5), rojo (>1.5).
- **Sueño** — duración, sueño profundo, score y tendencia semanal.
- **Smart Tips** — alertas locales instantáneas basadas en recuperación, HRV, carga acumulada y déficit de sueño.

### Pestaña Salud
- **Edad biológica** — algoritmo multifactor: VO2max, FC reposo, HRV, IMC, sueño, actividad semanal. Muestra delta con 1 decimal (ej. "2.4 años menos").
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
git clone https://github.com/diegoalvarezfrancos/forma.git
cd forma
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

### Body Battery
Modelo acumulativo day-over-day inspirado en PeakWatch/Garmin:
- **Sueño**: carga `recovery + (horas - 6) × 4` (8h de sueño con recovery=79 → 87 de batería)
- **Reposo**: -0.3 pts/hora
- **Ejercicio moderado (HRR 0.25–0.5)**: -1.5 a -3 pts/hora
- **Ejercicio intenso (HRR >0.5)**: -5.5 a -22 pts/hora
- **Estrés muy bajo (HRR <0.1)**: +0.15 pts/hora (ligera recarga)

### Recovery Score
`HRV (70%) + FC_reposo (30%)`

Z-score contra baseline de 60 días:
- z = 0 (en tu media) → 75 pts
- z = +1 (HRV elevada) → 89 pts
- z = -1 (HRV baja) → 61 pts

### ACWR (Carga de entrenamiento)
- ATL: EMA 7 días (k ≈ 0.134)
- CTL: EMA 42 días (k ≈ 0.0235)
- ACWR = ATL / CTL
- 180 días de historial para convergencia del CTL

### TRIMP (Esfuerzo)
`duración_h × HRR × e^(1.92 × HRR) × 13`

Para ciclismo con datos de potencia usa TSS: `(segundos × NP × IF) / (FTP × 3600) × 100`

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
