# UI.jl
# ============================
# OMNI MONITOR - Advanced Dashboard UI v3.0
# ============================
# Enhanced with AI Analytics v3.0:
# - Z-Score (MAD) display
# - Regime detection indicator
# - CUSUM drift alerts
# - Holt-Winters trends
# - Physical coherence status
# - Saturation model visualization
# - Percentile display (P50/P95/P99)
# - Adaptive sampling rate
# - Prediction confidence
# ============================

using Printf
using Dates
using Statistics: mean

# ============================
# TERMINAL CONTROL
# ============================

cursor_home() = print("\033[H")
clear_to_end() = print("\033[J")
clear_screen() = print("\033[2J\033[H")
hide_cursor() = print("\033[?25l")
show_cursor() = print("\033[?25h")
move_to(r, c) = print("\033[$r;$(c)H")

# Disable stdout buffering for smoother updates
function setup_terminal()
    hide_cursor()
end

function cleanup_terminal()
    show_cursor()
end

function term_size()
    try
        h, w = displaysize(stdout)
        return (w=max(w, 80), h=max(h, 24))
    catch
        return (w=100, h=30)
    end
end

# ============================
# VISUAL WIDTH CALCULATION
# ============================
# Some Unicode characters (emojis, symbols) take 2 columns

const WIDE_CHARS = Set(['⚡', '⚠', '✔'])

"""
Safely truncate a string to a maximum visual width.
Handles UTF-8 multi-byte characters and ANSI escape codes correctly.
"""
function safe_truncate(s::String, max_width::Int)
    max_width <= 0 && return ""

    result = IOBuffer()
    current_width = 0
    in_ansi = false

    for c in s
        if c == '\033'
            in_ansi = true
            write(result, c)
        elseif in_ansi
            write(result, c)
            if c == 'm'
                in_ansi = false
            end
        else
            char_width = c in WIDE_CHARS ? 2 : 1
            if current_width + char_width > max_width
                break
            end
            write(result, c)
            current_width += char_width
        end
    end

    return String(take!(result))
end

"""
Safely truncate and add ellipsis if needed.
"""
function safe_truncate_ellipsis(s::String, max_width::Int, ellipsis::String="..")
    max_width <= length(ellipsis) && return ellipsis[1:min(max_width, length(ellipsis))]

    vis_w = visual_width(s)
    vis_w <= max_width && return s

    return safe_truncate(s, max_width - length(ellipsis)) * ellipsis
end

"""Calculate visual width of a string (accounting for wide chars and ANSI codes)"""
function visual_width(s::String)
    # Remove ANSI escape codes
    clean = replace(s, r"\033\[[0-9;]*m" => "")
    width = 0
    for c in clean
        # Most Unicode symbols are single-width in modern terminals
        # Only count true double-width characters (CJK, some emojis)
        if c in WIDE_CHARS
            width += 1  # Changed: treat these as single-width (most terminals do)
        else
            width += 1
        end
    end
    return width
end

"""Pad string to exact visual width"""
function pad_to_width(s::String, target_width::Int)
    current = visual_width(s)
    if current >= target_width
        return s
    end
    return s * (" "^(target_width - current))
end

# ============================
# ANSI COLORS (16 only)
# ============================

const C = (
    reset="\033[0m",
    bold="\033[1m",
    dim="\033[2m",
    italic="\033[3m",
    underline="\033[4m",
    blink="\033[5m",
    black="\033[30m",
    red="\033[31m",
    green="\033[32m",
    yellow="\033[33m",
    blue="\033[34m",
    magenta="\033[35m",
    cyan="\033[36m",
    white="\033[37m",
    bred="\033[91m",
    bgreen="\033[92m",
    byellow="\033[93m",
    bblue="\033[94m",
    bmagenta="\033[95m",
    bcyan="\033[96m",
    bwhite="\033[97m",
    bg_black="\033[40m",
    bg_red="\033[41m",
    bg_green="\033[42m",
    bg_blue="\033[44m",
)

function pct_color(pct::Real)
    pct < 50 && return C.green
    pct < 75 && return C.yellow
    pct < 90 && return C.byellow
    return C.red
end

function temp_color(temp::Real)
    temp < 60 && return C.green
    temp < 75 && return C.yellow
    temp < 85 && return C.byellow
    return C.red
end

function anomaly_color(score::Real)
    score < 0.3 && return C.green
    score < 0.6 && return C.yellow
    score < 0.8 && return C.byellow
    return C.red
end

# ============================
# UNICODE CHARACTERS
# ============================

const BOX = (
    tl="┌", tr="┐", bl="└", br="┘",
    h="-", v="|",
    lt="├", rt="┤", tt="┬", bt="┴", x="┼",
    H_tl="┏", H_tr="┓", H_bl="┗", H_br="┛",
    H_h="━", H_v="┃",
)

