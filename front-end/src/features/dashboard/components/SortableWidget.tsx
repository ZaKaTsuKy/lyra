import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { WidgetContainer } from './WidgetContainer';

interface SortableWidgetProps {
    id: string;
    children: React.ReactNode;
}

export function SortableWidget({ id, children }: SortableWidgetProps) {
    const {
        attributes,
        listeners,
        setNodeRef,
        transform,
        transition,
        isDragging,
    } = useSortable({ id });

    const style = {
        transform: CSS.Transform.toString(transform),
        transition,
    };

    return (
        <div ref={setNodeRef} style={style} {...attributes} className="h-full">
            <WidgetContainer
                dragHandleProps={listeners}
                isDragging={isDragging}
            >
                {children}
            </WidgetContainer>
        </div>
    );
}
