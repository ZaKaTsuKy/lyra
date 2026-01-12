import { lazy, type LazyExoticComponent, type ComponentType } from 'react';

export interface WidgetDefinition {
    id: string;
    title: string;
    description: string;
    component: LazyExoticComponent<ComponentType<any>>;
    defaultSize: { w: number; h: number };
}

// Lazy load widgets to split chunks
const CpuWidget = lazy(() => import('@/features/monitoring/cpu/CpuWidget').then(m => ({ default: m.CpuWidget })));
const MemoryWidget = lazy(() => import('@/features/monitoring/memory/MemoryWidget').then(m => ({ default: m.MemoryWidget })));
const NetworkWidget = lazy(() => import('@/features/monitoring/network/NetworkWidget').then(m => ({ default: m.NetworkWidget })));
const AnomalyWidget = lazy(() => import('@/features/monitoring/ai/AnomalyWidget').then(m => ({ default: m.AnomalyWidget })));
const HistoryWidget = lazy(() => import('@/features/monitoring/history/HistoryWidget').then(m => ({ default: m.HistoryWidget })));

export const WIDGET_REGISTRY: Record<string, WidgetDefinition> = {
    'cpu': {
        id: 'cpu',
        title: 'CPU Usage',
        description: 'Real-time CPU load and temperature',
        component: CpuWidget,
        defaultSize: { w: 1, h: 1 }
    },
    'memory': {
        id: 'memory',
        title: 'Memory Usage',
        description: 'RAM and Swap utilization',
        component: MemoryWidget,
        defaultSize: { w: 1, h: 1 }
    },
    'network': {
        id: 'network',
        title: 'Network Traffic',
        description: 'Upload and Download rates',
        component: NetworkWidget,
        defaultSize: { w: 1, h: 1 }
    },
    'anomaly': {
        id: 'anomaly',
        title: 'AI Anomaly Detection',
        description: 'AI-driven anomaly scores and predictions',
        component: AnomalyWidget,
        defaultSize: { w: 1, h: 1 }
    },
    'history': {
        id: 'history',
        title: 'Historical Metrics',
        description: 'aggregated charts for system history',
        component: HistoryWidget,
        defaultSize: { w: 2, h: 1 }
    },
    'hardware-health': {
        id: 'hardware-health',
        title: 'Hardware Health',
        description: 'Physical diagnostics and thermal efficiency',
        component: lazy(() => import('@/features/monitoring/hardware/HardwareHealthCard').then(m => ({ default: m.HardwareHealthCard }))),
        defaultSize: { w: 1, h: 1 }
    },
    'sensors': {
        id: 'sensors',
        title: 'Sensors',
        description: 'Voltage and Fan speed readings',
        component: lazy(() => import('@/features/monitoring/hardware/SensorsWidget').then(m => ({ default: m.SensorsWidget }))),
        defaultSize: { w: 1, h: 1 }
    },
    'cognitive': {
        id: 'cognitive',
        title: 'Cognitive Engine',
        description: 'AI-driven behavioral analysis and insights',
        component: lazy(() => import('@/features/monitoring/ai/CognitiveWidget').then(m => ({ default: m.CognitiveWidget }))),
        defaultSize: { w: 1, h: 1 }
    },
    'digital-twin': {
        id: 'digital-twin',
        title: 'Smart Digital Twin',
        description: 'Interactive 3D System Visualization',
        component: lazy(() => import('@/features/digital-twin/DigitalTwinWidget').then(m => ({ default: m.DigitalTwinWidget }))),
        defaultSize: { w: 2, h: 2 }
    },
    // ============================================
    // NEW HARDWARE WIDGETS (Phase 2)
    // ============================================
    'sensors-overview': {
        id: 'sensors-overview',
        title: 'Thermal Overview',
        description: 'Heatmap of all temperature sensors',
        component: lazy(() => import('@/features/monitoring/hardware/SensorsOverviewWidget').then(m => ({ default: m.SensorsOverviewWidget }))),
        defaultSize: { w: 2, h: 1 }
    },
    'fans': {
        id: 'fans',
        title: 'System Fans',
        description: 'All fan speeds with visual indicators',
        component: lazy(() => import('@/features/monitoring/hardware/FansWidget').then(m => ({ default: m.FansWidget }))),
        defaultSize: { w: 1, h: 1 }
    },
    'voltages': {
        id: 'voltages',
        title: 'Power Rails',
        description: 'Voltage readings and stability',
        component: lazy(() => import('@/features/monitoring/hardware/VoltagesWidget').then(m => ({ default: m.VoltagesWidget }))),
        defaultSize: { w: 1, h: 1 }
    },
    'storage-health': {
        id: 'storage-health',
        title: 'Storage Health',
        description: 'Disk usage, NVMe temps, and IOPS',
        component: lazy(() => import('@/features/monitoring/hardware/StorageHealthWidget').then(m => ({ default: m.StorageHealthWidget }))),
        defaultSize: { w: 1, h: 1 }
    },
    // ============================================
    // PHYSICS ENGINE WIDGET (NEW)
    // ============================================
    'physics-diagnostics': {
        id: 'physics-diagnostics',
        title: 'Physics Diagnostics',
        description: 'Thermal efficiency, bottleneck detection, and hardware physics',
        component: lazy(() => import('@/features/physics/components/PhysicsDiagnosticsWidget').then(m => ({ default: m.PhysicsDiagnosticsWidget }))),
        defaultSize: { w: 1, h: 2 }
    }
};

export function getWidgetDefinition(id: string): WidgetDefinition | undefined {
    return WIDGET_REGISTRY[id];
}
