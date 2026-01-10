# OS/Linux/AI.jl
# ============================
# AI Anomaly Detection Module v3.0
# ============================
# Architecture probabiliste et statistique robuste (O(1) mémoire)
# 
# Implémente:
# - T-Digest pour centiles (P50, P95, P99) en streaming
# - Algorithme de Welford pour variance en ligne
# - MAD (Median Absolute Deviation) pour Z-Score robuste
# - Holt-Winters (Triple Lissage Exponentiel) pour saisonnalité
# - ADWIN pour détection de changement de régime
# - CUSUM pour détection de dérives lentes
# - Analyse multivariée et cohérence physique
# - Échantillonnage adaptatif (feedback loop)
# - Modèle de saturation asymptotique (Loi de Little)
# ============================

using Statistics: mean, std, median

# ============================
# CONFIGURATION
# ============================

const AI_CONFIG = (
    cpu_critical = 95.0,
    mem_critical = 95.0,
    temp_critical = 95.0,
    zscore_warning = 2.5,
    zscore_critical = 3.5,
    cusum_threshold = 5.0,
    cusum_drift = 0.5,
    adwin_delta = 0.002,
    adwin_min_window = 30,
    hw_alpha = 0.3,
    hw_beta = 0.1,
    hw_gamma = 0.1,
    hw_season_length = 60,
    sample_rate_min = 0.5,
    sample_rate_max = 5.0,
    volatility_threshold = 0.1,
    saturation_knee_ratio = 0.8,
    cpu_temp_correlation_min = 0.5,
    io_latency_correlation_min = 0.6,
    prediction_confidence_min = 0.6,
    min_samples_for_prediction = 30,
)

# ============================
# T-DIGEST (Streaming Percentiles)
# ============================

mutable struct TDigestCentroid
    mean::Float64
    weight::Float64
end

mutable struct TDigest
    centroids::Vector{TDigestCentroid}
    compression::Float64
    total_weight::Float64
    max_centroids::Int
    p50::Float64
    p95::Float64
    p99::Float64
end

function TDigest(compression::Float64=100.0)
    max_c = ceil(Int, compression * π / 2)
    TDigest(TDigestCentroid[], compression, 0.0, max_c, 0.0, 0.0, 0.0)
end

function add_sample!(td::TDigest, value::Float64, weight::Float64=1.0)
    push!(td.centroids, TDigestCentroid(value, weight))
    td.total_weight += weight
    if length(td.centroids) > td.max_centroids * 2
        compress!(td)
    end
end

function compress!(td::TDigest)
    isempty(td.centroids) && return
    sort!(td.centroids, by = c -> c.mean)
    new_centroids = TDigestCentroid[]
    current = td.centroids[1]
    for i in 2:length(td.centroids)
        c = td.centroids[i]
        q = (current.weight + c.weight / 2) / td.total_weight
        k = 4 * td.total_weight * q * (1 - q) / td.compression
        if current.weight + c.weight <= max(1.0, k)
            new_mean = (current.mean * current.weight + c.mean * c.weight) / (current.weight + c.weight)
            current = TDigestCentroid(new_mean, current.weight + c.weight)
        else
            push!(new_centroids, current)
            current = c
        end
    end
    push!(new_centroids, current)
    td.centroids = new_centroids
end

function quantile(td::TDigest, q::Float64)
    isempty(td.centroids) && return 0.0
    length(td.centroids) == 1 && return td.centroids[1].mean
    sort!(td.centroids, by = c -> c.mean)
    target = q * td.total_weight
    cumulative = 0.0
    for i in 1:length(td.centroids)
        c = td.centroids[i]
        if cumulative + c.weight >= target
            i == 1 && return c.mean
            prev = td.centroids[i-1]
            delta = (target - cumulative) / c.weight
            return prev.mean + delta * (c.mean - prev.mean)
        end
        cumulative += c.weight
    end
    return td.centroids[end].mean
end

function update_percentiles!(td::TDigest)
    td.p50 = quantile(td, 0.50)
    td.p95 = quantile(td, 0.95)
    td.p99 = quantile(td, 0.99)
end

# ============================
# ALGORITHME DE WELFORD
# ============================

mutable struct WelfordStats
    n::Int
    mean::Float64
    m2::Float64
    min_val::Float64
    max_val::Float64
end

WelfordStats() = WelfordStats(0, 0.0, 0.0, Inf, -Inf)

function update_welford!(w::WelfordStats, value::Float64)
    w.n += 1
    delta = value - w.mean
    w.mean += delta / w.n
    delta2 = value - w.mean
    w.m2 += delta * delta2
    w.min_val = min(w.min_val, value)
    w.max_val = max(w.max_val, value)
end

get_variance(w::WelfordStats) = w.n > 1 ? w.m2 / (w.n - 1) : 0.0
get_std(w::WelfordStats) = sqrt(get_variance(w))

mutable struct WelfordEWMA
    mean::Float64
    var::Float64
    alpha::Float64
    initialized::Bool
end

