import { GripVertical } from 'lucide-react';
import { cn } from '@/lib/utils';

interface WidgetContainerProps {
    children: React.ReactNode;
    dragHandleProps?: any;
    isDragging?: boolean;
    className?: string;
}

export function WidgetContainer({
    children,
    dragHandleProps,
    isDragging,
    className
}: WidgetContainerProps) {
    return (
        <div
            className={cn(
                "relative group flex flex-col h-full rounded-xl border bg-card/50 backdrop-blur-xl shadow-sm transition-all duration-300",
                isDragging && "scale-[1.02] shadow-2xl z-50 ring-2 ring-primary/50",
                className
            )}
        >
            {/* Header / Drag Handle */}
            <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity z-10">
                <div
                    {...dragHandleProps}
                    className="p-1.5 rounded-md hover:bg-muted cursor-grab active:cursor-grabbing text-muted-foreground"
                >
                    <GripVertical className="w-4 h-4" />
                </div>
            </div>

            {/* Content */}
            <div className="flex-1 h-full overflow-hidden">
                {children}
            </div>
        </div>
    );
}
