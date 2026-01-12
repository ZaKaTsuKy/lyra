# OS/Linux/ai/Physical.jl
# ============================
# Physical/Thermal Modeling Module
# ============================
# Builds thermal models from observed data and diagnoses hardware health.
# Detects issues like dry thermal paste, dusty fans, and unstable voltages.

# ============================
# THERMAL MODEL
# ============================

"""
Linear thermal model: Temp = α*CPU_Power + β*Fan_RPM + γ
Coefficients are estimated from observed data using online regression.
"""
mutable struct ThermalModel
    # Model coefficients
    alpha::Float64      # CPU power coefficient (positive)
    beta::Float64       # Fan RPM coefficient (negative - more RPM = cooler)
    gamma::Float64      # Ambient/baseline offset

    # Online regression state (for coefficient updates)
    sample_count::Int
    sum_temp::Float64
    sum_power::Float64
    sum_rpm::Float64
    sum_temp_sq::Float64
    sum_power_temp::Float64
    sum_rpm_temp::Float64

    # Model quality
    r_squared::Float64
    last_prediction::Float64
    last_error::Float64

    # Historical data for calibration
    samples::Vector{Tuple{Float64,Float64,Float64}}  # (Temp, Power, RPM)
    max_samples::Int
end

function ThermalModel(max_samples::Int=100)
    ThermalModel(
        0.05,   # Initial guess: 0.05°C per Watt
        -0.001, # Initial guess: -0.001°C per RPM
        35.0,   # Initial guess: 35°C ambient
        0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        Tuple{Float64,Float64,Float64}[],
        max_samples
    )
end

"""Add a new observation and update model coefficients"""
function update_model!(model::ThermalModel, cpu_temp::Float64, cpu_power::Float64, fan_rpm::Float64)
    # Store sample
    push!(model.samples, (cpu_temp, cpu_power, fan_rpm))
    while length(model.samples) > model.max_samples
        popfirst!(model.samples)
    end

    model.sample_count += 1

    # Update running sums
    model.sum_temp += cpu_temp
    model.sum_power += cpu_power
    model.sum_rpm += fan_rpm
    model.sum_power_temp += cpu_power * cpu_temp
    model.sum_rpm_temp += fan_rpm * cpu_temp

    # Recalculate coefficients periodically
    if model.sample_count % 10 == 0 && length(model.samples) >= 20
        fit_model!(model)
    end

    # Calculate prediction error
    model.last_prediction = predict_temp(model, cpu_power, fan_rpm)
    model.last_error = cpu_temp - model.last_prediction

    return nothing
end

"""Fit the thermal model using least squares on stored samples"""
function fit_model!(model::ThermalModel)
    n = length(model.samples)
    n < 10 && return

    # Simple least squares for: Temp = α*Power + β*RPM + γ
    # Using normal equations

    # Build matrices
    sum_p = sum(s[2] for s in model.samples)
    sum_r = sum(s[3] for s in model.samples)
    sum_t = sum(s[1] for s in model.samples)
    sum_pp = sum(s[2]^2 for s in model.samples)
    sum_rr = sum(s[3]^2 for s in model.samples)
    sum_pr = sum(s[2] * s[3] for s in model.samples)
    sum_pt = sum(s[2] * s[1] for s in model.samples)
    sum_rt = sum(s[3] * s[1] for s in model.samples)

    # Solve 3x3 system (simplified approach)
    # γ ≈ mean(T) - α*mean(P) - β*mean(R)
    mean_t = sum_t / n
    mean_p = sum_p / n
    mean_r = sum_r / n

    # Estimate α from power-temp correlation
    var_p = sum_pp / n - mean_p^2
    cov_pt = sum_pt / n - mean_p * mean_t
    model.alpha = var_p > 0.001 ? cov_pt / var_p : 0.05

    # Estimate β from rpm-temp correlation (after removing power effect)
    var_r = sum_rr / n - mean_r^2
    cov_rt = sum_rt / n - mean_r * mean_t
    model.beta = var_r > 0.001 ? cov_rt / var_r : -0.001

    # Estimate γ
    model.gamma = mean_t - model.alpha * mean_p - model.beta * mean_r

    # Clamp to physical bounds
    model.alpha = clamp(model.alpha, 0.01, 0.5)   # °C per Watt
    model.beta = clamp(model.beta, -0.01, 0.0)    # °C per RPM (negative)
    model.gamma = clamp(model.gamma, 15.0, 50.0)  # Ambient offset

    # Calculate R² (coefficient of determination)
    ss_tot = sum((s[1] - mean_t)^2 for s in model.samples)
    ss_res = sum((s[1] - predict_temp(model, s[2], s[3]))^2 for s in model.samples)
    model.r_squared = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0

    return nothing
end

"""Predict temperature given power and fan RPM"""
function predict_temp(model::ThermalModel, cpu_power::Float64, fan_rpm::Float64)::Float64
    return model.alpha * cpu_power + model.beta * fan_rpm + model.gamma
end

# ============================
# HARDWARE HEALTH DIAGNOSTICS
# ============================

"""Hardware health status"""
@enum FanStatus begin
    FAN_HEALTHY
    FAN_DEGRADED
    FAN_FAILING
    FAN_STOPPED
end

