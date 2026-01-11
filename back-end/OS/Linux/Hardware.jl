# OS/Linux/Hardware.jl
# ============================
# Hardware Sensor Collection Module
# ============================
# Collects physical sensor data from /sys/class/hwmon/
# - Voltages (Vcore, +12V, +5V, etc.)
# - Fan RPM
# - Chip identification
#
# NOTE: Sensor structs (VoltageSensor, FanSensor, HardwareSensors)
# are defined in types/MonitorTypes.jl

# HWMON_PATH is defined in CPU.jl (included before this file)

# ============================
# FILE READING UTILITIES
# ============================

"""Safely read an integer from a sysfs file"""
function read_sysfs_int(path::String)::Union{Int,Nothing}
    try
        isfile(path) || return nothing
        content = strip(read(path, String))
        return parse(Int, content)
    catch
        return nothing
    end
end

"""Safely read a string from a sysfs file"""
function read_sysfs_string(path::String)::String
    try
        isfile(path) || return ""
        return strip(read(path, String))
    catch
        return ""
    end
end

# ============================
# SENSOR PARSING
# ============================

"""Get chip name from hwmon directory"""
function get_chip_name(hwmon_dir::String)::String
    name_path = joinpath(hwmon_dir, "name")
    name = read_sysfs_string(name_path)
    return isempty(name) ? basename(hwmon_dir) : name
end

"""Parse voltage sensors from a hwmon directory"""
function parse_voltages(hwmon_dir::String, chip::String)::Vector{VoltageSensor}
    voltages = VoltageSensor[]

    # Scan for in*_input files (voltage readings in millivolts)
    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^in(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)

        # Read voltage value (millivolts -> volts)
        mv = read_sysfs_int(input_path)
        mv === nothing && continue
        voltage = mv / 1000.0

        # Try to get label
        label_path = joinpath(hwmon_dir, "in$(index)_label")
        label = read_sysfs_string(label_path)
        if isempty(label)
            label = "in$index"
        end

        push!(voltages, VoltageSensor(label, voltage, chip, index))
    end

    # Sort by index for consistent ordering
    sort!(voltages, by=v -> v.index)
    return voltages
end

"""Parse fan sensors from a hwmon directory"""
function parse_fans(hwmon_dir::String, chip::String)::Vector{FanSensor}
    fans = FanSensor[]

    # Scan for fan*_input files (RPM)
    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^fan(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)

        # Read RPM
        rpm = read_sysfs_int(input_path)
        rpm === nothing && continue

        # Try to get label
        label_path = joinpath(hwmon_dir, "fan$(index)_label")
        label = read_sysfs_string(label_path)
        if isempty(label)
            label = "fan$index"
        end

        push!(fans, FanSensor(label, rpm, chip, index))
    end

    # Sort by index for consistent ordering
    sort!(fans, by=f -> f.index)
    return fans
end

# ============================
# MAIN API
# ============================

"""
    get_hwmon_sensors() -> HardwareSensors

Scan all hwmon devices and collect voltage and fan readings.
Returns a snapshot with all discovered sensors.
"""
function get_hwmon_sensors()::HardwareSensors
    sensors = HardwareSensors()

    !isdir(HWMON_PATH) && return sensors

    for hwmon_entry in readdir(HWMON_PATH; join=true)
        !isdir(hwmon_entry) && continue

        # Resolve symlink if necessary
        hwmon_dir = islink(hwmon_entry) ? realpath(hwmon_entry) : hwmon_entry
        !isdir(hwmon_dir) && continue

        chip = get_chip_name(hwmon_dir)

        # Collect sensors
        append!(sensors.voltages, parse_voltages(hwmon_dir, chip))
        append!(sensors.fans, parse_fans(hwmon_dir, chip))
    end

    # Cache primary fan (first fan with non-zero RPM, or first fan)
    sensors.primary_cpu_fan_rpm = if !isempty(sensors.fans)
        active_fans = filter(f -> f.rpm > 0, sensors.fans)
        !isempty(active_fans) ? active_fans[1].rpm : sensors.fans[1].rpm
    else
        0
    end

    # Cache Vcore (look for common labels)
    sensors.vcore_voltage = 0.0
    for v in sensors.voltages
        lbl = lowercase(v.label)
        if occursin("vcore", lbl) || occursin("cpu", lbl) || v.label == "in0"
            sensors.vcore_voltage = v.value
            break
        end
    end

    sensors.timestamp = time()
    return sensors
end

"""
    update_hardware!(monitor::SystemMonitor)

Update the hardware sensors in the monitor.
"""
function update_hardware!(monitor)
    try
        monitor.hardware = get_hwmon_sensors()
    catch e
        @debug "Error reading hardware sensors" exception = e
    end
    return nothing
end

# ============================
# UTILITY FUNCTIONS
# ============================

"""Get primary CPU fan RPM (convenience function)"""
get_cpu_fan_rpm(sensors::HardwareSensors) = sensors.primary_cpu_fan_rpm

"""Get Vcore voltage (convenience function)"""
get_vcore(sensors::HardwareSensors) = sensors.vcore_voltage

"""Check if any fan is at 0 RPM (potential failure)"""
function has_stopped_fan(sensors::HardwareSensors)::Bool
    for fan in sensors.fans
        # Only consider fans that are typically active
        if fan.rpm == 0 && !occursin("opt", lowercase(fan.label))
            return true
        end
    end
    return false
end

"""Format sensors for display"""
function format_sensors(sensors::HardwareSensors)::String
    lines = String[]

    if !isempty(sensors.voltages)
        push!(lines, "Voltages:")
        for v in sensors.voltages
            push!(lines, "  $(v.label): $(round(v.value, digits=3))V")
        end
    end

    if !isempty(sensors.fans)
        push!(lines, "Fans:")
        for f in sensors.fans
            push!(lines, "  $(f.label): $(f.rpm) RPM")
        end
    end

    return join(lines, "\n")
end
