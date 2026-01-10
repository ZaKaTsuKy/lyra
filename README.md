# OMNI MONITOR

## Dashboard de Monitoring Système avec Intelligence Artificielle

**Version:** 3.0  
**Langage:** Julia 1.9+  
**Plateforme:** Linux (avec architecture préparée pour Windows/macOS)  
**Licence:** MIT

---

## Table des Matières

1. [Présentation](#présentation)
2. [Fonctionnalités](#fonctionnalités)
3. [Architecture](#architecture)
4. [Installation](#installation)
5. [Utilisation](#utilisation)
6. [Module IA - Analyse Approfondie](#module-ia---analyse-approfondie)
7. [Structure du Projet](#structure-du-projet)
8. [Référence des Modules](#référence-des-modules)
9. [Personnalisation](#personnalisation)
10. [Dépannage](#dépannage)
11. [Roadmap](#roadmap)
12. [Contribution](#contribution)

---

## Présentation

### Vision

OMNI MONITOR est un dashboard de monitoring système en temps réel qui se distingue par son **moteur d'intelligence artificielle statistique** intégré. Contrairement aux outils de monitoring traditionnels qui se contentent d'afficher des métriques brutes, OMNI MONITOR analyse en continu le comportement du système pour :

- **Détecter les anomalies** avant qu'elles ne deviennent des problèmes
- **Prédire les situations critiques** (mémoire pleine, surchauffe, saturation disque)
- **Identifier les changements de régime** (passage idle → compute → gaming)
- **Corréler les métriques** pour détecter les incohérences matérielles

### Philosophie

Le projet repose sur trois principes fondamentaux :

1. **Efficacité mémoire O(1)** : Les algorithmes statistiques (T-Digest, Welford, EWMA) fonctionnent en streaming sans accumulation de données historiques
2. **Zéro dépendance externe** : Lecture directe de `/proc` et `/sys` sans agents ni daemons
3. **Interface TUI native** : Affichage terminal fluide avec double-buffering, sans bibliothèque graphique lourde

### Public Cible

- Administrateurs système souhaitant un outil de diagnostic intelligent
- Développeurs analysant les performances de leurs applications
- Passionnés de hardware surveillant leur configuration (GPU, températures)
- Chercheurs en observabilité et AIOps

---

## Fonctionnalités

### Monitoring Hardware

| Composant | Métriques | Source |
|-----------|-----------|--------|
| **CPU** | Usage par cœur, fréquences, load average, température, context switches/s, interrupts/s, PSI | `/proc/stat`, `/proc/cpuinfo`, `/sys/class/hwmon`, `/proc/pressure` |
| **Mémoire** | Totale/utilisée/disponible, swap, composition (anon/cache/buffers), huge pages, dirty pages | `/proc/meminfo`, `/proc/vmstat` |
| **GPU** | Utilisation, VRAM, température, puissance, clocks SM/mem, throttling | `nvidia-smi` |
| **Réseau** | Débit RX/TX par interface, paquets/s, erreurs, drops, connexions TCP (ESTABLISHED/TIME_WAIT/CLOSE_WAIT) | `/proc/net/dev`, `/proc/net/tcp` |
| **Disques** | Espace par point de montage, IOPS, débit lecture/écriture, latence moyenne, queue depth | `df`, `/proc/diskstats` |
| **Batterie** | Pourcentage, état (charge/décharge), puissance, temps restant, santé | `/sys/class/power_supply` |
| **Processus** | Top 15 par CPU, état (R/S/D/Z), threads, I/O par processus | `/proc/[pid]/*` |

### Intelligence Artificielle

| Fonctionnalité | Algorithme | Description |
|----------------|------------|-------------|
| **Centiles en streaming** | T-Digest | P50, P95, P99 sans stocker l'historique complet |
| **Z-Score robuste** | MAD (Median Absolute Deviation) | Détection d'anomalies résistante aux outliers |
| **Prévision saisonnière** | Holt-Winters (Triple Exponential Smoothing) | Prédiction tenant compte des patterns cycliques |
| **Détection de régime** | ADWIN (Adaptive Windowing) | Identification automatique des changements de comportement |
| **Détection de dérive** | CUSUM (Cumulative Sum) | Alerte sur les dégradations lentes (fuites mémoire) |
| **Cohérence physique** | Corrélation CPU↔Temp, IOPS↔Latence | Détection d'anomalies matérielles |
| **Modèle de saturation** | Loi de Little | Estimation du point de knee et capacité maximale |
| **Échantillonnage adaptatif** | Feedback loop | Ajustement automatique de la fréquence selon la volatilité |

### Interface Utilisateur

- **Layout adaptatif** : 4 colonnes (≥140 cars), 3 colonnes (≥100), 2 colonnes (≥80), 1 colonne (mobile)
- **Sparklines** : Historique visuel compact des 2 dernières minutes
- **Heatmaps** : Visualisation de l'usage par cœur CPU
- **Barres de progression** : Avec dégradé de couleur selon criticité
- **Ticker d'alertes** : Notifications en temps réel des situations anormales
- **Panneaux dédiés** : CPU, Mémoire, GPU, Réseau, Disques, Processus, Anomalies, Analytics, Saturation

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         main.jl                                  │
│                    (Boucle principale)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SystemMonitor (État global)                   │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │CPUInfo  │ │MemInfo  │ │GPUInfo  │ │NetInfo  │ │DiskInfo │   │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │
│  ┌─────────────────────┐ ┌─────────────────────────────────┐   │
│  │  MetricHistory      │ │       AnomalyScore              │   │
│  │  (120 samples)      │ │  (CPU, MEM, IO, NET, GPU, TEMP) │   │
│  └─────────────────────┘ └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────────┐    ┌─────────────────────────────────────┐
│   OS/Linux/*.jl     │    │            AI.jl                    │
│  ┌───────────────┐  │    │  ┌─────────┐ ┌─────────┐ ┌───────┐ │
│  │ CPU.jl        │  │    │  │T-Digest │ │  MAD    │ │Welford│ │
│  │ Memory.jl     │  │    │  └─────────┘ └─────────┘ └───────┘ │
│  │ GPU.jl        │  │    │  ┌─────────┐ ┌─────────┐ ┌───────┐ │
│  │ Network.jl    │  │    │  │  H-W    │ │ ADWIN   │ │ CUSUM │ │
│  │ DiskIO.jl     │  │    │  └─────────┘ └─────────┘ └───────┘ │
│  │ DiskSpace.jl  │  │    │  ┌─────────────────────────────┐   │
│  │ Processes.jl  │  │    │  │   PhysicalCoherence         │   │
│  │ Battery.jl    │  │    │  │   SaturationModel           │   │
│  │ SystemUtils.jl│  │    │  │   AdaptiveSampler           │   │
│  └───────────────┘  │    │  └─────────────────────────────┘   │
└─────────────────────┘    └─────────────────────────────────────┘
         │                              │
         └──────────────┬───────────────┘
                        ▼
              ┌─────────────────┐
              │     UI.jl       │
              │  (Rendu TUI)    │
              │  ┌───────────┐  │
              │  │ Panels    │  │
              │  │ Sparklines│  │
              │  │ Alerts    │  │
              │  └───────────┘  │
              └─────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │    Terminal     │
              │   (stdout)      │
              └─────────────────┘
```

### Flux de Données

1. **Collecte** (toutes les 0.5s par défaut) : Les modules `OS/Linux/*.jl` lisent `/proc` et `/sys`
2. **Agrégation** : Les métriques sont stockées dans `SystemMonitor`
3. **Analyse IA** : `AI.jl` calcule les scores d'anomalie, tendances et prédictions
4. **Rendu** : `UI.jl` génère l'affichage ANSI et l'écrit atomiquement (double-buffering)

---

## Installation

### Prérequis

- **Julia 1.9+** : [julialang.org/downloads](https://julialang.org/downloads/)
- **Linux** : Kernel 4.x+ avec `/proc` et `/sys` montés
- **nvidia-smi** (optionnel) : Pour le monitoring GPU NVIDIA

### Installation Rapide

```bash
# Cloner le dépôt
git clone https://github.com/votre-repo/omni-monitor.git
cd omni-monitor/back-end

# Installer les dépendances Julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Lancer
julia --project=. main.jl
```

### Installation Système

```bash
# Créer un alias
echo 'alias omni="julia --project=/chemin/vers/omni-monitor/back-end /chemin/vers/omni-monitor/back-end/main.jl"' >> ~/.bashrc
source ~/.bashrc

# Utiliser
omni
```

---

## Utilisation

### Lancement

```bash
# Mode standard (rafraîchissement 0.5s)
julia main.jl

# Mode debug (une seule itération)
julia main.jl --once

# Sans GPU
julia main.jl --no-gpu

# Sans batterie
julia main.jl --no-battery

# Sans processus
julia main.jl --no-processes

# Aide
julia main.jl --help
```

### Contrôles

| Touche | Action |
|--------|--------|
| `Ctrl+C` | Quitter proprement |

### Lecture du Dashboard

#### Panel CPU
```
┌── CPU ─────────────────────────┐
│ ████████████░░░░░░░░░  45.2%   │  ← Barre de progression colorée
│ Load: 2.45 3.12 2.89 | 8 cores │  ← Load average 1/5/15 min
│ Cores: ▃▅▂▇▁▄▃▆                │  ← Heatmap par cœur
│ Freq: 3200 MHz | 45K ctx/s     │  ← Fréquence et context switches
│ History: ▂▃▅▇▆▄▃▂ ↗            │  ← Sparkline avec tendance
└────────────────────────────────┘
```

#### Panel AI Anomaly
```
┌── AI ANOMALY ──────────────────┐
│ OVERALL: 35% ↗ →MEM in 2.5h    │  ← Score global + prédiction
│                                │
│ CPU ████████░░ 42% ↗           │  ← Scores par métrique
│ MEM █████████░ 65% ↗ !         │  ← ! = spike détecté
│ I/O ████░░░░░░ 28% -           │
│ NET ██░░░░░░░░ 12% -           │
└────────────────────────────────┘
```

#### Panel Analytics (Mode avancé)
```
┌── AI ANALYTICS ────────────────┐
│ REGIME: COMPUTE | Sample: 0.5s │  ← Régime détecté + intervalle
│                                │
│ --- Z-Scores (MAD) ---         │
│ CPU: z=1.8 MEM: z=2.4!         │  ← Z-scores robustes
│                                │
│ --- Percentiles ---            │
│ CPU P50:32 P95:78 P99:92       │  ← Distribution historique
│                                │
│ --- Coherence ---              │
│ CPU↔Temp: 0.85 ✓               │  ← Corrélations physiques
│ IO↔Lat: 0.72 ✓                 │
└────────────────────────────────┘
```

---

## Module IA - Analyse Approfondie

### T-Digest : Centiles en Streaming

Le T-Digest permet de calculer des centiles (médiane, P95, P99) sur un flux de données sans stocker l'historique complet. Il utilise une compression adaptative qui garde plus de précision aux extrémités de la distribution.

**Complexité** : O(1) espace, O(log n) par insertion

```julia
# Structure interne
mutable struct TDigest
    centroids::Vector{TDigestCentroid}  # Clusters compressés
    compression::Float64                 # Facteur de compression
    total_weight::Float64
end

# Calcul du P95
p95 = quantile(td, 0.95)
```

### MAD : Z-Score Robuste

Le Z-Score classique `(x - μ) / σ` est sensible aux outliers. Le MAD (Median Absolute Deviation) utilise la médiane au lieu de la moyenne :

```
Z_robust = (x - médiane) / (1.4826 × MAD)
```

Le facteur 1.4826 normalise pour être comparable à un Z-Score classique sur une distribution normale.

### Holt-Winters : Prévision Saisonnière

L'algorithme de Holt-Winters (Triple Exponential Smoothing) décompose le signal en trois composantes :

1. **Level (α)** : Valeur de base lissée
2. **Trend (β)** : Pente de la tendance
3. **Seasonal (γ)** : Facteurs saisonniers (période = 60 échantillons ≈ 30s)

```julia
# Prédiction à l'horizon H
prediction = (level + H × trend) × seasonal[future_idx]
```

### ADWIN : Détection de Changement de Régime

ADWIN (ADaptive WINdowing) détecte automatiquement quand la distribution statistique d'un flux change. Il maintient une fenêtre adaptative et teste en continu si les sous-fenêtres ont des moyennes significativement différentes.

**Régimes détectés** :
- `idle` : CPU < 20%, MEM < 50%
- `normal` : Activité modérée
- `compute` : CPU > 70%
- `gaming` : GPU > 80% ou (CPU > 60% et GPU > 30%)
- `heavy_io` : I/O > P95 × 0.7
- `memory_intensive` : MEM > P95 × 0.9

### CUSUM : Détection de Dérive

CUSUM (CUmulative SUM) détecte les dérives lentes qui seraient invisibles avec un seuil fixe. Il accumule les écarts à la moyenne et alerte quand la somme dépasse un seuil.

**Cas d'usage typique** : Détection de fuites mémoire progressives.

### Cohérence Physique

Le module analyse les corrélations attendues physiquement :

| Corrélation | Attendue | Anomalie si |
|-------------|----------|-------------|
| CPU ↔ Température | Positive (> 0.5) | Température élevée sans charge CPU |
| IOPS ↔ Latence | Positive (> 0.6) | Latence élevée sans I/O |

Ces incohérences peuvent indiquer des problèmes matériels (ventilateur défaillant, disque en fin de vie).

### Modèle de Saturation

Basé sur la Loi de Little, le modèle estime la saturation des ressources :

```julia
saturation_score = utilization >= knee_ratio ? 
    1 - (1 - utilization)² :  # Zone de saturation (courbe quadratique)
    utilization / knee_ratio × 0.5  # Zone linéaire
```

Le **point de knee** (genou) est le seuil à partir duquel les performances se dégradent non-linéairement (typiquement 80%).

---

## Structure du Projet

```
ai_dashboard/
├── README.md                 # Ce fichier
├── back-end/
│   ├── main.jl              # Point d'entrée (207 lignes)
│   ├── Project.toml         # Dépendances Julia
│   ├── Manifest.toml        # Versions verrouillées
│   │
│   ├── types/
│   │   └── MonitorTypes.jl  # Structures de données (621 lignes)
│   │
│   ├── ui/
│   │   └── UI.jl            # Interface TUI (1034 lignes)
│   │
│   ├── helpers/
│   │   └── debug.jl         # Utilitaires de diagnostic (167 lignes)
│   │
│   └── OS/
│       ├── Linux/           # Collecteurs Linux (2539 lignes)
│       │   ├── AI.jl        # Moteur IA (897 lignes) ★
│       │   ├── CPU.jl       # CPU, température, fréquences (380 lignes)
│       │   ├── Memory.jl    # RAM, swap, composition (129 lignes)
│       │   ├── GPU.jl       # NVIDIA via nvidia-smi (248 lignes)
│       │   ├── Network.jl   # Interfaces, TCP stats (279 lignes)
│       │   ├── DiskIO.jl    # IOPS, débit, latence (159 lignes)
│       │   ├── DiskSpace.jl # Points de montage (190 lignes)
│       │   ├── Processes.jl # Top processus (176 lignes)
│       │   ├── Battery.jl   # État batterie (150 lignes)
│       │   └── SystemUtils.jl # Uptime, PSI, OOM (121 lignes)
│       │
│       ├── Windows/         # (Préparé, non implémenté)
│       └── MacOS/           # (Préparé, non implémenté)
│
└── .git/                    # Historique Git
```

**Total** : ~4758 lignes de code Julia

---

## Référence des Modules

### MonitorTypes.jl

Définit toutes les structures de données du système :

| Structure | Rôle |
|-----------|------|
| `SystemMonitor` | État global racine contenant tous les sous-systèmes |
| `CPUInfo` | Modèle, fréquences, load, température, context switches |
| `MemoryInfo` | RAM, swap, composition, huge pages, pression |
| `GPUInfo` | Nom, utilisation, VRAM, température, puissance, throttling |
| `NetworkInfo` | Interfaces, débits, TCP stats |
| `DiskUsage` | Points de montage, espace |
| `DiskIOMetrics` | IOPS, débit, latence, queue depth |
| `ProcessInfo` | PID, nom, CPU%, mémoire, état, I/O |
| `BatteryInfo` | Pourcentage, état, puissance, santé |
| `AnomalyScore` | Scores IA par métrique, tendances, spikes, prédictions |
| `MetricHistory` | Buffer circulaire + EMA baselines |
| `EMATracker` | Moyenne mobile exponentielle |
| `RateTracker` | Calcul de taux (delta/time) |
| `StaticCache` | Données invariantes (modèle CPU, hostname) |

### AI.jl

Le cœur de l'intelligence artificielle :

| Composant | Lignes | Description |
|-----------|--------|-------------|
| `TDigest` | 50-125 | Centiles en streaming |
| `WelfordStats` | 130-175 | Variance en ligne |
| `MADTracker` | 180-210 | Z-Score robuste |
| `HoltWinters` | 215-270 | Prévision triple lissage |
| `ADWIN` | 275-350 | Détection changement régime |
| `CUSUM` | 350-385 | Détection dérive |
| `PhysicalCoherence` | 390-430 | Corrélations matérielles |
| `SaturationModel` | 435-455 | Loi de Little |
| `AdaptiveSampler` | 460-510 | Fréquence adaptative |
| `MetricTracker` | 515-600 | Agrégateur par métrique |
| `AIState` | 605-670 | État global IA |
| Score functions | 675-760 | Calcul des scores |
| Predictions | 760-805 | Prédictions time-to-critical |
| Alerts | 810-870 | Génération d'alertes |

### UI.jl

Rendu terminal avancé :

| Section | Lignes | Description |
|---------|--------|-------------|
| Terminal control | 25-50 | Curseur, clear, ANSI |
| UTF-8 handling | 55-100 | safe_truncate, visual_width |
| Colors | 100-135 | Palette ANSI 16 couleurs |
| Formatting | 155-185 | fmt_bytes, fmt_rate, fmt_duration |
| Visual components | 190-280 | progress_bar, sparkline, heatmap |
| Box drawing | 285-335 | Bordures Unicode |
| Panel builders | 340-615 | CPU, MEM, GPU, NET, DISK, PROC |
| Anomaly panel | 615-660 | Affichage scores IA |
| Analytics panel | 665-780 | Z-scores, régimes, percentiles |
| Saturation panel | 780-825 | Modèle saturation |
| Alert ticker | 825-850 | Notifications scrollantes |
| Main render | 860-1035 | Layout adaptatif, double-buffering |

---

## Personnalisation

### Configuration

Modifier les constantes dans `main.jl` :

```julia
const CONFIG = (
    refresh_interval = 0.5,    # Secondes entre updates
    enable_gpu = true,         # Monitoring GPU
    enable_battery = true,     # Monitoring batterie
    enable_processes = true,   # Liste des processus
    max_iterations = nothing,  # nothing = infini
)
```

### Seuils IA

Modifier `AI_CONFIG` dans `AI.jl` :

```julia
const AI_CONFIG = (
    cpu_critical = 95.0,           # Seuil alerte CPU
    mem_critical = 95.0,           # Seuil alerte mémoire
    temp_critical = 95.0,          # Seuil alerte température
    zscore_warning = 2.5,          # Z-score pour warning
    zscore_critical = 3.5,         # Z-score pour critical
    cusum_threshold = 5.0,         # Seuil CUSUM
    saturation_knee_ratio = 0.8,   # Point de knee (80%)
    # ...
)
```

### Filtrage Réseau

Modifier `is_excluded_iface()` dans `Network.jl` pour inclure/exclure des interfaces.

### Filtrage Disques

Modifier `is_relevant_mount()` dans `DiskSpace.jl` pour choisir les points de montage affichés.

---

## Dépannage

### "No network interfaces"

**Cause** : Les interfaces ne correspondent pas aux patterns attendus.

**Solution** :
```bash
# Vérifier les interfaces disponibles
cat /proc/net/dev
# Modifier is_excluded_iface() si nécessaire
```

### "No NVIDIA GPU detected"

**Causes possibles** :
1. `nvidia-smi` non installé ou non dans le PATH
2. Driver NVIDIA non chargé

**Solution** :
```bash
# Vérifier nvidia-smi
which nvidia-smi
nvidia-smi

# Si absent, installer le driver NVIDIA
```

### "No disk IO data"

**Cause** : Aucun disque valide trouvé (nvme, sd, vd).

**Solution** :
```bash
# Vérifier les disques
cat /proc/diskstats | grep -E "nvme|sd|vd"
lsblk
```

### Erreur StringIndexError

**Cause** : Indexation UTF-8 incorrecte sur des chaînes avec caractères multi-octets.

**Solution** : Mise à jour vers la dernière version (corrigé avec `safe_truncate()`).

### Affichage cassé / scintillement

**Causes** :
1. Terminal trop étroit (< 80 colonnes)
2. Émulateur de terminal non compatible ANSI

**Solution** :
```bash
# Agrandir le terminal
# Utiliser un terminal moderne (gnome-terminal, kitty, alacritty)
```

---

## Roadmap

### Version 3.1 (Prévue)
- [ ] Export JSON/CSV des métriques
- [ ] Mode headless (sans TUI)
- [ ] Configuration via fichier YAML

### Version 3.2 (Prévue)
- [ ] Support AMD GPU (via rocm-smi)
- [ ] Support Intel GPU (via intel_gpu_top)
- [ ] Alertes par webhook (Slack, Discord)

### Version 4.0 (Future)
- [ ] Support Windows (WMI, Performance Counters)
- [ ] Support macOS (IOKit, sysctl)
- [ ] Interface web optionnelle (WebSocket + React)
- [ ] Modèles ML pour prédiction avancée

---

## Contribution

### Signaler un Bug

1. Vérifier que le bug n'est pas déjà signalé
2. Fournir : version Julia, distribution Linux, sortie de `julia main.jl --once`
3. Inclure les messages d'erreur complets

### Proposer une Amélioration

1. Ouvrir une issue décrivant la fonctionnalité
2. Discuter de l'implémentation
3. Soumettre une PR avec tests

### Style de Code

- Indentation : 4 espaces
- Noms de fonctions : `snake_case`
- Noms de types : `PascalCase`
- Constantes : `SCREAMING_SNAKE_CASE`
- Docstrings : Format Julia standard `"""Description"""`

---

## Licence

MIT License - Voir LICENSE pour les détails.

---

## Remerciements

- L'équipe Julia pour un langage performant et expressif
- Les contributeurs de `/proc` et `/sys` pour l'observabilité Linux
- La communauté open-source pour les algorithmes statistiques (T-Digest, ADWIN, etc.)

---

*OMNI MONITOR - Parce que votre système mérite une IA qui veille sur lui.*