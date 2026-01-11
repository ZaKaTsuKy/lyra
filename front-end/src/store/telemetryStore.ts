import { create } from 'zustand';
import type { OmniMessage, InitPayload, UpdatePayload } from '../types/omni';

// ============================================
// Type léger pour l'historique
// Réduit ~2KB par point à ~80 bytes
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

interface OmniState {
    socket: WebSocket | null;
    status: 'disconnected' | 'connecting' | 'connected' | 'error';
    staticInfo: InitPayload | null;
    liveData: UpdatePayload | null;

    // Historique ordonné (stocké directement, pas calculé)
    history: HistoryPoint[];

    error: string | null;
    retryCount: number;
    cleanupFn: (() => void) | null;
    lastUpdateTime: number;

    connect: (url?: string) => void;
    disconnect: () => void;
}

const DEFAULT_URL = import.meta.env.VITE_WS_URL || 'ws://localhost:8080/ws';
const HISTORY_SIZE = 180; // 3 minutes à 1Hz
const RECONNECT_INTERVAL = 3000;
const MAX_RETRIES = 10;
const UPDATE_THROTTLE_MS = 1000; // Throttle UI updates to 1Hz

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

export const useTelemetryStore = create<OmniState>((set, get) => ({
    socket: null,
    status: 'disconnected',
    staticInfo: null,
    liveData: null,
    history: [], // Commence vide, se remplit progressivement
    error: null,
    retryCount: 0,
    cleanupFn: null,
    lastUpdateTime: 0,

    connect: (url = DEFAULT_URL) => {
        const state = get();

        // Cleanup complet avant nouvelle connexion
        if (state.socket) {
            state.socket.onmessage = null;
            state.socket.onclose = null;
            state.socket.onerror = null;
            state.socket.onopen = null;

            if (state.socket.readyState === WebSocket.OPEN ||
                state.socket.readyState === WebSocket.CONNECTING) {
                state.socket.close();
            }
        }

        state.cleanupFn?.();

        set({ status: 'connecting', error: null, cleanupFn: null });

        let ws: WebSocket;
        try {
            ws = new WebSocket(url);
        } catch (e) {
            console.error('WebSocket creation failed:', e);
            set({ status: 'error', error: 'Failed to create WebSocket' });

            if (state.retryCount < MAX_RETRIES) {
                const timeout = setTimeout(() => {
                    set(s => ({ retryCount: s.retryCount + 1 }));
                    get().connect(url);
                }, RECONNECT_INTERVAL);
                set({ cleanupFn: () => clearTimeout(timeout) });
            } else {
                set({ error: 'Max reconnection attempts reached' });
            }
            return;
        }

        ws.onopen = () => {
            set({ status: 'connected', socket: ws, error: null, retryCount: 0 });
            console.log('Connected to Omni Monitor');
        };

        ws.onmessage = (event) => {
            try {
                if (event.data === 'pong') return;

                const data: OmniMessage = JSON.parse(event.data);

                if (data.type === 'init') {
                    set({ staticInfo: data });

                } else if (data.type === 'update') {
                    const now = Date.now();
                    const { lastUpdateTime, history } = get();

                    // Throttle: Une seule mise à jour par seconde
                    const shouldUpdateUI = now - lastUpdateTime >= UPDATE_THROTTLE_MS;

                    if (shouldUpdateUI) {
                        // Extraire le point léger
                        const historyPoint = extractHistoryPoint(data);

                        // Mettre à jour l'historique (garder les HISTORY_SIZE derniers)
                        const newHistory = history.length >= HISTORY_SIZE
                            ? [...history.slice(1), historyPoint]
                            : [...history, historyPoint];

                        set({
                            liveData: data,
                            history: newHistory,
                            lastUpdateTime: now,
                        });
                    }

                } else if (data.type === 'error') {
                    console.error('Server error:', data.message);
                    set({ error: data.message });

                } else if (data.type === 'shutdown') {
                    console.warn('Server shutdown:', data.message);
                    set({ status: 'disconnected', error: 'Server shutdown' });
                    ws.close();
                }
            } catch (e) {
                console.error('Failed to parse message:', e);
            }
        };

        ws.onclose = () => {
            const currentStatus = get().status;

            // Ne pas reconnecter si déconnexion intentionnelle
            if (currentStatus === 'disconnected') {
                set({ socket: null });
                return;
            }

            console.log('Connection lost, reconnecting in 3s...');

            const currentRetryCount = get().retryCount;
            if (currentRetryCount < MAX_RETRIES) {
                const timeout = setTimeout(() => {
                    set(s => ({ retryCount: s.retryCount + 1 }));
                    get().connect(url);
                }, RECONNECT_INTERVAL);

                set({
                    status: 'connecting',
                    socket: null,
                    cleanupFn: () => clearTimeout(timeout)
                });
            } else {
                set({
                    status: 'error',
                    socket: null,
                    error: 'Max reconnection attempts reached'
                });
            }
        };

        ws.onerror = (e) => {
            console.error('WebSocket error:', e);
        };

        set({ socket: ws });
    },

    disconnect: () => {
        const { socket, cleanupFn } = get();

        if (socket) {
            socket.onmessage = null;
            socket.onclose = null;
            socket.onerror = null;
            socket.onopen = null;
            socket.close();
        }

        cleanupFn?.();

        set({
            socket: null,
            status: 'disconnected',
            cleanupFn: null,
            retryCount: 0,
        });
    },
}));

// ============================================
// Sélecteurs atomiques pour éviter les re-renders
// ============================================
export const selectors = {
    cpuLoad: (s: OmniState) => s.liveData?.cpu.load1 ?? 0,
    cpuTemp: (s: OmniState) => s.liveData?.cpu.temp_package ?? 0,
    memoryUsed: (s: OmniState) => s.liveData?.memory.used_kb ?? 0,
    memoryTotal: (s: OmniState) => s.liveData?.memory.total_kb ?? 1,
    networkRx: (s: OmniState) => s.liveData?.network.rx_bps ?? 0,
    networkTx: (s: OmniState) => s.liveData?.network.tx_bps ?? 0,
    anomalyScore: (s: OmniState) => s.liveData?.anomaly.overall ?? 0,
    status: (s: OmniState) => s.status,
    isConnected: (s: OmniState) => s.status === 'connected',
    history: (s: OmniState) => s.history,
};