const HBLOCKS = [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█']
const SPARK = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
const TREND = (up="^", down="v", stable="-", spike="!")
const ICON = (rx="v", tx="^", temp="*", warn="!", ok="+")

# ============================
# FORMATTING
# ============================

function fmt_bytes(bytes::Real; precision=1)
    bytes < 0 && return "-" * fmt_bytes(-bytes; precision)
    if bytes < 1024
        return @sprintf("%dB", bytes)
    elseif bytes < 1024^2
        return precision == 0 ? @sprintf("%.0fK", bytes / 1024) : @sprintf("%.1fK", bytes / 1024)
    elseif bytes < 1024^3
        return precision == 0 ? @sprintf("%.0fM", bytes / 1024^2) : @sprintf("%.1fM", bytes / 1024^2)
    elseif bytes < 1024^4
        return precision == 0 ? @sprintf("%.0fG", bytes / 1024^3) : @sprintf("%.1fG", bytes / 1024^3)
    else
        return precision == 0 ? @sprintf("%.0fT", bytes / 1024^4) : @sprintf("%.1fT", bytes / 1024^4)
    end
end

function fmt_rate(bps::Real)
    bps < 1024 && return @sprintf("%dB/s", bps)
    bps < 1024^2 && return @sprintf("%.0fK/s", bps / 1024)
    bps < 1024^3 && return @sprintf("%.1fM/s", bps / 1024^2)
    return @sprintf("%.1fG/s", bps / 1024^3)
end

function fmt_duration(secs::Real)
    secs < 60 && return @sprintf("%ds", round(Int, secs))
    secs < 3600 && return @sprintf("%dm%ds", div(secs, 60), mod(round(Int, secs), 60))
    secs < 86400 && return @sprintf("%dh%dm", div(secs, 3600), div(mod(secs, 3600), 60))
    return @sprintf("%dd%dh", div(secs, 86400), div(mod(secs, 86400), 3600))
end

# ============================
# VISUAL COMPONENTS
# ============================

function progress_bar(pct::Real, width::Int; show_pct=true, color=nothing)
    pct = clamp(pct, 0.0, 100.0)
    fill_width = pct / 100 * width
    full_blocks = floor(Int, fill_width)
    partial = fill_width - full_blocks

    col = isnothing(color) ? pct_color(pct) : color
    bar = col * ('█'^full_blocks)

    if full_blocks < width
        partial_idx = clamp(round(Int, partial * 8) + 1, 1, 9)
        bar *= HBLOCKS[partial_idx]
        bar *= '░'^(width - full_blocks - 1)
    end
    bar *= C.reset

    if show_pct
        return bar * " " * col * @sprintf("%5.1f%%", pct) * C.reset
    end
    return bar
end

function mini_bar(pct::Real, width::Int)
    pct = clamp(pct, 0.0, 100.0)
    filled = round(Int, pct / 100 * width)
    col = pct_color(pct)
    return col * ('█'^filled) * C.dim * ('░'^(width - filled)) * C.reset
end

function sparkline(values::Vector{<:Real}, width::Int)
    isempty(values) && return C.dim * ("·"^width) * C.reset
    v = values[max(1, end - width + 1):end]
    min_v, max_v = extrema(v)
    range_v = max_v - min_v

    result = ""
    for val in v
        normalized = range_v > 0 ? (val - min_v) / range_v : 0.5
        idx = clamp(round(Int, normalized * 7) + 1, 1, 8)
        col = normalized < 0.5 ? C.green : normalized < 0.75 ? C.yellow : C.red
        result *= col * SPARK[idx]
    end

    padding = width - length(v)
    if padding > 0
        result = C.dim * ("·"^padding) * C.reset * result
    end
    return result * C.reset
end

function core_heatline(cores::Vector{CoreState}, width::Int)
    n = length(cores)
    n == 0 && return C.dim * ("·"^width) * C.reset

    if n > width
        group_size = ceil(Int, n / width)
        result = ""
        for i in 1:width
            start_idx = (i - 1) * group_size + 1
            end_idx = min(i * group_size, n)
            usages = [c.total > 0 ? 100.0 * (1 - c.idle / c.total) : 0.0 for c in cores[start_idx:end_idx]]
            avg_usage = mean(usages)
            idx = clamp(round(Int, avg_usage / 100 * 7) + 1, 1, 8)
            result *= pct_color(avg_usage) * SPARK[idx]
        end
        return result * C.reset
    else
        result = ""
        for core in cores
            usage = core.total > 0 ? 100.0 * (1 - core.idle / core.total) : 0.0
            idx = clamp(round(Int, usage / 100 * 7) + 1, 1, 8)
            result *= pct_color(usage) * SPARK[idx]
        end
        result *= C.dim * ("·"^(width - n)) * C.reset
        return result * C.reset
    end
end

function trend_indicator(trend::String, has_spike::Bool=false)
    if has_spike
        return C.bred * C.bold * TREND.spike * C.reset
    elseif trend == "rising"
        return C.red * TREND.up * C.reset
    elseif trend == "falling"
        return C.green * TREND.down * C.reset
    else
        return C.blue * TREND.stable * C.reset
    end
end

# ============================
# BOX DRAWING
# ============================

function draw_box(content::Vector{String}, width::Int; title="")
    result = String[]

    # Top border
    if isempty(title)
        push!(result, BOX.tl * (BOX.h^(width - 2)) * BOX.tr)
    else
        title_display = " $title "
        title_len = length(title_display)
        left_len = 2
        right_len = width - 2 - left_len - title_len
        push!(result, BOX.tl * (BOX.h^left_len) * C.bold * C.cyan * title_display * C.reset * (BOX.h^max(0, right_len)) * BOX.tr)
    end

    # Content lines - ensure exact width
    inner_width = width - 2
    for line in content
        vis_w = visual_width(line)
        if vis_w < inner_width
            padding = inner_width - vis_w
            push!(result, BOX.v * line * (" "^padding) * BOX.v)
        elseif vis_w > inner_width
            # Truncate safely for UTF-8
            push!(result, BOX.v * safe_truncate(line, inner_width) * BOX.v)
        else
            push!(result, BOX.v * line * BOX.v)
        end
    end

    # Bottom border
    push!(result, BOX.bl * (BOX.h^(width - 2)) * BOX.br)
    return result
end

"""Ensure a panel has exactly the specified width for each line"""
function normalize_panel_width(lines::Vector{String}, width::Int)
    result = String[]
    for line in lines
        vis_w = visual_width(line)
        if vis_w < width
            push!(result, line * (" "^(width - vis_w)))
        elseif vis_w > width
            # Should not happen, but handle gracefully
            push!(result, line)
        else
            push!(result, line)
        end
    end
    return result
end

# ============================
# PANEL BUILDERS
# ============================

function build_header(m::SystemMonitor, width::Int)
    cpu_usage = get_cpu_usage(m)
    mem_usage = get_memory_usage_percent(m)
    cpu_temp = get_cpu_temp(m)

    # Temperature indicator
    temp_str = cpu_temp > 0 ? @sprintf(" %s%s%.0f*C%s", ICON.temp, temp_color(cpu_temp), cpu_temp, C.reset) : ""

    gpu_str = isnothing(m.gpu) ? "" : @sprintf(" | GPU %s%.0f%%%s", pct_color(m.gpu.util), m.gpu.util, C.reset)

    net_str = @sprintf("%s%s %s%s", C.green, fmt_rate(m.network.rx_bps), C.cyan, fmt_rate(m.network.tx_bps))
    uptime = fmt_duration(m.system.uptime_sec)
    timestamp = Dates.format(now(), "HH:MM:SS")

    # Overall trend with spike indicator
    trend = trend_indicator(m.anomaly.trend, m.anomaly.cpu_spike || m.anomaly.mem_spike)

    left = @sprintf("%s%sOMNI%s%s MONITOR%s", C.bold, C.cyan, C.bwhite, C.bold, C.reset)

    cpu_spark = sparkline(m.history.cpu_usage, 8)
    cpu_part = @sprintf("CPU %s%.0f%%%s%s %s", pct_color(cpu_usage), cpu_usage, C.reset, temp_str, cpu_spark)
    mem_part = @sprintf("MEM %s%.0f%%%s", pct_color(mem_usage), mem_usage, C.reset)

    center = @sprintf("%s | %s%s | %s%s", cpu_part, mem_part, gpu_str, net_str, C.reset)
    right = @sprintf("%s | %s%s%s | %s", uptime, C.dim, timestamp, C.reset, trend)

    header_line = left * "  " * center * "  " * right

    top = C.cyan * BOX.H_tl * (BOX.H_h^(width - 2)) * BOX.H_tr * C.reset
    vis_len = length(replace(header_line, r"\033\[[0-9;]*m" => ""))
    pad = max(0, width - 2 - vis_len)
    content = C.cyan * BOX.H_v * C.reset * header_line * (" "^pad) * C.cyan * BOX.H_v * C.reset
    bottom = C.cyan * BOX.H_bl * (BOX.H_h^(width - 2)) * BOX.H_br * C.reset

    return [top, content, bottom]
end

function build_cpu_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]
    cpu_usage = get_cpu_usage(m)
    cpu_temp = get_cpu_temp(m)

    # Main bar with temperature
    temp_str = cpu_temp > 0 ? @sprintf(" %s%.0f*C%s", temp_color(cpu_temp), cpu_temp, C.reset) : ""
    push!(lines, progress_bar(cpu_usage, width - 14 - (cpu_temp > 0 ? 6 : 0)) * temp_str)

    # Load average with spike indicator
    n = Sys.CPU_THREADS
    load_col = m.cpu_info.load1 > n ? C.red : m.cpu_info.load1 > n * 0.7 ? C.yellow : C.green
    spike_ind = m.anomaly.cpu_spike ? C.bred * " " * TREND.spike * C.reset : ""
    push!(lines, @sprintf("Load: %s%.2f%s %.2f %.2f%s | %d cores",
        load_col, m.cpu_info.load1, C.reset, m.cpu_info.load5, m.cpu_info.load15, spike_ind, n))

    # Core heatline
    heat_width = min(width - 10, length(m.cores), 32)
    push!(lines, @sprintf("Cores: %s", core_heatline(m.cores, heat_width)))

    # Frequency and context switches per second
    if m.cpu_info.freq_avg > 0
        ctxt_str = m.cpu_info.ctxt_switches_ps > 0 ? @sprintf(" | %.0fK ctx/s", m.cpu_info.ctxt_switches_ps / 1000) : ""
        push!(lines, @sprintf("Freq: %.0f MHz%s", m.cpu_info.freq_avg, ctxt_str))
    end

    # History with trend
    spark_w = min(width - 14, 16)
    push!(lines, @sprintf("History: %s %s", sparkline(m.history.cpu_usage, spark_w), trend_indicator(m.anomaly.cpu_trend)))

    return draw_box(lines, width, title="CPU")
