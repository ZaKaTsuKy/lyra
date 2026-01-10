# OS/Linux/SystemUtils.jl
# ============================
# System Utils Collector - Linux
# ============================

const PROC_STAT = "/proc/stat"
const PROC_UPTIME = "/proc/uptime"
const PROC_LOADAVG = "/proc/loadavg"
const PROC_PRESSURE = "/proc/pressure"

# --------------------------
# Helper functions
# --------------------------

function read_uptime()
    try
        content = read(PROC_UPTIME, String)
        return parse(Float64, split(content)[1])
    catch
        return 0.0
    end
end

function read_pressure(kind::String)
    path = joinpath(PROC_PRESSURE, kind)
    isfile(path) || return 0.0
    
    try
        for line in eachline(path)
            startswith(line, "some") || continue
            m = match(r"avg10=([\d\.]+)", line)
            m !== nothing && return parse(Float64, m.captures[1])
        end
    catch
    end
    
    return 0.0
end

function read_oom_kills()
    try
        for line in eachline(PROC_STAT)
            if startswith(line, "oom_kill")
                parts = split(line)
                length(parts) >= 2 && return parse(Int, parts[2])
            end
        end
    catch
    end
    return 0
end

function detect_environment()
    # Container heuristics
    isfile("/.dockerenv") && return "container"
    
    try
        cgroup = read("/proc/1/cgroup", String)
        occursin("docker", cgroup) && return "container"
        occursin("lxc", cgroup) && return "container"
        occursin("kubepods", cgroup) && return "container"
    catch
    end
    
    # VM heuristics
    try
        cpuinfo = read("/proc/cpuinfo", String)
        occursin("hypervisor", cpuinfo) && return "vm"
    catch
    end
    
    try
        dmi = read("/sys/class/dmi/id/product_name", String)
        occursin("VirtualBox", dmi) && return "vm"
        occursin("VMware", dmi) && return "vm"
        occursin("QEMU", dmi) && return "vm"
        occursin("KVM", dmi) && return "vm"
    catch
    end
    
    return "baremetal"
end

# --------------------------
# High-level collector
# --------------------------

function update_system!(monitor::SystemMonitor)
    # Uptime
    monitor.system.uptime_sec = read_uptime()
    
    # Environment detection (only once)
    if monitor.system.environment == "unknown"
        monitor.system.environment = detect_environment()
    end
    
    # OOM kills
    monitor.system.oom_kills = read_oom_kills()
    
    # Pressure Stall Information
    monitor.system.psi_cpu = read_pressure("cpu")
    monitor.system.psi_mem = read_pressure("memory")
    monitor.system.psi_io = read_pressure("io")
    
    return nothing
end

"""Get formatted uptime string"""
function get_uptime_string(monitor::SystemMonitor)
    return format_duration(monitor.system.uptime_sec)
end

"""Check if system is under memory pressure"""
function is_memory_pressure_high(monitor::SystemMonitor)
    return monitor.system.psi_mem > 10.0  # >10% pressure
end

"""Check if system is under IO pressure"""
function is_io_pressure_high(monitor::SystemMonitor)
    return monitor.system.psi_io > 10.0  # >10% pressure
end