WelfordEWMA(alpha::Float64=0.1) = WelfordEWMA(0.0, 0.0, alpha, false)

function update_welford_ewma!(w::WelfordEWMA, value::Float64)
    if !w.initialized
        w.mean = value
        w.var = 0.0
        w.initialized = true
        return
    end
    delta = value - w.mean
    w.mean = w.mean + w.alpha * delta
    w.var = (1 - w.alpha) * (w.var + w.alpha * delta^2)
end

get_ewma_std(w::WelfordEWMA) = sqrt(max(0.0, w.var))

# ============================
# MAD (Median Absolute Deviation)
# ============================

mutable struct MADTracker
    value_digest::TDigest
    deviation_digest::TDigest
    current_median::Float64
    current_mad::Float64
    sample_buffer::Vector{Float64}
    buffer_size::Int
end

function MADTracker(buffer_size::Int=100)
    MADTracker(TDigest(50.0), TDigest(50.0), 0.0, 1.0, Float64[], buffer_size)
end

function update_mad!(m::MADTracker, value::Float64)
    add_sample!(m.value_digest, value)
    push!(m.sample_buffer, value)
    if length(m.sample_buffer) >= m.buffer_size
        m.current_median = quantile(m.value_digest, 0.5)
        m.deviation_digest = TDigest(50.0)
        for v in m.sample_buffer
            add_sample!(m.deviation_digest, abs(v - m.current_median))
        end
        m.current_mad = max(quantile(m.deviation_digest, 0.5), 0.001)
        m.sample_buffer = m.sample_buffer[end÷2:end]
    end
    update_percentiles!(m.value_digest)
end

robust_zscore(m::MADTracker, value::Float64) = (value - m.current_median) / (1.4826 * m.current_mad)

# ============================
# HOLT-WINTERS
# ============================

mutable struct HoltWinters
    level::Float64
    trend::Float64
    seasonals::Vector{Float64}
    season_length::Int
    alpha::Float64
    beta::Float64
    gamma::Float64
    sample_count::Int
    initialized::Bool
end

function HoltWinters(season_length::Int=60, alpha::Float64=0.3, beta::Float64=0.1, gamma::Float64=0.1)
    HoltWinters(0.0, 0.0, zeros(season_length), season_length, alpha, beta, gamma, 0, false)
end

function update_hw!(hw::HoltWinters, value::Float64)
    hw.sample_count += 1
    if !hw.initialized
        idx = mod1(hw.sample_count, hw.season_length)
        hw.seasonals[idx] = value
        if hw.sample_count >= hw.season_length
            hw.level = mean(hw.seasonals)
            hw.trend = 0.0
            for i in 1:hw.season_length
                hw.seasonals[i] = hw.seasonals[i] / max(hw.level, 0.001)
            end
            hw.initialized = true
        end
        return
    end
    idx = mod1(hw.sample_count, hw.season_length)
    prev_seasonal = hw.seasonals[idx]
    deseasonalized = value / max(prev_seasonal, 0.001)
    new_level = hw.alpha * deseasonalized + (1 - hw.alpha) * (hw.level + hw.trend)
    new_trend = hw.beta * (new_level - hw.level) + (1 - hw.beta) * hw.trend
    hw.seasonals[idx] = hw.gamma * (value / max(new_level, 0.001)) + (1 - hw.gamma) * prev_seasonal
    hw.level = new_level
    hw.trend = new_trend
end

function predict_hw(hw::HoltWinters, horizon::Int=1)
    !hw.initialized && return 0.0
    future_idx = mod1(hw.sample_count + horizon, hw.season_length)
    return (hw.level + horizon * hw.trend) * hw.seasonals[future_idx]
end

function residual_hw(hw::HoltWinters, actual::Float64)
    !hw.initialized && return 0.0
    idx = mod1(hw.sample_count, hw.season_length)
    predicted = hw.level * hw.seasonals[idx]
    return actual - predicted
end

# ============================
# ADWIN (Adaptive Windowing)
# ============================

mutable struct ADWIN
    bucket_means::Vector{Float64}
    bucket_variances::Vector{Float64}
    bucket_sizes::Vector{Int}
    total_n::Int
    total_sum::Float64
    delta::Float64
    min_window::Int
    regime_detected::Bool
    regime_change_time::Float64
end

function ADWIN(delta::Float64=0.002, min_window::Int=30)
    ADWIN(Float64[], Float64[], Int[], 0, 0.0, delta, min_window, false, 0.0)
end

function update_adwin!(a::ADWIN, value::Float64)
    a.regime_detected = false
    push!(a.bucket_means, value)
    push!(a.bucket_variances, 0.0)
    push!(a.bucket_sizes, 1)
    a.total_n += 1
    a.total_sum += value
    compress_buckets!(a)
    detect_regime_change!(a)
end