end

function build_memory_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]
    mem_usage = get_memory_usage_percent(m)
    total_gb = m.memory.total_kb / 1024 / 1024
    used_gb = m.memory.used_kb / 1024 / 1024

    # Main bar with spike indicator
    spike_ind = m.anomaly.mem_spike ? C.bred * TREND.spike * C.reset : ""
    push!(lines, @sprintf("%s %.1f/%.1fG %s", progress_bar(mem_usage, width - 24), used_gb, total_gb, spike_ind))

    # Swap
    if m.memory.swap_total_kb > 0
        swap_usage = get_swap_usage_percent(m)
        swap_gb = m.memory.swap_total_kb / 1024 / 1024
        swap_used = m.memory.swap_used_kb / 1024 / 1024
        push!(lines, @sprintf("Swap: %s %.1f/%.1fG", mini_bar(swap_usage, 10), swap_used, swap_gb))
    else
        push!(lines, "Swap: " * C.dim * "none" * C.reset)
    end

    # Composition bar
    anon_pct = m.memory.total_kb > 0 ? m.memory.anon_kb / m.memory.total_kb * 100 : 0
    cache_pct = m.memory.total_kb > 0 ? m.memory.file_kb / m.memory.total_kb * 100 : 0

    comp_width = width - 8
    anon_w = round(Int, anon_pct / 100 * comp_width)
    cache_w = round(Int, cache_pct / 100 * comp_width)
    free_w = comp_width - anon_w - cache_w

    comp_bar = C.red * ("█"^anon_w) * C.yellow * ("█"^cache_w) * C.dim * ("░"^max(0, free_w)) * C.reset
    push!(lines, comp_bar)
    push!(lines, C.red * "■" * C.reset * "Apps " * C.yellow * "■" * C.reset * "Cache")

    # History with trend
    push!(lines, @sprintf("History: %s %s", sparkline(m.history.mem_usage, min(width - 14, 16)), trend_indicator(m.anomaly.mem_trend)))

    return draw_box(lines, width, title="MEMORY")
