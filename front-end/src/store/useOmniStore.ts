import { create } from 'zustand';
import type { OmniMessage, InitPayload, UpdatePayload } from '../types/omni';

interface OmniState {
    socket: WebSocket | null;
    status: 'disconnected' | 'connecting' | 'connected' | 'error';
    staticInfo: InitPayload | null;
    liveData: UpdatePayload | null;
    history: UpdatePayload[]; // Keeping history for charts later
    error: string | null;

    connect: (url?: string) => void;
    disconnect: () => void;
}

const DEFAULT_URL = 'ws://localhost:8080/ws';
const HISTORY_SIZE = 60;
const RECONNECT_INTERVAL = 3000;

export const useOmniStore = create<OmniState>((set, get) => ({
    socket: null,
    status: 'disconnected',
    staticInfo: null,
    liveData: null,
    history: [],
    error: null,

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
            setTimeout(() => get().connect(url), RECONNECT_INTERVAL);
            return;
        }

        ws.onopen = () => {
            set({ status: 'connected', socket: ws, error: null });
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
                    setTimeout(() => get().connect(url), RECONNECT_INTERVAL);
                    return { status: 'connecting', socket: null };
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
        const { socket } = get();
        if (socket) {
            socket.close(); // This will trigger onclose
        }
        set({ socket: null, status: 'disconnected' });
    },
}));