function compress_buckets!(a::ADWIN)
    while length(a.bucket_sizes) > 1
        merged = false
        for i in 1:(length(a.bucket_sizes)-1)
            if a.bucket_sizes[i] == a.bucket_sizes[i+1]
                n1, n2 = a.bucket_sizes[i], a.bucket_sizes[i+1]
                m1, m2 = a.bucket_means[i], a.bucket_means[i+1]
                a.bucket_means[i] = (n1 * m1 + n2 * m2) / (n1 + n2)
                a.bucket_sizes[i] = n1 + n2
                deleteat!(a.bucket_means, i+1)
                deleteat!(a.bucket_variances, i+1)
                deleteat!(a.bucket_sizes, i+1)
                merged = true
                break
            end
        end
        !merged && break
    end
end

function detect_regime_change!(a::ADWIN)
    a.total_n < a.min_window && return
    n_left, sum_left = 0, 0.0
    for i in 1:length(a.bucket_sizes)
        n_left += a.bucket_sizes[i]
        sum_left += a.bucket_means[i] * a.bucket_sizes[i]
        n_right = a.total_n - n_left
        n_right == 0 && continue
        mean_left = sum_left / n_left
        mean_right = (a.total_sum - sum_left) / n_right
        m = 1.0 / n_left + 1.0 / n_right
        eps = sqrt(m * log(2/a.delta) / 2)
        if abs(mean_left - mean_right) > eps
            a.regime_detected = true
            a.regime_change_time = time()
            for _ in 1:i
                isempty(a.bucket_sizes) && break
                removed_n = popfirst!(a.bucket_sizes)
                removed_mean = popfirst!(a.bucket_means)
                popfirst!(a.bucket_variances)
                a.total_n -= removed_n
                a.total_sum -= removed_mean * removed_n
            end
            return
        end
    end
end

# ============================
# CUSUM (Cumulative Sum)
# ============================

mutable struct CUSUM
    cusum_pos::Float64
    cusum_neg::Float64
    target::Float64
    threshold::Float64
    drift::Float64
    alert::Bool
    drift_direction::Int
    welford::WelfordEWMA
end

function CUSUM(threshold::Float64=5.0, drift::Float64=0.5)
    CUSUM(0.0, 0.0, 0.0, threshold, drift, false, 0, WelfordEWMA(0.01))
end

function update_cusum!(c::CUSUM, value::Float64)
    c.alert = false
    c.drift_direction = 0
    update_welford_ewma!(c.welford, value)
    std_dev = max(get_ewma_std(c.welford), 0.001)
    normalized = (value - c.welford.mean) / std_dev
    c.cusum_pos = max(0.0, c.cusum_pos + normalized - c.drift)
    c.cusum_neg = max(0.0, c.cusum_neg - normalized - c.drift)
    if c.cusum_pos > c.threshold
        c.alert = true
        c.drift_direction = 1
        c.cusum_pos = 0.0
    elseif c.cusum_neg > c.threshold
        c.alert = true
        c.drift_direction = -1
        c.cusum_neg = 0.0
    end
end

# ============================
# PHYSICAL COHERENCE
# ============================

mutable struct PhysicalCoherence
    cpu_history::Vector{Float64}
    temp_history::Vector{Float64}
    iops_history::Vector{Float64}
    latency_history::Vector{Float64}
    cpu_temp_correlation::Float64
    io_latency_correlation::Float64
    temp_without_load::Bool
    latency_without_io::Bool
    window_size::Int
end

PhysicalCoherence(ws::Int=30) = PhysicalCoherence(Float64[], Float64[], Float64[], Float64[], 0.0, 0.0, false, false, ws)

function update_coherence!(pc::PhysicalCoherence, cpu::Float64, temp::Float64, iops::Float64, latency::Float64)
    push!(pc.cpu_history, cpu)
    push!(pc.temp_history, temp)
    push!(pc.iops_history, iops)
    push!(pc.latency_history, latency)
    while length(pc.cpu_history) > pc.window_size
        popfirst!(pc.cpu_history)
        popfirst!(pc.temp_history)
        popfirst!(pc.iops_history)
        popfirst!(pc.latency_history)
    end
    if length(pc.cpu_history) >= 10
        pc.cpu_temp_correlation = correlation(pc.cpu_history, pc.temp_history)
        pc.io_latency_correlation = correlation(pc.iops_history, pc.latency_history)
        pc.temp_without_load = temp > 70 && cpu < 30 && pc.cpu_temp_correlation < AI_CONFIG.cpu_temp_correlation_min
        pc.latency_without_io = latency > 10 && iops < 100 && pc.io_latency_correlation < AI_CONFIG.io_latency_correlation_min
    end
end

function correlation(x::Vector{Float64}, y::Vector{Float64})
    n = min(length(x), length(y))
    n < 3 && return 0.0
    mx, my = mean(x[1:n]), mean(y[1:n])
    sx, sy = std(x[1:n]), std(y[1:n])
    (sx < 0.001 || sy < 0.001) && return 0.0
    cov = sum((x[i] - mx) * (y[i] - my) for i in 1:n) / (n - 1)
    return clamp(cov / (sx * sy), -1.0, 1.0)
