# OS/Linux/ai/Simulation.jl
# ============================
# Load Simulation Module
# ============================
# Simulates the impact of hypothetical load scenarios
# on temperature, fan speed, and system noise.

# ============================
# SIMULATION RESULT
# ============================

"""Result of a load simulation"""
struct SimulationResult
    # Simulated values
    estimated_cpu_temp::Float64
    estimated_fan_rpm::Int
    estimated_noise_db::Float64    # Based on RPM curves

    # Headroom calculations
    thermal_headroom::Float64      # Degrees until throttle
    time_to_throttle_sec::Float64  # Estimated time before throttling

    # Sustainability assessment
    sustainable::Bool              # Can the system handle this load?
    warnings::Vector{String}
end

# ============================
# NOISE ESTIMATION
# ============================

"""
Estimate noise level (dB) from fan RPM.
Based on typical aftermarket cooler curves.
"""
function estimate_noise_db(fan_rpm::Int)::Float64
    # Typical curve:
    # < 500 RPM: ~20 dB (nearly silent)
    # 1000 RPM: ~25 dB
    # 2000 RPM: ~35 dB
    # 3000 RPM: ~45 dB
    # > 4000 RPM: ~55+ dB

    fan_rpm <= 0 && return 0.0

    # Logarithmic relationship between RPM and noise
    base_noise = 15.0
    rpm_factor = log10(max(fan_rpm, 100)) * 12.0

    return clamp(base_noise + rpm_factor, 15.0, 60.0)
end

# ============================
# FAN CURVE ESTIMATION
# ============================

"""
Estimate fan RPM for a given temperature.
Uses observed data to infer the fan curve.
"""
function estimate_fan_rpm(temp::Float64, thermal_model::ThermalModel)::Int
    # Use inverse of thermal model relationship
    # Higher temp -> higher RPM needed

    # Base RPM at idle temp (35°C)
    base_rpm = 800

    # RPM increase per degree above base
    rpm_per_degree = 100

    temp_delta = max(0, temp - 35.0)
    estimated_rpm = base_rpm + round(Int, temp_delta * rpm_per_degree)

    # Clamp to reasonable range
    return clamp(estimated_rpm, 0, 5000)
end

# ============================
# SIMULATION FUNCTIONS
# ============================

"""
Simulate the impact of a hypothetical CPU load.

Parameters:
- monitor: Current SystemMonitor state
- target_cpu_load: Target CPU load percentage (0-100)
- duration_sec: How long the load would run

Returns: SimulationResult with predictions
"""
function simulate_load(
    monitor,
    target_cpu_load::Float64,
    duration_sec::Float64=60.0
)::SimulationResult
    thermal_model = get_thermal_model()

    warnings = String[]

    # Current state
    current_temp = monitor.cpu_info.temperature.package
    current_power = estimate_cpu_power(monitor)
    current_rpm = monitor.hardware !== nothing ? monitor.hardware.primary_cpu_fan_rpm : 1500

    # Estimate power at target load
    # Assume power scales roughly with load^1.5 (due to voltage scaling)
    current_load = get_cpu_usage(monitor)
    load_ratio = target_cpu_load / max(current_load, 1.0)
    estimated_power = current_power * (load_ratio^1.2)

    # Cap at TDP (estimated from max observed power or 125W default)
    max_tdp = 125.0  # Default TDP
    estimated_power = min(estimated_power, max_tdp)

    # Predict steady-state temperature
    # Use thermal model if calibrated, otherwise estimate
    if thermal_model.sample_count > 50
        # Estimate what fan RPM would be at this temp (iterative)
        estimated_temp = current_temp
        for _ in 1:5  # Iterate to find equilibrium
            estimated_rpm = estimate_fan_rpm(estimated_temp, thermal_model)
            estimated_temp = predict_temp(thermal_model, estimated_power, Float64(estimated_rpm))
        end
        estimated_fan_rpm = estimate_fan_rpm(estimated_temp, thermal_model)
    else
        # Simple estimation without model
        temp_increase = (estimated_power - current_power) * 0.3  # ~0.3°C per Watt
        estimated_temp = current_temp + temp_increase
        estimated_fan_rpm = estimate_fan_rpm(estimated_temp, thermal_model)
    end

    # Calculate headroom
    throttle_temp = 95.0
    thermal_headroom = throttle_temp - estimated_temp

    # Estimate time to throttle
    if thermal_headroom <= 0
        time_to_throttle = 0.0
        push!(warnings, "Load would cause immediate thermal throttling!")
    elseif thermal_model.alpha > 0
        # Rough estimate based on thermal inertia
        # Assume ~30 second thermal time constant
        thermal_time_constant = 30.0
        temp_rise_needed = throttle_temp - current_temp
        rate = (estimated_temp - current_temp) / thermal_time_constant
        time_to_throttle = rate > 0 ? temp_rise_needed / rate : Inf
    else
        time_to_throttle = Inf
    end

    # Estimate noise
    estimated_noise = estimate_noise_db(estimated_fan_rpm)
    if estimated_noise > 45
        push!(warnings, "Expected noise level: $(round(estimated_noise, digits=1)) dB (loud)")
    end

    # Sustainability check
    sustainable = thermal_headroom > 5 && time_to_throttle > duration_sec
    if !sustainable && time_to_throttle <= duration_sec
        push!(warnings, "Load would cause throttling in ~$(round(time_to_throttle, digits=0)) seconds")
    end

    # Additional warnings
    if estimated_fan_rpm > 4000
        push!(warnings, "Fan would run at very high speed ($(estimated_fan_rpm) RPM)")
    end
    if thermal_headroom < 10
        push!(warnings, "Low thermal headroom ($(round(thermal_headroom, digits=1))°C)")
    end

    return SimulationResult(
        estimated_temp,
        estimated_fan_rpm,
        estimated_noise,
        thermal_headroom,
        time_to_throttle,
        sustainable,
        warnings
    )
end

"""Estimate CPU power consumption from current metrics"""
function estimate_cpu_power(monitor)::Float64
    # If we have GPU power info, we might infer CPU power
    # Otherwise, estimate from load

    cpu_load = get_cpu_usage(monitor)
    core_count = max(1, length(monitor.cores))

    # Estimate: ~5W idle per chip + ~5W per core at 100%
    idle_power = 10.0
    load_power = core_count * 5.0 * (cpu_load / 100.0)

    return idle_power + load_power
end

# ============================
# CONVENIENCE FUNCTIONS
# ============================

"""Quick simulation for "what if CPU goes to 100%?"""
function simulate_full_load(monitor)::SimulationResult
    return simulate_load(monitor, 100.0, 300.0)  # 5 minutes
end

"""Simulate a gaming-like mixed load"""
function simulate_gaming_load(monitor)::SimulationResult
    return simulate_load(monitor, 60.0, 3600.0)  # 1 hour at 60% CPU
end

"""Get a summary string for simulation result"""
function simulation_summary(result::SimulationResult)::String
    summary = "Temp: $(round(result.estimated_cpu_temp, digits=1))°C, " *
              "Fan: $(result.estimated_fan_rpm) RPM, " *
              "Noise: $(round(result.estimated_noise_db, digits=1)) dB"

    if !result.sustainable
        summary *= " [NOT SUSTAINABLE]"
    end

    return summary
end
