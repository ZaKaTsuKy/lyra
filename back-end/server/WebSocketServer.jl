# WebSocketServer.jl
# ============================
# OMNI MONITOR - WebSocket Server
# ============================
# High-performance WebSocket server using Oxygen.jl
# with optimized two-payload strategy:
# - INIT_PAYLOAD: Full history on connection
# - UPDATE_PAYLOAD: Instant values only per iteration
# ============================

using Oxygen
using HTTP
using JSON3
using StructTypes

# ============================
# DTO STRUCTURES (JSON Payloads)
# ============================

"""Subset of StaticCache for JSON serialization"""
struct StaticDTO
    cpu_model::String
    cpu_cache::String
    core_count::Int
    kernel_version::String
    hostname::String
end

StructTypes.StructType(::Type{StaticDTO}) = StructTypes.Struct()

"""Disk configuration for init payload"""
struct DiskDTO
    mount::String
    total_gb::Float64
end

StructTypes.StructType(::Type{DiskDTO}) = StructTypes.Struct()

"""History data for init payload"""
struct HistoryDTO
    cpu_usage::Vector{Float64}
    mem_usage::Vector{Float64}
    net_rx::Vector{Float64}
    net_tx::Vector{Float64}
    gpu_util::Vector{Float64}
    disk_io::Vector{Float64}
    cpu_temp::Vector{Float64}
    timestamps::Vector{Float64}
end

StructTypes.StructType(::Type{HistoryDTO}) = StructTypes.Struct()

"""INIT_PAYLOAD: Sent once on WebSocket connection"""
struct InitPayload
    type::String
    static::StaticDTO
    disks::Vector{DiskDTO}
    history::HistoryDTO
    timestamp::Float64
end

StructTypes.StructType(::Type{InitPayload}) = StructTypes.Struct()

InitPayload(static, disks, history) = InitPayload("init", static, disks, history, time())

"""CPU instant values"""
struct CPUInstant
    freq_avg::Float64
    freq_max::Float64
    load1::Float64
    load5::Float64
    load15::Float64
    pressure_avg10::Float64
    ctxt_switches_ps::Float64
    interrupts_ps::Float64
    temp_package::Float64
    temp_max::Float64
end

StructTypes.StructType(::Type{CPUInstant}) = StructTypes.Struct()

"""Memory instant values"""
struct MemoryInstant
    total_kb::Int
    used_kb::Int
    avail_kb::Int
    swap_total_kb::Int
    swap_used_kb::Int
    pressure_avg10::Float64
end

StructTypes.StructType(::Type{MemoryInstant}) = StructTypes.Struct()

"""GPU instant values"""
struct GPUInstant
    name::String
    util::Float64
    mem_used::Float64
    mem_total::Float64
    temp::Float64
    power_draw::Float64
    power_limit::Float64
end

StructTypes.StructType(::Type{GPUInstant}) = StructTypes.Struct()

"""Network instant values"""
struct NetworkInstant
    primary_iface::String
    rx_bps::Float64
    tx_bps::Float64
    classification::String
    tcp_established::Int
    tcp_time_wait::Int
end

StructTypes.StructType(::Type{NetworkInstant}) = StructTypes.Struct()

"""Disk instant values"""
struct DiskInstant
    mount::String
    used_gb::Float64
    avail_gb::Float64
    percent::Float64
    read_bps::Float64
    write_bps::Float64
end

StructTypes.StructType(::Type{DiskInstant}) = StructTypes.Struct()

"""Battery instant values"""
struct BatteryInstant
    present::Bool
    percent::Float64
    status::String
    power_w::Float64
    time_remaining_min::Float64
end

StructTypes.StructType(::Type{BatteryInstant}) = StructTypes.Struct()

"""System instant values"""
struct SystemInstant
    uptime_sec::Float64
    environment::String
    oom_kills::Int
    psi_cpu::Float64
    psi_mem::Float64
    psi_io::Float64
    procs_running::Int
    procs_blocked::Int
end

StructTypes.StructType(::Type{SystemInstant}) = StructTypes.Struct()

