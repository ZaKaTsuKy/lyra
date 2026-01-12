import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import type { OmniMessage, InitPayload, UpdatePayload } from '../types/omni';

// ============================================
// Type léger pour l'historique
// ============================================
export interface HistoryPoint {
    timestamp: number;
    cpu_load1: number;
    cpu_temp: number;
    memory_used_kb: number;
    memory_total_kb: number;
    network_rx_bps: number;
    network_tx_bps: number;
    disk_read_bps: number;
    disk_write_bps: number;
    gpu_util: number | null;
    gpu_temp: number | null;
}

// ============================================
// Ring Buffer - Zero allocation après init
// ============================================
class RingBuffer<T> {
    private buffer: (T | undefined)[];
    private head = 0;
    private _size = 0;
    private _version = 0; // Track mutations for React

    private capacity: number;

    constructor(capacity: number) {
        this.capacity = capacity;
        this.buffer = new Array(capacity);
    }

    push(item: T): void {
        this.buffer[this.head] = item;
        this.head = (this.head + 1) % this.capacity;
        if (this._size < this.capacity) this._size++;
        this._version++;
    }

    /**
     * Returns array snapshot. Only call when needed for rendering.
     * The array is created fresh but the operation is O(n) and only
     * happens when React needs to render, not on every push.
     */
    toArray(): T[] {
        if (this._size === 0) return [];
        const result: T[] = new Array(this._size);
        const start = this._size < this.capacity ? 0 : this.head;
        for (let i = 0; i < this._size; i++) {
            result[i] = this.buffer[(start + i) % this.capacity] as T;
        }
        return result;
    }

    get size(): number { return this._size; }
    get version(): number { return this._version; }

    get latest(): T | undefined {
        if (this._size === 0) return undefined;
        const idx = (this.head - 1 + this.capacity) % this.capacity;
        return this.buffer[idx];
    }

    /**
     * Get item at index from oldest to newest
     */
    at(index: number): T | undefined {
        if (index < 0 || index >= this._size) return undefined;
        const start = this._size < this.capacity ? 0 : this.head;
        return this.buffer[(start + index) % this.capacity];
    }
}

interface OmniState {
    socket: WebSocket | null;
    status: 'disconnected' | 'connecting' | 'connected' | 'error';
    staticInfo: InitPayload | null;
    liveData: UpdatePayload | null;

    // Ring buffer instance (not serializable, internal)
    _historyBuffer: RingBuffer<HistoryPoint>;
    // Version counter to trigger React updates only when needed
    historyVersion: number;

    error: string | null;
    retryCount: number;
    cleanupFn: (() => void) | null;
    lastUpdateTime: number;
    connectionId: number;
    heartbeatIntervalId: ReturnType<typeof setInterval> | null;

    connect: (url?: string) => void;
    disconnect: () => void;

    // Getter methods instead of derived state
    getHistory: () => HistoryPoint[];
    getHistoryLength: () => number;
}

const DEFAULT_URL = import.meta.env.VITE_WS_URL || 'ws://localhost:8080/ws';
const HISTORY_SIZE = 180; // 3 minutes at 2Hz
const RECONNECT_INTERVAL = 3000;
const MAX_RETRIES = 10;
const UPDATE_THROTTLE_MS = 1000; // Must match backend OMNI_REFRESH_INTERVAL (1.0s)
const HEARTBEAT_INTERVAL_MS = 15000; // Send ping every 15s to detect stale connections

// ============================================
// Helper: Extraire uniquement les données nécessaires
// ============================================
function extractHistoryPoint(data: UpdatePayload): HistoryPoint {
    const totalDiskRead = data.disks.reduce((acc, d) => acc + d.read_bps, 0);
    const totalDiskWrite = data.disks.reduce((acc, d) => acc + d.write_bps, 0);

    return {
        timestamp: data.timestamp,
        cpu_load1: data.cpu.load1,
        cpu_temp: data.cpu.temp_package,
        memory_used_kb: data.memory.used_kb,
        memory_total_kb: data.memory.total_kb,
        network_rx_bps: data.network.rx_bps,
        network_tx_bps: data.network.tx_bps,
        disk_read_bps: totalDiskRead,
        disk_write_bps: totalDiskWrite,
        gpu_util: data.gpu?.util ?? null,
        gpu_temp: data.gpu?.temp ?? null,
    };
}

