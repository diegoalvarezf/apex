# APEX — Fuentes científicas de cada métrica

Este documento registra la base científica de **cada algoritmo y métrica** de la app.
Regla del proyecto: ninguna métrica se inventa. Cada fórmula procede de literatura
publicada y verificable. Donde una constante es una **calibración de producto**
(mapeo a una escala 0–100 sin fuente pública), se marca explícitamente como tal.

Última revisión: 2026-07-07

---

## Índice

| Métrica | Fichero | Base científica |
|---|---|---|
| Carga por sesión (ATL/CTL) | `Services/TrainingMetrics.swift` | TRIMP de Banister / TSS de Coggan |
| ATL · CTL | `ViewModels/DashboardViewModel.swift` | EMA exponencial (Banister; TrainingPeaks) |
| ACWR (riesgo de lesión) | `Models/Activity.swift` | Gabbett 2016; Williams 2017 (EWMA) |
| TSB / Forma (frescura) | `Models/Activity.swift` | Coggan–Banister (Performance Manager Chart) |
| Esfuerzo diario | `Services/TrainingMetrics.swift` | TRIMP de Edwards 1993 |
| Estrés fisiológico | `Views/Dashboard/StressRecoveryEffortRow.swift` | % reserva cardíaca (Karvonen) |
| Recuperación | `Services/HealthKitManager.swift` | HRV + RHR vs baseline (autonómico) |
| Body Battery | `Services/BodyBatteryStore.swift` | Modelo propio (metodología PeakWatch) |
| Sueño | `Models/HealthData.swift` | Normas AASM / NSF |
| Zonas de FC | `Views/Health/HeartRateZonesView.swift` | Modelo %FCmáx de 5 zonas |
| Edad de fitness | `Models/HealthData.swift` | VO2max normativo HUNT (Loe 2013) |
| VO2max no-ejercicio (fallback) | `Models/HealthData.swift` | Nes 2011 (HUNT) |
| FCmáx | `Services/UserProfileManager.swift` | Máx. observada 30d / 220−edad |

---

## 1. Carga de entrenamiento por sesión (alimenta ATL/CTL)

**Fórmula — TRIMP de Banister** (unidades reales, coeficientes por sexo):

```
HRr  = (FCmedia − FCreposo) / (FCmáx − FCreposo)
TRIMP = t_min · HRr · 0.64 · e^(1.92·HRr)   (hombres)
TRIMP = t_min · HRr · 0.86 · e^(1.67·HRr)   (mujeres)
```

**Fórmula — TSS (ciclismo con potencia, Coggan/TrainingPeaks):**

```
IF  = NP / FTP
TSS = (segundos · NP · IF) / (FTP · 3600) · 100
FTP ≈ 0.95 × mejor potencia normalizada en salidas ≥20 min
```

- Banister EW, Calvert TW. *Planning for future performance.* Can J Appl Sport Sci. 1980.
- Morton RH, Fitz-Clarke JR, Banister EW. *Modeling human performance in running.* J Appl Physiol. 1990.
- Coggan A, Allen H. *Training and Racing with a Power Meter.* VeloPress (definición de TSS/IF/NP/FTP).

## 2. ATL y CTL (medias móviles exponenciales)

```
ATL(t) = ATL(t−1)·(1−k7)  + carga(t)·k7,   k7  = 1 − e^(−1/7)  ≈ 0.1331
CTL(t) = CTL(t−1)·(1−k42) + carga(t)·k42,  k42 = 1 − e^(−1/42) ≈ 0.0235
```

Constantes de tiempo estándar del Performance Manager Chart: ATL τ=7 días, CTL τ=42 días.
Se calculan sobre 180 días de historial para que el CTL (τ=42) converja.

- Banister EW. *Modeling elite athletic performance.* En: Physiological Testing of Elite Athletes. 1991.
- Allen H, Coggan A. TrainingPeaks Performance Manager (CTL/ATL/TSB).

## 3. ACWR — Acute:Chronic Workload Ratio (riesgo de lesión)

```
ACWR = ATL / CTL
```

Zonas: <0.8 subentrenado · **0.8–1.3 óptimo (sweet spot)** · 1.3–1.5 elevado · >1.5 riesgo.

- Gabbett TJ. *The training—injury prevention paradox.* Br J Sports Med. 2016;50(5):273-280.
- Hulin BT, Gabbett TJ, et al. *Spikes in acute workload are associated with increased injury risk.* BJSM. 2014.
- Williams S, et al. *Better way to determine the ACWR? (EWMA).* Br J Sports Med. 2017 (justifica usar EMA en lugar de medias simples).

## 4. TSB — Training Stress Balance / "Forma" (frescura)

```
TSB = CTL − ATL     (en unidades de carga; positivo = fresco)
```

Zonas de forma (TrainingPeaks): >+25 muy fresco/desentrenando · +5..+25 frescura de
competición · −10..+5 neutro · −30..−10 entrenamiento productivo · <−30 sobrecarga.

