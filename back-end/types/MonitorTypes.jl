# MonitorTypes.jl
# ============================
# OMNI MONITOR - Core Types v2.1
# ============================
# Enhanced with:
# - CPU temperature support
# - Rate-based metrics (context switches/s)
# - TCP connection tracking
# - IOPS metrics
# - AI baseline/prediction structures
# ============================

using Dates
using Statistics: mean, std

# ============================
# CPU STATE
# ============================

mutable struct CoreState
    idle::Int
    total::Int
end

CoreState() = CoreState(0, 0)

# ============================
# IO STATE (Generic)
# ============================

mutable struct IOState
    rx::Int
    tx::Int
    timestamp::Float64
end

IOState() = IOState(0, 0, time())

# ============================
# DISK IO STATE
# ============================

mutable struct DiskIOState
    read_sectors::Int
    write_sectors::Int
    read_ios::Int        # NEW: read operations count
    write_ios::Int       # NEW: write operations count
    io_time_ms::Int
    weighted_io_ms::Int
    timestamp::Float64
end

DiskIOState() = DiskIOState(0, 0, 0, 0, 0, 0, time())

# ============================
# PROCESS STATE
# ============================

mutable struct ProcState
    utime::Int
    stime::Int
    read_bytes::Int
    write_bytes::Int
end

ProcState() = ProcState(0, 0, 0, 0)

# ============================
# GPU INFO
# ============================

mutable struct GPUInfo
    name::String
    util::Float64
    mem_used::Float64
    mem_total::Float64
    temp::Float64
    power_draw::Float64
    power_limit::Float64
    sm_clock::Float64
    mem_clock::Float64
    throttling::Vector{String}
end

GPUInfo() = GPUInfo("", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, String[])

# ============================
# DISK USAGE
# ============================

mutable struct DiskUsage
    mount::String
    total_gb::Float64
    used_gb::Float64
    avail_gb::Float64
    percent::Float64
    read_bps::Float64
    write_bps::Float64
end

