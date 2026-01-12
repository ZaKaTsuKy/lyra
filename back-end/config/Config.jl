# Config.jl
# ============================
# OMNI MONITOR - Centralized Configuration
# ============================
# All configuration loaded from ENV with sensible defaults
# 
# Usage:
#   set OMNI_WEBSOCKET_PORT=3000 before running
#   or use a .env file with dotenv
# ============================

# ============================
# ENV HELPER
# ============================

"""
Get environment variable with type conversion and default.
Supports: Int, Float64, Bool, String, Vector{String}
"""
function env_get(key::String, default::T)::T where T
    val = get(ENV, key, nothing)
    val === nothing && return default

    try
        if T == Bool
            return lowercase(val) in ("true", "1", "yes", "on")
        elseif T == Int
            return parse(Int, val)
        elseif T == Float64
            return parse(Float64, val)
        elseif T == String
            return val
        elseif T <: Vector{String}
            return String.(strip.(split(val, ",")))
        else
            return default
        end
    catch
        @warn "Failed to parse ENV[$key]=$val as $(T), using default"
        return default
    end
end

# Convenience for nothing-able Int
function env_get_optional_int(key::String, default::Union{Nothing,Int})::Union{Nothing,Int}
    val = get(ENV, key, nothing)
    val === nothing && return default
    val == "" && return nothing
    try
        return parse(Int, val)
    catch
        return default
    end
end

# ============================
# APPLICATION CONFIG (main.jl)
# ============================

const APP_CONFIG = (
    refresh_interval=env_get("OMNI_REFRESH_INTERVAL", 1.0),
    enable_gpu=env_get("OMNI_ENABLE_GPU", true),
    enable_battery=env_get("OMNI_ENABLE_BATTERY", true),
    enable_processes=env_get("OMNI_ENABLE_PROCESSES", true),
    max_iterations=env_get_optional_int("OMNI_MAX_ITERATIONS", nothing),
)

# ============================
# SERVER CONFIG (WebSocketServer.jl)
# ============================

const SERVER_CONFIG = (
    # Network
    port=env_get("OMNI_WEBSOCKET_PORT", 8080),
    host=env_get("OMNI_WEBSOCKET_HOST", "0.0.0.0"),

    # Client limits
    max_clients=env_get("OMNI_MAX_CLIENTS", 50),

    # Timeouts
    send_timeout_sec=env_get("OMNI_SEND_TIMEOUT_SEC", 5.0),

    # Security
    max_message_size=env_get("OMNI_MAX_MESSAGE_SIZE", 1024),
    rate_limit_window_sec=env_get("OMNI_RATE_LIMIT_WINDOW_SEC", 1.0),
    rate_limit_max_messages=env_get("OMNI_RATE_LIMIT_MAX_MESSAGES", 10),

    # CORS
    # ⚠️ SECURITY: Change from ["*"] to specific origins in production!
    # Example: ["http://localhost:3000", "https://yourdomain.com"]
    allowed_origins=env_get("OMNI_CORS_ORIGINS", ["*"]),
)

# ============================
# AI CONFIG (AI.jl)
# ============================

