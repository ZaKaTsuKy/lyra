// omni.d.ts - Mirror of WebSocketServer.jl DTOs

export interface StaticDTO {
    cpu_model: string;
    cpu_cache: string;
    core_count: number;
    kernel_version: string;
    hostname: string;
}

export interface DiskDTO {
    mount: string;
    total_gb: number;
}

export interface HistoryDTO {
    cpu_usage: number[];
    mem_usage: number[];
    net_rx: number[];
    net_tx: number[];
    gpu_util: number[];
    disk_io: number[];
    cpu_temp: number[];
    timestamps: number[];
}

export interface InitPayload {
    type: "init";
    static: StaticDTO;
    disks: DiskDTO[];
    history: HistoryDTO;
    timestamp: number;
}

export interface CPUInstant {
    freq_avg: number;
    freq_max: number;
    load1: number;
    load5: number;
    load15: number;
    pressure_avg10: number;
    ctxt_switches_ps: number;
    interrupts_ps: number;
    temp_package: number;
    temp_max: number;
}

export interface MemoryInstant {
    total_kb: number;
    used_kb: number;
    avail_kb: number;
    swap_total_kb: number;
    swap_used_kb: number;
    pressure_avg10: number;
}

export interface GPUInstant {
    name: string;
    util: number;
    mem_used: number;
    mem_total: number;
    temp: number;
    power_draw: number;
    power_limit: number;
}

export interface NetworkInstant {
    primary_iface: string;
    rx_bps: number;
    tx_bps: number;
    classification: string;
    tcp_established: number;
    tcp_time_wait: number;
}

export interface DiskInstant {
    mount: string;
    used_gb: number;
    avail_gb: number;
    percent: number;
    read_bps: number;
    write_bps: number;
    // New fields
    read_iops: number;
    write_iops: number;
    avg_wait_ms: number;
    io_wait_pct: number;
}

export interface BatteryInstant {
    present: boolean;
    percent: number;
    status: string;
    power_w: number;
    time_remaining_min: number;
}

export interface SystemInstant {
    uptime_sec: number;
    environment: string;
    oom_kills: number;
    psi_cpu: number;
    psi_mem: number;
    psi_io: number;
    procs_running: number;
    procs_blocked: number;
}

export interface PredictionDTO {
    metric: string;              // e.g. "cpu", "mem", "io"
    time_to_critical_sec: number; // Estimated time to hit threshold
    confidence: number;          // 0.0-1.0
}

export interface AnomalyInstant {
    cpu: number;
    mem: number;
    io: number;
    net: number;
    gpu: number;
    temp: number;
    overall: number;
    trend: string;
    cpu_spike: boolean;
    mem_spike: boolean;
    io_spike: boolean;
    net_spike: boolean;
    // New fields
    cpu_trend: string;
    mem_trend: string;
    io_trend: string;
    net_trend: string;
    regime: string;
    predictions: PredictionDTO[];
    coherence_temp_alert: boolean;
    coherence_io_alert: boolean;
}

export interface ProcessInstant {
    pid: number;
    name: string;
    cpu: number;
    mem_kb: number;
    state: string; // Char in Julia, string in JSON
}

// New DTOs
export interface HardwareHealthDTO {
    thermal_efficiency: number;
    fan_status: string;
    voltage_stability: number;
    cooling_headroom: number;
    primary_fan_rpm: number;
    vcore_voltage: number;
    dry_thermal_paste: boolean;
    dusty_fan: boolean;
    unstable_voltage: boolean;
    diagnostics: string[];
}

export interface CognitiveInsightsDTO {
    iforest_score: number;
    oscillation_detected: boolean;
    oscillation_type: string;
    spectral_entropy_cpu: number;
    spectral_entropy_fan: number;
    behavioral_state: string;
    behavioral_anomaly: boolean;
    behavioral_description: string;
    state_stability: number;
}

export interface UpdatePayload {
    type: "update";
    cpu: CPUInstant;
    memory: MemoryInstant;
    gpu: GPUInstant | null;
    network: NetworkInstant;
    disks: DiskInstant[];
    battery: BatteryInstant;
    system: SystemInstant;
    anomaly: AnomalyInstant;
    top_processes: ProcessInstant[];
    hardware_health: HardwareHealthDTO | null; // NEW
    cognitive: CognitiveInsightsDTO | null;    // NEW
    update_count: number;
    timestamp: number;
}

export type OmniMessage = InitPayload | UpdatePayload | { type: "error"; message: string } | { type: "shutdown"; message: string };
