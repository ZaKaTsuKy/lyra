# OS/Linux/CPU.jl
# ============================
# CPU Collector - Linux v2.1
# ============================
# Enhanced with:
# - CPU temperature monitoring
# - Context switch rate (per second)
# - Static data caching
# - Interrupt rate tracking
# ============================

using Statistics: mean

# ============================
# STATIC DATA (cached)
# ============================

function init_cpu_static!(monitor::SystemMonitor)
    monitor.static_cache.initialized && return

    try
        info = read("/proc/cpuinfo", String)
        m = match(r"model name\s*:\s*(.*)", info)
        c = match(r"cache size\s*:\s*(.*)", info)
        m !== nothing && (monitor.static_cache.cpu_model = strip(m.captures[1]))
        c !== nothing && (monitor.static_cache.cpu_cache = strip(c.captures[1]))
        monitor.static_cache.core_count = Sys.CPU_THREADS

        # Get kernel version (safe UTF-8 truncation)
        kernel_str = strip(read("/proc/version", String))
        monitor.static_cache.kernel_version = first(kernel_str, 50)

        # Get hostname
        monitor.static_cache.hostname = strip(read("/etc/hostname", String))

        monitor.static_cache.initialized = true
    catch e
        @debug "Failed to init static cache: $e"
    end
end

# ============================
# CPU TEMPERATURE
# ============================

const HWMON_PATH = "/sys/class/hwmon"
const THERMAL_PATH = "/sys/class/thermal"

"""Find and read CPU temperature from hwmon or thermal zones"""
function get_cpu_temperature()
    temps = CPUTemperature()
    core_temps = Float64[]

    # Try hwmon first (more detailed)
    try
        if isdir(HWMON_PATH)
            for hwmon in readdir(HWMON_PATH)
                hwmon_dir = joinpath(HWMON_PATH, hwmon)

                # Check if this is a CPU temp sensor
                name_file = joinpath(hwmon_dir, "name")
                isfile(name_file) || continue

                name = strip(read(name_file, String))
                # Common CPU sensor names
                is_cpu = name in ["coretemp", "k10temp", "k8temp", "zenpower", "cpu_thermal"]
                is_cpu || continue

                # Read all temp inputs
                for f in readdir(hwmon_dir)
                    if startswith(f, "temp") && endswith(f, "_input")
                        temp_file = joinpath(hwmon_dir, f)
                        try
                            temp_mc = parse(Int, strip(read(temp_file, String)))
                            temp_c = temp_mc / 1000.0

                            # Check label to distinguish package vs core
                            label_file = replace(temp_file, "_input" => "_label")
                            if isfile(label_file)
                                label = lowercase(strip(read(label_file, String)))
                                if occursin("package", label) || occursin("tctl", label)
                                    temps.package = temp_c
                                elseif occursin("core", label)
                                    push!(core_temps, temp_c)
                                end
                            else
                                push!(core_temps, temp_c)
                            end

                            # Check for critical temp
                            crit_file = replace(temp_file, "_input" => "_crit")
                            if isfile(crit_file)
                                temps.critical_temp = parse(Int, strip(read(crit_file, String))) / 1000.0
                            end
                        catch
                        end
                    end
                end
            end
        end
    catch e
        @debug "Failed to read hwmon temps: $e"
    end

    # Fallback to thermal zones
    if temps.package == 0.0 && isempty(core_temps)
        try
            if isdir(THERMAL_PATH)
                for zone in readdir(THERMAL_PATH)
                    startswith(zone, "thermal_zone") || continue
                    zone_dir = joinpath(THERMAL_PATH, zone)

                    type_file = joinpath(zone_dir, "type")
                    temp_file = joinpath(zone_dir, "temp")

                    isfile(type_file) && isfile(temp_file) || continue

                    zone_type = lowercase(strip(read(type_file, String)))
                    if occursin("cpu", zone_type) || occursin("x86_pkg", zone_type) || occursin("acpitz", zone_type)
                        temp_mc = parse(Int, strip(read(temp_file, String)))
                        temps.package = temp_mc / 1000.0
                        break
                    end
                end
            end
        catch e
            @debug "Failed to read thermal zones: $e"
        end
    end

    temps.cores = core_temps
    temps.max_temp = max(temps.package, isempty(core_temps) ? 0.0 : maximum(core_temps))

    return temps
end

# ============================
# CPU FREQUENCIES
# ============================

function get_cpu_freqs()
    freqs = Float64[]
    base = "/sys/devices/system/cpu"

    try
        for cpu in readdir(base)
            m = match(r"^cpu(\d+)$", cpu)
            m === nothing && continue

            path = joinpath(base, cpu, "cpufreq", "scaling_cur_freq")
            isfile(path) || continue

            freq = parse(Int, strip(read(path, String))) / 1000  # kHz to MHz
            push!(freqs, freq)
        end
    catch e
        @debug "Failed to read CPU frequencies: $e"
    end

    isempty(freqs) && return (min=0.0, avg=0.0, max=0.0)
    return (min=minimum(freqs), avg=mean(freqs), max=maximum(freqs))
end

function get_cpu_governors()
    governors = Set{String}()
    base = "/sys/devices/system/cpu"

    try
        for cpu in readdir(base)
            m = match(r"^cpu(\d+)$", cpu)
            m === nothing && continue

            path = joinpath(base, cpu, "cpufreq", "scaling_governor")
            isfile(path) && push!(governors, strip(read(path, String)))
        end
    catch e
        @debug "Failed to read CPU governors: $e"
    end

    return collect(governors)
end

# ============================
# LOAD AVERAGE
# ============================