const AI_CONFIG = (
    # Thresholds
    cpu_critical=env_get("OMNI_AI_CPU_CRITICAL", 95.0),
    mem_critical=env_get("OMNI_AI_MEM_CRITICAL", 95.0),
    temp_critical=env_get("OMNI_AI_TEMP_CRITICAL", 95.0),

    # Z-Score thresholds
    zscore_warning=env_get("OMNI_AI_ZSCORE_WARNING", 2.5),
    zscore_critical=env_get("OMNI_AI_ZSCORE_CRITICAL", 3.5),

    # CUSUM parameters
    cusum_threshold=env_get("OMNI_AI_CUSUM_THRESHOLD", 5.0),
    cusum_drift=env_get("OMNI_AI_CUSUM_DRIFT", 0.5),

    # ADWIN parameters
    adwin_delta=env_get("OMNI_AI_ADWIN_DELTA", 0.002),
    adwin_min_window=env_get("OMNI_AI_ADWIN_MIN_WINDOW", 30),

    # Holt-Winters parameters
    hw_alpha=env_get("OMNI_AI_HW_ALPHA", 0.3),
    hw_beta=env_get("OMNI_AI_HW_BETA", 0.1),
    hw_gamma=env_get("OMNI_AI_HW_GAMMA", 0.1),
    hw_season_length=env_get("OMNI_AI_HW_SEASON_LENGTH", 60),

    # Sampling
    sample_rate_min=env_get("OMNI_AI_SAMPLE_RATE_MIN", 0.5),
    sample_rate_max=env_get("OMNI_AI_SAMPLE_RATE_MAX", 5.0),
    volatility_threshold=env_get("OMNI_AI_VOLATILITY_THRESHOLD", 0.1),

    # Saturation model
    saturation_knee_ratio=env_get("OMNI_AI_SATURATION_KNEE_RATIO", 0.8),

    # Correlations
    cpu_temp_correlation_min=env_get("OMNI_AI_CPU_TEMP_CORR_MIN", 0.5),
    io_latency_correlation_min=env_get("OMNI_AI_IO_LATENCY_CORR_MIN", 0.6),

    # Predictions
    prediction_confidence_min=env_get("OMNI_AI_PRED_CONFIDENCE_MIN", 0.6),
    min_samples_for_prediction=env_get("OMNI_AI_MIN_SAMPLES_PRED", 30),
)

# ============================
# COLLECTOR CONFIG (MonitorTypes, Processes, GPU)
# ============================

const COLLECTOR_CONFIG = (
    history_length=env_get("OMNI_HISTORY_LENGTH", 120),
    max_processes=env_get("OMNI_MAX_PROCESSES", 15),
    gpu_history_len=env_get("OMNI_GPU_HISTORY_LEN", 10),
)

# ============================
# PHYSICS ENGINE CONFIG
# ============================

const PHYSICS_CONFIG = (
    # ThermalEfficiency
    thermal_efficiency_alert_pct=env_get("OMNI_THERMAL_EFF_ALERT_PCT", 15.0),
    min_cpu_load_for_rth=env_get("OMNI_MIN_CPU_LOAD_RTH", 20.0),

    # FanStability
    temp_derivative_stable_threshold=env_get("OMNI_TEMP_DERIV_STABLE", 0.1),
    rpm_variance_hunting_threshold=env_get("OMNI_RPM_VAR_HUNTING", 10000.0),

    # PowerQuality
    rail_12v_variance_alert_pct=env_get("OMNI_12V_VAR_ALERT_PCT", 5.0),
    vcore_variance_alert_mv=env_get("OMNI_VCORE_VAR_ALERT_MV", 50.0),

    # ThermalSaturation
    t_critical=env_get("OMNI_T_CRITICAL", 95.0),
    throttle_warning_sec=env_get("OMNI_THROTTLE_WARN_SEC", 30.0),
    temp_ewma_alpha=env_get("OMNI_TEMP_EWMA_ALPHA", 0.15),

    # Bottleneck
    bottleneck_high_threshold=env_get("OMNI_BOTTLENECK_HIGH", 90.0),
    bottleneck_low_threshold=env_get("OMNI_BOTTLENECK_LOW", 50.0),
)

# ============================
# EXPORTS & UTILITIES
# ============================

"""Print loaded configuration for debugging"""
function print_config()
    println("=== OMNI MONITOR CONFIGURATION ===")
    println("\n[APP_CONFIG]")
    for (k, v) in pairs(APP_CONFIG)
        println("  $k = $v")
    end
    println("\n[SERVER_CONFIG]")
    for (k, v) in pairs(SERVER_CONFIG)
        println("  $k = $v")
    end
    println("\n[AI_CONFIG]")
    for (k, v) in pairs(AI_CONFIG)
        println("  $k = $v")
    end
    println("\n[COLLECTOR_CONFIG]")
    for (k, v) in pairs(COLLECTOR_CONFIG)
        println("  $k = $v")
    end
    println("\n[PHYSICS_CONFIG]")
    for (k, v) in pairs(PHYSICS_CONFIG)
        println("  $k = $v")
    end
    println("===================================")
end
