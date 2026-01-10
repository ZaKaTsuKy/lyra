# WebSocketServer.jl
# ============================
# OMNI MONITOR - WebSocket Server v2.0
# ============================
# Hardened implementation with:
# - MAX_CLIENTS limit (DoS protection)
# - Configurable CORS origins
# - safe_send with timeout
# - Atomic snapshot pattern (thread-safe)
# ============================

using Oxygen
using HTTP
using JSON3
using StructTypes

# ============================
# SERVER CONFIGURATION
# ============================

const MAX_CLIENTS = 50
const SEND_TIMEOUT_SEC = 5.0
const ALLOWED_ORIGINS = Ref{Vector{String}}(["*"])

"""Set allowed CORS origins. Use ["*"] for dev, specific origins for prod."""
function set_allowed_origins!(origins::Vector{String})
    ALLOWED_ORIGINS[] = origins
end

# ============================
# DTO STRUCTURES (Immutable JSON Payloads)
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

"""CPU instant values (immutable deep copy)"""
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

"""Memory instant values (immutable deep copy)"""
struct MemoryInstant
    total_kb::Int
    used_kb::Int
    avail_kb::Int
    swap_total_kb::Int
    swap_used_kb::Int
    pressure_avg10::Float64
end

StructTypes.StructType(::Type{MemoryInstant}) = StructTypes.Struct()

"""GPU instant values (immutable deep copy)"""
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

"""Network instant values (immutable deep copy)"""
struct NetworkInstant
    primary_iface::String
    rx_bps::Float64
    tx_bps::Float64
    classification::String
    tcp_established::Int
    tcp_time_wait::Int
end

StructTypes.StructType(::Type{NetworkInstant}) = StructTypes.Struct()

"""Disk instant values (immutable deep copy)"""
struct DiskInstant
    mount::String
    used_gb::Float64
    avail_gb::Float64
    percent::Float64
    read_bps::Float64
    write_bps::Float64
end

StructTypes.StructType(::Type{DiskInstant}) = StructTypes.Struct()

"""Battery instant values (immutable deep copy)"""
struct BatteryInstant
    present::Bool
    percent::Float64
    status::String
    power_w::Float64
    time_remaining_min::Float64
end

StructTypes.StructType(::Type{BatteryInstant}) = StructTypes.Struct()

"""System instant values (immutable deep copy)"""
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

"""Anomaly instant values (immutable deep copy)"""
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

"""Top process info (immutable deep copy)"""
struct ProcessInstant
    pid::Int
    name::String
    cpu::Float64
    mem_kb::Float64
    state::Char
end

StructTypes.StructType(::Type{ProcessInstant}) = StructTypes.Struct()

"""UPDATE_PAYLOAD: Sent every loop iteration (fully immutable)"""
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
# CLIENT MANAGEMENT (Thread-Safe)
# ============================

"""Thread-safe WebSocket client manager with limits"""
mutable struct WebSocketClients
    clients::Set{HTTP.WebSockets.WebSocket}
    lock::ReentrantLock
end

WebSocketClients() = WebSocketClients(Set{HTTP.WebSockets.WebSocket}(), ReentrantLock())

const CLIENTS = WebSocketClients()

"""
Add client with MAX_CLIENTS limit.
Returns true if added, false if rejected (limit reached).
"""
function add_client!(ws::HTTP.WebSockets.WebSocket)::Bool
    lock(CLIENTS.lock) do
        if length(CLIENTS.clients) >= MAX_CLIENTS
            @warn "Client rejected: MAX_CLIENTS ($MAX_CLIENTS) reached"
            return false
        end
        push!(CLIENTS.clients, ws)
        return true
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

function get_client_count()::Int
    lock(CLIENTS.lock) do
        length(CLIENTS.clients)
    end
end

# ============================
# SAFE SEND WITH TIMEOUT
# ============================

"""
Send data to WebSocket with timeout protection.
Returns true on success, false on timeout or error.
"""
function safe_send(ws::HTTP.WebSockets.WebSocket, data::String)::Bool
    result = Ref(false)

    task = @async begin
        try
            HTTP.WebSockets.send(ws, data)
            result[] = true
        catch e
            @debug "Send failed" exception = e
        end
    end

    # Wait with timeout
    timedwait(() -> istaskdone(task), SEND_TIMEOUT_SEC)

    if !istaskdone(task)
        @warn "Send timeout after $(SEND_TIMEOUT_SEC)s, client will be removed"
        # Note: Task may complete later, but we treat it as failed
    end

    return result[]
