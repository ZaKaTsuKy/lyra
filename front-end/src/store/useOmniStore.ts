import { create } from 'zustand';
import type { OmniMessage, InitPayload, UpdatePayload } from '../types/omni';

interface OmniState {
    socket: WebSocket | null;
    status: 'disconnected' | 'connecting' | 'connected' | 'error';
    staticInfo: InitPayload | null;
    liveData: UpdatePayload | null;
    history: UpdatePayload[]; // Keeping history for charts later
    error: string | null;

    // Internal state
    retryCount: number;
    cleanupFn: (() => void) | null;

    connect: (url?: string) => void;
    disconnect: () => void;
}

const DEFAULT_URL = import.meta.env.VITE_WS_URL || 'ws://localhost:8080/ws';
const HISTORY_SIZE = 60;
const RECONNECT_INTERVAL = 3000;
const MAX_RETRIES = 10;

export const useOmniStore = create<OmniState>((set, get) => ({
    socket: null,
    status: 'disconnected',
    staticInfo: null,
    liveData: null,
    history: [],
    error: null,

    // Internal state for retry management (not part of interface)
    retryCount: 0,
    cleanupFn: null as (() => void) | null,

    connect: (url = DEFAULT_URL) => {
        const currentSocket = get().socket;
        if (currentSocket && (currentSocket.readyState === WebSocket.OPEN || currentSocket.readyState === WebSocket.CONNECTING)) {
            return;
        }

        set({ status: 'connecting', error: null });

        let ws: WebSocket;
        try {
            ws = new WebSocket(url);
        } catch (e) {
            console.error('WebSocket creation failed:', e);
            set({ status: 'error', error: 'Failed to create WebSocket' });

            const state = get();
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
                    set((state) => {
                        const newHistory = [...state.history, data];
                        if (newHistory.length > HISTORY_SIZE) {
                            newHistory.shift();
                        }
                        return {
                            liveData: data,
                            history: newHistory,
                        };
                    });
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
            set((state) => {
                // If it was validly connected or connecting, try to reconnect
                if (state.status !== 'disconnected') {
                    console.log('Connection lost, reconnecting in 3s...');

                    if (state.retryCount < MAX_RETRIES) {
                        const timeout = setTimeout(() => {
                            set(s => ({ retryCount: s.retryCount + 1 }));
                            get().connect(url);
                        }, RECONNECT_INTERVAL);
                        return { status: 'connecting', socket: null, cleanupFn: () => clearTimeout(timeout) };
                    } else {
                        return { status: 'error', socket: null, error: 'Max reconnection attempts reached' };
                    }
                }
                return { status: 'disconnected', socket: null };
            });
        };

        ws.onerror = (e) => {
            console.error('WebSocket error:', e);
            // Verify if we should set error state here or let onclose handle it
            set({ status: 'error', error: 'Connection failed' });
        };
    },

    disconnect: () => {
        const { socket, cleanupFn } = get();
        if (socket) {
            socket.close();
        }
        if (cleanupFn) {
            cleanupFn();
        }
        set({ socket: null, status: 'disconnected', cleanupFn: null, retryCount: 0 });
    },
}));