end

# ============================
# SATURATION MODEL
# ============================

struct SaturationModel
    utilization::Float64
    latency::Float64
    queue_depth::Float64
    saturation_score::Float64
    at_knee_point::Bool
    estimated_max_throughput::Float64
end

function analyze_saturation(util::Float64, lat::Float64, qd::Float64)
    knee = AI_CONFIG.saturation_knee_ratio
    sat_score = util >= 1.0 ? 1.0 : util >= knee ? 1 - (1 - util)^2 : util / knee * 0.5
    at_knee = util >= knee && util < 0.95
    est_max = (lat > 0 && util > 0.1) ? (1 - lat * (1 - util) / 100.0) * (util > 0 ? qd / util : 0) : 0.0
    SaturationModel(util, lat, qd, clamp(sat_score, 0.0, 1.0), at_knee, est_max)
end

# ============================
# ADAPTIVE SAMPLER
# ============================

mutable struct AdaptiveSampler
    prev_value::Float64
    prev_derivative::Float64
    volatility::Float64
    recommended_interval::Float64
    last_sample_time::Float64
end

AdaptiveSampler() = AdaptiveSampler(0.0, 0.0, 0.0, 1.0, time())

function update_sampler!(s::AdaptiveSampler, value::Float64)
    now = time()
    dt = now - s.last_sample_time
    dt < 0.01 && return s.recommended_interval
    derivative = (value - s.prev_value) / dt
    s.volatility = abs(derivative - s.prev_derivative) / dt
    if s.volatility > AI_CONFIG.volatility_threshold
        s.recommended_interval = max(AI_CONFIG.sample_rate_min, s.recommended_interval * 0.8)
    else
        s.recommended_interval = min(AI_CONFIG.sample_rate_max, s.recommended_interval * 1.1)
    end
    s.prev_value = value
    s.prev_derivative = derivative
    s.last_sample_time = now
    return s.recommended_interval
end

# ============================
# METRIC ANALYZER
# ============================

mutable struct MetricAnalyzer
    name::String
    mad_tracker::MADTracker
    welford::WelfordStats
    welford_ewma::WelfordEWMA
    holt_winters::HoltWinters
    adwin::ADWIN
    cusum::CUSUM
    sampler::AdaptiveSampler
    current_value::Float64
    zscore_robust::Float64
    residual::Float64
    regime_id::Int
    in_regime_change::Bool
    drift_detected::Bool
    drift_direction::Int
end

function MetricAnalyzer(name::String)
    MetricAnalyzer(name, MADTracker(50), WelfordStats(), WelfordEWMA(0.1),
        HoltWinters(AI_CONFIG.hw_season_length, AI_CONFIG.hw_alpha, AI_CONFIG.hw_beta, AI_CONFIG.hw_gamma),
        ADWIN(AI_CONFIG.adwin_delta, AI_CONFIG.adwin_min_window),
        CUSUM(AI_CONFIG.cusum_threshold, AI_CONFIG.cusum_drift),
        AdaptiveSampler(), 0.0, 0.0, 0.0, 1, false, false, 0)
end

function update_analyzer!(ma::MetricAnalyzer, value::Float64)
    ma.current_value = value
    update_welford!(ma.welford, value)
    update_welford_ewma!(ma.welford_ewma, value)
    update_mad!(ma.mad_tracker, value)
    ma.zscore_robust = robust_zscore(ma.mad_tracker, value)
    update_hw!(ma.holt_winters, value)
    ma.residual = residual_hw(ma.holt_winters, value)
    update_adwin!(ma.adwin, value)
    if ma.adwin.regime_detected
        ma.in_regime_change = true
        ma.regime_id += 1
        ma.cusum = CUSUM(AI_CONFIG.cusum_threshold, AI_CONFIG.cusum_drift)
    else
        ma.in_regime_change = false
    end
    update_cusum!(ma.cusum, value)
    ma.drift_detected = ma.cusum.alert
    ma.drift_direction = ma.cusum.drift_direction
    update_sampler!(ma.sampler, value)
end

function get_anomaly_score(ma::MetricAnalyzer)
    zs = clamp(abs(ma.zscore_robust) / 5.0, 0.0, 1.0)
    rs = get_ewma_std(ma.welford_ewma) > 0.001 ? clamp(abs(ma.residual) / (3 * get_ewma_std(ma.welford_ewma)), 0.0, 1.0) : 0.0
    rg = ma.in_regime_change ? 0.3 : 0.0
    dr = ma.drift_detected ? 0.4 : 0.0
    clamp(0.4 * zs + 0.3 * rs + 0.15 * rg + 0.15 * dr, 0.0, 1.0)
end

function is_anomaly(ma::MetricAnalyzer; level::Symbol=:warning)
    th = level == :critical ? AI_CONFIG.zscore_critical : AI_CONFIG.zscore_warning
    abs(ma.zscore_robust) > th || ma.drift_detected
end

# ============================
# AI STATE
# ============================