end

"""Close WebSocket safely, ignoring errors"""
function safe_close(ws::HTTP.WebSockets.WebSocket)
    try
        close(ws)
    catch
        # Ignore close errors
    end
end

# ============================
# SNAPSHOT BUILDERS (Deep Copy)
# ============================

"""
Create immutable INIT payload from monitor.
Deep copies all data to ensure thread-safety.
"""
function build_init_payload(monitor::SystemMonitor)::InitPayload
    # Static info (strings are immutable)
    sc = monitor.static_cache
    static = StaticDTO(
        sc.cpu_model,
        sc.cpu_cache,
        sc.core_count,
        sc.kernel_version,
        sc.hostname
    )

    # Disk configuration (deep copy)
    disks = [DiskDTO(d.mount, d.total_gb) for d in monitor.disks]

    # Full history (deep copy vectors)
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

"""
Create immutable UPDATE payload (snapshot) from monitor.
CRITICAL: All values are deep-copied by value, no references to mutable structs.
This snapshot is safe for async serialization in another thread.
"""
function create_snapshot(monitor::SystemMonitor)::UpdatePayload
    # CPU - copy all primitive values
    ci = monitor.cpu_info
    cpu = CPUInstant(
        Float64(ci.freq_avg),
        Float64(ci.freq_max),
        Float64(ci.load1),
        Float64(ci.load5),
        Float64(ci.load15),
        Float64(ci.pressure_avg10),
        Float64(ci.ctxt_switches_ps),
        Float64(ci.interrupts_ps),
        Float64(ci.temperature.package),
        Float64(ci.temperature.max_temp)
    )

    # Memory - copy all primitive values
    m = monitor.memory
    memory = MemoryInstant(
        Int(m.total_kb),
        Int(m.used_kb),
        Int(m.avail_kb),
        Int(m.swap_total_kb),
        Int(m.swap_used_kb),
        Float64(m.pressure_avg10)
    )

    # GPU - deep copy if present
    gpu = if monitor.gpu !== nothing
        g = monitor.gpu
        GPUInstant(
            String(g.name),
            Float64(g.util),
            Float64(g.mem_used),
            Float64(g.mem_total),
            Float64(g.temp),
            Float64(g.power_draw),
            Float64(g.power_limit)
        )
    else
        nothing
    end

    # Network - copy all values
    n = monitor.network
    network = NetworkInstant(
        String(n.primary_iface),
        Float64(n.rx_bps),
        Float64(n.tx_bps),
        String(n.classification),
        Int(n.tcp.established),
        Int(n.tcp.time_wait)
    )

    # Disks - create new immutable structs
    disks = [
        DiskInstant(
            String(d.mount),
            Float64(d.used_gb),
            Float64(d.avail_gb),
            Float64(d.percent),
            Float64(d.read_bps),
            Float64(d.write_bps)
        )
        for d in monitor.disks
    ]

    # Battery - copy all values
    b = monitor.battery
    battery = BatteryInstant(
        Bool(b.present),
        Float64(b.percent),
        String(b.status),
        Float64(b.power_w),
        Float64(b.time_remaining_min)
    )

    # System - copy all values
    s = monitor.system
    system = SystemInstant(
        Float64(s.uptime_sec),
        String(s.environment),
        Int(s.oom_kills),
        Float64(s.psi_cpu),
        Float64(s.psi_mem),
        Float64(s.psi_io),
        Int(s.procs_running),
        Int(s.procs_blocked)
    )

    # Anomaly - copy all values
    a = monitor.anomaly
    anomaly = AnomalyInstant(
        Float64(a.cpu),
        Float64(a.mem),
        Float64(a.io),
        Float64(a.net),
        Float64(a.gpu),
        Float64(a.temp),
        Float64(a.overall),
        String(a.trend),
        Bool(a.cpu_spike),
        Bool(a.mem_spike),
        Bool(a.io_spike),
        Bool(a.net_spike)
    )

    # Top 5 processes - deep copy
    procs_sorted = sort(monitor.processes, by=p -> p.cpu, rev=true)
    top_processes = [
        ProcessInstant(
            Int(p.pid),
            String(p.name),
            Float64(p.cpu),
            Float64(p.mem_kb),
            Char(p.state)
        )
        for p in procs_sorted[1:min(5, length(procs_sorted))]
    ]

    return UpdatePayload(
        "update",
        cpu,
        memory,
        gpu,
        network,
        disks,
        battery,
        system,
        anomaly,
        top_processes,
        Int(monitor.update_count),
        Float64(time())
    )
