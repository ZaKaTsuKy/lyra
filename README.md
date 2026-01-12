# LYRA
## Dashboard de Monitoring Système avec Intelligence Artificielle

**Version:** 2.0.0  
**Stack Backend:** Julia 1.9+ avec WebSocket Server  
**Stack Frontend:** React 19 + TypeScript + Three.js  
**Plateforme:** Linux (architecture préparée pour Windows/macOS)  
**Licence:** MIT

---

## Table des Matières

1. [Présentation](#présentation)
2. [Architecture](#architecture)
3. [Fonctionnalités](#fonctionnalités)
4. [Module IA - Analyse Approfondie](#module-ia---analyse-approfondie)
5. [Physics Engine - Diagnostic Avancé](#physics-engine---diagnostic-avancé)
6. [Communication WebSocket](#communication-websocket)
7. [Interface Web (Frontend)](#interface-web-frontend)
8. [Installation](#installation)
9. [Configuration](#configuration)
10. [Structure du Projet](#structure-du-projet)
11. [Référence des Modules](#référence-des-modules)
12. [Dépannage](#dépannage)
13. [Roadmap](#roadmap)

---

## Présentation

### Vision

LYRA est un dashboard de monitoring système en temps réel qui se distingue par son **moteur d'intelligence artificielle statistique et comportementale** intégré. Contrairement aux outils de monitoring traditionnels qui affichent des métriques brutes, LYRA analyse en continu le comportement du système pour :

- **Détecter les anomalies** avant qu'elles ne deviennent des problèmes
- **Prédire les situations critiques** (mémoire pleine, surchauffe, saturation disque)
- **Identifier les changements de régime** (passage idle → compute → gaming)
- **Corréler les métriques** pour détecter les incohérences matérielles
- **Diagnostiquer les problèmes physiques** (pâte thermique sèche, ventilateur défaillant, PSU instable)

### Philosophie de Conception

Le projet repose sur quatre principes fondamentaux :

1. **Efficacité mémoire O(1)** : Algorithmes statistiques streaming (T-Digest, Welford, EWMA) sans accumulation de données historiques
2. **Zéro dépendance externe** : Lecture directe de `/proc` et `/sys` sans agents ni daemons
3. **Communication temps réel** : WebSocket bidirectionnel avec snapshots atomiques thread-safe
4. **Interface moderne** : React 19 + Three.js pour visualisation 3D du système (Digital Twin)

### Public Cible

- Administrateurs système souhaitant un outil de diagnostic intelligent
- Développeurs analysant les performances de leurs applications
- Passionnés de hardware surveillant leur configuration (GPU, températures, voltages)
- Chercheurs en observabilité et AIOps

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              FRONTEND (React 19)                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│  │ Dashboard   │ │ AI Widgets  │ │ Hardware    │ │ Digital Twin (Three.js) │ │
│  │ Grid (DnD)  │ │ Anomaly/Cog │ │ Sensors     │ │ 3D Tower Model          │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────────────────┘ │
│                              │                                               │
│                    Zustand TelemetryStore                                    │
│                              │ WebSocket                                     │
└──────────────────────────────┼───────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WEBSOCKET SERVER (Oxygen.jl)                        │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ • Thread-safe client manager (MAX_CLIENTS)                          │    │
│  │ • Rate limiting (configurable)                                      │    │
│  │ • CORS middleware                                                   │    │
│  │ • Atomic snapshot pattern (deep-copy DTOs)                          │    │
│  │ • Graceful shutdown                                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              │                                              │
│                    create_snapshot(monitor)                                 │
│                              │                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BACKEND (Julia Core)                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    SystemMonitor (État Global)                      │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────────┐   │    │
│  │  │CPUInfo  │ │MemInfo  │ │GPUInfo  │ │NetInfo  │ │FullSensorsDTO│   │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────────┘   │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │                    AIState (Intelligence)                   │    │    │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │    │    │
│  │  │  │ Trackers │ │ IForest  │ │ Spectral │ │ PhysicsEngine  │  │    │    │
│  │  │  │ (MAD,HW) │ │ (Anomaly)│ │ (FFT)    │ │ (6 modules)    │  │    │    │
│  │  │  └──────────┘ └──────────┘ └──────────┘ └────────────────┘  │    │    │
│  │  └─────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              │                                              │
│                    OS/Linux/*.jl Collectors                                 │
│                              │                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
                               ▼
              ┌─────────────────────────────────────┐
              │         Linux Kernel                │
              │  /proc  │  /sys  │  nvidia-smi      │
              └─────────────────────────────────────┘
```

### Flux de Données

1. **Collecte** (toutes les secondes par défaut) : Les modules `OS/Linux/*.jl` lisent `/proc`, `/sys` et `nvidia-smi`
2. **Agrégation** : Les métriques sont stockées dans `SystemMonitor`
3. **Analyse IA** : `AI.jl` + modules IA spécialisés calculent scores, tendances et prédictions
4. **Snapshot** : `create_snapshot()` crée une copie immuable thread-safe (deep-copy DTOs)
5. **Broadcast** : Le serveur WebSocket envoie le JSON à tous les clients connectés
6. **Rendu** : L'interface React met à jour les widgets via Zustand store

---

## Fonctionnalités

### Monitoring Hardware

| Composant | Métriques | Source |
|-----------|-----------|--------|
| **CPU** | Usage, fréquences, load average, température (Tctl/Tdie/cores), context switches/s, interrupts/s, PSI | `/proc/stat`, `/proc/cpuinfo`, `/sys/class/hwmon`, `/proc/pressure` |
| **Mémoire** | Totale/utilisée/disponible, swap, pression PSI | `/proc/meminfo`, `/proc/pressure` |
| **GPU** | Utilisation, VRAM, température (edge/hotspot/mem), puissance, voltage VDD | `nvidia-smi`, `/sys/class/hwmon` (AMD) |
| **Réseau** | Débit RX/TX par interface, classification trafic, connexions TCP (ESTABLISHED/TIME_WAIT) | `/proc/net/dev`, `/proc/net/tcp` |
| **Disques** | Espace par mount, IOPS R/W, débit R/W, latence moyenne, IO wait % | `df`, `/proc/diskstats` |
| **NVMe** | Températures composite/sensor1/sensor2 par drive | `/sys/class/hwmon` |
| **Batterie** | Pourcentage, état, puissance, temps restant | `/sys/class/power_supply` |
| **Voltages** | Vcore, +12V, +5V, +3.3V, VBAT | `/sys/class/hwmon` |
| **Ventilateurs** | RPM par ventilateur (CPU, case, rear) | `/sys/class/hwmon` |
| **Processus** | Top 5 par CPU, état (R/S/D/Z), mémoire | `/proc/[pid]/*` |

### Intelligence Artificielle (8 Moteurs)

| Module | Algorithme | Description |
|--------|------------|-------------|
| **T-Digest** | Streaming Quantiles | P50, P95, P99 sans stocker l'historique complet |
| **MAD Tracker** | Median Absolute Deviation | Z-Score robuste résistant aux outliers |
| **Holt-Winters** | Triple Exponential Smoothing | Prévision avec saisonnalité (période 60s) |
| **ADWIN** | Adaptive Windowing | Détection automatique de changement de régime |
| **CUSUM** | Cumulative Sum | Détection de dérives lentes (fuites mémoire) |
| **Isolation Forest** | Streaming iForest | Détection d'anomalies multivariées |
| **FFT Spectral** | Fast Fourier Transform | Détection d'oscillations (throttling CPU, fan hunting) |
| **Markov Behavioral** | Chaîne de Markov | Détection de transitions d'état impossibles |

### Physics Engine (6 Modules de Diagnostic)

| Module | Fonction | Indicateurs |
|--------|----------|-------------|
| **ThermalEfficiency** | Détecte dégradation thermique | Rth baseline vs instant, % efficacité |
| **FanStability** | Détecte fan hunting/pumping | Variance RPM, dT/dt |
| **PowerQuality** | Monitore stabilité PSU | Vcore variance, instabilité 12V |
| **ThermalSaturation** | Prédit temps avant throttle | Time-to-throttle, spike transient |
| **WorkloadClassifier** | Adapte seuils au workload | IDLE/COMPUTE/GAMING/IO_INTENSIVE |
| **BottleneckDetector** | Identifie ressource limitante | CPU/GPU/DISK/MEMORY + severity |

### Interface Web

| Fonctionnalité | Description |
|----------------|-------------|
| **Dashboard Grid** | Widgets réorganisables par drag & drop (dnd-kit) |
| **Digital Twin** | Modèle 3D animé du PC (Three.js + React Three Fiber) |
| **Sparklines** | Historique visuel des 3 dernières minutes (Recharts) |
| **Heatmaps** | Visualisation CPU par cœur |
| **Theme Toggle** | Mode clair/sombre |
| **Real-time Updates** | Mise à jour ~1Hz via WebSocket |
| **Hardware Health** | Diagnostic ventilateurs, voltages, pâte thermique |
| **Cognitive Insights** | Score Isolation Forest, entropie spectrale, état Markov |
| **Physics Diagnostics** | Efficacité thermique, time-to-throttle, bottleneck |

---

## Module IA - Analyse Approfondie

### T-Digest : Centiles en Streaming

Le T-Digest permet de calculer des centiles (médiane, P95, P99) sur un flux de données sans stocker l'historique complet. Il utilise une compression adaptative qui conserve plus de précision aux extrémités de la distribution.

**Complexité** : O(1) espace, O(log n) par insertion

```julia
mutable struct TDigest
    centroids::Vector{TDigestCentroid}  # Clusters compressés
    compression::Float64                 # Facteur de compression (défaut: 100)
    total_weight::Float64
    p50::Float64  # Médiane pré-calculée
    p95::Float64
    p99::Float64
end

# Usage
add_sample!(td, cpu_usage)
update_percentiles!(td)
```

### MAD : Z-Score Robuste

Le Z-Score classique `(x - μ) / σ` est sensible aux outliers. Le MAD (Median Absolute Deviation) utilise la médiane :

```
Z_robust = (x - médiane) / (1.4826 × MAD)
```

Le facteur 1.4826 normalise pour être comparable à un Z-Score classique sur une distribution normale.

### Holt-Winters : Prévision Saisonnière

L'algorithme de Holt-Winters (Triple Exponential Smoothing) décompose le signal en trois composantes :

1. **Level (α=0.3)** : Valeur de base lissée
2. **Trend (β=0.1)** : Pente de la tendance
3. **Seasonal (γ=0.1)** : Facteurs saisonniers (période = 60 échantillons)

```julia
# Prédiction à l'horizon H
prediction = (level + H × trend) × seasonal[future_idx]
```

### ADWIN : Détection de Changement de Régime

ADWIN maintient une fenêtre adaptative et teste en continu si les sous-fenêtres ont des moyennes significativement différentes (test statistique Hoeffding).

**Régimes détectés** :
- `IDLE` : CPU < 20%, MEM < 50%
- `COMPUTE` : CPU > 70%
- `GAMING` : GPU > 80% ou (CPU > 60% et GPU > 30%)
- `IO_INTENSIVE` : I/O > P95 × 0.7
- `MEMORY_INTENSIVE` : MEM > P95 × 0.9

### Isolation Forest : Détection Multivariée

L'Isolation Forest détecte les anomalies en mesurant la profondeur moyenne nécessaire pour isoler un point. Les anomalies sont isolées plus rapidement que les points normaux.

```julia
mutable struct StreamingIsolationForest
    trees::Vector{IsolationTreeNode}
    sample_buffer::Matrix{Float64}  # Fenêtre glissante
    n_trees::Int                     # 100 arbres par défaut
    sample_size::Int                 # 256 échantillons par arbre
end

# Features utilisées:
features = [cpu_usage, mem_usage, io_throughput, net_throughput, 
            gpu_usage, cpu_temp, disk_latency]
```

### Analyse Spectrale FFT

Le module FFT détecte les oscillations périodiques dans les métriques :

- **CPU Throttling** : Oscillations 0.1-0.5 Hz causées par thermal throttling
- **Fan Hunting** : Oscillations 0.05-0.2 Hz des ventilateurs avec contrôleur instable

```julia
mutable struct FFTAnalyzer
    buffer::Vector{Float64}      # Buffer circulaire 128 samples
    power_spectrum::Vector{Float64}
    dominant_freq::Float64
    oscillation_detected::Bool
end
```

### Analyse Comportementale Markov

Le module Markov détecte les transitions d'état impossibles ou suspectes :

```julia
# Transitions impossibles (physiquement)
(STATE_IDLE → STATE_THERMAL_THROTTLING)      # Pas de throttle sans charge
(STATE_FAN_SPINUP → STATE_IDLE)              # Fans ne s'arrêtent pas instantanément
(STATE_POWER_SAVING → STATE_OVERLOAD)        # Pas de surcharge depuis power saving

# États du système
@enum SystemState begin
    STATE_IDLE, STATE_LIGHT_LOAD, STATE_COMPUTE, STATE_IO_BOUND,
    STATE_MEMORY_PRESSURE, STATE_NETWORK_ACTIVE, STATE_GPU_ACTIVE,
    STATE_THERMAL_THROTTLING, STATE_FAN_SPINUP, STATE_FAN_SPINDOWN,
    STATE_POWER_SAVING, STATE_OVERLOAD
end
```

---

## Physics Engine - Diagnostic Avancé

Le Physics Engine orchestre 6 modules de diagnostic basés sur les lois physiques du hardware.

### Module 1 : ThermalEfficiency

Détecte la dégradation du refroidissement via la résistance thermique apparente :

```
Rth = (T_cpu - T_ambient) / Load_cpu
```

- **Rth baseline** : Établi sur les 120 premiers échantillons à charge > 20%
- **Alert** : Si Rth augmente de > 15% par rapport à la baseline (pâte thermique sèche, poussière)

### Module 2 : FanStability

Détecte le "fan hunting" (oscillation des ventilateurs) :

```julia
# Conditions de détection:
|dT/dt| < 0.1°C/s      # Température stable
variance(RPM) > 10000   # RPM instable
```

Le fan hunting indique un contrôleur PWM mal calibré ou un ventilateur défaillant.

### Module 3 : PowerQuality

Monitore la stabilité de l'alimentation :

- **Vcore variance** : Alert si > 50mV de variation (régulation VRM)
- **12V rail** : Alert si variation > 5% (PSU instable)

### Module 4 : ThermalSaturation

Prédit le temps avant throttling thermique :

```julia
# Extrapolation linéaire depuis EWMA
time_to_throttle = (T_critical - T_current) / (dT/dt)

# Détection de spike transient
is_transient = d²T/dt² < 0  # Inflexion = pic transitoire
```

### Module 5 : WorkloadClassifier

Adapte dynamiquement les seuils selon le workload détecté :

| Workload | T_warning | T_critical | Description |
|----------|-----------|------------|-------------|
| IDLE | 50°C | 70°C | Seuils bas pour idle |
| COMPUTE | 75°C | 90°C | Seuils hauts pour charge CPU |
| GAMING | 80°C | 95°C | Seuils maximaux pour jeu |
| IO_INTENSIVE | 60°C | 80°C | Seuils modérés |

### Module 6 : BottleneckDetector

Identifie la ressource limitante :

```julia
@enum Bottleneck begin
    BOTTLENECK_NONE
    BOTTLENECK_CPU
    BOTTLENECK_GPU
    BOTTLENECK_MEMORY
    BOTTLENECK_DISK
end

# Calcul de severity (0-100%)
severity = (usage - low_threshold) / (high_threshold - low_threshold)
```

---

## Communication WebSocket

### Protocol

Le serveur WebSocket utilise le pattern **atomic snapshot** pour garantir la cohérence des données en environnement multi-thread.

```
Client                    Server
   |                         |
   |--- WebSocket Connect -->|
   |<-- InitPayload ---------|  (Static info + history)
   |                         |
   |<-- UpdatePayload -------|  (1Hz updates)
   |<-- UpdatePayload -------|
   |        ...              |
   |                         |
   |--- ping --------------->|  (Heartbeat every 30s)
   |<-- pong ----------------|
   |                         |
   |--- close -------------->|
   |<-- shutdown ------------|
```

### InitPayload (Connexion)

```typescript
interface InitPayload {
    type: "init";
    static: StaticDTO;           // CPU model, cores, kernel, hostname
    disks: DiskDTO[];            // Disk configurations
    history: HistoryDTO;         // Last 120 samples
    timestamp: number;
}
```

### UpdatePayload (1Hz)

```typescript
interface UpdatePayload {
    type: "update";
    cpu: CPUInstant;
    memory: MemoryInstant;
    gpu: GPUInstant | null;
    network: NetworkInstant;
    disks: DiskInstant[];
    battery: BatteryInstant;
    system: SystemInstant;
    anomaly: AnomalyInstant;
    top_processes: ProcessInstant[];
    hardware_health: HardwareHealthDTO | null;
    cognitive: CognitiveInsightsDTO | null;
    full_sensors: FullSensorsDTO | null;
    physics_diagnostics: PhysicsDiagnosticsDTO | null;
    update_count: number;
    timestamp: number;
}
```

### Sécurité

| Feature | Configuration |
|---------|---------------|
| **MAX_CLIENTS** | 50 (DoS protection) |
| **Rate Limiting** | 10 messages/seconde par client |
| **Send Timeout** | 5 secondes |
| **CORS** | Configurable via `OMNI_CORS_ORIGINS` |

---

## Interface Web (Frontend)

### Stack Technique

| Technologie | Version | Usage |
|-------------|---------|-------|
| **React** | 19.2 | UI Framework |
| **TypeScript** | 5.9 | Type Safety |
| **Zustand** | 5.0 | State Management |
| **Vite** | 7.2 | Build Tool |
| **Three.js** | 0.182 | 3D Graphics |
| **React Three Fiber** | 9.5 | React + Three.js |
| **Recharts** | 3.6 | Charts |
| **dnd-kit** | 6.3 | Drag & Drop |
| **Tailwind CSS** | 3.4 | Styling |
| **Lucide** | 0.562 | Icons |

### Architecture des Widgets

```
src/features/
├── dashboard/
│   ├── components/
│   │   ├── DashboardGrid.tsx      # Grid DnD principal
│   │   └── SortableWidget.tsx     # Wrapper draggable
│   └── config/
│       └── widgetRegistry.ts      # Définitions widgets
├── monitoring/
│   ├── cpu/CpuWidget.tsx
│   ├── memory/MemoryWidget.tsx
│   ├── network/NetworkWidget.tsx
│   ├── ai/
│   │   ├── AnomalyWidget.tsx      # Scores d'anomalie
│   │   └── CognitiveWidget.tsx    # Insights IA avancés
│   ├── hardware/
│   │   ├── SensorsWidget.tsx      # Températures
│   │   ├── FansWidget.tsx         # Ventilateurs
│   │   ├── VoltagesWidget.tsx     # Voltages
│   │   └── HardwareHealthCard.tsx # Santé hardware
│   └── history/HistoryWidget.tsx  # Graphiques historiques
├── digital-twin/
│   ├── DigitalTwinWidget.tsx      # Container 3D
│   └── components/
│       ├── Scene.tsx              # Canvas Three.js
│       └── TowerModel.tsx         # Modèle PC animé
└── physics/
    └── PhysicsDiagnosticsWidget.tsx  # Diagnostics physiques
```

### State Management (Zustand)

```typescript
// telemetryStore.ts
interface OmniState {
    status: 'disconnected' | 'connecting' | 'connected' | 'error';
    staticInfo: InitPayload | null;
    liveData: UpdatePayload | null;
    _historyBuffer: RingBuffer<HistoryPoint>;  // O(1) push
    historyVersion: number;  // Trigger React re-renders
    
    connect: (url?: string) => void;
    disconnect: () => void;
    getHistory: () => HistoryPoint[];
}

// Atomic selectors pour éviter les re-renders inutiles
const selectors = {
    cpuLoad: (s) => s.liveData?.cpu.load1 ?? 0,
    cpuTemp: (s) => s.liveData?.cpu.temp_package ?? 0,
    // ...
};
```

---

## Installation

### Prérequis

- **Julia 1.9+** : [julialang.org/downloads](https://julialang.org/downloads/)
- **Node.js 18+** : [nodejs.org](https://nodejs.org/)
- **Linux** : Kernel 4.x+ avec `/proc` et `/sys` montés
- **nvidia-smi** (optionnel) : Pour le monitoring GPU NVIDIA

### Installation Backend

```bash
# Cloner le dépôt
git clone https://github.com/zakatsuky/ai_dashboard.git
cd ai_dashboard/back-end

# Installer les dépendances Julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Lancer le backend
julia --project=. main.jl
```

### Installation Frontend

```bash
cd ai_dashboard/front-end

# Installer les dépendances
npm install

# Mode développement
npm run dev

# Build production
npm run build
```

### Accès

- **Backend TUI** : Terminal où Julia est lancé
- **WebSocket** : `ws://localhost:8080/ws`
- **Frontend Dev** : `http://localhost:5173`
- **Frontend Prod** : Servir `front-end/dist/`

---

## Configuration

Toute la configuration est centralisée dans `config/Config.jl` et chargeable via variables d'environnement ou fichier `.env`.

### Variables d'Environnement

#### Application

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OMNI_REFRESH_INTERVAL` | `1.0` | Intervalle de collecte (secondes) |
| `OMNI_ENABLE_GPU` | `true` | Activer monitoring GPU |
| `OMNI_ENABLE_BATTERY` | `true` | Activer monitoring batterie |
| `OMNI_ENABLE_PROCESSES` | `true` | Activer liste processus |

#### Serveur WebSocket

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OMNI_WEBSOCKET_PORT` | `8080` | Port du serveur |
| `OMNI_WEBSOCKET_HOST` | `0.0.0.0` | Interface d'écoute |
| `OMNI_MAX_CLIENTS` | `50` | Limite de clients |
| `OMNI_CORS_ORIGINS` | `["*"]` | Origines CORS autorisées |

#### Intelligence Artificielle

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OMNI_AI_CPU_CRITICAL` | `95.0` | Seuil CPU critique (%) |
| `OMNI_AI_ZSCORE_WARNING` | `2.5` | Z-Score pour warning |
| `OMNI_AI_ZSCORE_CRITICAL` | `3.5` | Z-Score pour critical |
| `OMNI_AI_CUSUM_THRESHOLD` | `5.0` | Seuil CUSUM |
| `OMNI_AI_HW_ALPHA` | `0.3` | Holt-Winters alpha |
| `OMNI_AI_SATURATION_KNEE_RATIO` | `0.8` | Point de knee (80%) |

#### Physics Engine

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OMNI_THERMAL_EFF_ALERT_PCT` | `15.0` | Seuil dégradation thermique (%) |
| `OMNI_RPM_VAR_HUNTING` | `10000.0` | Variance RPM pour fan hunting |
| `OMNI_VCORE_VAR_ALERT_MV` | `50.0` | Variance Vcore pour alert (mV) |
| `OMNI_T_CRITICAL` | `95.0` | Température critique (°C) |

### CLI Options

```bash
julia main.jl [options]

Options:
    --help, -h      Afficher l'aide
    --once          Une seule itération (debug)
    --no-gpu        Désactiver monitoring GPU
    --no-battery    Désactiver monitoring batterie
    --no-processes  Désactiver liste processus
    --port PORT     Port WebSocket (défaut: 8080)
```

---

## Structure du Projet

```
ai_dashboard/
├── README.md
│
├── back-end/                          # Backend Julia
│   ├── main.jl                        # Point d'entrée (260 lignes)
│   ├── Project.toml                   # Dépendances Julia
│   ├── Manifest.toml                  # Versions lockées
│   ├── .env                           # Configuration locale
│   │
│   ├── config/
│   │   └── Config.jl                  # Configuration centralisée (205 lignes)
│   │
│   ├── types/
│   │   └── MonitorTypes.jl            # Structures de données (700+ lignes)
│   │
│   ├── server/
│   │   └── WebSocketServer.jl         # Serveur WebSocket (1128 lignes)
│   │
│   ├── ui/
│   │   └── UI.jl                      # Interface TUI terminal
│   │
│   ├── helpers/
│   │   └── debug.jl                   # Utilitaires debug
│   │
│   ├── utils/
│   │   └── watchdog.sh                # Script supervision
│   │
│   └── OS/
│       └── Linux/
│           ├── CPU.jl                 # Collecteur CPU (380 lignes)
│           ├── Memory.jl              # Collecteur mémoire
│           ├── GPU.jl                 # Collecteur GPU
│           ├── Network.jl             # Collecteur réseau
│           ├── DiskIO.jl              # Collecteur I/O disque
│           ├── DiskSpace.jl           # Collecteur espace disque
│           ├── Processes.jl           # Collecteur processus
│           ├── Battery.jl             # Collecteur batterie
│           ├── SystemUtils.jl         # Utilitaires système
│           ├── Hardware.jl            # Collecteur hardware sensors
│           ├── AI.jl                  # ★ Moteur IA principal (978 lignes)
│           └── ai/
│               ├── IsolationForest.jl # Isolation Forest streaming (307 lignes)
│               ├── Spectral.jl        # Analyse FFT (243 lignes)
│               ├── Behavioral.jl      # Analyse Markov (302 lignes)
│               ├── Physical.jl        # Cohérence physique
│               ├── Simulation.jl      # Simulations thermiques
│               └── PhysicsEngine.jl   # ★ Physics Engine (808 lignes)
│
└── front-end/                         # Frontend React
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.js
    ├── tsconfig.json
    │
    ├── src/
    │   ├── App.tsx                    # Composant racine
    │   ├── main.tsx                   # Point d'entrée React
    │   ├── index.css                  # Styles globaux
    │   │
    │   ├── types/
    │   │   └── omni.d.ts              # Types TypeScript (mirroir DTOs)
    │   │
    │   ├── store/
    │   │   ├── telemetryStore.ts      # Zustand store WebSocket
    │   │   └── preferencesStore.ts    # Préférences utilisateur
    │   │
    │   ├── lib/
    │   │   ├── utils.ts               # cn() helper
    │   │   └── formatters.ts          # formatBytes, etc.
    │   │
    │   ├── shared/components/
    │   │   ├── ui/                    # shadcn/ui components
    │   │   ├── ThemeToggle.tsx
    │   │   └── ErrorBoundary.tsx
    │   │
    │   ├── components/
    │   │   ├── dashboard/             # Cards spécifiques
    │   │   └── charts/                # MetricChart, CpuHeatmap
    │   │
    │   └── features/
    │       ├── dashboard/             # DashboardGrid, widgetRegistry
    │       ├── monitoring/            # Widgets de monitoring
    │       ├── digital-twin/          # Modèle 3D Three.js
    │       └── physics/               # Widget Physics Engine
    │
    └── dist/                          # Build production
```

**Total Backend** : ~5500 lignes Julia  
**Total Frontend** : ~4000 lignes TypeScript/React

---

## Référence des Modules

### MonitorTypes.jl

| Structure | Description |
|-----------|-------------|
| `SystemMonitor` | État global contenant tous les sous-systèmes |
| `CPUInfo` | Modèle, fréquences, load, température, PSI |
| `MemoryInfo` | RAM, swap, pression |
| `GPUInfo` | Nom, utilisation, VRAM, température, throttling |
| `NetworkInfo` | Interfaces, débits, TCP stats |
| `DiskUsage` | Points de montage, espace |
| `DiskIOMetrics` | IOPS, débit, latence, queue depth |
| `ProcessInfo` | PID, nom, CPU%, mémoire, état |
| `BatteryInfo` | Pourcentage, état, puissance |
| `FullSensors` | Tous les capteurs hwmon agrégés |
| `AnomalyScore` | Scores IA, tendances, spikes, prédictions |
| `HardwareHealth` | Diagnostic hardware synthétisé |

### AI.jl

| Composant | Description |
|-----------|-------------|
| `TDigest` | Centiles streaming |
| `WelfordStats` | Variance en ligne |
| `MADTracker` | Z-Score robuste |
| `HoltWinters` | Triple lissage exponentiel |
| `ADWIN` | Détection changement régime |
| `CUSUM` | Détection dérive |
| `PhysicalCoherence` | Corrélations CPU↔Temp, IO↔Latence |
| `MetricTracker` | Agrégateur par métrique |
| `AIState` | État global IA (singleton) |

### PhysicsEngine.jl

| Module | Responsabilité |
|--------|---------------|
| `ThermalEfficiencyModule` | Résistance thermique, dégradation |
| `FanStabilityModule` | Variance RPM, hunting |
| `PowerQualityModule` | Vcore, 12V stability |
| `ThermalSaturationModule` | Time-to-throttle |
| `WorkloadClassifierModule` | Seuils dynamiques |
| `BottleneckDetectorModule` | Resource limiting |

---

## Dépannage

### "WebSocket connection failed"

**Causes** :
1. Backend pas démarré
2. Port bloqué par firewall
3. URL incorrecte dans le frontend

**Solution** :
```bash
# Vérifier que le backend tourne
curl -i http://localhost:8080/

# Vérifier le port
ss -tlnp | grep 8080

# Frontend: vérifier VITE_WS_URL dans .env
```

### "No network interfaces"

**Cause** : Les interfaces ne correspondent pas aux patterns attendus.

**Solution** :
```bash
cat /proc/net/dev
# Modifier is_excluded_iface() dans Network.jl si nécessaire
```

### "No NVIDIA GPU detected"

**Causes** :
1. `nvidia-smi` non installé ou pas dans PATH
2. Driver NVIDIA non chargé

**Solution** :
```bash
which nvidia-smi
nvidia-smi
# Si absent, installer le driver propriétaire
```

### Frontend: "Cannot read property of null"

**Cause** : Données pas encore reçues du backend.

**Solution** : Ajouter des null checks dans les composants ou utiliser les atomic selectors avec valeurs par défaut.

### Rendu 3D saccadé

**Cause** : Conflit entre autoRotate et frame loop manuel.

**Solution** : Mise à jour du `Scene.tsx` avec `UnifiedFrameController` (voir corrections de performance).

---

## Roadmap

### Version 2.1 (En cours)
- [x] Physics Engine avec 6 modules diagnostics
- [x] Digital Twin 3D avec animation ventilateurs
- [x] Isolation Forest streaming
- [x] Analyse spectrale FFT
- [x] Analyse comportementale Markov
- [ ] Export JSON/CSV des métriques
- [ ] Mode headless (sans TUI)

### Version 2.2 (Planifié)
- [ ] Support AMD GPU (via rocm-smi)
- [ ] Support Intel GPU (via intel_gpu_top)
- [ ] Alertes webhook (Slack, Discord)
- [ ] Persistance des préférences utilisateur

### Version 3.0 (Futur)
- [ ] Support Windows (WMI, Performance Counters)
- [ ] Support macOS (IOKit, sysctl)
- [ ] Authentification WebSocket
- [ ] Mode cluster (multi-machines)
- [ ] Modèles ML prédictifs avancés

---

## Licence

MIT License - Copyright (c) 2025

---

*LYRA - Intelligent System Monitoring*