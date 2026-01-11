# OS/Linux/ai/Spectral.jl
# ============================
# FFT-based Spectral Analysis Module
# ============================
# Detects oscillations, periodic patterns, and frequency anomalies
# in system metrics (CPU usage, fan speed, etc.)

using FFTW

# ============================
# FFT ANALYZER
# ============================

"""
Streaming FFT analyzer for detecting oscillations in time series data.
"""
mutable struct FFTAnalyzer
    buffer::Vector{Float64}     # Circular buffer of samples
    buffer_size::Int            # Size of the buffer (power of 2 recommended)
    buffer_idx::Int             # Current write position
    sample_count::Int           # Total samples received
    sample_rate::Float64        # Samples per second

    # Results
    power_spectrum::Vector{Float64}
    frequencies::Vector{Float64}
    dominant_freq::Float64
    dominant_power::Float64
    oscillation_detected::Bool
    oscillation_freq::Float64
end

function FFTAnalyzer(buffer_size::Int=128, sample_rate::Float64=1.0)
    # Ensure buffer size is power of 2 for FFT efficiency
    n = nextpow(2, buffer_size)

    FFTAnalyzer(
        zeros(n),
        n,
        1,
        0,
        sample_rate,
        Float64[],
        Float64[],
        0.0,
        0.0,
        false,
        0.0
    )
end

"""Add a new sample to the analyzer's buffer"""
function add_sample!(fft::FFTAnalyzer, value::Float64)
    fft.buffer[fft.buffer_idx] = value
    fft.buffer_idx = mod1(fft.buffer_idx + 1, fft.buffer_size)
    fft.sample_count += 1
    return nothing
end

"""
Perform FFT analysis on the current buffer.
Returns true if oscillation is detected.
"""
function analyze!(fft::FFTAnalyzer; min_samples::Int=32)::Bool
    fft.sample_count < min_samples && return false

    # Apply Hann window to reduce spectral leakage
    n = fft.buffer_size
    windowed = similar(fft.buffer)
    for i in 1:n
        # Hann window
        w = 0.5 * (1 - cos(2π * (i - 1) / (n - 1)))
        windowed[i] = fft.buffer[i] * w
    end

    # Compute FFT
    fft_result = fft_func(windowed)

    # Compute power spectrum (only positive frequencies)
    n_freq = n ÷ 2
    fft.power_spectrum = abs.(fft_result[1:n_freq]) .^ 2 ./ n

    # Compute corresponding frequencies
    fft.frequencies = collect(0:n_freq-1) .* (fft.sample_rate / n)

    # Find dominant frequency (skip DC component at index 1)
    if length(fft.power_spectrum) > 1
        # Skip first few bins (DC and very low freq)
        start_idx = max(2, round(Int, 0.01 * n_freq) + 1)
        valid_range = start_idx:n_freq

        if !isempty(valid_range)
            fft.dominant_power = fft.power_spectrum[max_idx]
        end
    end

    # Update oscillation detection status
    detect_oscillations!(fft)

    return fft.oscillation_detected
end

# Wrapper for FFTW.fft to handle potential issues
function fft_func(x::Vector{Float64})
    try
        return FFTW.fft(x)
    catch
        # Fallback to simple DFT if FFTW fails
        return simple_dft(x)
    end
end

"""Simple DFT fallback (slow but always works)"""
function simple_dft(x::Vector{Float64})
    n = length(x)
    result = zeros(ComplexF64, n)
    for k in 0:n-1
        for j in 0:n-1
            result[k+1] += x[j+1] * exp(-2π * im * k * j / n)
        end
    end
    return result
end

"""
Detect oscillations in the signal.
- threshold: minimum power ratio to consider as significant oscillation
- min_freq: minimum frequency to consider (Hz)
- max_freq: maximum frequency to consider (Hz)
"""
function detect_oscillations!(
    fft::FFTAnalyzer;
    threshold::Float64=0.3,
    min_freq::Float64=0.05,
    max_freq::Float64=0.5
)::Bool
    isempty(fft.power_spectrum) && return false

    # Find power in the oscillation frequency range
    total_power = sum(fft.power_spectrum)
    total_power < 1e-10 && return false

    oscillation_power = 0.0
    oscillation_freq = 0.0
    max_power = 0.0

    for (i, freq) in enumerate(fft.frequencies)
        if min_freq <= freq <= max_freq
            power = fft.power_spectrum[i]
            oscillation_power += power
            if power > max_power
                max_power = power
                oscillation_freq = freq
            end
        end
    end

    # Check if oscillation power is significant
    ratio = oscillation_power / total_power
    fft.oscillation_detected = ratio > threshold && max_power > threshold * total_power / length(fft.power_spectrum)
    fft.oscillation_freq = oscillation_freq

    return fft.oscillation_detected
end

"""Get the period of detected oscillation in seconds"""
function get_oscillation_period(fft::FFTAnalyzer)::Float64
    fft.oscillation_freq > 0 ? 1.0 / fft.oscillation_freq : Inf
end

# ============================
# SPECTRAL ANOMALY RESULT
# ============================

struct SpectralResult
    dominant_frequency::Float64
    dominant_power::Float64
    oscillation_detected::Bool
    oscillation_frequency::Float64
    oscillation_period::Float64
    spectral_entropy::Float64   # Measure of frequency distribution uniformity
end

"""Calculate spectral entropy (measure of signal complexity)"""
function spectral_entropy(power_spectrum::Vector{Float64})::Float64
    isempty(power_spectrum) && return 0.0

    # Normalize to probability distribution
    total = sum(power_spectrum)
    total < 1e-10 && return 0.0

    probs = power_spectrum ./ total

    # Calculate entropy
    entropy = 0.0
    for p in probs
        p > 0 && (entropy -= p * log2(p))
    end

    # Normalize by maximum entropy
    max_entropy = log2(length(power_spectrum))
    return entropy / max_entropy
end

"""Get full spectral analysis result"""
function get_spectral_result(fft::FFTAnalyzer)::SpectralResult
    SpectralResult(
        fft.dominant_freq,
        fft.dominant_power,
        fft.oscillation_detected,
        fft.oscillation_freq,
        get_oscillation_period(fft),
        spectral_entropy(fft.power_spectrum)
    )
end

# ============================
# CONVENIENCE FUNCTIONS
# ============================

"""
Analyze a signal for micro-stuttering (rapid oscillations).
Typical symptoms: fan hunting, CPU throttling oscillation.
"""
function detect_micro_stuttering(
    fft::FFTAnalyzer;
    min_freq::Float64=0.1,   # At least 1 cycle per 10 seconds
    max_freq::Float64=0.5    # At most 2 seconds per cycle
)::Bool
    analyze!(fft)
    return detect_oscillations!(fft; threshold=0.25, min_freq=min_freq, max_freq=max_freq)
end

"""Check if fan is hunting (oscillating between speeds)"""
function detect_fan_hunting(fft::FFTAnalyzer)::Bool
    return detect_micro_stuttering(fft; min_freq=0.02, max_freq=0.2)
end

"""Check if CPU is throttling rapidly"""
function detect_cpu_throttling_oscillation(fft::FFTAnalyzer)::Bool
    return detect_micro_stuttering(fft; min_freq=0.1, max_freq=1.0)
end
