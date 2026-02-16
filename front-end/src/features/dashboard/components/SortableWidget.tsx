import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { WidgetContainer } from './WidgetContainer';
import { cn } from '@/lib/utils';

interface SortableWidgetProps {
    id: string;
    children: React.ReactNode;
    className?: string;
    animationDelay?: number;
}

export function SortableWidget({
    id,
    children,
    className,
    animationDelay = 0
}: SortableWidgetProps) {
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
        animationDelay: `${animationDelay}s`,
    };

    return (
        <div
            ref={setNodeRef}
            style={style}
            {...attributes}
            className={cn(
                "h-full animate-fade-in",
                isDragging && "z-50 opacity-90",
                className
            )}
        >
            <WidgetContainer
                dragHandleProps={listeners}
                isDragging={isDragging}
            >
                {children}
            </WidgetContainer>
        </div>
    );
}
