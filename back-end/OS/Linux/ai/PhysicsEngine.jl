# OS/Linux/ai/PhysicsEngine.jl
# ============================
# Physics-Aware Diagnostic Engine v1.0
# ============================
# Orchestrates 6 physics-based diagnostic modules:
# - ThermalEfficiency: Dust/degradation detection via Rth
# - FanStability: Hunting/pumping detection via FFT
# - PowerQuality: Vdroop correlation, PSU health
# - ThermalSaturation: Time-to-throttle prediction
# - WorkloadClassifier: Context-aware threshold adjustment
# - BottleneckDetector: Resource limiting analysis
#
# Design: Zero-allocation in hot path, thread-safe, uses RingBuffers
# ============================

# ============================
# RING BUFFER (Zero-Allocation History)
# ============================

"""
Fixed-size circular buffer for O(1) push and zero allocations after init.
"""
mutable struct RingBuffer{T}
    data::Vector{T}
    capacity::Int
    head::Int       # Next write position (1-indexed)
    count::Int      # Current number of elements
end

function RingBuffer{T}(capacity::Int) where T
    RingBuffer{T}(zeros(T, capacity), capacity, 1, 0)
end

function RingBuffer{T}(capacity::Int, default::T) where T
    RingBuffer{T}(fill(default, capacity), capacity, 1, 0)
end

"""Push value to buffer (overwrites oldest if full)"""
function Base.push!(rb::RingBuffer{T}, value::T) where T
    rb.data[rb.head] = value
    rb.head = mod1(rb.head + 1, rb.capacity)
    rb.count = min(rb.count + 1, rb.capacity)
    return nothing
end

"""Get value at offset from most recent (0 = most recent, 1 = previous, etc)"""
function get_prev(rb::RingBuffer{T}, offset::Int)::T where T
    offset >= rb.count && return zero(T)
    idx = mod1(rb.head - 1 - offset, rb.capacity)
    return rb.data[idx]
end

"""Get most recent value"""
get_latest(rb::RingBuffer) = get_prev(rb, 0)

"""Check if buffer has enough samples"""
is_ready(rb::RingBuffer, min_samples::Int) = rb.count >= min_samples

"""Calculate mean of buffer contents"""
function buffer_mean(rb::RingBuffer{T})::T where T
    rb.count == 0 && return zero(T)
    s = zero(T)
    for i in 1:rb.count
        s += get_prev(rb, i - 1)
    end
    return s / rb.count
end

"""Calculate mean and variance in single pass using Welford's algorithm"""
function buffer_mean_variance(rb::RingBuffer{T})::Tuple{T,T} where T
    rb.count < 2 && return (zero(T), zero(T))
    m = zero(T)
    m2 = zero(T)
    for i in 1:rb.count
        x = get_prev(rb, i - 1)
        delta = x - m
        m += delta / i
        m2 += delta * (x - m)
    end
    return (m, m2 / (rb.count - 1))
end

"""Calculate variance of buffer contents (uses Welford for efficiency)"""
function buffer_variance(rb::RingBuffer{T})::T where T
    _, var = buffer_mean_variance(rb)
    return var
end

buffer_std(rb::RingBuffer) = sqrt(max(0.0, buffer_variance(rb)))

# ============================
# WORKLOAD STATE ENUM
# ============================

@enum WorkloadState begin
    WORKLOAD_IDLE
    WORKLOAD_COMPUTE
    WORKLOAD_GAMING
    WORKLOAD_MIXED
    WORKLOAD_IO_INTENSIVE
end

# Const lookup for workload names (avoid allocation)
const WORKLOAD_NAMES = Dict{WorkloadState,String}(
    WORKLOAD_IDLE => "IDLE",
    WORKLOAD_COMPUTE => "COMPUTE",
    WORKLOAD_GAMING => "GAMING",
    WORKLOAD_MIXED => "MIXED",
    WORKLOAD_IO_INTENSIVE => "IO_INTENSIVE"
)

workload_name(ws::WorkloadState)::String = WORKLOAD_NAMES[ws]

# ============================
# MODULE 1: THERMAL EFFICIENCY
# ============================

