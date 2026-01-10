# OS/Linux/Battery.jl
# ============================
# Battery Collector - Linux
# ============================

const POWER_SUPPLY_PATH = "/sys/class/power_supply"

# --------------------------
# Helper functions
# --------------------------

function read_sysfs_float(path::String)
    try
        return parse(Float64, strip(read(path, String)))
    catch
        return 0.0
    end
end

function read_sysfs_string(path::String)
    try
        return strip(read(path, String))
    catch
        return ""
    end
end

function detect_battery()
    isdir(POWER_SUPPLY_PATH) || return nothing
    
    try
        for dev in readdir(POWER_SUPPLY_PATH)
            startswith(dev, "BAT") && return joinpath(POWER_SUPPLY_PATH, dev)
        end
    catch
    end
    
    return nothing
end

function detect_ac()
    isdir(POWER_SUPPLY_PATH) || return nothing
    
    try
        for dev in readdir(POWER_SUPPLY_PATH)
            if startswith(dev, "AC") || startswith(dev, "ACAD") || startswith(dev, "ADP")
                return joinpath(POWER_SUPPLY_PATH, dev)
            end
        end
    catch
    end
    
    return nothing
end

# --------------------------
# High-level collector
# --------------------------

function update_battery!(monitor::SystemMonitor)
    bat_path = detect_battery()
    
    # Desktop / no battery
    if bat_path === nothing
        monitor.battery = BatteryInfo(
            false,      # present
            0.0,        # percent
            "NoBattery",# status
            0.0,        # power_w
            0.0,        # energy_now
            0.0,        # energy_full
            0.0,        # energy_design
            0.0,        # time_remaining_min
            0.0,        # health_percent
            "AC"        # source
        )
        return nothing
    end
    
    # Read values
    status = read_sysfs_string(joinpath(bat_path, "status"))
    
    energy_now = read_sysfs_float(joinpath(bat_path, "energy_now")) / 1_000_000
    energy_full = read_sysfs_float(joinpath(bat_path, "energy_full")) / 1_000_000
    energy_design = read_sysfs_float(joinpath(bat_path, "energy_full_design")) / 1_000_000
    
    # Some systems use charge_* instead of energy_*
    if energy_now == 0.0
        energy_now = read_sysfs_float(joinpath(bat_path, "charge_now")) / 1_000_000
        energy_full = read_sysfs_float(joinpath(bat_path, "charge_full")) / 1_000_000
        energy_design = read_sysfs_float(joinpath(bat_path, "charge_full_design")) / 1_000_000
    end
    
    percent = energy_full > 0 ? (energy_now / energy_full) * 100 : 0.0
    
    power = read_sysfs_float(joinpath(bat_path, "power_now")) / 1_000_000
    power_w = status == "Discharging" ? -power : power
    
    # Time estimation
    time_remaining = 0.0
    if power > 0
        if status == "Discharging"
            time_remaining = (energy_now / power) * 60  # minutes
        elseif status == "Charging"
            time_remaining = ((energy_full - energy_now) / power) * 60
        end
    end
    
    # Health
    health = energy_design > 0 ? (energy_full / energy_design) * 100 : 0.0
    
    # Power source
    ac_path = detect_ac()
    source = "Unknown"
    if ac_path !== nothing
        online = read_sysfs_string(joinpath(ac_path, "online"))
        source = online == "1" ? "AC" : "Battery"
    end
    
    monitor.battery = BatteryInfo(
        true,
        percent,
        status,
        power_w,
        energy_now,
        energy_full,
        energy_design,
        time_remaining,
        health,
        source
    )
    
    return nothing
end

"""Check if running on battery power"""
function is_on_battery(monitor::SystemMonitor)
    return monitor.battery.present && monitor.battery.source == "Battery"
end

"""Get formatted time remaining"""
function get_battery_time_remaining(monitor::SystemMonitor)
    mins = monitor.battery.time_remaining_min
    mins <= 0 && return "N/A"
    
    hours = Int(floor(mins / 60))
    remaining_mins = Int(floor(mins % 60))
    
    return @sprintf("%dh %02dm", hours, remaining_mins)
end
