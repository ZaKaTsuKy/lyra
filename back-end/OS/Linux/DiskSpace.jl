# OS/Linux/DiskSpace.jl
# ============================
# Disk Space Collector - Linux v2.2
# Fixed: locale-independent parsing, SubString handling
# ============================

# --------------------------
# Helper functions
# --------------------------

function is_relevant_mount(mount::AbstractString)
    m = String(mount)
    m == "/" && return true
    startswith(m, "/home") && return true
    startswith(m, "/mnt/") && return true
    startswith(m, "/data") && return true
    startswith(m, "/opt") && return true
    startswith(m, "/var") && return true
    startswith(m, "/media") && return true
    return false
end

function is_noise_mount(mount::AbstractString)
    m = String(mount)
    occursin("docker", m) && return true
    occursin("wslg", m) && return true
    occursin("overlay", m) && return true
    occursin("shm", m) && return true
    occursin("snap", m) && return true
    occursin("loop", m) && return true
    return false
end

"""Parse a size value with unit suffix (G, M, K, T) to GB"""
function parse_size_to_gb(s::AbstractString)
    s = strip(String(s))
    isempty(s) && return 0.0

    # Remove any trailing 'B' (some systems show "1GB" vs "1G")
    s = replace(s, r"B$"i => "")

    # Extract number and unit
    m = match(r"^([\d.,]+)\s*([TGMK])?$"i, s)
    m === nothing && return 0.0

    # Parse number (handle both . and , as decimal separator)
    num_str = replace(m.captures[1], "," => ".")
    num = tryparse(Float64, num_str)
    num === nothing && return 0.0

    # Convert to GB based on unit
    unit = m.captures[2]
    if unit === nothing
        return num / 1e9  # Assume bytes
    end

    unit = uppercase(unit)
    if unit == "T"
        return num * 1024
    elseif unit == "G"
        return num
    elseif unit == "M"
        return num / 1024
    elseif unit == "K"
        return num / 1024 / 1024
    end

    return num
end

# --------------------------
# High-level collector
# --------------------------

function update_disk_space!(monitor::SystemMonitor)
    disks = DiskUsage[]

    # Use POSIX locale to ensure consistent output format
    # Also use -P for POSIX output format (single line per filesystem)
    try
        # Try with POSIX locale first for consistent parsing
        output = withenv("LC_ALL" => "C", "LANG" => "C") do
            read(`df -BG -P`, String)
        end

        lines = split(output, '\n')

        # Header should be: Filesystem 1G-blocks Used Available Use% Mounted on
        # With -P flag, format is guaranteed to be single line per entry

        for line in lines[2:end]
            isempty(strip(line)) && continue

            parts = split(line)
            # -P format: Filesystem Size Used Avail Use% Mounted
            length(parts) < 6 && continue

            # Last element is mount point (could have spaces, but -P prevents that)
            mount = String(parts[6])

            # In case mount point has spaces (shouldn't with -P, but just in case)
            if length(parts) > 6
                mount = String(join(parts[6:end], " "))
            end

            # Filter mounts
            is_relevant_mount(mount) || continue
            is_noise_mount(mount) && continue

            total = parse_size_to_gb(parts[2])
            used = parse_size_to_gb(parts[3])
            avail = parse_size_to_gb(parts[4])

            # Parse percent (remove %)
            pct_str = replace(String(parts[5]), "%" => "")
            pct = tryparse(Float64, pct_str)
            if pct === nothing
                pct = total > 0 ? (used / total * 100) : 0.0
            end

            push!(disks, DiskUsage(
                mount,
                total,
                used,
                avail,
                pct,
                0.0,  # read_bps (filled by DiskIO)
                0.0   # write_bps (filled by DiskIO)
            ))
        end
    catch e
        @debug "Failed to get disk space" exception = e

        # Fallback: try without locale override
        try
            output = read(`df -BG`, String)
            lines = split(output, '\n')

            for line in lines[2:end]
                isempty(strip(line)) && continue
                parts = split(line)
                length(parts) < 5 && continue

                # Try to find the mount point (starts with /)
                mount_idx = findfirst(p -> startswith(String(p), "/"), parts)
                mount_idx === nothing && continue

                mount = String(parts[mount_idx])
                is_relevant_mount(mount) || continue
                is_noise_mount(mount) && continue

                # Find percentage (contains %)
                pct_idx = findfirst(p -> occursin("%", String(p)), parts)
                pct = 0.0
                if pct_idx !== nothing
                    pct_str = replace(String(parts[pct_idx]), "%" => "")
                    pct = something(tryparse(Float64, pct_str), 0.0)
                end

                # Try to extract sizes (look for values with G suffix before mount)
                sizes = Float64[]
                for i in 1:min(mount_idx - 1, length(parts))
                    val = parse_size_to_gb(parts[i])
                    val > 0 && push!(sizes, val)
                end

                total = length(sizes) >= 1 ? sizes[1] : 0.0
                used = length(sizes) >= 2 ? sizes[2] : 0.0
                avail = length(sizes) >= 3 ? sizes[3] : 0.0

                push!(disks, DiskUsage(mount, total, used, avail, pct, 0.0, 0.0))
            end
        catch e2
            @debug "Fallback disk space collection also failed" exception = e2
        end
    end

    # Sort by mount point
    sort!(disks, by=d -> d.mount)
    monitor.disks = disks

    return nothing
end

"""Get disk usage for root filesystem"""
function get_root_disk_usage(monitor::SystemMonitor)
    for disk in monitor.disks
        disk.mount == "/" && return disk.percent
    end
    return 0.0
end