export const useTelemetryStore = create<OmniState>()(
    subscribeWithSelector((set, get) => ({
        socket: null,
        status: 'disconnected',
        staticInfo: null,
        liveData: null,
        _historyBuffer: new RingBuffer<HistoryPoint>(HISTORY_SIZE),
        historyVersion: 0,
        error: null,
        retryCount: 0,
        cleanupFn: null,
        lastUpdateTime: 0,
        connectionId: 0,
        heartbeatIntervalId: null,

        // ============================================
        // Getter methods - call these instead of reading history directly
        // ============================================
        getHistory: () => get()._historyBuffer.toArray(),
        getHistoryLength: () => get()._historyBuffer.size,

        connect: (url = DEFAULT_URL) => {
            const state = get();
            get().disconnect();

            const currentId = state.connectionId + 1;
            set({ status: 'connecting', error: null, connectionId: currentId });

            let ws: WebSocket;
            try {
                ws = new WebSocket(url);
            } catch (e) {
                console.error('WebSocket creation failed:', e);
                set({ status: 'error', error: 'Failed to create WebSocket' });

                if (get().connectionId === currentId && get().retryCount < MAX_RETRIES) {
                    const timeout = setTimeout(() => {
                        if (get().connectionId === currentId) {
                            set(s => ({ retryCount: s.retryCount + 1 }));
                            get().connect(url);
                        }
                    }, RECONNECT_INTERVAL);
                    set({ cleanupFn: () => clearTimeout(timeout) });
                }
                return;
            }

            ws.onopen = () => {
                if (get().connectionId !== currentId) {
                    ws.close();
                    return;
                }
                // Start heartbeat ping
                const heartbeatId = setInterval(() => {
                    if (ws.readyState === WebSocket.OPEN) {
                        ws.send('ping');
                    }
                }, HEARTBEAT_INTERVAL_MS);

                set({ status: 'connected', socket: ws, error: null, retryCount: 0, heartbeatIntervalId: heartbeatId });
                if (import.meta.env.DEV) console.log('[WS] Connected to Omni Monitor');
            };

            ws.onmessage = (event) => {
                if (get().connectionId !== currentId) return;

                try {
                    if (event.data === 'pong') return;
                    const data: OmniMessage = JSON.parse(event.data);

                    if (data.type === 'init') {
                        set({ staticInfo: data });
                    } else if (data.type === 'update') {
                        const now = Date.now();
                        const { lastUpdateTime, _historyBuffer } = get();

                        if (now - lastUpdateTime >= UPDATE_THROTTLE_MS) {
                            const historyPoint = extractHistoryPoint(data);

                            // ✅ Ring buffer push - NO new array created
                            _historyBuffer.push(historyPoint);

                            set({
                                liveData: data,
                                historyVersion: _historyBuffer.version,
                                lastUpdateTime: now,
                            });
                        }
                    } else if (data.type === 'error') {
                        set({ error: data.message });
                    } else if (data.type === 'shutdown') {
                        set({ status: 'disconnected', error: 'Server shutdown' });
                        ws.close();
                    }
                } catch (e) {
                    console.error('Failed to parse message:', e);
                }
            };

            ws.onclose = () => {
                if (get().connectionId !== currentId) return;

                const currentStatus = get().status;
                if (currentStatus === 'disconnected') {
                    set({ socket: null });
                    return;
                }

                if (import.meta.env.DEV) console.log('[WS] Connection lost, reconnecting...');
                if (get().retryCount < MAX_RETRIES) {
                    const timeout = setTimeout(() => {
                        if (get().connectionId === currentId) {
                            set(s => ({ retryCount: s.retryCount + 1 }));
                            get().connect(url);
                        }
                    }, RECONNECT_INTERVAL);
                    set({
                        status: 'connecting',
                        socket: null,
                        cleanupFn: () => clearTimeout(timeout)
                    });
                } else {
                    set({ status: 'error', socket: null, error: 'Max retries reached' });
                }
            };

            ws.onerror = (e) => {
                if (get().connectionId === currentId) {
                    console.error('WebSocket error:', e);
                }
            };

            set({ socket: ws });
        },

        disconnect: () => {
            const { socket, cleanupFn, heartbeatIntervalId } = get();
            set(s => ({ connectionId: s.connectionId + 1 }));

            // Clear heartbeat
            if (heartbeatIntervalId) {
                clearInterval(heartbeatIntervalId);
            }

            if (socket) {
                socket.onopen = null;
                socket.onmessage = null;
                socket.onclose = null;
                socket.onerror = null;
                socket.close();
            }

            cleanupFn?.();

            set({
                socket: null,
                status: 'disconnected',
                cleanupFn: null,
                retryCount: 0,
                liveData: null,
                heartbeatIntervalId: null
            });
        },
    }))
);