DiskUsage() = DiskUsage("", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

# ============================
# PROCESS INFO
# ============================

mutable struct ProcessInfo
    pid::Int
    name::String
    cpu::Float64
    mem_kb::Float64
    threads::Int
    io_read_bps::Float64
    io_write_bps::Float64
    state::Char          # NEW: R/S/D/Z/T
    nice::Int            # NEW: nice value
end

ProcessInfo() = ProcessInfo(0, "", 0.0, 0.0, 0, 0.0, 0.0, 'S', 0)

# ============================
# NETWORK INTERFACE
# ============================

mutable struct NetworkInterface
    name::String
    rx_bytes::Int
    tx_bytes::Int
    rx_bps::Float64
    tx_bps::Float64
    rx_packets_s::Float64
    tx_packets_s::Float64
    rx_errors::Int
    tx_errors::Int
    rx_drops::Int
    tx_drops::Int
end

NetworkInterface() = NetworkInterface("", 0, 0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0)

# ============================
# TCP CONNECTION STATS (NEW)
# ============================

mutable struct TCPStats
    established::Int
    time_wait::Int
    close_wait::Int
    listen::Int
    total::Int
end

TCPStats() = TCPStats(0, 0, 0, 0, 0)

# ============================
# NETWORK INFO
# ============================

mutable struct NetworkInfo
    primary_iface::String
    rx_bps::Float64
    tx_bps::Float64
    total_rx_bytes::Int
    total_tx_bytes::Int
    interfaces::Vector{NetworkInterface}
    classification::String
    tcp::TCPStats        # NEW
end

NetworkInfo() = NetworkInfo("", 0.0, 0.0, 0, 0, NetworkInterface[], "idle", TCPStats())

# ============================
# BATTERY INFO
# ============================

mutable struct BatteryInfo
    present::Bool
    percent::Float64
    status::String
    power_w::Float64
    energy_now::Float64
    energy_full::Float64
    energy_design::Float64
    time_remaining_min::Float64
    health_percent::Float64
    source::String
end

BatteryInfo() = BatteryInfo(false, 0.0, "Unknown", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "Unknown")

# ============================
# MEMORY INFO
# ============================

mutable struct MemoryInfo
    total_kb::Int
    used_kb::Int
    avail_kb::Int
    swap_total_kb::Int
    swap_used_kb::Int
    # Composition
    anon_kb::Int
    file_kb::Int
    buffers_kb::Int
    slab_kb::Int
    # Huge pages
    hugepages_total::Int
    hugepages_free::Int
    hugepage_size_kb::Int
    # Pressure
    pressure_avg10::Float64
    # VM stats
    pgfault::Int
    pgmajfault::Int
    swap_in::Int
    swap_out::Int
    # NEW: Dirty pages
    dirty_kb::Int
    writeback_kb::Int
end

MemoryInfo() = MemoryInfo(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0, 0, 0, 0, 0, 0)

# ============================
# CPU TEMPERATURE (NEW)
# ============================

mutable struct CPUTemperature
    package::Float64         # Overall package temp
    cores::Vector{Float64}   # Per-core temps
    max_temp::Float64        # Maximum across all
    critical_temp::Float64   # Critical threshold
end

CPUTemperature() = CPUTemperature(0.0, Float64[], 0.0, 100.0)

# ============================
# CPU INFO (Enhanced)
# ============================

mutable struct CPUInfo
    model::String
    cache::String
    freq_min::Float64
    freq_avg::Float64
    freq_max::Float64
    governors::Vector{String}
    load1::Float64
    load5::Float64
    load15::Float64
    ctxt_switches::Int
    interrupts::Int
    pressure_avg10::Float64
    # NEW fields
    temperature::CPUTemperature
    ctxt_switches_ps::Float64    # Per second rate
    interrupts_ps::Float64       # Per second rate
end

CPUInfo() = CPUInfo("", "", 0.0, 0.0, 0.0, String[], 0.0, 0.0, 0.0, 0, 0, 0.0,
    CPUTemperature(), 0.0, 0.0)

# ============================
# DISK IO EXTENDED (NEW)
# ============================

const DiskIOMetrics = @NamedTuple{
    read_mb_s::Float64,
    write_mb_s::Float64,
    read_iops::Float64,      # NEW
    write_iops::Float64,     # NEW
    io_wait_pct::Float64,
    queue_depth::Float64,
    avg_wait_ms::Float64     # NEW: average wait time
}

# ============================
# SYSTEM INFO (Enhanced)
# ============================

mutable struct SystemInfo
    uptime_sec::Float64
    environment::String  # baremetal, vm, container
    oom_kills::Int
    psi_cpu::Float64
    psi_mem::Float64
    psi_io::Float64
    # NEW fields
    procs_running::Int       # Running processes
    procs_blocked::Int       # Blocked on IO
end

SystemInfo() = SystemInfo(0.0, "unknown", 0, 0.0, 0.0, 0.0, 0, 0)

# ============================
# AI BASELINE TRACKER (NEW)
# ============================

"""Exponential Moving Average tracker for establishing baselines"""
mutable struct EMATracker
    value::Float64      # Current EMA value
    variance::Float64   # EMA of variance (for std dev)
    alpha::Float64      # Smoothing factor (0.1 = slow, 0.3 = fast)
    initialized::Bool
    sample_count::Int
end

EMATracker(alpha=0.1) = EMATracker(0.0, 0.0, alpha, false, 0)

function update_ema!(tracker::EMATracker, new_value::Float64)
    if !tracker.initialized
        tracker.value = new_value
        tracker.variance = 0.0
        tracker.initialized = true
        tracker.sample_count = 1
        return
    end

    tracker.sample_count += 1

    # Update EMA
    delta = new_value - tracker.value
    tracker.value += tracker.alpha * delta

    # Update variance EMA (for standard deviation)
    tracker.variance = (1 - tracker.alpha) * (tracker.variance + tracker.alpha * delta^2)
end

get_ema_std(tracker::EMATracker) = sqrt(max(tracker.variance, 0.0))

"""Check if value is a spike (> threshold standard deviations from baseline)"""
function is_spike(tracker::EMATracker, value::Float64, threshold::Float64=2.0)
    !tracker.initialized && return false
    tracker.sample_count < 10 && return false  # Need enough samples

    std_dev = get_ema_std(tracker)
    std_dev < 0.001 && return false  # Avoid division issues

    z_score = abs(value - tracker.value) / std_dev
    return z_score > threshold
end

# ============================
# AI PREDICTION (NEW)
# ============================

mutable struct Prediction
    metric::String
    current_value::Float64
    trend_per_sec::Float64     # Rate of change per second
    time_to_critical_sec::Float64  # Estimated time to hit threshold
    threshold::Float64
    confidence::Float64        # 0-1 confidence in prediction
end

Prediction() = Prediction("", 0.0, 0.0, Inf, 100.0, 0.0)

# ============================
# AI ANOMALY SCORES (Enhanced)
# ============================

mutable struct AnomalyScore
    cpu::Float64
    mem::Float64
    io::Float64
    net::Float64
    gpu::Float64
    temp::Float64           # NEW: temperature anomaly
    overall::Float64
    trend::String           # stable, rising, falling
    # NEW: Per-metric trends
    cpu_trend::String
    mem_trend::String
    io_trend::String
    net_trend::String
    # NEW: Spike flags
    cpu_spike::Bool
    mem_spike::Bool
    io_spike::Bool
    net_spike::Bool
    # NEW: Predictions
    predictions::Vector{Prediction}
end

AnomalyScore() = AnomalyScore(
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    "stable", "stable", "stable", "stable", "stable",
    false, false, false, false,
    Prediction[]
)

# ============================
# HISTORY BUFFER (Enhanced)
# ============================

const HISTORY_LENGTH = COLLECTOR_CONFIG.history_length

mutable struct MetricHistory
    cpu_usage::Vector{Float64}
    mem_usage::Vector{Float64}
    net_rx::Vector{Float64}
    net_tx::Vector{Float64}
    gpu_util::Vector{Float64}
    disk_io::Vector{Float64}
    cpu_temp::Vector{Float64}    # NEW
    timestamps::Vector{Float64}

    # NEW: EMA baselines for anomaly detection
    cpu_baseline::EMATracker
    mem_baseline::EMATracker
    io_baseline::EMATracker
    net_baseline::EMATracker
    temp_baseline::EMATracker
end

function MetricHistory()
    MetricHistory(
        Float64[], Float64[], Float64[], Float64[],
        Float64[], Float64[], Float64[], Float64[],
        EMATracker(0.05),  # Slow baseline for CPU
        EMATracker(0.05),  # Slow baseline for MEM
        EMATracker(0.1),   # Faster for IO (more variable)
        EMATracker(0.1),   # Faster for NET
        EMATracker(0.02)   # Very slow for temperature
    )
end

function push_metric!(h::MetricHistory, cpu, mem, rx, tx, gpu, dio, temp=0.0)
    push!(h.cpu_usage, cpu)
    push!(h.mem_usage, mem)
    push!(h.net_rx, rx)
    push!(h.net_tx, tx)
    push!(h.gpu_util, gpu)
    push!(h.disk_io, dio)
    push!(h.cpu_temp, temp)
    push!(h.timestamps, time())

    # Update baselines
    update_ema!(h.cpu_baseline, cpu)
    update_ema!(h.mem_baseline, mem)
    update_ema!(h.io_baseline, dio)
    update_ema!(h.net_baseline, rx + tx)
    temp > 0 && update_ema!(h.temp_baseline, temp)

    # Trim to history length
    while length(h.cpu_usage) > HISTORY_LENGTH
        popfirst!(h.cpu_usage)
        popfirst!(h.mem_usage)
        popfirst!(h.net_rx)
        popfirst!(h.net_tx)
        popfirst!(h.gpu_util)
        popfirst!(h.disk_io)
        popfirst!(h.cpu_temp)
        popfirst!(h.timestamps)
    end
end

# ============================
# STATIC CACHE (NEW)
# ============================

"""Cache for data that doesn't change during runtime"""
mutable struct StaticCache
    cpu_model::String
    cpu_cache::String
    core_count::Int
    kernel_version::String
    hostname::String
    initialized::Bool
end

StaticCache() = StaticCache("", "", 0, "", "", false)

# ============================
# RATE TRACKER (NEW)
# ============================

"""Track cumulative counters and compute rates"""
mutable struct RateTracker
    prev_value::Int
    prev_time::Float64
    rate::Float64
end

RateTracker() = RateTracker(0, time(), 0.0)

function update_rate!(tracker::RateTracker, current_value::Int)
    now = time()
    dt = now - tracker.prev_time

    if dt > 0 && tracker.prev_value > 0
        delta = current_value - tracker.prev_value
        tracker.rate = max(0.0, delta / dt)
    end

    tracker.prev_value = current_value
    tracker.prev_time = now
    return tracker.rate
end

# ============================
# HARDWARE SENSORS (NEW - for voltages and fans)
# ============================

"""Voltage sensor reading"""
struct VoltageSensor
    label::String       # e.g., "Vcore", "+12V"
    value::Float64      # Volts
    chip::String        # e.g., "nct6775"
    index::Int          # Sensor index (in0, in1, etc.)
end

"""Fan sensor reading"""
struct FanSensor
    label::String       # e.g., "CPU Fan", "System Fan"
    rpm::Int            # Revolutions per minute
    chip::String        # e.g., "nct6775"
    index::Int          # Sensor index (fan1, fan2, etc.)
end

"""Aggregated hardware sensors snapshot"""
mutable struct HardwareSensors
    voltages::Vector{VoltageSensor}
    fans::Vector{FanSensor}
    timestamp::Float64
    primary_cpu_fan_rpm::Int        # Cached for quick access
    vcore_voltage::Float64          # Cached for quick access
end

HardwareSensors() = HardwareSensors(VoltageSensor[], FanSensor[], time(), 0, 0.0)

# ============================
# EXTENDED SENSORS (Full Integration)
# ============================

"""Extended CPU temperatures from k10temp (AMD) or coretemp (Intel)"""
struct CPUTemperatureExtended
    tctl::Float64               # Control temp (k10temp)
    tdie::Float64               # Die temp (k10temp)
    tccd::Vector{Float64}       # Per-CCD temps (Zen2+)
    tccd_max::Float64           # Max CCD temp
    package::Float64            # Package temp (coretemp)
    cores::Vector{Float64}      # Per-core temps (coretemp)
    critical::Float64           # Critical threshold
end

CPUTemperatureExtended() = CPUTemperatureExtended(0.0, 0.0, Float64[], 0.0, 0.0, Float64[], 100.0)

"""GPU sensors from amdgpu or nvidia-smi"""
struct GPUSensors
    edge_temp::Float64          # Edge temperature
    hotspot_temp::Float64       # Junction/Hotspot (if available)
    mem_temp::Float64           # Memory temperature
    vdd_voltage::Float64        # GPU core voltage (mV -> V)
    power_w::Float64            # Power consumption
    ppt_limit::Float64          # Power limit
end

GPUSensors() = GPUSensors(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

"""NVMe storage sensor"""
struct NVMeSensor
    name::String                # Device name (nvme0, nvme1)
    temp_composite::Float64     # Main composite temp
    temp_sensor1::Float64       # Sensor 1 (if available)
    temp_sensor2::Float64       # Sensor 2 (if available)
end

NVMeSensor() = NVMeSensor("", 0.0, 0.0, 0.0)

"""Generic temperature sensor"""
struct TempSensor
    label::String               # e.g., "SYSTIN", "AUXTIN"
    value::Float64              # Temperature in Celsius
    chip::String                # Source chip
    index::Int                  # Sensor index
end

"""
Full sensors aggregate - captures ALL available hwmon data.
This is the master struct sent to frontend for comprehensive monitoring.
"""
mutable struct FullSensors
    # Specialized sensors (chip-specific parsing)
    cpu_temps::CPUTemperatureExtended
    gpu_sensors::Union{Nothing,GPUSensors}
    nvme_sensors::Vector{NVMeSensor}

    # Generic sensors (Super I/O chips like nct6775, it87)
    voltages::Vector{VoltageSensor}
    fans::Vector{FanSensor}
    temps_generic::Vector{TempSensor}

    # Metadata
    timestamp::Float64
    chip_names::Vector{String}  # All detected hwmon chips
end

FullSensors() = FullSensors(
    CPUTemperatureExtended(),
    nothing,
    NVMeSensor[],
    VoltageSensor[],
    FanSensor[],
    TempSensor[],
    time(),
    String[]
)

# ============================
# SYSTEM MONITOR ROOT
# ============================

mutable struct SystemMonitor
    # CPU per-core state
    cores::Vector{CoreState}
    cpu_prev::Dict{String,CoreState}

    # Disk IO state
    disk_prev::Dict{String,DiskIOState}

    # Network state
    net_prev::Dict{String,NetworkInterface}
    net_prev_ts::Float64

    # Process state
    proc_prev::Dict{Int,ProcState}
    proc_prev_ts::Float64

    # Current metrics
    cpu_info::CPUInfo
    memory::MemoryInfo
    gpu::Union{Nothing,GPUInfo}
    disks::Vector{DiskUsage}
    disk_io::Dict{String,DiskIOMetrics}
    processes::Vector{ProcessInfo}
    network::NetworkInfo
    battery::BatteryInfo
    system::SystemInfo

    # AI components
    anomaly::AnomalyScore
    history::MetricHistory

    # NEW: Static cache
    static_cache::StaticCache

    # NEW: Rate trackers
    ctxt_rate::RateTracker
    intr_rate::RateTracker

    # NEW: Hardware sensors (voltages, fans)
    hardware::Union{Nothing,HardwareSensors}

    # NEW: Full sensors snapshot (all hwmon data)
    full_sensors::Union{Nothing,FullSensors}

    # Timestamps
    last_update::Float64
    update_count::Int
end

function SystemMonitor()
    n_cores = Sys.CPU_THREADS
    SystemMonitor(
        [CoreState() for _ in 1:n_cores],
        Dict{String,CoreState}(),
        Dict{String,DiskIOState}(),
        Dict{String,NetworkInterface}(),
        time(),
        Dict{Int,ProcState}(),
        time(),
        CPUInfo(),
        MemoryInfo(),
        nothing,
        DiskUsage[],
        Dict{String,DiskIOMetrics}(),
        ProcessInfo[],
        NetworkInfo(),
        BatteryInfo(),
        SystemInfo(),
        AnomalyScore(),
        MetricHistory(),
        StaticCache(),
        RateTracker(),
        RateTracker(),
        nothing,  # hardware sensors (initialized later)
        nothing,  # full_sensors (initialized later)
        time(),
        0
    )
end

# ============================
# UTILITY FUNCTIONS
# ============================

"""Clamp value between 0 and 1 for anomaly scores"""
clamp01(x) = clamp(x, 0.0, 1.0)

"""Format bytes to human readable"""
function format_bytes(bytes::Number)
    units = ["B", "KB", "MB", "GB", "TB"]
    val = Float64(bytes)
    unit_idx = 1
    while val >= 1024 && unit_idx < length(units)
        val /= 1024
        unit_idx += 1
    end
    return @sprintf("%.1f %s", val, units[unit_idx])
end

"""Format duration in seconds to human readable"""
function format_duration(seconds::Number)
    s = Int(floor(seconds))
    days = s ÷ 86400
    hours = (s % 86400) ÷ 3600
    mins = (s % 3600) ÷ 60
    secs = s % 60

    if days > 0
        return @sprintf("%dd %02dh %02dm", days, hours, mins)
    elseif hours > 0
        return @sprintf("%dh %02dm %02ds", hours, mins, secs)
    else
        return @sprintf("%dm %02ds", mins, secs)
    end
end

"""Format time remaining prediction"""
function format_time_remaining(seconds::Float64)
    seconds == Inf && return "∞"
    seconds < 0 && return "N/A"
    seconds < 60 && return @sprintf("%.0fs", seconds)
    seconds < 3600 && return @sprintf("%.0fm", seconds / 60)
    seconds < 86400 && return @sprintf("%.1fh", seconds / 3600)
    return @sprintf("%.1fd", seconds / 86400)
end
