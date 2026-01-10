# OS/Linux/Processes.jl
# Process Collector - Linux v2.1
# Enhanced with process state and nice value

const MAX_PROCESSES = COLLECTOR_CONFIG.max_processes

function get_proc_static(pid::Int)
    name = ""
    threads = 0
    state = 'S'
    nice = 0

    try
        status = "/proc/$pid/status"
        isfile(status) || return (name=name, threads=threads, state=state, nice=nice)

        for line in eachline(status)
            if startswith(line, "Name:")
                parts = split(line)
                length(parts) >= 2 && (name = parts[2])
            elseif startswith(line, "Threads:")
                parts = split(line)
                length(parts) >= 2 && (threads = parse(Int, parts[2]))
            elseif startswith(line, "State:")
                parts = split(line)
                length(parts) >= 2 && (state = first(parts[2]))
            end
        end

        # Get nice value from stat
        stat_path = "/proc/$pid/stat"
        if isfile(stat_path)
            content = read(stat_path, String)
            m = match(r"\) [A-Za-z] (.+)", content)
            if m !== nothing
                fields = split(m.captures[1])
                if length(fields) >= 16
                    nice = parse(Int, fields[16])
                end
            end
        end
    catch
    end

    return (name=name, threads=threads, state=state, nice=nice)
end

function get_proc_cpu_time(pid::Int)
    try
        stat_path = "/proc/$pid/stat"
        isfile(stat_path) || return (0, 0)

        content = read(stat_path, String)
        m = match(r"\) [A-Za-z] (.+)", content)
        m === nothing && return (0, 0)

        fields = split(m.captures[1])
        length(fields) >= 12 || return (0, 0)

        utime = parse(Int, fields[11])
        stime = parse(Int, fields[12])
        return (utime, stime)
    catch
        return (0, 0)
    end
end

function get_proc_memory(pid::Int)
    rss = 0
    try
        for line in eachline("/proc/$pid/status")
            if startswith(line, "VmRSS:")
                parts = split(line)
                length(parts) >= 2 && (rss = parse(Int, parts[2]))
                break
            end
        end
    catch
    end
    return rss
end

function get_proc_io(pid::Int)
    read_b = 0
    write_b = 0
    try
        io_path = "/proc/$pid/io"
        isfile(io_path) || return (0, 0)

        for line in eachline(io_path)
            if startswith(line, "read_bytes:")
                parts = split(line)
                length(parts) >= 2 && (read_b = parse(Int, parts[2]))
            elseif startswith(line, "write_bytes:")
                parts = split(line)
                length(parts) >= 2 && (write_b = parse(Int, parts[2]))
            end
        end
    catch
    end
    return (read_b, write_b)
end

function update_processes!(monitor::SystemMonitor)
    now = time()
    dt = max(now - monitor.proc_prev_ts, 0.001)

    procs = ProcessInfo[]
    hz = 100

    try
        for pid_str in readdir("/proc")
            m = match(r"^\d+$", pid_str)
            m === nothing && continue

            pid = parse(Int, pid_str)

            static = get_proc_static(pid)
            isempty(static.name) && continue

            utime, stime = get_proc_cpu_time(pid)
            mem_kb = get_proc_memory(pid)
            read_b, write_b = get_proc_io(pid)

            cpu_pct = 0.0
            io_read_bps = 0.0
            io_write_bps = 0.0

            if haskey(monitor.proc_prev, pid)
                prev = monitor.proc_prev[pid]
                cpu_ticks = (utime - prev.utime) + (stime - prev.stime)
                cpu_pct = (cpu_ticks / hz) / dt * 100

                io_read_bps = max(0.0, (read_b - prev.read_bytes) / dt)
                io_write_bps = max(0.0, (write_b - prev.write_bytes) / dt)
            end

            monitor.proc_prev[pid] = ProcState(utime, stime, read_b, write_b)

            push!(procs, ProcessInfo(
                pid,
                static.name,
                clamp(cpu_pct, 0.0, 100.0 * Sys.CPU_THREADS),
                Float64(mem_kb),
                static.threads,
                io_read_bps,
                io_write_bps,
                static.state,
                static.nice
            ))
        end
    catch e
        @debug "Failed to update processes: $e"
    end

    monitor.proc_prev_ts = now

    current_pids = Set(p.pid for p in procs)
    for pid in keys(monitor.proc_prev)
        pid in current_pids || delete!(monitor.proc_prev, pid)
    end

    sort!(procs, by=p -> p.cpu, rev=true)
    monitor.processes = procs[1:min(length(procs), MAX_PROCESSES)]

    return nothing
end

function get_top_cpu_process(monitor::SystemMonitor)
    isempty(monitor.processes) && return nothing
    return monitor.processes[1]
end

function get_total_process_cpu(monitor::SystemMonitor)
    return sum(p.cpu for p in monitor.processes; init=0.0)
end