// ============================================
// Sélecteurs atomiques pour éviter les re-renders
// Ces sélecteurs retournent des PRIMITIVES ou des objets stables
// ============================================
export const selectors = {
    // Primitives - ne déclenchent un re-render que si la valeur change
    cpuLoad: (s: OmniState) => s.liveData?.cpu.load1 ?? 0,
    cpuTemp: (s: OmniState) => s.liveData?.cpu.temp_package ?? 0,
    memoryUsed: (s: OmniState) => s.liveData?.memory.used_kb ?? 0,
    memoryTotal: (s: OmniState) => s.liveData?.memory.total_kb ?? 1,
    networkRx: (s: OmniState) => s.liveData?.network.rx_bps ?? 0,
    networkTx: (s: OmniState) => s.liveData?.network.tx_bps ?? 0,
    anomalyScore: (s: OmniState) => s.liveData?.anomaly.overall ?? 0,
    status: (s: OmniState) => s.status,
    isConnected: (s: OmniState) => s.status === 'connected',

    // History version - use this to trigger re-renders, then call getHistory()
    historyVersion: (s: OmniState) => s.historyVersion,

    // CPU Widget specific
    cpuSpike: (s: OmniState) => s.liveData?.anomaly.cpu_spike ?? false,

    // Memory Widget specific
    swapUsedKb: (s: OmniState) => s.liveData?.memory.swap_used_kb ?? 0,
    swapTotalKb: (s: OmniState) => s.liveData?.memory.swap_total_kb ?? 0,
    memSpike: (s: OmniState) => s.liveData?.anomaly.mem_spike ?? false,

    // Network Widget specific
    primaryIface: (s: OmniState) => s.liveData?.network.primary_iface ?? '',

    // Anomaly Widget specific
    regime: (s: OmniState) => s.liveData?.anomaly.regime ?? 'Unknown',
    cpuTrend: (s: OmniState) => s.liveData?.anomaly.cpu_trend ?? 'stable',
    memTrend: (s: OmniState) => s.liveData?.anomaly.mem_trend ?? 'stable',
    ioTrend: (s: OmniState) => s.liveData?.anomaly.io_trend ?? 'stable',
    netTrend: (s: OmniState) => s.liveData?.anomaly.net_trend ?? 'stable',
};

// ============================================
// Hook personnalisé pour l'historique avec throttling
// ============================================
import { useMemo } from 'react';

export function useThrottledHistory(throttleMs: number = 1000): HistoryPoint[] {
    const version = useTelemetryStore(selectors.historyVersion);
    const getHistory = useTelemetryStore(s => s.getHistory);

    // Only recompute every throttleMs by rounding version
    const throttledVersion = Math.floor(version / (throttleMs / 1000));

    return useMemo(() => getHistory(), [throttledVersion, getHistory]);
}