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
# SERVER CONFIGURATION (from Config.jl)
# ============================

# These read from the centralized SERVER_CONFIG (loaded by main.jl)
# Aliases for backward compatibility and cleaner code
get_max_clients() = SERVER_CONFIG.max_clients
get_send_timeout() = SERVER_CONFIG.send_timeout_sec
get_max_message_size() = SERVER_CONFIG.max_message_size
get_rate_limit_window() = SERVER_CONFIG.rate_limit_window_sec
get_rate_limit_max() = SERVER_CONFIG.rate_limit_max_messages
get_allowed_origins() = SERVER_CONFIG.allowed_origins

# Server state for graceful shutdown
const SERVER_RUNNING = Ref{Bool}(true)

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
    # IOPS and latency metrics
    read_iops::Float64
    write_iops::Float64
    avg_wait_ms::Float64
    io_wait_pct::Float64
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

"""Prediction DTO for AI time-to-critical predictions"""
struct PredictionDTO
    metric::String
    time_to_critical_sec::Float64
    confidence::Float64
end

StructTypes.StructType(::Type{PredictionDTO}) = StructTypes.Struct()

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
    # Per-metric trends
    cpu_trend::String
    mem_trend::String
    io_trend::String
    net_trend::String
    # Regime detection
    regime::String
    # AI predictions
    predictions::Vector{PredictionDTO}
    # Coherence alerts
    coherence_temp_alert::Bool
    coherence_io_alert::Bool
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

"""Hardware health status for frontend (NEW)"""
struct HardwareHealthDTO
    thermal_efficiency::Float64     # 0.0 - 1.0
    fan_status::String              # "healthy", "degraded", "failing", "stopped"
    voltage_stability::Float64      # 0.0 - 1.0
    cooling_headroom::Float64       # Degrees before throttle
    primary_fan_rpm::Int
    vcore_voltage::Float64
    dry_thermal_paste::Bool
    dusty_fan::Bool
    unstable_voltage::Bool
    diagnostics::Vector{String}
end

StructTypes.StructType(::Type{HardwareHealthDTO}) = StructTypes.Struct()

"""Cognitive AI insights for frontend (NEW)"""
struct CognitiveInsightsDTO
    iforest_score::Float64
    oscillation_detected::Bool
    oscillation_type::String
    spectral_entropy_cpu::Float64
    spectral_entropy_fan::Float64
    behavioral_state::String
    behavioral_anomaly::Bool
    behavioral_description::String
    state_stability::Float64
end

StructTypes.StructType(::Type{CognitiveInsightsDTO}) = StructTypes.Struct()

# ============================
# FULL SENSORS DTO (NEW)
# ============================

"""Extended CPU temperatures DTO"""
struct CPUTempsDTO
    tctl::Float64
    tdie::Float64
    tccd::Vector{Float64}
    tccd_max::Float64
    package::Float64
    cores::Vector{Float64}
    critical::Float64
end

StructTypes.StructType(::Type{CPUTempsDTO}) = StructTypes.Struct()

"""GPU sensors DTO"""
struct GPUSensorsDTO
    edge_temp::Float64
    hotspot_temp::Float64
    mem_temp::Float64
    vdd_voltage::Float64
    power_w::Float64
    ppt_limit::Float64
end

StructTypes.StructType(::Type{GPUSensorsDTO}) = StructTypes.Struct()

"""NVMe sensor DTO"""
struct NVMeSensorDTO
    name::String
    temp_composite::Float64
    temp_sensor1::Float64
    temp_sensor2::Float64
end

StructTypes.StructType(::Type{NVMeSensorDTO}) = StructTypes.Struct()

"""Generic temperature DTO"""
struct TempDTO
    label::String
    value::Float64
    chip::String
    index::Int
end

StructTypes.StructType(::Type{TempDTO}) = StructTypes.Struct()

"""Voltage DTO"""
struct VoltageDTO
    label::String
    value::Float64
    chip::String
    index::Int
end

StructTypes.StructType(::Type{VoltageDTO}) = StructTypes.Struct()

"""Fan DTO"""
struct FanDTO
    label::String
    rpm::Int
    chip::String
    index::Int
end

StructTypes.StructType(::Type{FanDTO}) = StructTypes.Struct()

"""Full sensors aggregate DTO"""
struct FullSensorsDTO
    cpu_temps::CPUTempsDTO
    gpu_sensors::Union{Nothing,GPUSensorsDTO}
    nvme_sensors::Vector{NVMeSensorDTO}
    voltages::Vector{VoltageDTO}
    fans::Vector{FanDTO}
    temps_generic::Vector{TempDTO}
    chip_names::Vector{String}
end

StructTypes.StructType(::Type{FullSensorsDTO}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,GPUSensorsDTO}}) = StructTypes.Struct()

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
    hardware_health::Union{Nothing,HardwareHealthDTO}
    cognitive::Union{Nothing,CognitiveInsightsDTO}
    full_sensors::Union{Nothing,FullSensorsDTO}  # NEW
    update_count::Int
    timestamp::Float64
end