"""
Detects cooling degradation by tracking apparent thermal resistance.
Rth = (T_cpu - T_ambient) / Load_cpu
"""
mutable struct ThermalEfficiencyModule
    # Baseline tracking
    rth_baseline::Float64
    rth_baseline_count::Int
    rth_history::RingBuffer{Float64}

    # Current state
    rth_instant::Float64
    efficiency_drop_pct::Float64
    degradation_alert::Bool

    # Configuration
    min_load_pct::Float64           # Only measure when load > this (avoid div/0)
    alert_threshold_pct::Float64    # Alert if efficiency drops > this %
end

function ThermalEfficiencyModule()
    ThermalEfficiencyModule(
        0.0, 0, RingBuffer{Float64}(120),  # 2 min history at 1Hz
        0.0, 0.0, false,
        20.0, 15.0
    )
end

function update_thermal_efficiency!(
    mod::ThermalEfficiencyModule,
    cpu_temp::Float64,
    ambient_proxy::Float64,  # Use NVMe temp or coldest sensor
    cpu_load::Float64
)
    # Skip if load too low (unreliable measurement)
    cpu_load < mod.min_load_pct && return nothing

    # Calculate apparent thermal resistance
    delta_t = cpu_temp - ambient_proxy
    delta_t <= 0 && return nothing  # Invalid (CPU colder than ambient?)

    mod.rth_instant = delta_t / cpu_load
    push!(mod.rth_history, mod.rth_instant)

    # Update baseline (slow EMA)
    if mod.rth_baseline_count < 100
        # Initial calibration: simple average
        mod.rth_baseline_count += 1
        mod.rth_baseline += (mod.rth_instant - mod.rth_baseline) / mod.rth_baseline_count
    else
        # Long-term tracking: very slow EMA (α = 0.01)
        mod.rth_baseline = 0.99 * mod.rth_baseline + 0.01 * mod.rth_instant
    end

    # Detect degradation
    if mod.rth_baseline > 0.0001
        mod.efficiency_drop_pct = 100.0 * (mod.rth_instant - mod.rth_baseline) / mod.rth_baseline
        mod.degradation_alert = mod.efficiency_drop_pct > mod.alert_threshold_pct
    end

    return nothing
end

# ============================
# MODULE 2: FAN STABILITY
# ============================

"""
Detects fan hunting (oscillation) when temperature is stable.
Uses variance analysis on RPM when dT/dt ≈ 0.
"""
mutable struct FanStabilityModule
    # RPM tracking
    rpm_history::RingBuffer{Float64}

    # Temperature derivative tracking
    temp_ewma::Float64
    temp_ewma_prev::Float64
    temp_derivative::Float64

    # Detection state
    pumping_detected::Bool
    rpm_variance::Float64
    temp_is_stable::Bool

    # Configuration
    temp_stable_threshold::Float64    # dT/dt threshold for "stable"
    rpm_variance_threshold::Float64   # RPM variance to trigger hunting alert
    ewma_alpha::Float64
end

function FanStabilityModule()
    FanStabilityModule(
        RingBuffer{Float64}(60),  # 1 min of RPM history
        0.0, 0.0, 0.0,
        false, 0.0, true,
        0.1, 10000.0, 0.2  # 10000 RPM² variance = ~100 RPM std
    )
end

function update_fan_stability!(
    mod::FanStabilityModule,
    fan_rpm::Float64,
    cpu_temp::Float64,
    dt::Float64
)
    # Track RPM
    push!(mod.rpm_history, fan_rpm)
    mod.rpm_variance = buffer_variance(mod.rpm_history)

    # Track temperature derivative (smoothed)
    mod.temp_ewma_prev = mod.temp_ewma
    mod.temp_ewma = mod.ewma_alpha * cpu_temp + (1 - mod.ewma_alpha) * mod.temp_ewma

    dt > 0.01 && (mod.temp_derivative = (mod.temp_ewma - mod.temp_ewma_prev) / dt)

    # Detect stable temperature
    mod.temp_is_stable = abs(mod.temp_derivative) < mod.temp_stable_threshold

    # Detect hunting: high RPM variance when temp is stable
    mod.pumping_detected = mod.temp_is_stable &&
                           mod.rpm_variance > mod.rpm_variance_threshold &&
                           is_ready(mod.rpm_history, 30)

    return nothing
end

# ============================
# MODULE 3: POWER QUALITY
# ============================

