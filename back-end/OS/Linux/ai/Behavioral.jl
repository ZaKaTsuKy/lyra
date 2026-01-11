# OS/Linux/ai/Behavioral.jl
# ============================
# Markov Chain Behavioral Analysis Module
# ============================
# Detects suspicious state transitions and impossible sequences
# in system behavior patterns.

# ============================
# SYSTEM STATES
# ============================

"""
Enumeration of distinct system behavioral states.
States are inferred from metrics and used for transition analysis.
"""
@enum SystemState begin
    STATE_IDLE              # Low CPU, low memory, low I/O
    STATE_LIGHT_LOAD        # Light activity
    STATE_COMPUTE           # CPU-intensive workload
    STATE_IO_BOUND          # I/O-heavy workload
    STATE_MEMORY_PRESSURE   # High memory usage
    STATE_NETWORK_ACTIVE    # Network-intensive
    STATE_GPU_ACTIVE        # GPU workload
    STATE_THERMAL_THROTTLING  # NEW: High temp, reduced performance
    STATE_FAN_SPINUP        # NEW: Fans ramping up
    STATE_FAN_SPINDOWN      # NEW: Fans slowing down
    STATE_POWER_SAVING      # Low power mode
    STATE_OVERLOAD          # System overloaded
    STATE_UNKNOWN           # Cannot determine
end

const N_STATES = length(instances(SystemState))

# ============================
# MARKOV CHAIN
# ============================

"""
Markov Chain for system state transition analysis.
Tracks transition probabilities and detects anomalous sequences.
"""
mutable struct MarkovChain
    transition_counts::Matrix{Int}      # State transition counts
    transition_probs::Matrix{Float64}   # Normalized probabilities
    state_history::Vector{SystemState}  # Recent state sequence
    current_state::SystemState
    previous_state::SystemState
    history_length::Int                 # Max history to keep
    total_transitions::Int

    # Anomaly detection
    impossible_transitions::Set{Tuple{SystemState,SystemState}}
    suspicious_transitions::Set{Tuple{SystemState,SystemState}}
    last_anomaly::Union{Nothing,Tuple{SystemState,SystemState}}
    anomaly_count::Int
end

function MarkovChain(history_length::Int=100)
    # Initialize impossible transitions (physical impossibilities)
    impossible = Set{Tuple{SystemState,SystemState}}([
        # Can't go directly from IDLE to THERMAL_THROTTLING without load
        (STATE_IDLE, STATE_THERMAL_THROTTLING),
        # Can't go from FAN_SPINUP directly to IDLE (need cooldown)
        (STATE_FAN_SPINUP, STATE_IDLE),
        # Can't go from POWER_SAVING to OVERLOAD instantly
        (STATE_POWER_SAVING, STATE_OVERLOAD),
    ])

    # Suspicious but not impossible transitions
    suspicious = Set{Tuple{SystemState,SystemState}}([
        # Unusual to go from low to overload
        (STATE_LIGHT_LOAD, STATE_OVERLOAD),
        # Thermal throttling without prior compute
        (STATE_NETWORK_ACTIVE, STATE_THERMAL_THROTTLING),
    ])

    MarkovChain(
        zeros(Int, N_STATES, N_STATES),
        zeros(Float64, N_STATES, N_STATES),
        SystemState[],
        STATE_UNKNOWN,
        STATE_UNKNOWN,
        history_length,
        0,
        impossible,
        suspicious,
        nothing,
        0
    )
end

"""Update the Markov chain with a new observed state"""
function update_state!(chain::MarkovChain, new_state::SystemState)
    chain.previous_state = chain.current_state

    # Record transition
    if chain.current_state != STATE_UNKNOWN
        from_idx = Int(chain.current_state) + 1
        to_idx = Int(new_state) + 1
        chain.transition_counts[from_idx, to_idx] += 1
        chain.total_transitions += 1

        # Update probabilities
        row_sum = sum(chain.transition_counts[from_idx, :])
        if row_sum > 0
            chain.transition_probs[from_idx, :] .= chain.transition_counts[from_idx, :] ./ row_sum
        end

        # Check for anomalies
        transition = (chain.current_state, new_state)
        if transition in chain.impossible_transitions
            chain.last_anomaly = transition
            chain.anomaly_count += 1
        elseif transition in chain.suspicious_transitions
            chain.last_anomaly = transition
            chain.anomaly_count += 1
        else
            chain.last_anomaly = nothing
        end
    end

    chain.current_state = new_state

    # Update history
    push!(chain.state_history, new_state)
    while length(chain.state_history) > chain.history_length
        popfirst!(chain.state_history)
    end

    return nothing
end

"""Get the probability of a specific transition"""
function transition_probability(chain::MarkovChain, from::SystemState, to::SystemState)::Float64
    from_idx = Int(from) + 1
    to_idx = Int(to) + 1
    return chain.transition_probs[from_idx, to_idx]
end

"""Check if the last transition was anomalous"""
function is_transition_anomalous(chain::MarkovChain)::Bool
    return chain.last_anomaly !== nothing
end

"""Get the last detected anomalous transition"""
function get_last_anomaly(chain::MarkovChain)::Union{Nothing,Tuple{SystemState,SystemState}}
    return chain.last_anomaly