end

function build_gpu_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]

    if isnothing(m.gpu)
        push!(lines, C.dim * "No NVIDIA GPU detected" * C.reset)
        push!(lines, "")
        push!(lines, C.dim * "nvidia-smi not available" * C.reset)
        return draw_box(lines, width, title="GPU")
    end

    g = m.gpu
    name = safe_truncate_ellipsis(g.name, width - 6, "...")
    push!(lines, C.magenta * name * C.reset)

    push!(lines, @sprintf("Util: %s", progress_bar(g.util, width - 14)))

    vram_pct = g.mem_total > 0 ? g.mem_used / g.mem_total * 100 : 0
    push!(lines, @sprintf("VRAM: %s %.1f/%.0fG", mini_bar(vram_pct, 10), g.mem_used, g.mem_total))

    temp_col = g.temp > 80 ? C.red : g.temp > 70 ? C.yellow : C.green
    push!(lines, @sprintf("%s%.0f*C%s | %s%.0f%s/%.0fW", temp_col, g.temp, C.reset, C.yellow, g.power_draw, C.reset, g.power_limit))

    push!(lines, @sprintf("SM: %.0f MHz | Mem: %.0f MHz", g.sm_clock, g.mem_clock))

    if !isempty(g.throttling)
        push!(lines, C.red * C.bold * "[!] THROTTLING" * C.reset)
    end

    return draw_box(lines, width, title="GPU")
end

function build_network_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]
    n = m.network

    if isempty(n.interfaces)
        push!(lines, C.dim * "No network interfaces" * C.reset)
        return draw_box(lines, width, title="NETWORK")
    end

    class_col = n.classification == "saturated" ? C.red : n.classification == "burst" ? C.yellow : C.green
    push!(lines, @sprintf("%s%s%s [%s%s%s]", C.bold, n.primary_iface, C.reset, class_col, n.classification, C.reset))

    rx_pct = min(n.rx_bps / 1e8 * 100, 100)
    push!(lines, @sprintf("%s RX %s %s", C.green * ICON.rx * C.reset, mini_bar(rx_pct, 12), fmt_rate(n.rx_bps)))

    tx_pct = min(n.tx_bps / 1e8 * 100, 100)
    push!(lines, @sprintf("%s TX %s %s", C.cyan * ICON.tx * C.reset, mini_bar(tx_pct, 12), fmt_rate(n.tx_bps)))

    # TCP connection stats (NEW)
    tcp = n.tcp
    if tcp.total > 0
        push!(lines, @sprintf("TCP: %s%d%s est | %d tw | %d cw",
            C.green, tcp.established, C.reset, tcp.time_wait, tcp.close_wait))
    end

    spark_w = min(div(width - 12, 2), 10)
    push!(lines, @sprintf("RX %s TX %s %s",
        sparkline(m.history.net_rx, spark_w),
        sparkline(m.history.net_tx, spark_w),
        trend_indicator(m.anomaly.net_trend, m.anomaly.net_spike)))

    return draw_box(lines, width, title="NETWORK")
