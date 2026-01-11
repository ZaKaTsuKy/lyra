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
import { Suspense } from 'react';
import { Skeleton } from '@/shared/components/ui/skeleton';
import { getWidgetDefinition } from '../config/widgetRegistry';

export function DashboardGrid() {
    const widgets = usePreferencesStore((s) => s.widgets);
    const moveWidget = usePreferencesStore((s) => s.moveWidget);

    const sensors = useSensors(
        useSensor(PointerSensor),
        useSensor(KeyboardSensor, {
            coordinateGetter: sortableKeyboardCoordinates,
        })
    );

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
                items={widgets.map(w => w.id)}
                strategy={rectSortingStrategy}
            >
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 auto-rows-[minmax(200px,auto)]">
                    {widgets.filter(w => w.isVisible).map((widget) => {
                        const def = getWidgetDefinition(widget.type);

                        if (!def) return null;

                        const Component = def.component;

                        return (
                            <SortableWidget key={widget.id} id={widget.id}>
                                <Suspense fallback={<Skeleton className="h-full w-full rounded-xl" />}>
                                    <Component />
                                </Suspense>
                            </SortableWidget>
                        );
                    })}
                </div>
            </SortableContext>
        </DndContext>
    );
}