mutable struct AIState
    cpu::MetricAnalyzer
    mem::MetricAnalyzer
    io_throughput::MetricAnalyzer
    io_latency::MetricAnalyzer
    net::MetricAnalyzer
    temp::MetricAnalyzer
    gpu::MetricAnalyzer
    coherence::PhysicalCoherence
    cpu_digest::TDigest
    mem_digest::TDigest
    io_digest::TDigest
    overall_anomaly::Float64
    regime_description::String
    recommended_sample_interval::Float64
    sample_count::Int
    last_update::Float64
end

function AIState()
    AIState(MetricAnalyzer("CPU"), MetricAnalyzer("Memory"), MetricAnalyzer("IO_Throughput"),
        MetricAnalyzer("IO_Latency"), MetricAnalyzer("Network"), MetricAnalyzer("Temperature"),
        MetricAnalyzer("GPU"), PhysicalCoherence(30), TDigest(100.0), TDigest(100.0), TDigest(100.0),
        0.0, "initializing", 1.0, 0, time())
end

const AI_STATE = Ref{AIState}()

function get_ai_state()
    isassigned(AI_STATE) || (AI_STATE[] = AIState())
    AI_STATE[]
end

# ============================
# SCORING FUNCTIONS
# ============================

function score_cpu_anomaly(monitor::SystemMonitor)
    ai = get_ai_state()
    cpu_usage = get_cpu_usage(monitor)
    update_analyzer!(ai.cpu, cpu_usage)
    add_sample!(ai.cpu_digest, cpu_usage)
    score = get_anomaly_score(ai.cpu)
    load_ratio = monitor.cpu_info.load1 / max(Sys.CPU_THREADS, 1)
    load_ratio > 1.0 && (score += 0.1 * min(load_ratio - 1.0, 1.0))
    monitor.cpu_info.pressure_avg10 > 10.0 && (score += 0.1 * min(monitor.cpu_info.pressure_avg10 / 50.0, 1.0))
    clamp01(score)
end

function score_mem_anomaly(monitor::SystemMonitor)
    ai = get_ai_state()
    mem_usage = get_memory_usage_percent(monitor)
    update_analyzer!(ai.mem, mem_usage)
    add_sample!(ai.mem_digest, mem_usage)
    score = get_anomaly_score(ai.mem)
    ai.mem.drift_detected && ai.mem.drift_direction > 0 && (score += 0.2)
    monitor.memory.swap_total_kb > 0 && (score += monitor.memory.swap_used_kb / monitor.memory.swap_total_kb * 0.2)
    score += monitor.memory.pressure_avg10 / 100.0 * 0.1
    clamp01(score)
end

function score_io_anomaly(monitor::SystemMonitor)
    ai = get_ai_state()
    dio = get_total_disk_io(monitor)
    total_io_mb = dio.read + dio.write
    max_lat, max_q, max_u = 0.0, 0.0, 0.0
    for (_, io) in monitor.disk_io
        max_lat = max(max_lat, io.avg_wait_ms)
        max_q = max(max_q, io.queue_depth)
        max_u = max(max_u, io.io_wait_pct / 100.0)
    end
    update_analyzer!(ai.io_throughput, total_io_mb)
    update_analyzer!(ai.io_latency, max_lat)
    add_sample!(ai.io_digest, total_io_mb)
    sat = analyze_saturation(max_u, max_lat, max_q)
    score = 0.3 * get_anomaly_score(ai.io_throughput) + 0.4 * get_anomaly_score(ai.io_latency) + 0.3 * sat.saturation_score
    sat.at_knee_point && (score += 0.15)
    clamp01(score)
end

function score_net_anomaly(monitor::SystemMonitor)
    ai = get_ai_state()
    total_bps = (monitor.network.rx_bps + monitor.network.tx_bps) / 1e6
    update_analyzer!(ai.net, total_bps)
    score = get_anomaly_score(ai.net)
    monitor.network.classification == "saturated" && (score += 0.3)
    monitor.network.classification == "burst" && (score += 0.1)
    monitor.network.tcp.time_wait > 1000 && (score += 0.1)
    monitor.network.tcp.close_wait > 100 && (score += 0.15)
    clamp01(score)
end

function score_gpu_anomaly(monitor::SystemMonitor)
    monitor.gpu === nothing && return 0.0
    ai = get_ai_state()
    update_analyzer!(ai.gpu, monitor.gpu.util)
    score = get_anomaly_score(ai.gpu)
    monitor.gpu.temp > 80 && (score += (monitor.gpu.temp - 80) / 20 * 0.2)
    monitor.gpu.mem_total > 0 && monitor.gpu.mem_used / monitor.gpu.mem_total > 0.9 && (score += 0.2)
    !isempty(monitor.gpu.throttling) && (score += 0.15)
    clamp01(score)
end