> **Nota importante:** TSB (diferencia, frescura) y ACWR (ratio, riesgo de lesión) son
> métricas **distintas**. La app las muestra por separado. Antes estaban confundidas.

- Coggan A, Allen H. *Training and Racing with a Power Meter* (Performance Manager Chart, TSB).
- Banister EW. Modelo fitness-fatiga (impulse-response): rendimiento ≈ fitness − fatiga.

## 5. Esfuerzo diario (tile "Esfuerzo")

**Fórmula — TRIMP de Banister continuo acumulado en el día:**

```
Por actividad y por hora de fondo con FC elevada (HRr > 0.20):
  TRIMP = t_min · HRr · a · e^(b·HRr)   (a,b según sexo — ver §1)
El umbral HRr > 0.20 excluye reposo / estar sentado (solo cuenta actividad).
```

Se usó TRIMP de Banister continuo (no Edwards por zonas) porque el corte de Edwards al
50% de FCmáx daba **0 en días sin entreno intenso**, mientras que la carga cardiovascular
diaria (estilo PeakWatch Exertion) debe tener resolución también a intensidad baja-media.

- Banister EW. 1991 (misma base que ATL/CTL — ver §1).
- Edwards S. *The Heart Rate Monitor Book.* 1993 (método de zonas; se usa para el desglose visual por zonas, no para el score).

⚠️ **Calibración de producto** (curva saturante `EFFORT_K = 90`):
`score = 100·(1 − e^(−TRIMP_diario / 90))`. Da ≈10-20 en descanso, ≈35-45 en día activo
ligero, ≈80-95 en entreno duro. No procede de literatura; es la escala de presentación.

## 6. Estrés fisiológico

```
estrés_horario = (FC − FCreposo) / (FCmáx − FCreposo) × 100   (% reserva cardíaca)
estrés_diario  = media de las muestras horarias del día
```

Basado en la reserva de frecuencia cardíaca (fórmula de Karvonen). No es el "inverso de
la recuperación" (eso era incorrecto); es una medida directa a partir de la FC.

- Karvonen MJ, Kentala E, Mustala O. *The effects of training on heart rate.* Ann Med Exp Biol Fenn. 1957.

## 7. Recuperación (Recovery Score)

```
score = 0.70 · HRV_score + 0.30 · RHR_score
```

Cada componente es un **z-score** del valor de hoy contra el baseline de 60 días
(excluyendo hoy). Anclaje: z=0 (en tu media) → 50 pts; ±1 SD ≈ ±17 pts.

- Metodología de PeakWatch (documentada): "two key physiological indicators: HRV and RHR",
  media móvil de 60 días como baseline.
- Plews DJ, Laursen PB, et al. *Training adaptation and HRV in elite endurance athletes.*
  Eur J Appl Physiol. 2013 (uso de HRV vs baseline personal para readiness).
- Altini M. (HRV4Training): la línea base personal importa más que valores poblacionales;
  baseline = media móvil, se juzga la desviación del día respecto a ella.

⚠️ **Calibración de producto** (z=0 → 50 pts, ±17/SD): anclaje sin fuente pública,
ajustado con datos reales comparando contra PeakWatch (recuperación de Apex leía ~15-30
pts alta). "En tu media" = 50; sube/baja 17 por cada desviación estándar. Documentado en
código. HealthKit expone **SDNN**, no RMSSD (limitación de la fuente de datos).

## 8. Body Battery

Modelo acumulativo día-a-día. Principio alineado con **Garmin/Firstbeat**: el drenaje del
ejercicio correlaciona con el **EPOC / carga de entrenamiento** (no con el promedio de FC,
que se diluye en ejercicios intermitentes como el gimnasio), y la batería carga durmiendo.

- Arranca del Recovery del día + bonus por duración de sueño.
- **Drenaje de entrenamiento**: cada sesión de Strava drena según su TRIMP de Banister
  mediante curva saturante `65·(1−e^(−TRIMP/45))` — 50' de gym ≈ 33 pts, 1h Z2 ≈ 55.
- **Drenaje de vida diaria** (horas sin actividad): por FC sobre reposo, sin recarga de día.
- **Carga**: solo durmiendo, curva logarítmica hasta `recovery + bonus`.

Referencias del enfoque (no publican fórmulas exactas, sí la metodología):
- Firstbeat Analytics / Garmin — Body Battery basado en HRV-stress + EPOC (Training Effect).
- doc.peakwatch.co/en/battery.html — Body Energy (mismo principio cualitativo).

⚠️ Las constantes de carga/descarga y la curva de drenaje (`activityDrain`, factores por HRR,
`sleepBonus`) son **calibración propia de Apex** documentada en `BodyBatteryStore.swift`.

## 9. Sueño

```
score = 0.40·duración + 0.20·profundo(N3) + 0.20·REM + 0.20·eficiencia
duración:  óptimo 7–9h (crédito pleno)
N3:        crédito pleno ≥16% del total (normal AASM 15–20%)
REM:       crédito pleno ≥20% del total (normal AASM 20–25%)
eficiencia = tiempo dormido / tiempo en cama; 50%→0, ≥85%→1 (normal AASM ≥85%)
```

