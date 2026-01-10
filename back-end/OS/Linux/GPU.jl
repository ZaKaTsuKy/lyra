# OS/Linux/GPU.jl
# ============================
# GPU Collector - Linux (NVIDIA)
# ============================

const GPU_HISTORY_LEN = COLLECTOR_CONFIG.gpu_history_len

# GPU history for trend detection
mutable struct GPUHistory
    util_gpu::Vector{Float64}
    util_mem::Vector{Float64}
end

GPUHistory() = GPUHistory(Float64[], Float64[])

# Global history instance
const _gpu_history = Ref{GPUHistory}(GPUHistory())

# --------------------------
# Helper functions
# --------------------------

# Cache for nvidia-smi path
const _nvidia_smi_path = Ref{Union{String,Nothing}}(nothing)
const _nvidia_smi_checked = Ref{Bool}(false)

"""Find nvidia-smi executable path"""
function find_nvidia_smi()
    if _nvidia_smi_checked[]
        return _nvidia_smi_path[]
    end

    _nvidia_smi_checked[] = true

    # Common paths for nvidia-smi
    paths = [
        "/usr/bin/nvidia-smi",
        "/usr/local/bin/nvidia-smi",
        "/opt/nvidia/bin/nvidia-smi",
        "/usr/lib/nvidia/bin/nvidia-smi",
        # For some distributions
        "/usr/lib/wsl/lib/nvidia-smi",  # WSL2
    ]

    # First try to find in PATH
    try
        result = read(`which nvidia-smi`, String)
        path = strip(result)
        if !isempty(path) && isfile(path)
            _nvidia_smi_path[] = path
            return path
        end
    catch
        # which failed, try known paths
    end

    # Try known paths
    for path in paths
        if isfile(path)
            _nvidia_smi_path[] = path
            return path
        end
    end

    _nvidia_smi_path[] = nothing
    return nothing
end

"""Run nvidia-smi with proper argument handling"""
function run_nvidia_smi(args::Vector{String}=String[])
    nvidia_path = find_nvidia_smi()

    if nvidia_path === nothing
        @debug "nvidia-smi not found in any known location"
        return ""
    end

    try
        if isempty(args)
            cmd = Cmd([nvidia_path])
        else
            cmd = Cmd([nvidia_path; args])
        end
        return read(cmd, String)
    catch e
        @debug "nvidia-smi execution failed" exception = e nvidia_path = nvidia_path args = args
        return ""
    end
end

"""Convenience wrapper for string arguments (splits properly)"""
function run_nvidia_smi(args::String)
    isempty(args) && return run_nvidia_smi(String[])
    # Split arguments properly, respecting the command structure
    return run_nvidia_smi(split(args))
end

function parse_throttling(txt::String)
    reasons = String[]
    for line in split(txt, '\n')
        occursin("Clocks Throttle Reasons", line) && continue
        if occursin("Active", line)
            parts = split(line, ":")
            !isempty(parts) && push!(reasons, strip(parts[1]))
        end
    end
    return reasons
end

function detect_gpu_trend(v::Vector{Float64})
    length(v) < 3 && return "stable"
    d = v[end] - v[1]
    abs(d) < 5 && return "stable"
    return d > 0 ? "rising" : "falling"
end

# --------------------------
# High-level collector
# --------------------------

function update_gpu!(monitor::SystemMonitor)
    # Check if nvidia-smi is available
    out = run_nvidia_smi()

    if isempty(out)
        @debug "nvidia-smi returned empty output"
        monitor.gpu = nothing
        return nothing
    end

    if occursin("command not found", out) || occursin("NVIDIA-SMI has failed", out)
        @debug "nvidia-smi error" output = first(out, 200)
        monitor.gpu = nothing
        return nothing
    end

    # Query detailed GPU info with proper argument array
    query_args = [
        "--query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.sm,clocks.mem",
        "--format=csv,noheader,nounits"
    ]
    query = run_nvidia_smi(query_args)

    if isempty(query)
        @debug "nvidia-smi query returned empty"
        monitor.gpu = nothing
        return nothing
    end

    try
        # Handle potential multi-GPU systems (take first GPU)
        lines = split(strip(query), '\n')
        first_gpu_line = strip(lines[1])

        # Split by comma, but be careful with GPU names that might contain commas
        # nvidia-smi CSV format uses ", " (comma-space) as separator
        fields = split(first_gpu_line, ", ")

        # Fallback: if we don't have enough fields, try simple comma split
        if length(fields) < 10
            fields = split(first_gpu_line, ",")
            fields = [strip(f) for f in fields]
        end

        if length(fields) < 10
            @debug "nvidia-smi returned unexpected format" fields_count = length(fields) line = first_gpu_line
            monitor.gpu = nothing
            return nothing
        end

        name = strip(fields[1])

        # Parse with fallback for [Not Supported] values
        util_gpu = tryparse_float(fields[2], 0.0)
        util_mem = tryparse_float(fields[3], 0.0)
        mem_used = tryparse_float(fields[4], 0.0) / 1024  # MB to GB
        mem_total = tryparse_float(fields[5], 0.0) / 1024  # MB to GB
        temp = tryparse_float(fields[6], 0.0)
        power_draw = tryparse_float(fields[7], 0.0)
        power_limit = tryparse_float(fields[8], 0.0)
        sm_clock = tryparse_float(fields[9], 0.0)
        mem_clock = tryparse_float(fields[10], 0.0)

        # Get throttling reasons
        throttle_args = ["-q", "-d", "PERFORMANCE,POWER,TEMPERATURE"]
        q = run_nvidia_smi(throttle_args)
        throttling = parse_throttling(q)

        # Update history
        h = _gpu_history[]
        push!(h.util_gpu, util_gpu)
        push!(h.util_mem, util_mem)

        while length(h.util_gpu) > GPU_HISTORY_LEN
            popfirst!(h.util_gpu)
        end
        while length(h.util_mem) > GPU_HISTORY_LEN
            popfirst!(h.util_mem)
        end

        # Create or update GPU info
        if monitor.gpu === nothing
            monitor.gpu = GPUInfo()
        end

        monitor.gpu.name = name
        monitor.gpu.util = util_gpu
        monitor.gpu.mem_used = mem_used
        monitor.gpu.mem_total = mem_total
        monitor.gpu.temp = temp
        monitor.gpu.power_draw = power_draw
        monitor.gpu.power_limit = power_limit
        monitor.gpu.sm_clock = sm_clock
        monitor.gpu.mem_clock = mem_clock
        monitor.gpu.throttling = throttling

        @debug "GPU updated successfully" name = name util = util_gpu temp = temp

    catch e
        @debug "Failed to parse GPU info" exception = e
        monitor.gpu = nothing
    end

    return nothing
end

"""Parse float with fallback for [Not Supported] or invalid values"""
function tryparse_float(s::AbstractString, default::Float64=0.0)
    s = strip(String(s))
    # Handle nvidia-smi special values
    if isempty(s) || occursin("Not Supported", s) || occursin("N/A", s) || s == "[N/A]"
        return default
    end
    result = tryparse(Float64, s)
    return result === nothing ? default : result
end

"""Get GPU utilization history average"""
function get_gpu_util_avg()
    h = _gpu_history[]
    isempty(h.util_gpu) && return 0.0
    return sum(h.util_gpu) / length(h.util_gpu)
end

"""Get GPU trend"""
function get_gpu_trend()
    h = _gpu_history[]
    return detect_gpu_trend(h.util_gpu)
end