function get_load_avg()
    try
        content = read("/proc/loadavg", String)
        parts = split(content)

        # Also get running/total processes
        procs = split(parts[4], "/")
        running = parse(Int, procs[1])

        return (
            load1=parse(Float64, parts[1]),
            load5=parse(Float64, parts[2]),
            load15=parse(Float64, parts[3]),
            running=running
        )
    catch e
        @debug "Failed to read load average: $e"
        return (load1=0.0, load5=0.0, load15=0.0, running=0)
    end
end

# ============================
# CPU USAGE (delta-based)
# ============================

function update_cpu_usage!(monitor::SystemMonitor)
    usage = Dict{String,Float64}()

    try
        for line in eachline("/proc/stat")
            startswith(line, "cpu") || continue
            parts = split(line)
            key = parts[1]

            length(parts) < 8 && continue
            vals = parse.(Int, parts[2:min(end, 11)])

            # idle = idle + iowait
            idle = length(vals) >= 4 ? vals[4] : 0
            idle += length(vals) >= 5 ? vals[5] : 0
            total = sum(vals)

            if haskey(monitor.cpu_prev, key)
                prev = monitor.cpu_prev[key]
                diff_total = total - prev.total
                diff_idle = idle - prev.idle

                usage[key] = diff_total > 0 ?
                             (diff_total - diff_idle) / diff_total * 100 : 0.0

                prev.idle = idle
                prev.total = total
            else
                monitor.cpu_prev[key] = CoreState(idle, total)
                usage[key] = 0.0
            end
        end
    catch e
        @debug "Failed to update CPU usage: $e"
    end

    # Update per-core state
    for (i, core) in enumerate(monitor.cores)
        key = "cpu$(i-1)"
        if haskey(monitor.cpu_prev, key)
            core.idle = monitor.cpu_prev[key].idle
            core.total = monitor.cpu_prev[key].total
        end
    end

    return usage
end

# ============================
# SCHEDULER STATS (with rates)
# ============================

function get_cpu_scheduler_stats!(monitor::SystemMonitor)
    ctxt = 0
    intr = 0
    procs_running = 0
    procs_blocked = 0

    try
        for line in eachline("/proc/stat")
            if startswith(line, "ctxt ")
                ctxt = parse(Int, split(line)[2])
            elseif startswith(line, "intr ")
                intr = parse(Int, split(line)[2])
            elseif startswith(line, "procs_running")
                procs_running = parse(Int, split(line)[2])
            elseif startswith(line, "procs_blocked")
                procs_blocked = parse(Int, split(line)[2])
            end
        end
    catch e
        @debug "Failed to read scheduler stats: $e"
    end

    # Calculate rates
    ctxt_rate = update_rate!(monitor.ctxt_rate, ctxt)
    intr_rate = update_rate!(monitor.intr_rate, intr)

    return (ctxt=ctxt, intr=intr, ctxt_rate=ctxt_rate, intr_rate=intr_rate,
        procs_running=procs_running, procs_blocked=procs_blocked)
end

# ============================
# CPU PRESSURE (PSI)
# ============================

function get_cpu_pressure()
    path = "/proc/pressure/cpu"
    isfile(path) || return 0.0

    try
        for line in eachline(path)
            startswith(line, "some") || continue
            m = match(r"avg10=([\d\.]+)", line)
            m !== nothing && return parse(Float64, m.captures[1])
        end
    catch e
        @debug "Failed to read CPU pressure: $e"
    end

    return 0.0
end

# ============================
# HIGH-LEVEL COLLECTOR
# ============================

function update_cpu!(monitor::SystemMonitor)
    # Initialize static cache once
    init_cpu_static!(monitor)

    # Use cached static data
    monitor.cpu_info.model = monitor.static_cache.cpu_model
    monitor.cpu_info.cache = monitor.static_cache.cpu_cache

    # Get frequencies
    freq = get_cpu_freqs()
    monitor.cpu_info.freq_min = freq.min
    monitor.cpu_info.freq_avg = freq.avg
    monitor.cpu_info.freq_max = freq.max

    # Get governors (rarely changes, but keep updating)
    monitor.cpu_info.governors = get_cpu_governors()

    # Get load average and running processes
    load = get_load_avg()
    monitor.cpu_info.load1 = load.load1
    monitor.cpu_info.load5 = load.load5
    monitor.cpu_info.load15 = load.load15
    monitor.system.procs_running = load.running

    # Update usage
    update_cpu_usage!(monitor)

    # Get scheduler stats with rates
    sched = get_cpu_scheduler_stats!(monitor)
    monitor.cpu_info.ctxt_switches = sched.ctxt
    monitor.cpu_info.interrupts = sched.intr
    monitor.cpu_info.ctxt_switches_ps = sched.ctxt_rate
    monitor.cpu_info.interrupts_ps = sched.intr_rate
    monitor.system.procs_blocked = sched.procs_blocked

    # Get pressure
    monitor.cpu_info.pressure_avg10 = get_cpu_pressure()

    # NEW: Get temperature
    monitor.cpu_info.temperature = get_cpu_temperature()

    return nothing
end

"""Calculate overall CPU usage percentage"""
function get_cpu_usage(monitor::SystemMonitor)
    if isempty(monitor.cores)
        return 0.0
    end

    total_idle = sum(c.idle for c in monitor.cores)
    total_total = sum(c.total for c in monitor.cores)

    total_total == 0 && return 0.0
    return 100.0 * (1.0 - total_idle / total_total)
end

"""Get CPU temperature (package or max core)"""
function get_cpu_temp(monitor::SystemMonitor)
    temp = monitor.cpu_info.temperature
    temp.package > 0 && return temp.package
    return temp.max_temp
end