"""Anomaly instant values"""
struct AnomalyInstant
    cpu::Float64
    mem::Float64
    io::Float64
    net::Float64
    gpu::Float64
    temp::Float64
    overall::Float64
    trend::String
    cpu_spike::Bool
    mem_spike::Bool
    io_spike::Bool
    net_spike::Bool
end

StructTypes.StructType(::Type{AnomalyInstant}) = StructTypes.Struct()

"""Top process info for updates"""
struct ProcessInstant
    pid::Int
    name::String
    cpu::Float64
    mem_kb::Float64
    state::Char
end

StructTypes.StructType(::Type{ProcessInstant}) = StructTypes.Struct()

"""UPDATE_PAYLOAD: Sent every loop iteration"""
struct UpdatePayload
    type::String
    cpu::CPUInstant
    memory::MemoryInstant
    gpu::Union{Nothing,GPUInstant}
    network::NetworkInstant
    disks::Vector{DiskInstant}
    battery::BatteryInstant
    system::SystemInstant
    anomaly::AnomalyInstant
    top_processes::Vector{ProcessInstant}
    update_count::Int
    timestamp::Float64
end

StructTypes.StructType(::Type{UpdatePayload}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,GPUInstant}}) = StructTypes.Struct()

# ============================
# CLIENT MANAGEMENT
# ============================

"""Thread-safe WebSocket client manager"""
mutable struct WebSocketClients
    clients::Set{HTTP.WebSockets.WebSocket}
    lock::ReentrantLock
end

WebSocketClients() = WebSocketClients(Set{HTTP.WebSockets.WebSocket}(), ReentrantLock())

const CLIENTS = WebSocketClients()

function add_client!(ws::HTTP.WebSockets.WebSocket)
    lock(CLIENTS.lock) do
        push!(CLIENTS.clients, ws)
    end
end

function remove_client!(ws::HTTP.WebSockets.WebSocket)
    lock(CLIENTS.lock) do
        delete!(CLIENTS.clients, ws)
    end
end

function get_clients()::Vector{HTTP.WebSockets.WebSocket}
    lock(CLIENTS.lock) do
        collect(CLIENTS.clients)
    end
end

# ============================
# PAYLOAD BUILDERS
# ============================

function build_init_payload(monitor::SystemMonitor)::InitPayload
    # Static info
    sc = monitor.static_cache
    static = StaticDTO(
        sc.cpu_model,
        sc.cpu_cache,
        sc.core_count,
        sc.kernel_version,
        sc.hostname
    )

    # Disk configuration
    disks = [DiskDTO(d.mount, d.total_gb) for d in monitor.disks]

    # Full history
    h = monitor.history
    history = HistoryDTO(
        copy(h.cpu_usage),
        copy(h.mem_usage),
        copy(h.net_rx),
        copy(h.net_tx),
        copy(h.gpu_util),
        copy(h.disk_io),
        copy(h.cpu_temp),
        copy(h.timestamps)
    )

    return InitPayload(static, disks, history)
end

function build_update_payload(monitor::SystemMonitor)::UpdatePayload
    ci = monitor.cpu_info
    cpu = CPUInstant(
        ci.freq_avg, ci.freq_max,
        ci.load1, ci.load5, ci.load15,
        ci.pressure_avg10,
        ci.ctxt_switches_ps, ci.interrupts_ps,
        ci.temperature.package, ci.temperature.max_temp
    )

    m = monitor.memory
    memory = MemoryInstant(
        m.total_kb, m.used_kb, m.avail_kb,
        m.swap_total_kb, m.swap_used_kb,
        m.pressure_avg10
    )

    gpu = if monitor.gpu !== nothing
        g = monitor.gpu
        GPUInstant(g.name, g.util, g.mem_used, g.mem_total, g.temp, g.power_draw, g.power_limit)
    else
        nothing
    end

    n = monitor.network
    network = NetworkInstant(
        n.primary_iface, n.rx_bps, n.tx_bps,
        n.classification,
        n.tcp.established, n.tcp.time_wait
    )

    disks = [DiskInstant(d.mount, d.used_gb, d.avail_gb, d.percent, d.read_bps, d.write_bps)
             for d in monitor.disks]

    b = monitor.battery
    battery = BatteryInstant(b.present, b.percent, b.status, b.power_w, b.time_remaining_min)

    s = monitor.system
    system = SystemInstant(
        s.uptime_sec, s.environment, s.oom_kills,
        s.psi_cpu, s.psi_mem, s.psi_io,
        s.procs_running, s.procs_blocked
    )

    a = monitor.anomaly
    anomaly = AnomalyInstant(
        a.cpu, a.mem, a.io, a.net, a.gpu, a.temp, a.overall,
        a.trend, a.cpu_spike, a.mem_spike, a.io_spike, a.net_spike
    )

    # Top 5 processes by CPU
    top_procs = sort(monitor.processes, by=p -> p.cpu, rev=true)[1:min(5, length(monitor.processes))]
    top_processes = [ProcessInstant(p.pid, p.name, p.cpu, p.mem_kb, p.state) for p in top_procs]

    return UpdatePayload(
        "update",
        cpu, memory, gpu, network, disks, battery, system, anomaly,
        top_processes,
        monitor.update_count,
        time()
    )
