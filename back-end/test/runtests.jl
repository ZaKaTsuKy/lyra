# test/runtests.jl
# ============================
# OMNI MONITOR - Test Suite
# ============================
# Run with: julia --project=. test/runtests.jl
# ============================

using Test
using Statistics

# Load configuration first
include("../config/Config.jl")
include("../types/MonitorTypes.jl")

@testset "OMNI Monitor Tests" begin

    @testset "MonitorTypes" begin
        @testset "EMATracker" begin
            tracker = EMATracker(0.1)
            @test !tracker.initialized
            @test tracker.sample_count == 0

            # First update initializes
            update_ema!(tracker, 10.0)
            @test tracker.initialized
            @test tracker.value ≈ 10.0
            @test tracker.sample_count == 1

            # Subsequent updates apply EMA
            update_ema!(tracker, 20.0)
            @test tracker.value > 10.0
            @test tracker.value < 20.0
            @test tracker.sample_count == 2
        end

        @testset "RateTracker" begin
            tracker = RateTracker()
            @test tracker.rate == 0.0

            # Simulate counter updates
            tracker.prev_value = 100
            tracker.prev_time = time() - 1.0

            rate = update_rate!(tracker, 200)
            @test rate ≈ 100.0 atol = 5.0  # ~100/s with small timing variance
        end

        @testset "MetricHistory" begin
            history = MetricHistory()
            @test length(history.cpu_usage) == 0

            # Push some metrics
            push_metric!(history, 50.0, 60.0, 1000.0, 500.0, 30.0, 100.0, 45.0)
            @test length(history.cpu_usage) == 1
            @test history.cpu_usage[1] == 50.0
            @test history.cpu_temp[1] == 45.0
        end

        @testset "SystemMonitor Initialization" begin
            monitor = SystemMonitor()
            @test monitor.update_count == 0
            @test length(monitor.cores) == Sys.CPU_THREADS
            @test monitor.gpu === nothing
            @test monitor.hardware === nothing
        end

        @testset "Utility Functions" begin
            @test format_bytes(1024) == "1.0 KB"
            @test format_bytes(1048576) == "1.0 MB"
            @test format_bytes(1073741824) == "1.0 GB"

            @test format_duration(3661) == "1h 01m 01s"
            @test format_duration(86461) == "1d 00h 01m"

            @test format_time_remaining(Inf) == "∞"
            @test format_time_remaining(30.0) == "30s"
            @test format_time_remaining(180.0) == "3m"
        end
    end

    @testset "Configuration" begin
        @testset "APP_CONFIG defaults" begin
            @test APP_CONFIG.refresh_interval == 0.5
            @test APP_CONFIG.enable_gpu == true
            @test APP_CONFIG.max_iterations === nothing
        end

        @testset "SERVER_CONFIG defaults" begin
            @test SERVER_CONFIG.port == 8080
            @test SERVER_CONFIG.max_clients == 50
            @test SERVER_CONFIG.send_timeout_sec == 5.0
        end

        @testset "AI_CONFIG defaults" begin
            @test AI_CONFIG.cpu_critical == 95.0
            @test AI_CONFIG.zscore_warning == 2.5
            @test AI_CONFIG.saturation_knee_ratio == 0.8
        end
    end
end

println("\n✅ All tests passed!")