end

function build_disk_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]

    sorted_disks = sort(m.disks, by=d -> d.percent, rev=true)
    for disk in sorted_disks[1:min(3, length(sorted_disks))]
        mount = safe_truncate_ellipsis(disk.mount, 10, "..")
        push!(lines, @sprintf("%-10s %s %.0f%%", mount, mini_bar(disk.percent, 10), disk.percent))
    end

    if !isempty(m.disk_io)
        push!(lines, "")
        dio = get_total_disk_io(m)
        # Show throughput and IOPS (NEW)
        push!(lines, @sprintf("IO: %sR%.1f%s %sW%.1f%s MB/s",
            C.green, dio.read, C.reset, C.cyan, dio.write, C.reset))
        push!(lines, @sprintf("IOPS: %s%.0f%s r | %s%.0f%s w",
            C.green, dio.read_iops, C.reset, C.cyan, dio.write_iops, C.reset))

        push!(lines, @sprintf("IO: %s %s", sparkline(m.history.disk_io, min(width - 10, 12)), trend_indicator(m.anomaly.io_trend, m.anomaly.io_spike)))
    end

    return draw_box(lines, width, title="DISK")
end

function build_process_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]

    name_w = max(width - 36, 10)
    header = C.dim * rpad("PID", 6) * " " * rpad("NAME", name_w) * " " * "ST" * " " * lpad("CPU%", 5) * " " * lpad("IO", 7) * C.reset
    push!(lines, header)

    max_procs = min(10, height - 3, length(m.processes))

    for proc in m.processes[1:max_procs]
        name = proc.name
        if visual_width(name) > name_w
            name = safe_truncate_ellipsis(name, name_w, "..")
        end
        name = rpad(name, name_w)

        cpu_col = pct_color(proc.cpu)
        io_rate = proc.io_read_bps + proc.io_write_bps

        # Process state coloring (NEW)
        state_col = proc.state == 'R' ? C.green : proc.state == 'D' ? C.red : C.dim
        state_str = state_col * string(proc.state) * " " * C.reset

        cpu_bar = mini_bar(min(proc.cpu, 100), 5)
        pid_str = rpad(string(proc.pid), 6)
        cpu_str = @sprintf("%4.1f", proc.cpu)

        line = pid_str * " " * name * " " * state_str * cpu_bar * " " * cpu_col * cpu_str * C.reset * " " * fmt_rate(io_rate)
        push!(lines, line)
    end

    return draw_box(lines, width, title="PROCESSES (by CPU)")
end

function build_anomaly_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]
    a = m.anomaly

    # Overall with prediction warning
    overall_pct = a.overall * 100
    overall_col = anomaly_color(a.overall)

    # Check for predictions
    pred_str = ""
    if !isempty(a.predictions)
        pred = a.predictions[1]
        pred_str = @sprintf(" %s→%s in %s%s", C.yellow, pred.metric, format_time_remaining(pred.time_to_critical_sec), C.reset)
    end

    push!(lines, @sprintf("%sOVERALL: %.0f%%%s %s%s", overall_col * C.bold, overall_pct, C.reset, trend_indicator(a.trend), pred_str))
    push!(lines, "")

    # Individual scores with trends and spike indicators
    scores = [
        ("CPU", a.cpu, a.cpu_trend, a.cpu_spike),
        ("MEM", a.mem, a.mem_trend, a.mem_spike),
        ("I/O", a.io, a.io_trend, a.io_spike),
        ("NET", a.net, a.net_trend, a.net_spike),
        ("GPU", a.gpu, "stable", false),
        ("TMP", a.temp, "stable", false),
    ]

    bar_width = 8
    for (name, score, trend, spike) in scores
        pct = score * 100
        col = anomaly_color(score)
        trend_str = trend_indicator(trend, spike)
        push!(lines, @sprintf("%s %s %s%3.0f%%%s %s", name, mini_bar(pct, bar_width), col, pct, C.reset, trend_str))
    end

    return draw_box(lines, width, title="AI ANOMALY")
end

# ============================
# AI ANALYTICS PANEL (NEW v3.0)
# ============================

function zscore_color(z::Real)
    az = abs(z)
    az < 1.5 && return C.green
    az < 2.5 && return C.yellow
    az < 3.5 && return C.byellow
    return C.red
end

function regime_color(regime::String)
    regime == "idle" && return C.dim
    regime == "normal" && return C.green
    regime == "gaming" && return C.magenta
    regime == "compute" && return C.yellow
    regime == "heavy_io" && return C.cyan
    regime == "memory_intensive" && return C.byellow
    return C.white
end