"""Comprehensive hardware health assessment"""
mutable struct HardwareHealth
    thermal_efficiency::Float64    # 0.0 - 1.0 (how well cooling works)
    fan_status::FanStatus
    voltage_stability::Float64     # 0.0 - 1.0 (1.0 = very stable)
    cooling_headroom::Float64      # Degrees before throttle temp

    # Diagnostic flags
    dry_thermal_paste::Bool
    dusty_fan::Bool
    unstable_voltage::Bool

    # Human-readable diagnostics
    diagnostics::Vector{String}
    critical_issues::Vector{String}

    # Timestamps
    last_assessment::Float64
end

HardwareHealth() = HardwareHealth(
    1.0, FAN_HEALTHY, 1.0, 20.0,
    false, false, false,
    String[], String[],
    time()
)

"""
Diagnose hardware health from current metrics.
Returns a HardwareHealth struct with issues detected.
"""
function diagnose_hardware(
    thermal_model::ThermalModel,
    cpu_temp::Float64,
    cpu_power::Float64,
    fan_rpm::Int,
    vcore_voltage::Float64,
    voltage_history::Vector{Float64},
    throttle_temp::Float64=95.0
)::HardwareHealth
    health = HardwareHealth()
    health.last_assessment = time()

    # 1. Assess thermal efficiency
    if thermal_model.sample_count > 50
        predicted = predict_temp(thermal_model, cpu_power, Float64(fan_rpm))

        # If actual temp is much higher than predicted, cooling is degraded
        temp_delta = cpu_temp - predicted
        health.thermal_efficiency = clamp(1.0 - temp_delta / 20.0, 0.0, 1.0)

        # Dry thermal paste detection: temp rises too fast relative to power
        if thermal_model.alpha > 0.2  # More than 0.2°C per Watt is suspicious
            health.dry_thermal_paste = true
            push!(health.diagnostics, "Thermal paste may be degraded (high temp/power ratio)")
        end
    end

    # 2. Fan health assessment
    if fan_rpm == 0
        health.fan_status = FAN_STOPPED
        push!(health.critical_issues, "CPU fan stopped!")
    elseif fan_rpm > 0 && health.thermal_efficiency < 0.5
        # High RPM but poor cooling = dusty fan
        health.fan_status = FAN_DEGRADED
        health.dusty_fan = true
        push!(health.diagnostics, "Fan may be dusty (high RPM but poor cooling)")
    elseif fan_rpm < 300 && cpu_temp > 50
        health.fan_status = FAN_FAILING
        push!(health.diagnostics, "Fan running very slow despite elevated temperature")
    else
        health.fan_status = FAN_HEALTHY
    end

    # 3. Voltage stability
    if length(voltage_history) >= 10
        mean_v = sum(voltage_history) / length(voltage_history)
        variance = sum((v - mean_v)^2 for v in voltage_history) / length(voltage_history)
        std_v = sqrt(variance)

        # Voltage should be very stable (std < 0.02V)
        health.voltage_stability = clamp(1.0 - std_v / 0.1, 0.0, 1.0)

        if std_v > 0.05
            health.unstable_voltage = true
            push!(health.diagnostics, "Vcore voltage unstable (±$(round(std_v * 1000, digits=1))mV)")
        end
    end

    # 4. Cooling headroom
    health.cooling_headroom = throttle_temp - cpu_temp
    if health.cooling_headroom < 10
        push!(health.diagnostics, "Low thermal headroom ($(round(health.cooling_headroom, digits=1))°C to throttle)")
    end
    if health.cooling_headroom < 5
        push!(health.critical_issues, "Critical: Near thermal throttle temperature!")
    end

    return health
end

"""Convert FanStatus enum to string"""
function fan_status_string(status::FanStatus)::String
    return Dict(
        FAN_HEALTHY => "healthy",
        FAN_DEGRADED => "degraded",
        FAN_FAILING => "failing",
        FAN_STOPPED => "stopped"
    )[status]
end

# ============================
# GLOBAL STATE
# ============================

mutable struct PhysicalState
    thermal_model::ThermalModel
    voltage_history::Vector{Float64}
    max_voltage_history::Int
    last_health::HardwareHealth
end

PhysicalState() = PhysicalState(ThermalModel(100), Float64[], 100, HardwareHealth())

const PHYSICAL_STATE = Ref{PhysicalState}()

function get_physical_state()
    isassigned(PHYSICAL_STATE) || (PHYSICAL_STATE[] = PhysicalState())
    PHYSICAL_STATE[]
end

"""Update physical state with new measurements"""
function update_physical_state!(
    cpu_temp::Float64,
    cpu_power::Float64,
    fan_rpm::Int,
    vcore_voltage::Float64
)
    state = get_physical_state()

    # Update thermal model
    update_model!(state.thermal_model, cpu_temp, cpu_power, Float64(fan_rpm))

    # Track voltage history
    push!(state.voltage_history, vcore_voltage)
    while length(state.voltage_history) > state.max_voltage_history
        popfirst!(state.voltage_history)
    end

    # Periodic health assessment (every 30 samples)
    if state.thermal_model.sample_count % 30 == 0
        state.last_health = diagnose_hardware(
            state.thermal_model,
            cpu_temp,
            cpu_power,
            fan_rpm,
            vcore_voltage,
            state.voltage_history
        )
    end

    return nothing
end

"""Get current hardware health"""
get_hardware_health() = get_physical_state().last_health

"""Get thermal model"""
get_thermal_model() = get_physical_state().thermal_model