end

# ============================
# CORS MIDDLEWARE
# ============================

function cors_middleware(handler)
    return function (req::HTTP.Request)
        # Handle preflight
        if req.method == "OPTIONS"
            return HTTP.Response(204, [
                "Access-Control-Allow-Origin" => "*",
                "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers" => "Content-Type",
                "Access-Control-Max-Age" => "86400"
            ])
        end

        # Normal request
        response = handler(req)
        HTTP.setheader(response, "Access-Control-Allow-Origin" => "*")
        return response
    end
end

# ============================
# SERVER MANAGEMENT
# ============================

# Global reference to the monitor for WebSocket handler
const MONITOR_REF = Ref{Union{Nothing,SystemMonitor}}(nothing)

function set_monitor_ref!(monitor::SystemMonitor)
    MONITOR_REF[] = monitor
end

"""
Start the WebSocket server asynchronously on the specified port.
Returns the server task.
"""
function start_websocket_server!(port::Int=8080)
    @info "Starting WebSocket server on port $port..."

    # WebSocket endpoint
    @websocket "/ws" function (ws::HTTP.WebSockets.WebSocket)
        add_client!(ws)
        @info "Client connected. Total clients: $(length(get_clients()))"

        try
            # Send init payload if monitor is available
            if MONITOR_REF[] !== nothing
                init_json = JSON3.write(build_init_payload(MONITOR_REF[]))
                HTTP.WebSockets.send(ws, init_json)
            end

            # Keep connection alive, listen for client messages (ping/pong)
            while !eof(ws)
                try
                    msg = HTTP.WebSockets.receive(ws)
                    # Handle ping or ignore other messages
                    if msg == "ping"
                        HTTP.WebSockets.send(ws, "pong")
                    end
                catch e
                    if !(e isa EOFError || e isa HTTP.WebSockets.WebSocketError)
                        @warn "WebSocket receive error" exception = e
                    end
                    break
                end
            end
        catch e
            @warn "WebSocket error" exception = e
        finally
            remove_client!(ws)
            @info "Client disconnected. Total clients: $(length(get_clients()))"
        end
    end

    # Health check endpoint
    @get "/health" function ()
        return Dict("status" => "ok", "clients" => length(get_clients()))
    end

    # Start server in background task
    server_task = Threads.@spawn begin
        serve(host="0.0.0.0", port=port, middleware=[cors_middleware], async=false, show_banner=false)
    end

    @info "WebSocket server started on ws://0.0.0.0:$port/ws"
    return server_task
end

"""
Broadcast UPDATE_PAYLOAD to all connected WebSocket clients.
Non-blocking: errors on individual clients don't affect others.
"""
function broadcast_update!(monitor::SystemMonitor)
    clients = get_clients()
    isempty(clients) && return

    # Build payload once
    payload_json = JSON3.write(build_update_payload(monitor))

    # Send to all clients
    for ws in clients
        try
            HTTP.WebSockets.send(ws, payload_json)
        catch e
            # Client probably disconnected, will be cleaned up
            @debug "Failed to send to client" exception = e
        end
    end
end