function build_analytics_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]

    # Get AI diagnostic data
    diag = get_ai_diagnostic()
    regime = get_current_regime()
    interval = get_recommended_sample_interval()

    # Header: Regime & Sample Rate
    regime_col = regime_color(regime)
    push!(lines, @sprintf("%sREGIME:%s %s%s%s | Sample: %.1fs",
        C.bold, C.reset, regime_col, uppercase(regime), C.reset, interval))
    push!(lines, "")

    # Z-Scores (Robust MAD-based)
    push!(lines, C.dim * "--- Z-Scores (MAD) ---" * C.reset)

    cpu_z = diag.cpu.z
    mem_z = diag.mem.z
    io_z = diag.io.z_tp

    push!(lines, @sprintf("CPU: %s%+.2f%s | MEM: %s%+.2f%s | IO: %s%+.2f%s",
        zscore_color(cpu_z), cpu_z, C.reset,
        zscore_color(mem_z), mem_z, C.reset,
        zscore_color(io_z), io_z, C.reset))

    # Drift Detection (CUSUM)
    push!(lines, "")
    push!(lines, C.dim * "--- Drift Detection ---" * C.reset)

    drift_parts = String[]
    if diag.cpu.drift
        push!(drift_parts, C.red * "CPU" * C.reset)
    end
    if diag.mem.drift
        push!(drift_parts, C.red * "MEM" * (diag.mem.trend > 0 ? "+" : "-") * C.reset)
    end
    if diag.io.drift
        push!(drift_parts, C.red * "IO" * C.reset)
    end

    if isempty(drift_parts)
        push!(lines, C.green * "[OK] No drift detected" * C.reset)
    else
        push!(lines, C.yellow * "[!] CUSUM: " * C.reset * join(drift_parts, ", "))
    end

    # Holt-Winters Trends
    push!(lines, "")
    push!(lines, C.dim * "--- HW Trends (/sec) ---" * C.reset)

    cpu_trend = diag.cpu.trend
    mem_trend = diag.mem.trend

    cpu_t_col = cpu_trend > 0.1 ? C.red : cpu_trend < -0.1 ? C.green : C.blue
    mem_t_col = mem_trend > 0.1 ? C.red : mem_trend < -0.1 ? C.green : C.blue

    push!(lines, @sprintf("CPU: %s%+.3f%s | MEM: %s%+.3f%s",
        cpu_t_col, cpu_trend, C.reset,
        mem_t_col, mem_trend, C.reset))

    # Physical Coherence
    push!(lines, "")
    push!(lines, C.dim * "--- Coherence ---" * C.reset)

    coherence_ok = !diag.coherence.temp_anom && !diag.coherence.io_anom
    if coherence_ok
        push!(lines, @sprintf("%s[OK]%s CPU<>Temp: %.2f | IO<>Lat: %.2f",
            C.green, C.reset,
            diag.coherence.cpu_temp, diag.coherence.io_lat))
    else
        if diag.coherence.temp_anom
            push!(lines, C.red * "[!] Temp without CPU load!" * C.reset)
        end
        if diag.coherence.io_anom
            push!(lines, C.red * "[!] Latency without IO!" * C.reset)
        end
    end

    # Percentiles
    push!(lines, "")
    push!(lines, C.dim * "--- Percentiles ---" * C.reset)

    cpu_p = get_metric_percentiles(:cpu)
    mem_p = get_metric_percentiles(:mem)

    push!(lines, @sprintf("CPU P50/95/99: %.0f/%.0f/%.0f%%", cpu_p.p50, cpu_p.p95, cpu_p.p99))
    push!(lines, @sprintf("MEM P50/95/99: %.0f/%.0f/%.0f%%", mem_p.p50, mem_p.p95, mem_p.p99))

    # Predictions
    if !isempty(m.anomaly.predictions)
        push!(lines, "")
        push!(lines, C.dim * "--- Predictions ---" * C.reset)
        for pred in m.anomaly.predictions[1:min(3, length(m.anomaly.predictions))]
            time_str = format_time_remaining(pred.time_to_critical_sec)
            conf_col = pred.confidence > 0.7 ? C.red : C.yellow
            push!(lines, @sprintf("%s%s%s -> %.0f%% in %s (%.0f%% conf)",
                conf_col, pred.metric, C.reset, pred.threshold, time_str, pred.confidence * 100))
        end
    end

    # Sample count
    push!(lines, "")
    push!(lines, C.dim * @sprintf("Samples: %d | Regimes: CPU#%d MEM#%d",
                     diag.sample_count, diag.cpu.regime, diag.mem.regime) * C.reset)

    return draw_box(lines, width, title="AI ANALYTICS v3.0")
end

