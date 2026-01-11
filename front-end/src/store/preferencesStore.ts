import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface WidgetConfig {
    id: string;
    type: string;
    position: number;
    isVisible: boolean;
}

interface PreferencesState {
    theme: 'light' | 'dark';
    layout: 'overview' | 'minimal' | 'performance';
    widgets: WidgetConfig[];

    setTheme: (theme: 'light' | 'dark') => void;
    setLayout: (layout: 'overview' | 'minimal' | 'performance') => void;
    setWidgets: (widgets: WidgetConfig[]) => void;
    moveWidget: (activeId: string, overId: string) => void;
    resetLayout: () => void;
}

const DEFAULT_WIDGETS: WidgetConfig[] = [
    { id: 'cpu', type: 'cpu', position: 0, isVisible: true },
    { id: 'memory', type: 'memory', position: 1, isVisible: true },
    { id: 'network', type: 'network', position: 2, isVisible: true },
    { id: 'anomaly', type: 'anomaly', position: 3, isVisible: true },
    { id: 'history', type: 'history', position: 4, isVisible: true },
];

export const usePreferencesStore = create<PreferencesState>()(
    persist(
        (set) => ({
            theme: 'light',
            layout: 'overview',
            widgets: DEFAULT_WIDGETS,

            setTheme: (theme) => set({ theme }),
            setLayout: (layout) => set({ layout }),
            setWidgets: (widgets) => set({ widgets }),
            moveWidget: (activeId, overId) => set((state) => {
                const oldIndex = state.widgets.findIndex((w) => w.id === activeId);
                const newIndex = state.widgets.findIndex((w) => w.id === overId);

                if (oldIndex === -1 || newIndex === -1) return state;

                const newWidgets = [...state.widgets];
                const [movedItem] = newWidgets.splice(oldIndex, 1);
                newWidgets.splice(newIndex, 0, movedItem);

                // Update positions
                return {
                    widgets: newWidgets.map((w, i) => ({ ...w, position: i }))
                };
            }),
            resetLayout: () => set({ widgets: DEFAULT_WIDGETS }),
        }),
        {
            name: 'omni-preferences',
        }
    )
);