function score_temp_anomaly(monitor::SystemMonitor)
    cpu_temp = get_cpu_temp(monitor)
    cpu_temp == 0 && return 0.0
    ai = get_ai_state()
    update_analyzer!(ai.temp, cpu_temp)
    score = get_anomaly_score(ai.temp)
    cpu_temp > 90 && (score = max(score, 0.9))
    cpu_temp > 80 && (score = max(score, 0.6))
    cpu_usage = get_cpu_usage(monitor)
    update_coherence!(ai.coherence, cpu_usage, cpu_temp, ai.io_throughput.current_value, ai.io_latency.current_value)
    ai.coherence.temp_without_load && (score += 0.3)
    clamp01(score)
end

# ============================
# PREDICTIONS
# ============================

function predict_time_to_critical_advanced(ma::MetricAnalyzer, current::Float64, threshold::Float64)
    hw = ma.holt_winters
    !hw.initialized && return Prediction()
    rate = hw.trend
    rate <= 0.001 && return Prediction("", current, 0.0, Inf, threshold, 0.0)
    remaining = threshold - current
    remaining <= 0 && return Prediction("", current, rate, 0.0, threshold, 0.9)
    ttc = remaining / rate
    conf = (1.0 - min(abs(ma.zscore_robust) / 5.0, 1.0)) * (ma.in_regime_change ? 0.3 : 1.0) * 0.8
    Prediction("", current, rate, ttc, threshold, conf)
end

function generate_predictions(monitor::SystemMonitor)
    preds = Prediction[]
    ai = get_ai_state()
    
    cpu = get_cpu_usage(monitor)
    if ai.cpu.welford.n >= AI_CONFIG.min_samples_for_prediction
        p = predict_time_to_critical_advanced(ai.cpu, cpu, AI_CONFIG.cpu_critical)
        p.time_to_critical_sec < 3600 && p.confidence > AI_CONFIG.prediction_confidence_min &&
            push!(preds, Prediction("CPU", p.current_value, p.trend_per_sec, p.time_to_critical_sec, p.threshold, p.confidence))
    end
    
    mem = get_memory_usage_percent(monitor)
    if ai.mem.welford.n >= AI_CONFIG.min_samples_for_prediction
        p = predict_time_to_critical_advanced(ai.mem, mem, AI_CONFIG.mem_critical)
        ai.mem.drift_detected && ai.mem.drift_direction > 0 &&
            (p = Prediction("Memory (leak)", p.current_value, p.trend_per_sec, p.time_to_critical_sec, p.threshold, min(p.confidence + 0.2, 1.0)))
        p.time_to_critical_sec < 3600 && p.confidence > AI_CONFIG.prediction_confidence_min &&
            push!(preds, Prediction("Memory", p.current_value, p.trend_per_sec, p.time_to_critical_sec, p.threshold, p.confidence))
    end
    
    temp = get_cpu_temp(monitor)
    if temp > 0 && ai.temp.welford.n >= AI_CONFIG.min_samples_for_prediction
        p = predict_time_to_critical_advanced(ai.temp, temp, AI_CONFIG.temp_critical)
        p.time_to_critical_sec < 1800 && p.confidence > AI_CONFIG.prediction_confidence_min &&
            push!(preds, Prediction("Temperature", p.current_value, p.trend_per_sec, p.time_to_critical_sec, p.threshold, p.confidence))
    end
    
    for disk in monitor.disks
        if disk.percent > 70
            dio = get_total_disk_io(monitor)
            if dio.write > 0 && disk.avail_gb > 0
                sat = analyze_saturation(disk.percent / 100.0, 0.0, 0.0)
                ttf = disk.avail_gb * 1024 / (dio.write * (1 + sat.saturation_score))
                ttf < 86400 && push!(preds, Prediction("Disk $(disk.mount)", disk.percent, 0.0, ttf, 100.0, 0.6 + 0.2 * sat.saturation_score))
            end
        end
    end
    preds
end

# ============================
# REGIME DETECTION
# ============================

function detect_current_regime(monitor::SystemMonitor)
    ai = get_ai_state()
    cpu = get_cpu_usage(monitor)
    mem = get_memory_usage_percent(monitor)
    gpu = monitor.gpu !== nothing ? monitor.gpu.util : 0.0
    io = ai.io_throughput.current_value
    cpu < 20 && mem < 50 && io < max(10, ai.io_digest.p95 * 0.2) && return "idle"
    gpu > 80 || (cpu > 60 && gpu > 30) && return "gaming"
    io > max(50, ai.io_digest.p95 * 0.7) && return "heavy_io"
    cpu > max(70, ai.cpu_digest.p95 * 0.8) && return "compute"
    mem > max(80, ai.mem_digest.p95 * 0.9) && return "memory_intensive"
    "normal"
end

# ============================
# SPIKE DETECTION
# ============================

function detect_spikes!(monitor::SystemMonitor)
    ai = get_ai_state()
    a = monitor.anomaly
    a.cpu_spike = abs(ai.cpu.zscore_robust) > AI_CONFIG.zscore_warning
    a.mem_spike = abs(ai.mem.zscore_robust) > AI_CONFIG.zscore_warning
    a.io_spike = abs(ai.io_throughput.zscore_robust) > AI_CONFIG.zscore_warning
    a.net_spike = abs(ai.net.zscore_robust) > AI_CONFIG.zscore_warning