end

# Legacy alias for compatibility
build_update_payload(monitor::SystemMonitor) = create_snapshot(monitor)

# ============================
# CORS MIDDLEWARE (Configurable)
# ============================

function cors_middleware(handler)
    return function (req::HTTP.Request)
        origin = HTTP.header(req, "Origin", "*")
        allowed = ALLOWED_ORIGINS[]

        # Check if origin is allowed
        allow_origin = if "*" in allowed
            "*"
        elseif origin in allowed
            origin
        else
            ""  # Not allowed
        end

        # Handle preflight
        if req.method == "OPTIONS"
            return HTTP.Response(204, [
                "Access-Control-Allow-Origin" => allow_origin,
                "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers" => "Content-Type",
                "Access-Control-Max-Age" => "86400"
            ])
        end

        # Normal request
        response = handler(req)
        if !isempty(allow_origin)
            HTTP.setheader(response, "Access-Control-Allow-Origin" => allow_origin)
        end
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
    @info "Starting WebSocket server on port $port (max clients: $MAX_CLIENTS)..."

    # WebSocket endpoint
    @websocket "/ws" function (ws::HTTP.WebSockets.WebSocket)
        # Check client limit
        if !add_client!(ws)
            # Reject: send error and close
            try
                HTTP.WebSockets.send(ws, """{"type":"error","message":"Server full"}""")
            catch
            end
            safe_close(ws)
            return
        end

        @info "Client connected. Total clients: $(get_client_count())"

        try
            # Send init payload if monitor is available
            if MONITOR_REF[] !== nothing
                init_json = JSON3.write(build_init_payload(MONITOR_REF[]))
                if !safe_send(ws, init_json)
                    @warn "Failed to send init payload"
                    return
                end
            end

            # Keep connection alive, listen for client messages
            while !eof(ws)
                try
                    msg = HTTP.WebSockets.receive(ws)
                    if msg == "ping"
                        safe_send(ws, "pong")
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
            @info "Client disconnected. Total clients: $(get_client_count())"
        end
    end

    # Health check endpoint
    @get "/health" function ()
        return Dict(
            "status" => "ok",
            "clients" => get_client_count(),
            "max_clients" => MAX_CLIENTS
        )
    end

    # Start server in background task
    server_task = Threads.@spawn begin
        serve(host="0.0.0.0", port=port, middleware=[cors_middleware], async=false, show_banner=false)
    end

    @info "WebSocket server started on ws://0.0.0.0:$port/ws"
    return server_task
end

# ============================
# ASYNC BROADCAST (Thread-Safe)
# ============================

"""
Broadcast UPDATE_PAYLOAD to all connected WebSocket clients.
ASYNC: JSON serialization happens in spawned task, not main loop.
Uses immutable snapshot to prevent race conditions.
"""
function broadcast_async!(snapshot::UpdatePayload)
    clients = get_clients()
    isempty(clients) && return nothing

    Threads.@spawn begin
        # Serialize in async context (not blocking main loop)
        json = try
            JSON3.write(snapshot)
        catch e
            @error "JSON serialization failed" exception = e
            return
        end

        failed_clients = HTTP.WebSockets.WebSocket[]

        for ws in clients
            if !safe_send(ws, json)
                push!(failed_clients, ws)
            end
        end

        # Cleanup failed clients
        for ws in failed_clients
            remove_client!(ws)
            safe_close(ws)
            @debug "Removed slow/dead client"
        end
    end

    return nothing
end

# Legacy function - now just creates snapshot and broadcasts async
function broadcast_update!(monitor::SystemMonitor)
    snapshot = create_snapshot(monitor)
    broadcast_async!(snapshot)
end