function build_saturation_panel(m::SystemMonitor, width::Int, height::Int)
    lines = String[]

    push!(lines, C.dim * "--- Disk Saturation ---" * C.reset)

    has_io = false
    for (dev, io) in m.disk_io
        has_io = true
        util = io.io_wait_pct / 100.0
        sat = analyze_saturation(util, io.avg_wait_ms, io.queue_depth)

        # Saturation bar with knee indicator
        sat_pct = sat.saturation_score * 100
        sat_col = sat_pct < 50 ? C.green : sat_pct < 80 ? C.yellow : C.red
        knee_ind = sat.at_knee_point ? C.bred * " [!]KNEE" * C.reset : ""

        dev_short = safe_truncate_ellipsis(dev, 8, "..")
        push!(lines, @sprintf("%s: %s %s%.0f%%%s%s",
            rpad(dev_short, 8), mini_bar(sat_pct, 10), sat_col, sat_pct, C.reset, knee_ind))
        push!(lines, @sprintf("  Lat: %.1fms | Q: %.1f", io.avg_wait_ms, io.queue_depth))
    end

    if !has_io
        push!(lines, C.dim * "No disk IO data" * C.reset)
    end

    push!(lines, "")
    push!(lines, C.dim * "--- Network Queue ---" * C.reset)

    net_util = (m.network.rx_bps + m.network.tx_bps) / 1e9  # Assume 1Gbps max
    net_sat = analyze_saturation(min(net_util, 1.0), 0.0, 0.0)
    net_pct = net_sat.saturation_score * 100
    net_col = net_pct < 50 ? C.green : net_pct < 80 ? C.yellow : C.red

    push!(lines, @sprintf("Net: %s %s%.0f%%%s", mini_bar(net_pct, 12), net_col, net_pct, C.reset))

    return draw_box(lines, width, title="SATURATION")
end

function build_alert_ticker(m::SystemMonitor, width::Int)
    alerts = generate_alerts(m)

    if isempty(alerts)
        return C.green * ICON.ok * " All systems nominal" * C.reset
    end

    parts = String[]
    for alert in alerts[1:min(3, length(alerts))]
        sym = alert.level == :critical ? C.red * "*" * C.reset :
              alert.level == :warning ? C.yellow * "*" * C.reset :
              C.blue * "*" * C.reset
        push!(parts, @sprintf("%s %s", sym, alert.message))
    end

    ticker = join(parts, " | ")

    if length(alerts) > 3
        ticker *= @sprintf(" | %s+%d more%s", C.dim, length(alerts) - 3, C.reset)
    end

    return ticker
end

function build_footer(width::Int)
    left = C.dim * "Ctrl+C: exit | Refresh: 0.5s" * C.reset
    right = C.dim * Dates.format(now(), "yyyy-mm-dd HH:MM:SS.sss") * C.reset
    mid_space = width - 28 - 23
    return left * (" "^max(1, mid_space)) * right
end

# ============================
# MAIN LAYOUT
# ============================

const _first_render = Ref(true)
const _output_buffer = Ref{IOBuffer}(IOBuffer())

