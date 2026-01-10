# OS/Linux/Network.jl
# Network Collector - Linux v2.2
# Enhanced with TCP connection state tracking
# Fixed interface detection for modern Linux systems

const NET_DEV_PATH = "/proc/net/dev"
const TCP_PATH = "/proc/net/tcp"
const TCP6_PATH = "/proc/net/tcp6"

"""
Check if interface should be excluded (virtual/internal interfaces).
We use a blacklist approach - exclude known virtual interfaces.
"""
function is_excluded_iface(name::AbstractString)
    n = String(name)  # Convert SubString to String if needed

    # Loopback
    n == "lo" && return true

    # Docker/container interfaces
    startswith(n, "docker") && return true
    startswith(n, "veth") && return true
    startswith(n, "br-") && return true

    # Libvirt/KVM
    startswith(n, "virbr") && return true
    startswith(n, "vnet") && return true

    # VPN tunnels (optional - might want to keep these)
    # startswith(n, "tun") && return true
    # startswith(n, "tap") && return true

    # Kubernetes
    startswith(n, "cni") && return true
    startswith(n, "flannel") && return true
    startswith(n, "cali") && return true  # Calico

    # WSL internal
    startswith(n, "bond") && return true
    startswith(n, "dummy") && return true

    return false
end

"""
Check if interface looks like a real physical or important virtual interface.
"""
function is_valid_iface(name::AbstractString)
    # First check exclusion list
    is_excluded_iface(name) && return false

    # Accept everything else - we already filtered out the bad ones
    return true
end

function classify_network_traffic(total_bps::Float64)
    total_bps < 50_000 && return "idle"
    total_bps < 5_000_000 && return "streaming"
    total_bps < 50_000_000 && return "burst"
    return "saturated"
end

# TCP states from kernel
const TCP_STATES = Dict(
    "01" => :established, "02" => :syn_sent, "03" => :syn_recv,
    "04" => :fin_wait1, "05" => :fin_wait2, "06" => :time_wait,
    "07" => :close, "08" => :close_wait, "09" => :last_ack,
    "0A" => :listen, "0B" => :closing
)

function get_tcp_stats()
    stats = TCPStats()

    for tcp_file in [TCP_PATH, TCP6_PATH]
        isfile(tcp_file) || continue
        try
            lines = readlines(tcp_file)
            for line in lines[2:end]
                parts = split(strip(line))
                length(parts) < 4 && continue
                state_hex = uppercase(parts[4])
                state = get(TCP_STATES, state_hex, :unknown)
                stats.total += 1
                if state == :established
                    stats.established += 1
                elseif state == :time_wait
                    stats.time_wait += 1
                elseif state == :close_wait
                    stats.close_wait += 1
                elseif state == :listen
                    stats.listen += 1
                end
            end
        catch e
            @debug "Failed to parse TCP stats from $tcp_file" exception = e
        end
    end
    return stats
end

"""
Parse a line from /proc/net/dev and extract interface stats.
Format: iface: rx_bytes rx_packets rx_errs rx_drop ... tx_bytes tx_packets tx_errs tx_drop ...
"""
function parse_net_dev_line(line::String)
    # Split by colon to separate interface name from stats
    colon_pos = findfirst(':', line)
    colon_pos === nothing && return nothing

    iface = String(strip(line[1:colon_pos-1]))  # Convert to String!
    stats_str = strip(line[colon_pos+1:end])

    # Split stats by whitespace
    stats = split(stats_str)

    # Need at least 10 fields (rx: bytes packets errs drop fifo frame compressed multicast, tx: bytes packets)
    # Full format has 16 fields, but we only need 12
    length(stats) < 10 && return nothing

    try
        return (
            iface=iface,
            rx_bytes=parse(Int, stats[1]),
            rx_packets=parse(Int, stats[2]),
            rx_errs=parse(Int, stats[3]),
            rx_drop=parse(Int, stats[4]),
            tx_bytes=parse(Int, stats[9]),
            tx_packets=parse(Int, stats[10]),
            tx_errs=length(stats) >= 11 ? parse(Int, stats[11]) : 0,
            tx_drop=length(stats) >= 12 ? parse(Int, stats[12]) : 0
        )
    catch e
        @debug "Failed to parse net dev stats" line = line exception = e
        return nothing
    end
end

