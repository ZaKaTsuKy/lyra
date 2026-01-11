# OMNI MONITOR
## Guide de Configuration des Sensors Hardware
**Configuration modulaire pour Linux**  
*Version 1.0 - Janvier 2025*

---

## Table des Matières
1. [Introduction et Prérequis](#1-introduction-et-prérequis)
2. [Architecture hwmon sous Linux](#2-architecture-hwmon-sous-linux)
3. [Détection Automatique des Sensors](#3-détection-automatique-des-sensors)
4. [Configuration par Type de Hardware](#4-configuration-par-type-de-hardware)
5. [Dépannage et Problèmes Courants](#5-dépannage-et-problèmes-courants)
6. [Référence des Modules Kernel](#6-référence-des-modules-kernel)

---

## 1. Introduction et Prérequis

Ce guide explique comment configurer les sensors hardware (ventilateurs, voltages, températures) pour qu'ils soient détectés par Omni Monitor sur n'importe quelle machine Linux.

### 1.1 Prérequis

> [!NOTE]
> **Packages Requis**  
> Installez `lm-sensors` avant de continuer. Ce package fournit les outils de détection et les modules kernel nécessaires.

```bash
# Debian/Ubuntu
sudo apt install lm-sensors

# Fedora/RHEL
sudo dnf install lm_sensors

# Arch Linux
sudo pacman -S lm_sensors
```

### 1.2 Vérification Initiale

```bash
sensors
```

Si la commande affiche uniquement les températures CPU/GPU sans les ventilateurs ni voltages, continuez ce guide.

---

## 2. Architecture hwmon sous Linux

### 2.1 Comment Linux Expose les Sensors

Linux expose les sensors hardware via `/sys/class/hwmon/`. Chaque périphérique contient :

| Fichier | Type | Description |
|---------|------|-------------|
| `temp*_input` | Température | Valeur en milli-°C (÷1000) |
| `fan*_input` | Ventilateur | Vitesse en RPM |
| `in*_input` | Voltage | Tension en mV (÷1000) |
| `*_label` | Label | Nom lisible |
| `name` | ID | Nom du driver/chip |

### 2.2 Sources des Données Hardware

| Composant | Source | Module Kernel |
|-----------|--------|---------------|
| CPU AMD | Sensor intégré | `k10temp` |
| CPU Intel | Sensor intégré | `coretemp` |
| GPU NVIDIA | nvidia-smi | `nvidia` |
| GPU AMD | hwmon via amdgpu | `amdgpu` |
| Fans/Voltages | Chip Super I/O | `nct6775`, `it87` |
| Carte mère ASUS | ACPI/WMI | `asus-wmi`, `asus-ec-sensors` |
| NVMe SSD | Sensor intégré | `nvme` |

---

## 3. Détection Automatique des Sensors

### 3.1 Lancer la Détection

> [!WARNING]
> La détection peut écrire dans les registres hardware. Répondez **YES** uniquement aux questions que vous comprenez.

```bash
# Détection interactive (recommandé)
sudo sensors-detect

# Détection automatique (risqué)
sudo sensors-detect --auto
```

### 3.2 Comprendre les Questions

| Question | Signification | Recommandation |
|----------|---------------|----------------|
| Probe for PCI sensors? | GPU, cartes réseau | YES (sûr) |
| Probe for Super I/O sensors? | Fans/voltages carte mère | YES (important) |
| Probe for ISA I/O sensors? | Anciens chipsets | YES si pas de Super I/O |
| Probe for IPMI? | Serveurs avec BMC | YES si serveur |
| Scan specific addresses? | Adresses I2C non standard | NO sauf si nécessaire |

### 3.3 Charger les Modules Détectés

```bash
# Charger les modules immédiatement
sudo systemctl restart systemd-modules-load

# Ou manuellement
sudo modprobe nct6775

# Vérifier
lsmod | grep -E "nct|it87|k10temp|coretemp"
```

---

## 4. Configuration par Type de Hardware

### 4.1 Processeurs AMD (Ryzen, EPYC)

```bash
sudo modprobe k10temp
sensors | grep -A5 k10temp
```

> [!TIP]
> `Tctl` peut afficher un offset de +27°C sur certains Ryzen. `Tdie` est la vraie température.

### 4.2 Processeurs Intel

```bash
sudo modprobe coretemp
sensors | grep -A10 coretemp
```

### 4.3 Cartes Mères (Fans et Voltages)

| Fabricant Chip | Module Kernel | Cartes Mères |
|----------------|---------------|--------------|
| Nuvoton NCT67xx | `nct6775` | ASUS, Gigabyte, MSI récentes |
| ITE IT87xx | `it87` | ASRock, anciennes cartes |
| Fintek F718xx | `f71882fg` | Certaines Gigabyte |
| Winbond W836xx | `w83627hf` | Anciennes cartes |

```bash
sudo modprobe nct6775  # Le plus courant
sudo modprobe it87     # Alternative
sensors | grep -E "fan|in[0-9]"
```

### 4.4 Cartes Mères ASUS (Configuration Spéciale)

> [!IMPORTANT]
> **ASUS ROG/TUF/ProArt**  
> Ces cartes nécessitent souvent des modules spécifiques en plus de `nct6775`.

```bash
# Module ASUS EC Sensors (kernel 5.18+)
sudo modprobe asus-ec-sensors

# Module ASUS WMI (alternatif)
sudo modprobe asus-wmi

# Vérifier les modules ASUS disponibles
find /lib/modules/$(uname -r) -name "*asus*"
```

Cartes supportées : ROG CROSSHAIR VIII, ROG STRIX X570/B550, ProArt X570, TUF GAMING X570/B550, etc.

### 4.5 GPU NVIDIA

> [!NOTE]
> Les GPU NVIDIA n'utilisent **PAS** hwmon. Omni Monitor utilise `nvidia-smi` directement.

```bash
nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,power.draw --format=csv
```

### 4.6 GPU AMD

```bash
sensors | grep -A10 amdgpu
lsmod | grep amdgpu
```

---

## 5. Dépannage et Problèmes Courants

### 5.1 Aucun Fan Détecté

| Symptôme | Cause Probable | Solution |
|----------|----------------|----------|
| sensors ne montre aucun fan | Module Super I/O non chargé | `sudo modprobe nct6775` ou `it87` |
| Module refuse de charger | Paramètre force nécessaire | Voir section 5.2 |
| Fan visible mais RPM=0 | Fan PWM sans tachymètre | Normal pour certains fans |
| Certains fans manquants | Headers non monitorés | Vérifier connexions carte mère |

### 5.2 Forcer le Chargement d'un Module

```bash
# Forcer le module it87
sudo modprobe it87 force_id=0x8628

# Forcer nct6775 
sudo modprobe nct6775 force_id=0xd42a

# Rendre permanent
echo "options it87 force_id=0x8628" | sudo tee /etc/modprobe.d/sensors.conf
```

### 5.3 Trouver l'ID du Chipset

```bash
sudo dmidecode -t baseboard | grep -E "Manufacturer|Product"
sudo sensors-detect 2>&1 | grep -E "Found|Chip"
```

### 5.4 Vérifier les Données Brutes

```bash
for hw in /sys/class/hwmon/hwmon*; do
    echo "=== $(cat $hw/name 2>/dev/null || basename $hw) ==="
    ls $hw/ | grep -E "^(fan|in[0-9]|temp)" | head -5
done
```

---

## 6. Référence des Modules Kernel

### 6.1 Modules par Type de Sensor

| Catégorie | Module | Description |
|-----------|--------|-------------|
| CPU AMD | `k10temp` | Températures Ryzen/EPYC |
| CPU AMD (ancien) | `fam15h_power` | Puissance Family 15h |
| CPU Intel | `coretemp` | Températures Intel Core |
| GPU AMD | `amdgpu` | Intégré au driver GPU |
| Super I/O Nuvoton | `nct6775` | NCT6775/6776/6779/6791/etc |
| Super I/O ITE | `it87` | IT8705/8712/8716/8718/etc |
| Super I/O Fintek | `f71882fg` | F71808E/71858/71862/71868/etc |
| ASUS EC | `asus-ec-sensors` | Sensors embarqués ASUS |
| ASUS WMI | `asus-wmi` | Interface WMI ASUS |
| Dell | `dell-smm-hwmon` | Fans Dell laptops/serveurs |
| NVMe | `nvme` | Températures SSD NVMe |

### 6.2 Configuration Persistante

```bash
# Méthode 1: /etc/modules (Debian/Ubuntu)
echo "nct6775" | sudo tee -a /etc/modules
echo "k10temp" | sudo tee -a /etc/modules

# Méthode 2: /etc/modules-load.d/ (systemd)
echo "nct6775" | sudo tee /etc/modules-load.d/hwmon.conf
echo "k10temp" | sudo tee -a /etc/modules-load.d/hwmon.conf

# Méthode 3: Avec options (force_id)
echo "options it87 force_id=0x8628" | sudo tee /etc/modprobe.d/hwmon.conf

# Recharger
sudo systemctl restart systemd-modules-load
```

### 6.3 Commandes de Diagnostic

```bash
sensors -u                                    # Format parseable
ls -la /sys/class/hwmon/                     # Modules hwmon chargés
modinfo nct6775                              # Info module
dmesg | grep -iE "nct|it87|hwmon|sensor"     # Logs kernel
```

---

## Checklist Finale

- [ ] Installer `lm-sensors`
- [ ] Lancer `sudo sensors-detect`
- [ ] Charger les modules suggérés
- [ ] Vérifier avec `sensors`
- [ ] Rendre persistent via `/etc/modules` ou `/etc/modules-load.d/`
- [ ] Redémarrer Omni Monitor

---

*— Fin du Document —*