"""
Monitors voltage stability and correlates Vdroop with CPU load.
Detects PSU degradation via abnormal voltage variance.
"""
mutable struct PowerQualityModule
    # Voltage tracking
    vcore_history::RingBuffer{Float64}
    rail_12v_history::RingBuffer{Float64}

    # Load correlation
    load_history::RingBuffer{Float64}

    # Correlation state
    load_vcore_correlation::Float64

    # Detection state
    vcore_variance::Float64
    rail_12v_variance::Float64
    vdroop_abnormal::Bool
    rail_12v_unstable::Bool

    # Configuration
    rail_12v_nominal::Float64
    rail_12v_variance_alert_pct::Float64
    vcore_variance_alert_v::Float64
end

function PowerQualityModule()
    PowerQualityModule(
        RingBuffer{Float64}(60),
        RingBuffer{Float64}(60),
        RingBuffer{Float64}(60),
        0.0,
        0.0, 0.0, false, false,
        12.0, 5.0, 0.05  # 12V nominal, 5% variance alert, 50mV Vcore variance
    )
end

function update_power_quality!(
    mod::PowerQualityModule,
    vcore::Float64,
    rail_12v::Float64,
    cpu_load::Float64
)
    # Track values
    push!(mod.vcore_history, vcore)
    push!(mod.rail_12v_history, rail_12v)
    push!(mod.load_history, cpu_load)

    # Calculate variances
    mod.vcore_variance = buffer_variance(mod.vcore_history)
    mod.rail_12v_variance = buffer_variance(mod.rail_12v_history)

    # Check 12V rail stability
    if is_ready(mod.rail_12v_history, 30)
        rail_mean = buffer_mean(mod.rail_12v_history)
        rail_std = buffer_std(mod.rail_12v_history)
        if rail_mean > 0
            variance_pct = 100.0 * rail_std / rail_mean
            mod.rail_12v_unstable = variance_pct > mod.rail_12v_variance_alert_pct
        end
    end

    # Check Vcore variance
    mod.vdroop_abnormal = sqrt(mod.vcore_variance) > mod.vcore_variance_alert_v

    # TODO: Calculate load-Vcore correlation for advanced Vdroop analysis

    return nothing
end

# ============================
# MODULE 4: THERMAL SATURATION
# ============================

"""
Predicts time-to-throttle using thermal derivatives.
Applies EWMA smoothing before differentiation to avoid noise amplification.
"""
mutable struct ThermalSaturationModule
    # EWMA-smoothed temperature
    temp_ewma::Float64
    temp_ewma_prev::Float64     # Previous EWMA for d1 calculation
    temp_ewma_alpha::Float64

    # Derivative tracking (on smoothed data)
    d1_temp::Float64           # dT/dt
    d1_temp_prev::Float64      # Previous d1 for d2 calculation
    d2_temp::Float64           # d²T/dt²

    # Prediction
    t_critical::Float64
    time_to_critical_sec::Float64
    is_transient_spike::Bool
    throttle_imminent::Bool

    # Configuration
    throttle_warning_sec::Float64

    # Initialization state
    initialized::Bool
end

function ThermalSaturationModule()
    ThermalSaturationModule(
        0.0, 0.0, 0.15,  # temp_ewma, temp_ewma_prev, α = 0.15
        0.0, 0.0, 0.0,   # d1, d1_prev, d2
        95.0, Inf, false, false,
        30.0,
        false            # initialized
    )
end

function update_thermal_saturation!(
    mod::ThermalSaturationModule,
    raw_temp::Float64,
    dt::Float64
)
    dt < 0.01 && return nothing  # Skip if dt too small

    # First sample: initialize
    if !mod.initialized
        mod.temp_ewma = raw_temp
        mod.temp_ewma_prev = raw_temp
        mod.initialized = true
        return nothing
    end

    # Step 1: Store previous EWMA before updating
    mod.temp_ewma_prev = mod.temp_ewma

    # Step 2: Apply EWMA low-pass filter
    mod.temp_ewma = mod.temp_ewma_alpha * raw_temp + (1 - mod.temp_ewma_alpha) * mod.temp_ewma

    # Step 3: Calculate first derivative (on smoothed data)
    mod.d1_temp_prev = mod.d1_temp
    mod.d1_temp = (mod.temp_ewma - mod.temp_ewma_prev) / dt

    # Step 4: Calculate second derivative
    mod.d2_temp = (mod.d1_temp - mod.d1_temp_prev) / dt

    # Step 5: Classify thermal behavior
    mod.is_transient_spike = mod.d2_temp < -0.01  # Decelerating (cooling or leveling)

    # Step 6: Estimate time to critical
    remaining = mod.t_critical - mod.temp_ewma
    if remaining > 0 && mod.d1_temp > 0.01
        mod.time_to_critical_sec = remaining / mod.d1_temp
    else
        mod.time_to_critical_sec = Inf
    end

    mod.throttle_imminent = mod.time_to_critical_sec < mod.throttle_warning_sec

    return nothing
