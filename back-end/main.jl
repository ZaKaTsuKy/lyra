# main.jl
# ============================
# OMNI MONITOR - Main Entry Point
# ============================
# AI-oriented system monitoring dashboard for Linux
# 
# Usage: julia main.jl
# ============================

using Dates
using Printf
using Statistics: mean

# ============================
# LOAD MODULES
# ============================

# Core types
include("types/MonitorTypes.jl")

# Linux collectors
include("OS/Linux/CPU.jl")
include("OS/Linux/Memory.jl")
include("OS/Linux/GPU.jl")
include("OS/Linux/Network.jl")
include("OS/Linux/DiskSpace.jl")
include("OS/Linux/DiskIO.jl")
include("OS/Linux/Processes.jl")
include("OS/Linux/Battery.jl")
include("OS/Linux/SystemUtils.jl")
include("OS/Linux/AI.jl")

# UI
include("ui/UI.jl")

# WebSocket Server
include("server/WebSocketServer.jl")

# ============================
# CONFIGURATION
# ============================

const CONFIG = (
    refresh_interval=0.5,  # seconds
    enable_gpu=true,
    enable_battery=true,
    enable_processes=true,
    max_iterations=nothing,  # nothing = infinite
    websocket_port=8080,  # WebSocket server port
)

# ============================
# MAIN LOOP
# ============================

function collect_all_metrics!(monitor::SystemMonitor)
    # CPU
    update_cpu!(monitor)

    # Memory
    update_memory!(monitor)

    # Disk
    update_disk!(monitor)

    # Network
    update_network!(monitor)

    # GPU (optional)
    if CONFIG.enable_gpu
        update_gpu!(monitor)
    end

    # Processes (optional)
    if CONFIG.enable_processes
        update_processes!(monitor)
    end

    # Battery (optional)
    if CONFIG.enable_battery
        update_battery!(monitor)
    end

    # System info
    update_system!(monitor)

    # AI anomaly detection
    update_anomaly!(monitor)

    # Update timestamp
    monitor.last_update = time()
    monitor.update_count += 1

    return nothing
end

function run_monitor()
    # Initialize monitor
    monitor = SystemMonitor()

    # Set monitor reference for WebSocket server
    set_monitor_ref!(monitor)

    # Start WebSocket server asynchronously
    server_task = start_websocket_server!(CONFIG.websocket_port)

    # Hide cursor for cleaner display
    hide_cursor()

    iteration = 0

    try
        while true
            iteration += 1

            # Check iteration limit
            if CONFIG.max_iterations !== nothing && iteration > CONFIG.max_iterations
                break
            end

            # Collect all metrics
            try
                collect_all_metrics!(monitor)
            catch e
                @warn "Error collecting metrics" exception = e
            end

            # Create atomic snapshot BEFORE any async operations
            # This deep-copies all values to prevent race conditions
            snapshot = create_snapshot(monitor)

            # Render dashboard (sync - uses monitor directly, safe here)
            try
                render_dashboard(monitor)
            catch e
                @warn "Error rendering dashboard" exception = e
                # Try basic output
                println("Update #$(monitor.update_count) - Collecting metrics...")
            end

            # Async broadcast using immutable snapshot
            # JSON serialization happens in spawned task, non-blocking
            broadcast_async!(snapshot)

            # Wait for next refresh
            sleep(CONFIG.refresh_interval)
        end
    catch e
        if isa(e, InterruptException)
            println("\n\nShutting down...")
        else
            rethrow(e)
        end
    finally
        # Always show cursor on exit
        show_cursor()
        println("\nOmni Monitor stopped.")
    end
end

# ============================
# CLI INTERFACE
# ============================

function print_help()
    println("""
    OMNI MONITOR - AI-oriented System Dashboard

    Usage: julia main.jl [options]

    Options:
        --help, -h      Show this help message
        --once          Run once and exit (for debugging)
        --no-gpu        Disable GPU monitoring
        --no-battery    Disable battery monitoring
        --no-processes  Disable process monitoring
        --port PORT     WebSocket server port (default: 8080)

    Controls:
        Ctrl+C          Exit the monitor

    Requirements:
        - Linux system
        - Julia 1.9+
        - Term.jl package
        - (Optional) nvidia-smi for GPU monitoring
    """)
end

function main(args=ARGS)
    # Parse arguments
    if "--help" in args || "-h" in args
        print_help()
        return
    end

    # Apply CLI options
    if "--no-gpu" in args
        @eval CONFIG = merge(CONFIG, (enable_gpu=false,))
    end
    if "--no-battery" in args
        @eval CONFIG = merge(CONFIG, (enable_battery=false,))
    end
    if "--no-processes" in args
        @eval CONFIG = merge(CONFIG, (enable_processes=false,))
    end
    if "--once" in args
        @eval CONFIG = merge(CONFIG, (max_iterations=1,))
    end

    # Parse --port argument
    for (i, arg) in enumerate(args)
        if arg == "--port" && i < length(args)
            port = tryparse(Int, args[i+1])
            if port !== nothing
                @eval CONFIG = merge(CONFIG, (websocket_port=$port,))
            end
        end
    end

    # Check platform
    if !Sys.islinux()
        println("Warning: This monitor is designed for Linux. Some features may not work.")
    end

    # Run
    run_monitor()
end

# ============================
# ENTRY POINT
# ============================

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