end

# ============================
# MAIN UPDATE FUNCTION
# ============================

function update_anomaly!(monitor::SystemMonitor)
    ai = get_ai_state()
    ai.sample_count += 1
    ai.last_update = time()
    
    monitor.anomaly.cpu = score_cpu_anomaly(monitor)
    monitor.anomaly.mem = score_mem_anomaly(monitor)
    monitor.anomaly.io = score_io_anomaly(monitor)
    monitor.anomaly.net = score_net_anomaly(monitor)
    monitor.anomaly.gpu = score_gpu_anomaly(monitor)
    monitor.anomaly.temp = score_temp_anomaly(monitor)
    
    w = (cpu=0.20, mem=0.20, io=0.15, net=0.10, gpu=0.15, temp=0.20)
    gpu_c = monitor.gpu !== nothing ? w.gpu * monitor.anomaly.gpu : 0.0
    gpu_w = monitor.gpu !== nothing ? w.gpu : 0.0
    temp_c = get_cpu_temp(monitor) > 0 ? w.temp * monitor.anomaly.temp : 0.0
    temp_w = get_cpu_temp(monitor) > 0 ? w.temp : 0.0
    total_w = w.cpu + w.mem + w.io + w.net + gpu_w + temp_w
    
    monitor.anomaly.overall = (w.cpu * monitor.anomaly.cpu + w.mem * monitor.anomaly.mem + 
        w.io * monitor.anomaly.io + w.net * monitor.anomaly.net + gpu_c + temp_c) / total_w
    
    (ai.coherence.temp_without_load || ai.coherence.latency_without_io) && 
        (monitor.anomaly.overall = min(1.0, monitor.anomaly.overall + 0.2))
    
    push_metric!(monitor.history, get_cpu_usage(monitor), get_memory_usage_percent(monitor),
        monitor.network.rx_bps / 1e6, monitor.network.tx_bps / 1e6,
        monitor.gpu !== nothing ? monitor.gpu.util : 0.0,
        sum(io.read_mb_s + io.write_mb_s for (_, io) in monitor.disk_io; init=0.0),
        get_cpu_temp(monitor))
    
    monitor.anomaly.cpu_trend = ai.cpu.holt_winters.trend > 0.1 ? "rising" : ai.cpu.holt_winters.trend < -0.1 ? "falling" : "stable"
    monitor.anomaly.mem_trend = ai.mem.holt_winters.trend > 0.1 ? "rising" : ai.mem.holt_winters.trend < -0.1 ? "falling" : "stable"
    monitor.anomaly.io_trend = ai.io_throughput.holt_winters.trend > 0.1 ? "rising" : ai.io_throughput.holt_winters.trend < -0.1 ? "falling" : "stable"
    monitor.anomaly.net_trend = ai.net.holt_winters.trend > 0.1 ? "rising" : ai.net.holt_winters.trend < -0.1 ? "falling" : "stable"
    monitor.anomaly.trend = monitor.anomaly.cpu_trend
    
    detect_spikes!(monitor)
    monitor.anomaly.predictions = generate_predictions(monitor)
    ai.regime_description = detect_current_regime(monitor)
    ai.recommended_sample_interval = minimum([ai.cpu.sampler.recommended_interval, ai.mem.sampler.recommended_interval,
        ai.io_throughput.sampler.recommended_interval, ai.net.sampler.recommended_interval])
    nothing
end

# ============================
# ALERT GENERATION
# ============================

struct Alert
    level::Symbol
    category::String
    message::String
    value::Float64
    threshold::Float64
end