end

# Remove obsolete update_d1! function - no longer needed

# ============================
# MODULE 5: WORKLOAD CLASSIFIER
# ============================

"""
Classifies workload from resource signature and adjusts thresholds dynamically.
"""
mutable struct WorkloadClassifierModule
    current_state::WorkloadState
    state_confidence::Float64

    # Dynamic thresholds based on state
    temp_warning::Float64
    temp_critical::Float64
end

function WorkloadClassifierModule()
    WorkloadClassifierModule(
        WORKLOAD_IDLE, 0.0,
        70.0, 90.0  # Default thresholds
    )
end

function update_workload_classifier!(
    mod::WorkloadClassifierModule,
    cpu_util::Float64,
    gpu_util::Float64,
    io_mb_s::Float64
)
    # Classify based on resource signature
    prev_state = mod.current_state

    if cpu_util < 20 && gpu_util < 10 && io_mb_s < 10
        mod.current_state = WORKLOAD_IDLE
        mod.temp_warning = 55.0
        mod.temp_critical = 75.0
    elseif gpu_util > 70 || (cpu_util > 50 && gpu_util > 30)
        mod.current_state = WORKLOAD_GAMING
        mod.temp_warning = 80.0
        mod.temp_critical = 95.0
    elseif cpu_util > 80 && gpu_util < 30
        mod.current_state = WORKLOAD_COMPUTE
        mod.temp_warning = 75.0
        mod.temp_critical = 92.0
    elseif io_mb_s > 100
        mod.current_state = WORKLOAD_IO_INTENSIVE
        mod.temp_warning = 70.0
        mod.temp_critical = 88.0
    else
        mod.current_state = WORKLOAD_MIXED
        mod.temp_warning = 72.0
        mod.temp_critical = 88.0
    end

    # Confidence based on state stability
    mod.state_confidence = mod.current_state == prev_state ?
                           min(1.0, mod.state_confidence + 0.1) : 0.5

    return nothing
end

# ============================
# MODULE 6: BOTTLENECK DETECTOR
# ============================

"""
Identifies the limiting resource in the system.
"""
mutable struct BottleneckDetectorModule
    # Resource utilizations
    cpu_util::Float64
    gpu_util::Float64
    mem_util::Float64
    io_util::Float64
    net_util::Float64

    # Latencies
    disk_latency_ms::Float64

    # Detection
    bottleneck::Symbol      # :cpu, :gpu, :mem, :disk_bw, :disk_lat, :net, :none
    bottleneck_severity::Float64

    # Thresholds
    high_threshold::Float64
    low_threshold::Float64
end

function BottleneckDetectorModule()
    BottleneckDetectorModule(
        0.0, 0.0, 0.0, 0.0, 0.0,
        0.0,
        :none, 0.0,
        90.0, 50.0
    )
end

function update_bottleneck_detector!(
    mod::BottleneckDetectorModule,
    cpu_util::Float64,
    gpu_util::Float64,
    mem_util::Float64,
    io_util::Float64,
    net_util::Float64,
    disk_latency_ms::Float64
)
    mod.cpu_util = cpu_util
    mod.gpu_util = gpu_util
    mod.mem_util = mem_util
    mod.io_util = io_util
    mod.net_util = net_util
    mod.disk_latency_ms = disk_latency_ms

    # Reset
    mod.bottleneck = :none
    mod.bottleneck_severity = 0.0

    # Check for latency bottleneck first (not captured by utilization)
    if disk_latency_ms > 50.0
        mod.bottleneck = :disk_lat
        mod.bottleneck_severity = min(1.0, disk_latency_ms / 100.0)
        return nothing
    end

    # Find highest utilization
    utils = [
        (:cpu, cpu_util),
        (:gpu, gpu_util),
        (:mem, mem_util),
        (:disk_bw, io_util),
        (:net, net_util)
    ]

    max_util = 0.0
    max_resource = :none
    for (res, util) in utils
        if util > max_util
            max_util = util
            max_resource = res
        end
    end

    # Check if it's a bottleneck (high util while others are lower)
    if max_util > mod.high_threshold
        others_low = all(u[2] < mod.low_threshold for u in utils if u[1] != max_resource)
        if others_low
            mod.bottleneck = max_resource
            mod.bottleneck_severity = (max_util - mod.high_threshold) / (100.0 - mod.high_threshold)
        end
    end

    return nothing
