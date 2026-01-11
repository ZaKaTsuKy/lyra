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
    }
};

export function getWidgetDefinition(id: string): WidgetDefinition | undefined {
    return WIDGET_REGISTRY[id];
}