- American Academy of Sleep Medicine (AASM) — arquitectura normal del sueño (N1 3-8%,
  N2 45-55%, N3 15-20%, REM 20-25%; eficiencia ≥85%).
- Physiology, Sleep Stages. StatPearls, NCBI Bookshelf NBK526132.
- National Sleep Foundation — recomendación de duración 7–9h en adultos (Hirshkowitz 2015).

## 10. Zonas de frecuencia cardíaca

Modelo estándar de 5 zonas por **% de la FCmáx**: 50-60 / 60-70 / 70-80 / 80-90 / 90-100.

- ACSM. *Guidelines for Exercise Testing and Prescription* (clasificación de intensidad por %FCmáx).

## 11. Edad de fitness (edad biológica)

Concepto CERG/NTNU y Garmin: la "edad de fitness" es la edad a la que la **media
poblacional de VO2max** iguala tu VO2max medido. Se invierte la curva normativa por
edad y sexo:

```
edad_fitness = edad tal que VO2max_medio_poblacional(edad, sexo) = VO2max_medido
```

Datos normativos (medias por década, ml·kg⁻¹·min⁻¹):

| Edad | Hombres | Mujeres |
|---|---|---|
| 20–29 | 54.4 | 43.0 |
| 30–39 | 49.0 | 39.9 |
| 40–49 | 47.0 | 37.2 |
| 50–59 | 42.7 | 33.0 |
| 60–69 | 38.5 | 29.8 |
| 70–79 | 34.7 | 27.1 |
| 80–89 | 31.4 | 24.4 |

El VO2max **domina** el número (enfoque "honesto con el VO2max", igual que Garmin/CERG):
la edad de fitness es directamente la edad normativa de tu VO2max. FC en reposo, HRV, IMC,
sueño y actividad son un **ajuste fino a media potencia** (están correlacionados con el
VO2max, no se duplican). Nota: HealthKit puede infravalorar el VO2max si no corres al aire
libre, y las medias del HUNT son de una cohorte en forma (una persona "media" saldrá mayor).

- Loe H, Steinshamn S, Wisløff U. *Aerobic Capacity Reference Data in 3816 Healthy Men and
  Women 20–90 Years.* PLoS One. 2013;8(5):e64319. (tabla normativa de VO2max)
- CERG/NTNU Fitness Calculator (concepto de fitness age).

## 12. VO2max no-ejercicio (fallback cuando el reloj no lo mide)

**Ecuaciones de Nes 2011 (HUNT):**

```
Hombres: VO2max = 100.27 − 0.296·edad + 0.226·PA − 0.369·WC − 0.155·RHR
Mujeres: VO2max = 74.736 − 0.247·edad + 0.198·PA − 0.259·WC − 0.114·RHR
   PA = índice de actividad física · WC = perímetro de cintura (cm) · RHR = FC reposo
```

Error estándar ±3.5 ml/kg/min.

- Nes BM, Janszky I, Wisløff U, Støylen A, Karlsen T. *Estimating V̇O2peak from a nonexercise
  prediction model: the HUNT Study, Norway.* Med Sci Sports Exerc. 2011;43(11):2024-30.

## 13. Frecuencia cardíaca máxima (FCmáx)

Prioridad: **FCmáx personalizada** por el usuario → **máxima registrada en 30 días**
(HealthKit; metodología PeakWatch) → **220 − edad** (fórmula clásica).

- Fox SM, Naughton JP, Haskell WL. *Physical activity and the prevention of coronary heart
  disease.* Ann Clin Res. 1971 (origen de 220−edad).
- Nota: 220−edad tiene alta variabilidad interindividual (±10-12 lpm); por eso se prioriza
  el valor observado. Alternativa conocida: Tanaka 2001 (208 − 0.7·edad).

---

## Calibraciones de producto (sin fuente pública) — resumen

Estas son las **únicas** constantes que no proceden de literatura. Son decisiones de
escala/presentación, están aisladas y documentadas en código, y son las candidatas a
ajustar si los números no encajan con la percepción real:

1. **`EFFORT_K = 90`** (`TrainingMetrics.swift`) — curva saturante del TRIMP diario a 0–100.
2. **Recovery z=0 → 50 pts, ±17/SD** (`HealthKitManager.swift`) — anclaje del z-score de HRV/RHR.
3. **Constantes de Body Battery** (`BodyBatteryStore.swift`) — carga/descarga por hora (sin recarga diurna; drenaje de ejercicio ∝ −HRr²·42).

---

## Fuentes que NO se han usado (y por qué)

- **PeakWatch** publica *metodología* pero **no fórmulas ni coeficientes**. Se sigue su
  enfoque cualitativo (recovery = HRV+RHR vs baseline 60d; exertion = tiempo en zonas;
  body energy acumulativo) pero **no se replican sus números exactos** porque no son públicos.
- **Firstbeat/Garmin** (VO2max desde pace+HR, EPOC): algoritmos propietarios no publicados;
  se usa el VO2max que ya calcula Apple Watch en su lugar.