function render_dashboard(m::SystemMonitor)
    sz = term_size()
    w = sz.w
    h = sz.h

    # Build all output first (double-buffering to avoid flicker)
    output = String[]
    append!(output, build_header(m, w))

    if w >= 140
        # Extra wide: 4 columns with dedicated analytics
        col_w = div(w - 6, 4)

        # Row 1: CPU, Memory, GPU, Anomaly
        cpu_lines = normalize_panel_width(build_cpu_panel(m, col_w, 8), col_w)
        mem_lines = normalize_panel_width(build_memory_panel(m, col_w, 8), col_w)
        gpu_lines = normalize_panel_width(build_gpu_panel(m, col_w, 8), col_w)
        anom_lines = normalize_panel_width(build_anomaly_panel(m, col_w, 10), col_w)

        max_h = max(length(cpu_lines), length(mem_lines), length(gpu_lines), length(anom_lines))
        for i in 1:max_h
            l1 = i <= length(cpu_lines) ? cpu_lines[i] : " "^col_w
            l2 = i <= length(mem_lines) ? mem_lines[i] : " "^col_w
            l3 = i <= length(gpu_lines) ? gpu_lines[i] : " "^col_w
            l4 = i <= length(anom_lines) ? anom_lines[i] : " "^col_w
            push!(output, l1 * " " * l2 * " " * l3 * " " * l4)
        end

        # Row 2: Network, Disk, Saturation, AI Analytics
        net_lines = normalize_panel_width(build_network_panel(m, col_w, 8), col_w)
        disk_lines = normalize_panel_width(build_disk_panel(m, col_w, 10), col_w)
        sat_lines = normalize_panel_width(build_saturation_panel(m, col_w, 10), col_w)
        analytics_lines = normalize_panel_width(build_analytics_panel(m, col_w, 20), col_w)

        max_h = max(length(net_lines), length(disk_lines), length(sat_lines), length(analytics_lines))
        for i in 1:max_h
            l1 = i <= length(net_lines) ? net_lines[i] : " "^col_w
            l2 = i <= length(disk_lines) ? disk_lines[i] : " "^col_w
            l3 = i <= length(sat_lines) ? sat_lines[i] : " "^col_w
            l4 = i <= length(analytics_lines) ? analytics_lines[i] : " "^col_w
            push!(output, l1 * " " * l2 * " " * l3 * " " * l4)
        end

        proc_lines = build_process_panel(m, w, 10)
        append!(output, proc_lines)

    elseif w >= 100
        col_w = div(w - 4, 3)

        cpu_lines = normalize_panel_width(build_cpu_panel(m, col_w, 8), col_w)
        mem_lines = normalize_panel_width(build_memory_panel(m, col_w, 8), col_w)
        gpu_lines = normalize_panel_width(build_gpu_panel(m, col_w, 8), col_w)

        max_h = max(length(cpu_lines), length(mem_lines), length(gpu_lines))
        for i in 1:max_h
            l1 = i <= length(cpu_lines) ? cpu_lines[i] : " "^col_w
            l2 = i <= length(mem_lines) ? mem_lines[i] : " "^col_w
            l3 = i <= length(gpu_lines) ? gpu_lines[i] : " "^col_w
            push!(output, l1 * " " * l2 * " " * l3)
        end

        net_lines = normalize_panel_width(build_network_panel(m, col_w, 8), col_w)
        disk_lines = normalize_panel_width(build_disk_panel(m, col_w, 10), col_w)
        anom_lines = normalize_panel_width(build_anomaly_panel(m, col_w, 12), col_w)

        max_h = max(length(net_lines), length(disk_lines), length(anom_lines))
        for i in 1:max_h
            l1 = i <= length(net_lines) ? net_lines[i] : " "^col_w
            l2 = i <= length(disk_lines) ? disk_lines[i] : " "^col_w
            l3 = i <= length(anom_lines) ? anom_lines[i] : " "^col_w
            push!(output, l1 * " " * l2 * " " * l3)
        end

        # Add Analytics panel in wide mode
        analytics_w = div(w - 2, 2)
        sat_lines = normalize_panel_width(build_saturation_panel(m, analytics_w, 10), analytics_w)
        analytics_lines = normalize_panel_width(build_analytics_panel(m, analytics_w, 20), analytics_w)

        max_h = max(length(sat_lines), length(analytics_lines))
        for i in 1:max_h
            l1 = i <= length(sat_lines) ? sat_lines[i] : " "^analytics_w
            l2 = i <= length(analytics_lines) ? analytics_lines[i] : " "^analytics_w
            push!(output, l1 * " " * l2)
        end

        proc_lines = build_process_panel(m, w, 12)
        append!(output, proc_lines)

    elseif w >= 80
        col_w = div(w - 2, 2)

        cpu_lines = normalize_panel_width(build_cpu_panel(m, col_w, 8), col_w)
        mem_lines = normalize_panel_width(build_memory_panel(m, col_w, 8), col_w)
        max_h = max(length(cpu_lines), length(mem_lines))
        for i in 1:max_h
            l1 = i <= length(cpu_lines) ? cpu_lines[i] : " "^col_w
            l2 = i <= length(mem_lines) ? mem_lines[i] : " "^col_w
            push!(output, l1 * " " * l2)
        end

        gpu_lines = normalize_panel_width(build_gpu_panel(m, col_w, 8), col_w)
        net_lines = normalize_panel_width(build_network_panel(m, col_w, 8), col_w)
        max_h = max(length(gpu_lines), length(net_lines))
        for i in 1:max_h
            l1 = i <= length(gpu_lines) ? gpu_lines[i] : " "^col_w
            l2 = i <= length(net_lines) ? net_lines[i] : " "^col_w
            push!(output, l1 * " " * l2)
        end

        disk_lines = normalize_panel_width(build_disk_panel(m, col_w, 8), col_w)
        anom_lines = normalize_panel_width(build_anomaly_panel(m, col_w, 10), col_w)
        max_h = max(length(disk_lines), length(anom_lines))
        for i in 1:max_h
            l1 = i <= length(disk_lines) ? disk_lines[i] : " "^col_w
            l2 = i <= length(anom_lines) ? anom_lines[i] : " "^col_w
            push!(output, l1 * " " * l2)
        end

        # Add compact analytics
        analytics_lines = build_analytics_panel(m, w, 15)
        append!(output, analytics_lines)

        proc_lines = build_process_panel(m, w, 10)
        append!(output, proc_lines)
    else
        append!(output, build_cpu_panel(m, w, 6))
        append!(output, build_memory_panel(m, w, 6))
        append!(output, build_gpu_panel(m, w, 6))
        append!(output, build_network_panel(m, w, 6))
        append!(output, build_disk_panel(m, w, 6))
        append!(output, build_anomaly_panel(m, w, 8))
        append!(output, build_analytics_panel(m, w, 12))
        append!(output, build_process_panel(m, w, 8))
    end

    push!(output, "")
    push!(output, build_alert_ticker(m, w))
    push!(output, build_footer(w))

    # Pad all lines to full width to overwrite previous content
    for i in eachindex(output)
        vis_w = visual_width(output[i])
        if vis_w < w
            output[i] *= " "^(w - vis_w)
        end
    end

    # Render without flicker using single write
    buf = IOBuffer()

    if _first_render[]
        # First render: hide cursor and clear screen
        write(buf, "\033[?25l")  # Hide cursor
        write(buf, "\033[2J")    # Clear screen
        write(buf, "\033[H")     # Home
        _first_render[] = false
    else
        # Subsequent renders: just move cursor home (no clear = no flicker)
        write(buf, "\033[H")
    end

    # Write all content
    write(buf, join(output, "\n"))

    # Clear any remaining lines below current output
    write(buf, "\033[J")

    # Single atomic write to terminal
    write(stdout, take!(buf))
    flush(stdout)

    return nothing
end