end

"""Detect if a transition is statistically unusual (low probability)"""
function is_transition_unusual(
    chain::MarkovChain,
    from::SystemState,
    to::SystemState;
    threshold::Float64=0.01
)::Bool
    chain.total_transitions < 50 && return false  # Not enough data
    prob = transition_probability(chain, from, to)
    return prob < threshold && prob > 0
end

# ============================
# STATE INFERENCE
# ============================

"""
Infer the current system state from metrics.
Uses thresholds to classify the overall system behavior.
"""
function infer_system_state(
    cpu_usage::Float64,
    mem_percent::Float64,
    io_mb_s::Float64,
    net_mb_s::Float64,
    gpu_util::Float64,
    cpu_temp::Float64,
    fan_rpm::Int,
    prev_fan_rpm::Int
)::SystemState
    # Thermal throttling takes precedence
    cpu_temp > 90 && return STATE_THERMAL_THROTTLING

    # Fan state changes
    fan_delta = fan_rpm - prev_fan_rpm
    fan_delta > 500 && return STATE_FAN_SPINUP
    fan_delta < -500 && return STATE_FAN_SPINDOWN

    # Overload
    cpu_usage > 95 && mem_percent > 90 && return STATE_OVERLOAD

    # GPU active
    gpu_util > 50 && return STATE_GPU_ACTIVE

    # Memory pressure
    mem_percent > 85 && return STATE_MEMORY_PRESSURE

    # I/O bound
    io_mb_s > 100 && cpu_usage < 50 && return STATE_IO_BOUND

    # Network active
    net_mb_s > 50 && return STATE_NETWORK_ACTIVE

    # Compute intensive
    cpu_usage > 70 && return STATE_COMPUTE

    # Light load
    cpu_usage > 20 || mem_percent > 40 && return STATE_LIGHT_LOAD

    # Idle
    cpu_usage < 10 && mem_percent < 30 && io_mb_s < 10 && return STATE_IDLE

    return STATE_LIGHT_LOAD
end

"""Infer state from SystemMonitor"""
function infer_system_state_from_monitor(monitor, prev_fan_rpm::Int=0)::SystemState
    cpu_usage = monitor.cpu_info.load1 / max(1, Sys.CPU_THREADS) * 100
    mem_percent = monitor.memory.total_kb > 0 ?
                  (monitor.memory.used_kb / monitor.memory.total_kb) * 100 : 0.0

    # Total I/O
    io_mb_s = sum(d.read_bps + d.write_bps for d in monitor.disks; init=0.0) / 1e6

    # Network
    net_mb_s = (monitor.network.rx_bps + monitor.network.tx_bps) / 1e6

    # GPU
    gpu_util = monitor.gpu !== nothing ? monitor.gpu.util : 0.0

    # Temperature
    cpu_temp = monitor.cpu_info.temperature.package

    # Fan
    fan_rpm = monitor.hardware !== nothing ? monitor.hardware.primary_cpu_fan_rpm : 0

    return infer_system_state(cpu_usage, mem_percent, io_mb_s, net_mb_s, gpu_util, cpu_temp, fan_rpm, prev_fan_rpm)
end

# ============================
# ANALYSIS RESULTS
# ============================

struct BehavioralResult
    current_state::SystemState
    previous_state::SystemState
    transition_probability::Float64
    is_anomalous::Bool
    anomaly_description::String
    state_stability::Float64  # How long in current state pattern
end

"""Get comprehensive behavioral analysis result"""
function get_behavioral_result(chain::MarkovChain)::BehavioralResult
    prob = if chain.previous_state != STATE_UNKNOWN
        transition_probability(chain, chain.previous_state, chain.current_state)
    else
        0.0
    end

    anomaly_desc = if chain.last_anomaly !== nothing
        "Anomalous transition: $(chain.last_anomaly[1]) -> $(chain.last_anomaly[2])"
    else
        ""
    end

    # Calculate state stability (fraction of recent history in current state)
    stability = if !isempty(chain.state_history)
        count(s -> s == chain.current_state, chain.state_history) / length(chain.state_history)
    else
        0.0
    end

    BehavioralResult(
        chain.current_state,
        chain.previous_state,
        prob,
        is_transition_anomalous(chain),
        anomaly_desc,
        stability
    )
end

"""Get state name as string"""
function state_name(state::SystemState)::String
    names = Dict(
        STATE_IDLE => "Idle",
        STATE_LIGHT_LOAD => "Light Load",
        STATE_COMPUTE => "Compute",
        STATE_IO_BOUND => "I/O Bound",
        STATE_MEMORY_PRESSURE => "Memory Pressure",
        STATE_NETWORK_ACTIVE => "Network Active",
        STATE_GPU_ACTIVE => "GPU Active",
        STATE_THERMAL_THROTTLING => "Thermal Throttling",
        STATE_FAN_SPINUP => "Fan Spin-up",
        STATE_FAN_SPINDOWN => "Fan Spin-down",
        STATE_POWER_SAVING => "Power Saving",
        STATE_OVERLOAD => "Overload",
        STATE_UNKNOWN => "Unknown"
    )
    return get(names, state, "Unknown")
end
