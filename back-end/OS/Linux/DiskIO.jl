# OS/Linux/DiskIO.jl
# Disk IO Collector - Linux v2.2
# Enhanced with IOPS and average wait time
# Fixed: SubString handling

const SECTOR_SIZE = 512

function is_valid_disk_device(dev::AbstractString)
    d = String(dev)
    startswith(d, "sd") && return true
    startswith(d, "nvme") && return true
    startswith(d, "vd") && return true
    startswith(d, "xvd") && return true
    startswith(d, "hd") && return true
    startswith(d, "mmcblk") && return true
    return false
end

"""Check if device name is a whole disk (not a partition)"""
function is_whole_disk(dev::AbstractString)
    d = String(dev)
    # Match whole disk patterns only (no partition numbers)
    return match(r"^(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|mmcblk\d+)$", d) !== nothing
end

function collect_diskstats()
    stats = Dict{String,NamedTuple{(:read_sectors, :write_sectors, :read_ios, :write_ios, :io_time_ms, :weighted_io_ms),NTuple{6,Int}}}()

    diskstats_path = "/proc/diskstats"
    if !isfile(diskstats_path)
        @debug "diskstats file not found" path = diskstats_path
        return stats
    end

    try
        for line in eachline(diskstats_path)
            parts = split(line)
            length(parts) < 14 && continue

            dev = String(parts[3])  # Convert SubString to String

            # Check if it's a valid disk type
            is_valid_disk_device(dev) || continue

            # Skip partitions - only keep whole disks
            is_whole_disk(dev) || continue

            stats[dev] = (
                read_sectors=parse(Int, parts[6]),
                write_sectors=parse(Int, parts[10]),
                read_ios=parse(Int, parts[4]),
                write_ios=parse(Int, parts[8]),
                io_time_ms=parse(Int, parts[13]),
                weighted_io_ms=length(parts) >= 14 ? parse(Int, parts[14]) : 0
            )
        end

        @debug "Collected disk stats" devices = collect(keys(stats))

    catch e
        @debug "Failed to read diskstats" exception = e
    end

    return stats
end

function update_disk_io!(monitor::SystemMonitor)
    now = time()
    result = Dict{String,DiskIOMetrics}()

    curr = collect_diskstats()

    for (dev, s) in curr
        if !haskey(monitor.disk_prev, dev)
            # First time seeing this device - store baseline
            monitor.disk_prev[dev] = DiskIOState(
                s.read_sectors, s.write_sectors,
                s.read_ios, s.write_ios,
                s.io_time_ms, s.weighted_io_ms, now
            )
            # Still add to results with zero rates (will show the device exists)
            result[dev] = (
                read_mb_s=0.0,
                write_mb_s=0.0,
                read_iops=0.0,
                write_iops=0.0,
                io_wait_pct=0.0,
                queue_depth=0.0,
                avg_wait_ms=0.0
            )
            continue
        end

        prev = monitor.disk_prev[dev]
        dt = now - prev.timestamp
        dt <= 0 && continue

        # Throughput
        read_mb_s = (s.read_sectors - prev.read_sectors) * SECTOR_SIZE / 1e6 / dt
        write_mb_s = (s.write_sectors - prev.write_sectors) * SECTOR_SIZE / 1e6 / dt

        # IOPS
        read_iops = (s.read_ios - prev.read_ios) / dt
        write_iops = (s.write_ios - prev.write_ios) / dt

        # IO utilization
        io_time_delta = s.io_time_ms - prev.io_time_ms
        io_wait_pct = io_time_delta / (dt * 1000) * 100

        # Queue depth
        weighted_delta = s.weighted_io_ms - prev.weighted_io_ms
        queue_depth = io_time_delta > 0 ? weighted_delta / io_time_delta : 0.0

        # Average wait time
        total_ios = (s.read_ios - prev.read_ios) + (s.write_ios - prev.write_ios)
        avg_wait_ms = total_ios > 0 ? weighted_delta / total_ios : 0.0

        result[dev] = (
            read_mb_s=max(read_mb_s, 0.0),
            write_mb_s=max(write_mb_s, 0.0),
            read_iops=max(read_iops, 0.0),
            write_iops=max(write_iops, 0.0),
            io_wait_pct=clamp(io_wait_pct, 0.0, 100.0),
            queue_depth=max(queue_depth, 0.0),
            avg_wait_ms=max(avg_wait_ms, 0.0)
        )

        monitor.disk_prev[dev] = DiskIOState(
            s.read_sectors, s.write_sectors,
            s.read_ios, s.write_ios,
            s.io_time_ms, s.weighted_io_ms, now
        )
    end

    monitor.disk_io = result
    return nothing
end

function update_disk!(monitor::SystemMonitor)
    update_disk_space!(monitor)
    update_disk_io!(monitor)
    return nothing
end

function get_total_disk_io(monitor::SystemMonitor)
    total_read = 0.0
    total_write = 0.0
    total_read_iops = 0.0
    total_write_iops = 0.0

    for (dev, io) in monitor.disk_io
        total_read += io.read_mb_s
        total_write += io.write_mb_s
        total_read_iops += io.read_iops
        total_write_iops += io.write_iops
    end

    return (read=total_read, write=total_write,
        read_iops=total_read_iops, write_iops=total_write_iops)
end