StructTypes.StructType(::Type{UpdatePayload}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,GPUInstant}}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,HardwareHealthDTO}}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,CognitiveInsightsDTO}}) = StructTypes.Struct()
StructTypes.StructType(::Type{Union{Nothing,FullSensorsDTO}}) = StructTypes.Struct()

# ============================
# CLIENT MANAGEMENT (Thread-Safe)
# ============================

"""Per-client rate limiting state"""
mutable struct ClientState
    ws::HTTP.WebSockets.WebSocket
    message_count::Int
    window_start::Float64
end

ClientState(ws) = ClientState(ws, 0, time())

"""Thread-safe WebSocket client manager with limits and rate tracking"""
mutable struct WebSocketClients
    clients::Dict{HTTP.WebSockets.WebSocket,ClientState}
    lock::ReentrantLock
end

WebSocketClients() = WebSocketClients(Dict{HTTP.WebSockets.WebSocket,ClientState}(), ReentrantLock())

const CLIENTS = WebSocketClients()

"""
Add client with MAX_CLIENTS limit.
Returns true if added, false if rejected (limit reached).
"""
function add_client!(ws::HTTP.WebSockets.WebSocket)::Bool
    lock(CLIENTS.lock) do
        if length(CLIENTS.clients) >= get_max_clients()
            @warn "Client rejected: max clients $(get_max_clients()) reached"
            return false
        end
        CLIENTS.clients[ws] = ClientState(ws)
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
        collect(keys(CLIENTS.clients))
    end
end

function get_client_count()::Int
    lock(CLIENTS.lock) do
        length(CLIENTS.clients)
    end
end