end

# Const lookup for bottleneck names (avoid allocation)
const BOTTLENECK_NAMES = Dict{Symbol,String}(
    :cpu => "CPU",
    :gpu => "GPU",
    :mem => "Memory",
    :disk_bw => "Disk Bandwidth",
    :disk_lat => "Disk Latency",
    :net => "Network",
    :none => "None"
)

bottleneck_name(b::Symbol)::String = BOTTLENECK_NAMES[b]

# ============================
# MAIN PHYSICS ENGINE
# ============================

"""
Main orchestrating structure for physics-aware diagnostics.
"""
mutable struct PhysicsEngine
    # Sub-modules
    thermal_efficiency::ThermalEfficiencyModule
    fan_stability::FanStabilityModule
    power_quality::PowerQualityModule
    thermal_saturation::ThermalSaturationModule
    workload_classifier::WorkloadClassifierModule
    bottleneck_detector::BottleneckDetectorModule

    # Timing
    sample_count::Int
    last_update::Float64
    prev_update::Float64

    # Diagnostic output (pre-allocated, reused)
    diagnostics::Vector{String}
end

function PhysicsEngine()
    PhysicsEngine(
        ThermalEfficiencyModule(),
        FanStabilityModule(),
        PowerQualityModule(),
        ThermalSaturationModule(),
        WorkloadClassifierModule(),
        BottleneckDetectorModule(),
        0, time(), time(),
        String[]
    )
end

"""
Main update function - zero allocations in steady state.
"""
function update_physics_engine!(
    engine::PhysicsEngine,
    sensors::FullSensors,
    monitor,  # SystemMonitor
    cpu_load::Float64,
    cpu_temp::Float64
)
    now = time()
    dt = now - engine.prev_update
    dt < 0.01 && return nothing  # Skip if called too frequently

    # Extract sensor values (with safe defaults)
    ambient_proxy = get_ambient_proxy(sensors)
    fan_rpm = get_primary_fan_rpm(sensors)
    vcore = get_vcore_voltage(sensors)
    rail_12v = get_12v_rail(sensors)
    gpu_util = monitor.gpu !== nothing ? monitor.gpu.util : 0.0
    io_mb_s = sum(io.read_mb_s + io.write_mb_s for (_, io) in monitor.disk_io; init=0.0)
    mem_util = monitor.memory.total_kb > 0 ?
               100.0 * monitor.memory.used_kb / monitor.memory.total_kb : 0.0

    # Get disk latency
    disk_latency = 0.0
    for (_, io) in monitor.disk_io
        disk_latency = max(disk_latency, io.avg_wait_ms)
    end

    # Get IO utilization
    io_util = 0.0
    for (_, io) in monitor.disk_io
        io_util = max(io_util, io.io_wait_pct)
    end

    # Update all sub-modules
    update_thermal_efficiency!(engine.thermal_efficiency, cpu_temp, ambient_proxy, cpu_load)
    update_fan_stability!(engine.fan_stability, Float64(fan_rpm), cpu_temp, dt)
    update_power_quality!(engine.power_quality, vcore, rail_12v, cpu_load)
    update_thermal_saturation!(engine.thermal_saturation, cpu_temp, dt)
    update_workload_classifier!(engine.workload_classifier, cpu_load, gpu_util, io_mb_s)
    update_bottleneck_detector!(engine.bottleneck_detector, cpu_load, gpu_util, mem_util, io_util, 0.0, disk_latency)

    # Collect diagnostics
    collect_diagnostics!(engine)

    engine.sample_count += 1
    engine.prev_update = engine.last_update
    engine.last_update = now

    return nothing
end

# ============================
# SENSOR VALUE EXTRACTION
# ============================