function update_network!(monitor::SystemMonitor)
    if !isfile(NET_DEV_PATH)
        @debug "Network stats file not found" path = NET_DEV_PATH
        return nothing
    end

    now = time()
    dt = max(now - monitor.net_prev_ts, 0.001)

    interfaces = NetworkInterface[]
    total_rx_bytes = 0
    total_tx_bytes = 0
    max_traffic = 0.0
    primary_iface = monitor.network.primary_iface

    try
        lines = readlines(NET_DEV_PATH)

        # First two lines are headers
        # Inter-|   Receive                                                |  Transmit
        #  face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed

        if length(lines) < 3
            @debug "No interfaces found in /proc/net/dev" line_count = length(lines)
            return nothing
        end

        for line in lines[3:end]
            isempty(strip(line)) && continue

            parsed = parse_net_dev_line(line)
            parsed === nothing && continue

            iface = parsed.iface

            # Check if valid interface
            if !is_valid_iface(iface)
                @debug "Skipping excluded interface" iface = iface
                continue
            end

            rx_bytes = parsed.rx_bytes
            tx_bytes = parsed.tx_bytes
            rx_packets = parsed.rx_packets
            tx_packets = parsed.tx_packets
            rx_err = parsed.rx_errs
            tx_err = parsed.tx_errs
            rx_drop = parsed.rx_drop
            tx_drop = parsed.tx_drop

            # Calculate rates
            rx_bps = 0.0
            tx_bps = 0.0
            rx_pkt_s = 0.0
            tx_pkt_s = 0.0

            if haskey(monitor.net_prev, iface)
                prev = monitor.net_prev[iface]
                rx_bps = max(0.0, (rx_bytes - prev.rx_bytes) / dt)
                tx_bps = max(0.0, (tx_bytes - prev.tx_bytes) / dt)
                # Previous rx_packets_s/tx_packets_s store previous packet counts
                rx_pkt_s = max(0.0, (rx_packets - Int(prev.rx_packets_s)) / dt)
                tx_pkt_s = max(0.0, (tx_packets - Int(prev.tx_packets_s)) / dt)
            end

            iface_state = NetworkInterface(
                iface, rx_bytes, tx_bytes, rx_bps, tx_bps,
                rx_pkt_s, tx_pkt_s, rx_err, tx_err, rx_drop, tx_drop
            )

            push!(interfaces, iface_state)

            # Store current values for next delta calculation
            # Note: rx_packets_s/tx_packets_s are reused to store packet counts
            monitor.net_prev[iface] = NetworkInterface(
                iface, rx_bytes, tx_bytes, rx_bps, tx_bps,
                Float64(rx_packets), Float64(tx_packets),
                rx_err, tx_err, rx_drop, tx_drop
            )

            total_rx_bytes += rx_bytes
            total_tx_bytes += tx_bytes

            # Track primary interface (highest traffic)
            traffic = rx_bps + tx_bps
            if traffic > max_traffic
                max_traffic = traffic
                primary_iface = iface
            end
        end

        @debug "Network interfaces found" count = length(interfaces) names = [i.name for i in interfaces]

    catch e
        @debug "Failed to update network" exception = e
        return nothing
    end

    monitor.net_prev_ts = now

    total_rx_bps = sum(i.rx_bps for i in interfaces; init=0.0)
    total_tx_bps = sum(i.tx_bps for i in interfaces; init=0.0)

    # Set primary interface
    if isempty(primary_iface) && !isempty(interfaces)
        primary_iface = interfaces[1].name
    end

    # Get TCP stats
    tcp_stats = get_tcp_stats()

    monitor.network = NetworkInfo(
        primary_iface, total_rx_bps, total_tx_bps,
        total_rx_bytes, total_tx_bytes, interfaces,
        classify_network_traffic(total_rx_bps + total_tx_bps),
        tcp_stats
    )

    return nothing
end

function get_primary_network_rates(monitor::SystemMonitor)
    isempty(monitor.network.interfaces) && return (rx=0.0, tx=0.0)
    for iface in monitor.network.interfaces
        iface.name == monitor.network.primary_iface && return (rx=iface.rx_bps, tx=iface.tx_bps)
    end
    return (rx=monitor.network.interfaces[1].rx_bps, tx=monitor.network.interfaces[1].tx_bps)
end

"""List all detected network interfaces (for debugging)"""
function list_all_interfaces()
    isfile(NET_DEV_PATH) || return String[]

    interfaces = String[]
    try
        for line in readlines(NET_DEV_PATH)[3:end]
            parsed = parse_net_dev_line(line)
            parsed !== nothing && push!(interfaces, parsed.iface)
        end
    catch
    end
    return interfaces
end