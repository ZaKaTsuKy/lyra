# OS/Linux/Memory.jl
# ============================
# Memory Collector - Linux
# ============================

# --------------------------
# /proc/meminfo — raw parse
# --------------------------

function get_meminfo_raw()
    info = Dict{String, Int}()
    
    try
        for line in eachline("/proc/meminfo")
            parts = split(line)
            length(parts) < 2 && continue
            key = replace(parts[1], ":" => "")
            info[key] = parse(Int, parts[2])  # kB
        end
    catch e
        @debug "Failed to read meminfo: $e"
    end
    
    return info
end

# --------------------------
# Memory pressure (PSI)
# --------------------------

function get_memory_pressure()
    path = "/proc/pressure/memory"
    isfile(path) || return 0.0
    
    try
        for line in eachline(path)
            startswith(line, "some") || continue
            m = match(r"avg10=([\d\.]+)", line)
            m !== nothing && return parse(Float64, m.captures[1])
        end
    catch e
        @debug "Failed to read memory pressure: $e"
    end
    
    return 0.0
end

# --------------------------
# VM stats
# --------------------------

function get_vm_stats()
    stats = Dict{String, Int}()
    
    try
        for line in eachline("/proc/vmstat")
            parts = split(line)
            length(parts) >= 2 || continue
            stats[parts[1]] = parse(Int, parts[2])
        end
    catch e
        @debug "Failed to read vmstat: $e"
    end
    
    return (
        pgfault = get(stats, "pgfault", 0),
        pgmajfault = get(stats, "pgmajfault", 0),
        pswpin = get(stats, "pswpin", 0),
        pswpout = get(stats, "pswpout", 0)
    )
end

# --------------------------
# High-level collector
# --------------------------

function update_memory!(monitor::SystemMonitor)
    m = get_meminfo_raw()
    
    # Basic memory
    total = get(m, "MemTotal", 0)
    avail = get(m, "MemAvailable", 0)
    
    monitor.memory.total_kb = total
    monitor.memory.avail_kb = avail
    monitor.memory.used_kb = total - avail
    
    # Swap
    swap_total = get(m, "SwapTotal", 0)
    swap_free = get(m, "SwapFree", 0)
    
    monitor.memory.swap_total_kb = swap_total
    monitor.memory.swap_used_kb = swap_total - swap_free
    
    # Composition
    monitor.memory.anon_kb = get(m, "AnonPages", 0)
    monitor.memory.file_kb = get(m, "Cached", 0)
    monitor.memory.buffers_kb = get(m, "Buffers", 0)
    monitor.memory.slab_kb = get(m, "Slab", 0)
    
    # Huge pages
    monitor.memory.hugepages_total = get(m, "HugePages_Total", 0)
    monitor.memory.hugepages_free = get(m, "HugePages_Free", 0)
    monitor.memory.hugepage_size_kb = get(m, "Hugepagesize", 0)
    
    # Pressure
    monitor.memory.pressure_avg10 = get_memory_pressure()
    
    # VM stats
    vm = get_vm_stats()
    monitor.memory.pgfault = vm.pgfault
    monitor.memory.pgmajfault = vm.pgmajfault
    monitor.memory.swap_in = vm.pswpin
    monitor.memory.swap_out = vm.pswpout
    
    return nothing
end

"""Calculate memory usage percentage"""
function get_memory_usage_percent(monitor::SystemMonitor)
    monitor.memory.total_kb == 0 && return 0.0
    return 100.0 * monitor.memory.used_kb / monitor.memory.total_kb
end

"""Calculate swap usage percentage"""
function get_swap_usage_percent(monitor::SystemMonitor)
    monitor.memory.swap_total_kb == 0 && return 0.0
    return 100.0 * monitor.memory.swap_used_kb / monitor.memory.swap_total_kb
end
