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
    layoutVersion?: number;  // NEW: Track widget layout version

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
    // NEW: Full hardware monitoring widgets
    { id: 'sensors-overview', type: 'sensors-overview', position: 4, isVisible: true },
    { id: 'fans', type: 'fans', position: 5, isVisible: true },
    { id: 'voltages', type: 'voltages', position: 6, isVisible: true },
    { id: 'storage-health', type: 'storage-health', position: 7, isVisible: true },
    // Legacy hardware widgets (can be hidden in favor of new ones)
    { id: 'hardware-health', type: 'hardware-health', position: 8, isVisible: true },
    { id: 'sensors', type: 'sensors', position: 9, isVisible: false },  // Hidden - replaced by fans/voltages
    { id: 'cognitive', type: 'cognitive', position: 10, isVisible: true },
    { id: 'history', type: 'history', position: 11, isVisible: true },
    { id: 'digital-twin', type: 'digital-twin', position: 12, isVisible: true },
];

// Version pour forcer la mise à jour du localStorage si les widgets par défaut changent
const WIDGET_LAYOUT_VERSION = 2;

export const usePreferencesStore = create<PreferencesState>()(
    persist(
        (set) => ({
            theme: 'light',
            layout: 'overview',
            widgets: DEFAULT_WIDGETS,
            layoutVersion: WIDGET_LAYOUT_VERSION,

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
            resetLayout: () => set({ widgets: DEFAULT_WIDGETS, layoutVersion: WIDGET_LAYOUT_VERSION }),
        }),
        {
            name: 'omni-preferences',
            // Migrate old layouts to include new widgets
            migrate: (persistedState: any, _version: number) => {
                const state = persistedState as PreferencesState;

                // If layout version is outdated or missing, reset to defaults
                if (!state.layoutVersion || state.layoutVersion < WIDGET_LAYOUT_VERSION) {
                    console.log('[Preferences] Migrating widget layout to version', WIDGET_LAYOUT_VERSION);
                    return {
                        ...state,
                        widgets: DEFAULT_WIDGETS,
                        layoutVersion: WIDGET_LAYOUT_VERSION,
                    };
                }

                return state;
            },
            version: WIDGET_LAYOUT_VERSION,
        }
    )
);