# OS/Linux/Hardware.jl
# ============================
# Hardware Sensor Collection Module v2.0
# ============================
# Collects ALL physical sensor data from /sys/class/hwmon/
# - CPU temps (k10temp/coretemp)
# - GPU sensors (amdgpu)
# - NVMe temps
# - Voltages (Super I/O)
# - Fan RPM (All fans)
# - Generic temperatures
#
# NOTE: Sensor structs are defined in types/MonitorTypes.jl

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

"""Read temperature in millicelsius and convert to Celsius"""
function read_temp_celsius(path::String)::Float64
    val = read_sysfs_int(path)
    return val === nothing ? 0.0 : val / 1000.0
end

# ============================
# CHIP IDENTIFICATION
# ============================

"""Get chip name from hwmon directory"""
function get_chip_name(hwmon_dir::String)::String
    name_path = joinpath(hwmon_dir, "name")
    name = read_sysfs_string(name_path)
    return isempty(name) ? basename(hwmon_dir) : name
end

# ============================
# SPECIALIZED PARSERS
# ============================

"""Parse AMD k10temp sensors (Ryzen CPUs)"""
function parse_k10temp(hwmon_dir::String)::CPUTemperatureExtended
    tctl = 0.0
    tdie = 0.0
    tccd = Float64[]
    critical = 100.0

    for entry in readdir(hwmon_dir; join=false)
        # Look for temp*_input files
        m = match(r"^temp(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)
        temp = read_temp_celsius(input_path)

        # Get label to identify sensor type
        label_path = joinpath(hwmon_dir, "temp$(index)_label")
        label = lowercase(read_sysfs_string(label_path))

        if occursin("tctl", label)
            tctl = temp
        elseif occursin("tdie", label)
            tdie = temp
        elseif occursin("tccd", label)
            push!(tccd, temp)
        elseif occursin("crit", label) || index == 1
            # Try to read critical temp
            crit_path = joinpath(hwmon_dir, "temp$(index)_crit")
            crit = read_temp_celsius(crit_path)
            if crit > 0
                critical = crit
            end
        end
    end

    tccd_max = isempty(tccd) ? 0.0 : maximum(tccd)

    return CPUTemperatureExtended(
        tctl, tdie, tccd, tccd_max,
        0.0, Float64[], critical  # package/cores for Intel
    )
end

"""Parse Intel coretemp sensors"""
function parse_coretemp(hwmon_dir::String)::CPUTemperatureExtended
    package = 0.0
    cores = Float64[]
    critical = 100.0

    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^temp(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)
        temp = read_temp_celsius(input_path)

        label_path = joinpath(hwmon_dir, "temp$(index)_label")
        label = lowercase(read_sysfs_string(label_path))

        if occursin("package", label)
            package = temp
            # Read critical
            crit_path = joinpath(hwmon_dir, "temp$(index)_crit")
            crit = read_temp_celsius(crit_path)
            if crit > 0
                critical = crit
            end
        elseif occursin("core", label)
            push!(cores, temp)
        end
    end

    return CPUTemperatureExtended(
        0.0, 0.0, Float64[], 0.0,  # tctl/tdie/tccd for AMD
        package, cores, critical
    )
end

"""Parse AMD GPU sensors from amdgpu hwmon"""
function parse_amdgpu(hwmon_dir::String)::GPUSensors
    edge = 0.0
    hotspot = 0.0
    mem = 0.0
    vdd = 0.0
    power = 0.0
    ppt = 0.0

    for entry in readdir(hwmon_dir; join=false)
        # Temperatures
        if startswith(entry, "temp") && endswith(entry, "_input")
            m = match(r"^temp(\d+)_input$", entry)
            m === nothing && continue

            index = parse(Int, m.captures[1])
            temp = read_temp_celsius(joinpath(hwmon_dir, entry))

            label_path = joinpath(hwmon_dir, "temp$(index)_label")
            label = lowercase(read_sysfs_string(label_path))

            if occursin("edge", label) || index == 1
                edge = temp
            elseif occursin("junction", label) || occursin("hotspot", label)
                hotspot = temp
            elseif occursin("mem", label)
                mem = temp
            end
        end

        # Voltage (in*_input, millivolts)
        if startswith(entry, "in") && endswith(entry, "_input")
            m = match(r"^in(\d+)_input$", entry)
            m === nothing && continue

            mv = read_sysfs_int(joinpath(hwmon_dir, entry))
            if mv !== nothing
                vdd = mv / 1000.0  # Convert to volts
            end
        end

        # Power (power*_average, microwatts)
        if entry == "power1_average"
            uw = read_sysfs_int(joinpath(hwmon_dir, entry))
            if uw !== nothing
                power = uw / 1_000_000.0  # Convert to watts
            end
        end

        # Power limit (power1_cap, microwatts)
        if entry == "power1_cap"
            uw = read_sysfs_int(joinpath(hwmon_dir, entry))
            if uw !== nothing
                ppt = uw / 1_000_000.0
            end
        end
    end

    return GPUSensors(edge, hotspot, mem, vdd, power, ppt)
end

"""Parse NVMe temperature sensors"""
function parse_nvme(hwmon_dir::String, chip::String)::NVMeSensor
    composite = 0.0
    sensor1 = 0.0
    sensor2 = 0.0

    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^temp(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        temp = read_temp_celsius(joinpath(hwmon_dir, entry))

        label_path = joinpath(hwmon_dir, "temp$(index)_label")
        label = lowercase(read_sysfs_string(label_path))

        if occursin("composite", label) || index == 1
            composite = temp
        elseif occursin("sensor 1", label) || index == 2
            sensor1 = temp
        elseif occursin("sensor 2", label) || index == 3
            sensor2 = temp
        end
    end

    return NVMeSensor(chip, composite, sensor1, sensor2)
end

"""Parse generic temperatures from Super I/O chips"""
function parse_temps(hwmon_dir::String, chip::String)::Vector{TempSensor}
    temps = TempSensor[]

    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^temp(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)
        temp = read_temp_celsius(input_path)

        # Skip invalid readings
        temp <= 0 && continue
        temp > 150 && continue  # Likely disconnected sensor

        label_path = joinpath(hwmon_dir, "temp$(index)_label")
        label = read_sysfs_string(label_path)
        if isempty(label)
            label = "temp$index"
        end

        push!(temps, TempSensor(label, temp, chip, index))
    end

    sort!(temps, by=t -> t.index)
    return temps
end

"""Parse voltage sensors from a hwmon directory"""
function parse_voltages(hwmon_dir::String, chip::String)::Vector{VoltageSensor}
    voltages = VoltageSensor[]

    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^in(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)

        mv = read_sysfs_int(input_path)
        mv === nothing && continue
        voltage = mv / 1000.0

        label_path = joinpath(hwmon_dir, "in$(index)_label")
        label = read_sysfs_string(label_path)
        if isempty(label)
            label = "in$index"
        end

        push!(voltages, VoltageSensor(label, voltage, chip, index))
    end

    sort!(voltages, by=v -> v.index)
    return voltages
end

"""Parse fan sensors from a hwmon directory"""
function parse_fans(hwmon_dir::String, chip::String)::Vector{FanSensor}
    fans = FanSensor[]

    for entry in readdir(hwmon_dir; join=false)
        m = match(r"^fan(\d+)_input$", entry)
        m === nothing && continue

        index = parse(Int, m.captures[1])
        input_path = joinpath(hwmon_dir, entry)

        rpm = read_sysfs_int(input_path)
        rpm === nothing && continue

        label_path = joinpath(hwmon_dir, "fan$(index)_label")
        label = read_sysfs_string(label_path)
        if isempty(label)
            label = "fan$index"
        end

        push!(fans, FanSensor(label, rpm, chip, index))
    end

    sort!(fans, by=f -> f.index)
    return fans
end

# ============================
# MAIN API
# ============================

"""
    get_full_sensors() -> FullSensors

Scan ALL hwmon devices and collect complete sensor data.
Uses chip-specific parsing for k10temp, amdgpu, nvme.
"""
function get_full_sensors()::FullSensors
    sensors = FullSensors()

    !isdir(HWMON_PATH) && return sensors

    for hwmon_entry in readdir(HWMON_PATH; join=true)
        !isdir(hwmon_entry) && continue

        hwmon_dir = islink(hwmon_entry) ? realpath(hwmon_entry) : hwmon_entry
        !isdir(hwmon_dir) && continue

        chip = get_chip_name(hwmon_dir)
        push!(sensors.chip_names, chip)

        # Route to specialized parser based on chip name
        if chip == "k10temp"
            sensors.cpu_temps = parse_k10temp(hwmon_dir)
        elseif chip == "coretemp"
            sensors.cpu_temps = parse_coretemp(hwmon_dir)
        elseif chip == "amdgpu"
            sensors.gpu_sensors = parse_amdgpu(hwmon_dir)
        elseif startswith(chip, "nvme")
            push!(sensors.nvme_sensors, parse_nvme(hwmon_dir, chip))
        else
            # Super I/O chips (nct6775, it87, etc.) -> generic collection
            append!(sensors.voltages, parse_voltages(hwmon_dir, chip))
            append!(sensors.fans, parse_fans(hwmon_dir, chip))
            append!(sensors.temps_generic, parse_temps(hwmon_dir, chip))
        end
    end

    sensors.timestamp = time()
    return sensors
end

"""
    get_hwmon_sensors() -> HardwareSensors

Legacy function for backwards compatibility.
"""
function get_hwmon_sensors()::HardwareSensors
    sensors = HardwareSensors()

    !isdir(HWMON_PATH) && return sensors

    for hwmon_entry in readdir(HWMON_PATH; join=true)
        !isdir(hwmon_entry) && continue

        hwmon_dir = islink(hwmon_entry) ? realpath(hwmon_entry) : hwmon_entry
        !isdir(hwmon_dir) && continue

        chip = get_chip_name(hwmon_dir)

        append!(sensors.voltages, parse_voltages(hwmon_dir, chip))
        append!(sensors.fans, parse_fans(hwmon_dir, chip))
    end

    # Cache primary fan
    sensors.primary_cpu_fan_rpm = 0
    for fan in sensors.fans
        if fan.rpm > 0
            sensors.primary_cpu_fan_rpm = fan.rpm
            break
        end
    end
    if sensors.primary_cpu_fan_rpm == 0 && !isempty(sensors.fans)
        sensors.primary_cpu_fan_rpm = sensors.fans[1].rpm
    end

    # Cache Vcore
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

Update both legacy hardware sensors and full sensors snapshot.
"""
function update_hardware!(monitor)
    try
        monitor.hardware = get_hwmon_sensors()
        monitor.full_sensors = get_full_sensors()
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
        if fan.rpm == 0 && !occursin("opt", lowercase(fan.label))
            return true
        end
    end
    return false
end

"""Format full sensors for display"""
function format_full_sensors(sensors::FullSensors)::String
    lines = String[]

    # CPU temps
    cpu = sensors.cpu_temps
    if cpu.tctl > 0
        push!(lines, "CPU (k10temp): Tctl=$(round(cpu.tctl, digits=1))°C Tdie=$(round(cpu.tdie, digits=1))°C")
        if !isempty(cpu.tccd)
            push!(lines, "  CCDs: " * join(["$(round(t, digits=1))°C" for t in cpu.tccd], ", "))
        end
    elseif cpu.package > 0
        push!(lines, "CPU (coretemp): Package=$(round(cpu.package, digits=1))°C")
        if !isempty(cpu.cores)
            push!(lines, "  Cores: " * join(["$(round(t, digits=1))°C" for t in cpu.cores], ", "))
        end
    end

    # GPU
    if sensors.gpu_sensors !== nothing
        gpu = sensors.gpu_sensors
        push!(lines, "GPU: Edge=$(round(gpu.edge_temp, digits=1))°C Power=$(round(gpu.power_w, digits=1))W")
    end

    # NVMe
    for nvme in sensors.nvme_sensors
        push!(lines, "$(nvme.name): $(round(nvme.temp_composite, digits=1))°C")
    end

    # Fans
    if !isempty(sensors.fans)
        push!(lines, "Fans:")
        for f in sensors.fans
            push!(lines, "  $(f.label): $(f.rpm) RPM")
        end
    end

    # Voltages
    if !isempty(sensors.voltages)
        push!(lines, "Voltages:")
        for v in sensors.voltages
            push!(lines, "  $(v.label): $(round(v.value, digits=3))V")
        end
    end

    return join(lines, "\n")
end
