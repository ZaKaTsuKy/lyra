import {
    DndContext,
    closestCenter,
    KeyboardSensor,
    PointerSensor,
    useSensor,
    useSensors,
    type DragEndEvent
} from '@dnd-kit/core';
import {
    SortableContext,
    sortableKeyboardCoordinates,
    rectSortingStrategy
} from '@dnd-kit/sortable';
import { usePreferencesStore } from '@/store/preferencesStore';
import { SortableWidget } from './SortableWidget';
import { Suspense, useMemo } from 'react';
import { Skeleton } from '@/shared/components/ui/skeleton';
import { ErrorBoundary } from '@/shared/components/ErrorBoundary';
import { getWidgetDefinition } from '../config/widgetRegistry';

/**
 * ✅ ENHANCED DASHBOARD GRID
 * 
 * Now respects widget defaultSize from the registry:
 * - w: 1 = 1 column span
 * - w: 2 = 2 column span (spans md:col-span-2)
 * - h: 2 = 2 row span (spans row-span-2)
 */

// Map size values to Tailwind classes
function getSpanClasses(w: number, h: number): string {
    const colSpan = w >= 2 ? 'md:col-span-2' : '';
    const rowSpan = h >= 2 ? 'row-span-2' : '';
    return `${colSpan} ${rowSpan}`.trim();
}

export function DashboardGrid() {
    const widgets = usePreferencesStore((s) => s.widgets);
    const moveWidget = usePreferencesStore((s) => s.moveWidget);

    const sensors = useSensors(
        useSensor(PointerSensor, {
            activationConstraint: {
                distance: 8, // Prevent accidental drags
            },
        }),
        useSensor(KeyboardSensor, {
            coordinateGetter: sortableKeyboardCoordinates,
        })
    );

    // Memoize widget IDs to prevent array recreation on every render
    const widgetIds = useMemo(() => widgets.map(w => w.id), [widgets]);

    // Memoize filtered visible widgets to prevent filter on every render
    const visibleWidgets = useMemo(() => widgets.filter(w => w.isVisible), [widgets]);

    const handleDragEnd = (event: DragEndEvent) => {
        const { active, over } = event;

        if (active.id !== over?.id && over) {
            moveWidget(active.id as string, over.id as string);
        }
    };

    return (
        <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
        >
            <SortableContext
                items={widgetIds}
                strategy={rectSortingStrategy}
            >
                <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 auto-rows-[minmax(180px,auto)]">
                    {visibleWidgets.map((widget, index) => {
                        const def = getWidgetDefinition(widget.type);

                        if (!def) return null;

                        const Component = def.component;
                        const { w = 1, h = 1 } = def.defaultSize;
                        const spanClasses = getSpanClasses(w, h);

                        return (
                            <SortableWidget
                                key={widget.id}
                                id={widget.id}
                                className={spanClasses}
                                animationDelay={index * 0.05}
                            >
                                <ErrorBoundary>
                                    <Suspense fallback={
                                        <Skeleton className="h-full w-full rounded-xl animate-pulse" />
                                    }>
                                        <Component />
                                    </Suspense>
                                </ErrorBoundary>
                            </SortableWidget>
                        );
                    })}
                </div>
            </SortableContext>
        </DndContext>
    );
}