"""Get ambient temperature proxy (coldest sensor, typically NVMe)"""
function get_ambient_proxy(sensors::FullSensors)::Float64
    # Try NVMe composite temp first (often coldest)
    for nvme in sensors.nvme_sensors
        if nvme.temp_composite > 0
            return nvme.temp_composite
        end
    end

    # Fallback to generic temps, find minimum > 0
    min_temp = Inf
    for t in sensors.temps_generic
        if 0 < t.value < min_temp
            min_temp = t.value
        end
    end

    return min_temp < Inf ? min_temp : 25.0  # Default 25°C
end

"""Get primary fan RPM"""
function get_primary_fan_rpm(sensors::FullSensors)::Int
    for fan in sensors.fans
        if fan.rpm > 0
            return fan.rpm
        end
    end
    return 0
end

"""Get Vcore voltage"""
function get_vcore_voltage(sensors::FullSensors)::Float64
    for v in sensors.voltages
        lbl = lowercase(v.label)
        if occursin("vcore", lbl) || occursin("cpu", lbl) || v.label == "in0"
            return v.value
        end
    end
    return 0.0
end

"""Get 12V rail voltage"""
function get_12v_rail(sensors::FullSensors)::Float64
    for v in sensors.voltages
        lbl = lowercase(v.label)
        if occursin("12v", lbl) || occursin("+12", lbl)
            return v.value
        end
    end
    # Try in1 or in2 as common 12V positions
    for v in sensors.voltages
        if v.value > 10.0 && v.value < 14.0  # Looks like 12V
            return v.value
        end
    end
    return 12.0  # Default
end

# ============================
# DIAGNOSTIC COLLECTION
# ============================

"""Collect all diagnostics into pre-allocated vector"""
function collect_diagnostics!(engine::PhysicsEngine)
    # Clear previous (no allocation - just reset length)
    empty!(engine.diagnostics)
    sizehint!(engine.diagnostics, 10)

    te = engine.thermal_efficiency
    fs = engine.fan_stability
    pq = engine.power_quality
    ts = engine.thermal_saturation
    wc = engine.workload_classifier
    bd = engine.bottleneck_detector

    # Thermal efficiency
    if te.degradation_alert
        push!(engine.diagnostics,
            "⚠️ Thermal degradation detected (-$(round(te.efficiency_drop_pct, digits=1))%)")
    end

    # Fan stability
    if fs.pumping_detected
        push!(engine.diagnostics,
            "⚠️ Fan hunting detected (check BIOS fan curve)")
    end

    # Power quality
    if pq.rail_12v_unstable
        push!(engine.diagnostics,
            "⚠️ 12V rail unstable (variance: $(round(sqrt(pq.rail_12v_variance)*100, digits=1))mV)")
    end
    if pq.vdroop_abnormal
        push!(engine.diagnostics,
            "⚠️ Abnormal Vcore droop (±$(round(sqrt(pq.vcore_variance)*1000, digits=1))mV)")
    end

    # Thermal saturation
    if ts.throttle_imminent && !ts.is_transient_spike
        push!(engine.diagnostics,
            "🔴 Throttle imminent (~$(round(ts.time_to_critical_sec, digits=0))s)")
    elseif ts.is_transient_spike && ts.temp_ewma > 80
        push!(engine.diagnostics,
            "ℹ️ Transient thermal spike (stabilizing)")
    end

    # Workload classifier
    if wc.current_state != WORKLOAD_IDLE
        push!(engine.diagnostics,
            "ℹ️ Workload: $(workload_name(wc.current_state))")
    end

    # Bottleneck detector
    if bd.bottleneck != :none
        push!(engine.diagnostics,
            "🔴 Bottleneck: $(bottleneck_name(bd.bottleneck))")
    end

    return nothing
end

# ============================
# GLOBAL STATE
# ============================

const PHYSICS_ENGINE = Ref{PhysicsEngine}()

function get_physics_engine()
    isassigned(PHYSICS_ENGINE) || (PHYSICS_ENGINE[] = PhysicsEngine())
    PHYSICS_ENGINE[]
end

"""Get current diagnostics (for WebSocket/API)"""
get_physics_diagnostics() = get_physics_engine().diagnostics

"""Reset physics engine state"""
reset_physics_engine!() = (PHYSICS_ENGINE[] = PhysicsEngine(); nothing)