"""
Check rate limit for client. Returns true if allowed, false if rate exceeded.
Also updates the rate counter.
"""
function check_rate_limit!(ws::HTTP.WebSockets.WebSocket)::Bool
    lock(CLIENTS.lock) do
        state = get(CLIENTS.clients, ws, nothing)
        state === nothing && return false

        now = time()

        # Reset window if expired
        if now - state.window_start >= get_rate_limit_window()
            state.message_count = 0
            state.window_start = now
        end

        state.message_count += 1

        if state.message_count > get_rate_limit_max()
            @warn "Rate limit exceeded: $(state.message_count) messages in $(get_rate_limit_window())s"
            return false
        end

        return true
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
    timedwait(() -> istaskdone(task), get_send_timeout())

    if !istaskdone(task)
        @warn "Send timeout after $(get_send_timeout())s, client will be removed"
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

    # Disks - create new immutable structs with IO metrics
    disks = [
        begin
            # Find matching IO metrics by mount point
            io_data = get(monitor.disk_io, d.mount, nothing)
            DiskInstant(
                String(d.mount),
                Float64(d.used_gb),
                Float64(d.avail_gb),
                Float64(d.percent),
                Float64(d.read_bps),
                Float64(d.write_bps),
                io_data !== nothing ? Float64(io_data.read_iops) : 0.0,
                io_data !== nothing ? Float64(io_data.write_iops) : 0.0,
                io_data !== nothing ? Float64(io_data.avg_wait_ms) : 0.0,
                io_data !== nothing ? Float64(io_data.io_wait_pct) : 0.0
            )
        end
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

    # Anomaly - copy all values with AI enrichment
    a = monitor.anomaly
    ai_state = get_ai_state()
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
        Bool(a.net_spike),
        # Per-metric trends
        String(a.cpu_trend),
        String(a.mem_trend),
        String(a.io_trend),
        String(a.net_trend),
        # Regime from AI state
        String(get_current_regime()),
        # Predictions
        [PredictionDTO(String(p.metric), Float64(p.time_to_critical_sec), Float64(p.confidence))
         for p in a.predictions],
        # Coherence alerts
        Bool(ai_state.coherence.temp_without_load),
        Bool(ai_state.coherence.latency_without_io)
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

    # Hardware health (NEW)
    hardware_health = if monitor.hardware !== nothing
        hw = monitor.hardware
        health = get_hardware_health()
        HardwareHealthDTO(
            Float64(health.thermal_efficiency),
            fan_status_string(health.fan_status),
            Float64(health.voltage_stability),
            Float64(health.cooling_headroom),
            Int(hw.primary_cpu_fan_rpm),
            Float64(hw.vcore_voltage),
            Bool(health.dry_thermal_paste),
            Bool(health.dusty_fan),
            Bool(health.unstable_voltage),
            copy(health.diagnostics)
        )
    else
        nothing
    end

    # Cognitive Insights (NEW)
    cognitive = try
        # Oscillation type
        oscillation_type = if ai_state.cpu_oscillation_detected
            "CPU Throttling"
        elseif ai_state.fan_hunting_detected
            "Fan Hunting"
        else
            "None"
        end

        # Spectral entropy
        cpu_spec = get_spectral_result(ai_state.fft_cpu)
        fan_spec = get_spectral_result(ai_state.fft_fan)

        # Behavioral stability
        beh_res = get_behavioral_result(ai_state.markov)

        CognitiveInsightsDTO(
            Float64(ai_state.iforest_score),
            Bool(ai_state.cpu_oscillation_detected || ai_state.fan_hunting_detected),
            String(oscillation_type),
            Float64(cpu_spec.spectral_entropy),
            Float64(fan_spec.spectral_entropy),
            state_name(ai_state.markov.current_state),
            Bool(ai_state.behavioral_anomaly),
            String(ai_state.behavioral_anomaly_desc),
            Float64(beh_res.state_stability)
        )
    catch e
        # Fallback if AI state isn't fully initialized
        CognitiveInsightsDTO(0.0, false, "None", 0.0, 0.0, "Unknown", false, "", 1.0)
    end

    # Full Sensors (NEW)
    full_sensors = if monitor.full_sensors !== nothing
        fs = monitor.full_sensors

        # Build CPU temps DTO
        cpu_temps_dto = CPUTempsDTO(
            Float64(fs.cpu_temps.tctl),
            Float64(fs.cpu_temps.tdie),
            copy(fs.cpu_temps.tccd),
            Float64(fs.cpu_temps.tccd_max),
            Float64(fs.cpu_temps.package),
            copy(fs.cpu_temps.cores),
            Float64(fs.cpu_temps.critical)
        )

        # Build GPU sensors DTO
        gpu_sensors_dto = if fs.gpu_sensors !== nothing
            gs = fs.gpu_sensors
            GPUSensorsDTO(
                Float64(gs.edge_temp),
                Float64(gs.hotspot_temp),
                Float64(gs.mem_temp),
                Float64(gs.vdd_voltage),
                Float64(gs.power_w),
                Float64(gs.ppt_limit)
            )
        else
            nothing
        end

        # Build NVMe DTOs
        nvme_dtos = [
            NVMeSensorDTO(String(n.name), Float64(n.temp_composite), Float64(n.temp_sensor1), Float64(n.temp_sensor2))
            for n in fs.nvme_sensors
        ]

        # Build voltage DTOs
        voltage_dtos = [
            VoltageDTO(String(v.label), Float64(v.value), String(v.chip), Int(v.index))
            for v in fs.voltages
        ]

        # Build fan DTOs
        fan_dtos = [
            FanDTO(String(f.label), Int(f.rpm), String(f.chip), Int(f.index))
            for f in fs.fans
        ]

        # Build temp DTOs
        temp_dtos = [
            TempDTO(String(t.label), Float64(t.value), String(t.chip), Int(t.index))
            for t in fs.temps_generic
        ]

        FullSensorsDTO(
            cpu_temps_dto,
            gpu_sensors_dto,
            nvme_dtos,
            voltage_dtos,
            fan_dtos,
            temp_dtos,
            copy(fs.chip_names)
        )
    else
        nothing
    end

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
        hardware_health,
        cognitive,
        full_sensors,
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
        allowed = get_allowed_origins()

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
    @info "Starting WebSocket server on port $port (max clients: $(get_max_clients()))..."

    # WebSocket endpoint
    @websocket "/ws" function (ws::HTTP.WebSockets.WebSocket)
        # Check server state
        if !SERVER_RUNNING[]
            try
                HTTP.WebSockets.send(ws, """{"type":"error","message":"Server shutting down"}""")
            catch
            end
            safe_close(ws)
            return
        end

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
            # Note: HTTP.jl WebSocket doesn't have eof() or isopen()
            # Use infinite loop with exception-based termination
            while SERVER_RUNNING[]
                local msg
                try
                    msg = HTTP.WebSockets.receive(ws)
                catch e
                    # Connection closed (normal) or error
                    if !(e isa EOFError || e isa HTTP.WebSockets.WebSocketError)
                        @debug "WebSocket closed" exception = e
                    end
                    break
                end

                # Message size limit check
                if length(msg) > get_max_message_size()
                    @warn "Message too large: $(length(msg)) bytes (max: $(get_max_message_size()))"
                    safe_send(ws, """{"type":"error","message":"Message too large"}""")
                    break  # Close connection
                end

                # Rate limit check
                if !check_rate_limit!(ws)
                    safe_send(ws, """{"type":"error","message":"Rate limit exceeded"}""")
                    break  # Close connection
                end

                # Handle valid messages
                if msg == "ping"
                    safe_send(ws, "pong")
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
            "max_clients" => get_max_clients()
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

# ============================
# GRACEFUL SHUTDOWN
# ============================

"""
Gracefully shutdown the WebSocket server.
Sends close frame (1001 Going Away) to all clients.
"""
function stop_server!()
    @info "Initiating graceful shutdown..."

    # Mark server as stopping
    SERVER_RUNNING[] = false

    # Get all clients
    clients = get_clients()

    @info "Closing $(length(clients)) client connections..."

    # Send close message to all clients
    for ws in clients
        try
            # Send shutdown notification
            safe_send(ws, """{"type":"shutdown","message":"Server shutting down"}""")
            # Close with 1001 Going Away
            HTTP.WebSockets.close(ws, HTTP.WebSockets.CloseFrameBody(1001, "Server shutting down"))
        catch e
            @debug "Error closing client" exception = e
        end
        remove_client!(ws)
    end

    @info "All clients disconnected. Server stopped."
end
