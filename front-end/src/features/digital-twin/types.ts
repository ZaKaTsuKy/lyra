
export interface TwinMapping {
    sensorId: string; // ex: "fan1_input", "cpu_core_0"
    meshId: string;   // ex: "Fan_Front", "CPU_Block"
    type: 'fan' | 'thermal' | 'led';
}

export interface TwinConfig {
    chassisType: 'tower' | 'laptop' | 'server';
    mappings: TwinMapping[];
}

export const DEFAULT_TWIN_CONFIG: TwinConfig = {
    chassisType: 'tower',
    mappings: [
        { sensorId: 'fan1_input', meshId: 'Fan_Cpu', type: 'fan' },
        { sensorId: 'temp1_input', meshId: 'CPU_Block', type: 'thermal' },
        { sensorId: 'fan2_input', meshId: 'Fan_Front', type: 'fan' },
    ],
};