function generate_alerts(monitor::SystemMonitor)
    alerts = Alert[]
    ai = get_ai_state()
    cpu = get_cpu_usage(monitor)
    mem = get_memory_usage_percent(monitor)
    temp = get_cpu_temp(monitor)
    
    cpu > AI_CONFIG.cpu_critical && push!(alerts, Alert(:critical, "CPU", "Critical CPU usage", cpu, AI_CONFIG.cpu_critical))
    is_anomaly(ai.cpu) && push!(alerts, Alert(:warning, "CPU", "CPU anomaly (Z=$(round(ai.cpu.zscore_robust, digits=2)))", cpu, 0.0))
    ai.cpu.drift_detected && push!(alerts, Alert(:warning, "CPU", "CPU drift ($(ai.cpu.drift_direction > 0 ? "+" : "-"))", cpu, 0.0))
    monitor.anomaly.cpu_spike && push!(alerts, Alert(:warning, "CPU", "CPU spike", cpu, 0.0))
    
    mem > AI_CONFIG.mem_critical && push!(alerts, Alert(:critical, "Memory", "Critical memory", mem, AI_CONFIG.mem_critical))
    is_anomaly(ai.mem) && push!(alerts, Alert(:warning, "Memory", "Memory anomaly", mem, 0.0))
    ai.mem.drift_detected && ai.mem.drift_direction > 0 && push!(alerts, Alert(:warning, "Memory", "Potential memory leak (CUSUM)", mem, 0.0))
    monitor.anomaly.mem_spike && push!(alerts, Alert(:warning, "Memory", "Memory spike", mem, 0.0))
    
    temp > AI_CONFIG.temp_critical && push!(alerts, Alert(:critical, "Temp", "Critical temperature", temp, AI_CONFIG.temp_critical))
    temp > 80 && push!(alerts, Alert(:warning, "Temp", "High temperature", temp, 80.0))
    ai.coherence.temp_without_load && push!(alerts, Alert(:warning, "Hardware", "Temp without load (hardware?)", temp, 0.0))
    ai.coherence.latency_without_io && push!(alerts, Alert(:warning, "Hardware", "IO latency without throughput (disk?)", ai.io_latency.current_value, 0.0))
    
    for (dev, io) in monitor.disk_io
        sat = analyze_saturation(io.io_wait_pct / 100.0, io.avg_wait_ms, io.queue_depth)
        sat.at_knee_point && push!(alerts, Alert(:warning, "Disk", "Disk $dev at saturation knee", io.io_wait_pct, 80.0))
    end
    
    if monitor.gpu !== nothing
        monitor.gpu.temp > 85 && push!(alerts, Alert(:warning, "GPU", "High GPU temp", monitor.gpu.temp, 85.0))
        !isempty(monitor.gpu.throttling) && push!(alerts, Alert(:warning, "GPU", "GPU throttling", 1.0, 0.0))
    end
    
    for disk in monitor.disks
        disk.percent > 95 && push!(alerts, Alert(:critical, "Disk", "Disk $(disk.mount) critical", disk.percent, 95.0))
        disk.percent > 90 && disk.percent <= 95 && push!(alerts, Alert(:warning, "Disk", "Disk $(disk.mount) full", disk.percent, 90.0))
    end
    
    monitor.battery.present && monitor.battery.source == "Battery" && monitor.battery.percent < 10 &&
        push!(alerts, Alert(:critical, "Battery", "Critical battery", monitor.battery.percent, 10.0))
    monitor.battery.present && monitor.battery.source == "Battery" && monitor.battery.percent < 20 && monitor.battery.percent >= 10 &&
        push!(alerts, Alert(:warning, "Battery", "Low battery", monitor.battery.percent, 20.0))
    
    monitor.system.oom_kills > 0 && push!(alerts, Alert(:critical, "System", "OOM kills", Float64(monitor.system.oom_kills), 0.0))
    (ai.cpu.in_regime_change || ai.mem.in_regime_change) && push!(alerts, Alert(:info, "System", "Regime: $(ai.regime_description)", 0.0, 0.0))
    
    for p in monitor.anomaly.predictions
        p.time_to_critical_sec < 600 && push!(alerts, Alert(:warning, "Predict", "$(p.metric) critical ~$(format_time_remaining(p.time_to_critical_sec))", p.current_value, p.threshold))
    end
    
    monitor.network.tcp.close_wait > 100 && push!(alerts, Alert(:warning, "Network", "High CLOSE_WAIT", Float64(monitor.network.tcp.close_wait), 100.0))
    alerts
end

# ============================
# UTILITY API
# ============================

get_recommended_sample_interval() = get_ai_state().recommended_sample_interval
get_current_regime() = get_ai_state().regime_description

function get_metric_percentiles(metric::Symbol)
    ai = get_ai_state()
    metric == :cpu && return (p50=ai.cpu_digest.p50, p95=ai.cpu_digest.p95, p99=ai.cpu_digest.p99)
    metric == :mem && return (p50=ai.mem_digest.p50, p95=ai.mem_digest.p95, p99=ai.mem_digest.p99)
    metric == :io && return (p50=ai.io_digest.p50, p95=ai.io_digest.p95, p99=ai.io_digest.p99)
    (p50=0.0, p95=0.0, p99=0.0)
end

function get_ai_diagnostic()
    ai = get_ai_state()
    (sample_count=ai.sample_count, regime=ai.regime_description, interval=ai.recommended_sample_interval,
     cpu=(z=ai.cpu.zscore_robust, regime=ai.cpu.regime_id, drift=ai.cpu.drift_detected, trend=ai.cpu.holt_winters.trend),
     mem=(z=ai.mem.zscore_robust, regime=ai.mem.regime_id, drift=ai.mem.drift_detected, trend=ai.mem.holt_winters.trend),
     io=(z_tp=ai.io_throughput.zscore_robust, z_lat=ai.io_latency.zscore_robust, drift=ai.io_throughput.drift_detected),
     coherence=(cpu_temp=ai.coherence.cpu_temp_correlation, io_lat=ai.coherence.io_latency_correlation,
                temp_anom=ai.coherence.temp_without_load, io_anom=ai.coherence.latency_without_io))
end

reset_ai_state!() = (AI_STATE[] = AIState(); nothing)
