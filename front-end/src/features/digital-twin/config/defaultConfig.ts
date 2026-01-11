import type { TwinConfig, TwinMapping } from '../types';

export const INITIAL_TWIN_CONFIG: TwinConfig = {
    chassisType: 'tower',
    mappings: [
        { sensorId: 'fan1_input', meshId: 'Fan_Cpu', type: 'fan' },
        { sensorId: 'Tctl', meshId: 'CPU_Block', type: 'thermal' }, // Tctl is common for AMD, or Package id 0 for Intel
        { sensorId: 'fan2_input', meshId: 'Fan_Back', type: 'fan' },
    ]
};

// Helper to find mapping by meshId
export const getMappingForMesh = (config: TwinConfig, meshId: string): TwinMapping | undefined => {
    return config.mappings.find(m => m.meshId === meshId);
};
