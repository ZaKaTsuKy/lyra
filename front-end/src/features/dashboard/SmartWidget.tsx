import { type ReactNode, useEffect, useRef, useState } from 'react';
import { GlassPanel } from '@/components/ui/GlassPanel';
import { cn } from '@/lib/utils';

export type WidgetSize = 'small' | 'medium' | 'large' | 'xlarge';

interface SmartWidgetProps {
    title: string;
    children: (size: WidgetSize) => ReactNode;
    className?: string;
    variant?: 'default' | 'active' | 'danger';
    glow?: boolean;
}

export default function SmartWidget({ title, children, className, variant, glow }: SmartWidgetProps) {
    const containerRef = useRef<HTMLDivElement>(null);
    const [size, setSize] = useState<WidgetSize>('medium');

    useEffect(() => {
        if (!containerRef.current) return;

        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                const width = entry.contentRect.width;
                const height = entry.contentRect.height;

                // Determine size based on dimensions (approximate grid cells)
                // Assuming 1 cell ~ 100-150px widely depending on screen
                let newSize: WidgetSize = 'medium';

                if (width < 250 && height < 200) {
                    newSize = 'small'; // 1x1
                } else if (width > 250 && height < 200) {
                    newSize = 'medium'; // 2x1
                } else if (width > 250 && height > 200 && width < 600) {
                    newSize = 'large'; // 2x2
                } else if (width >= 600) {
                    newSize = 'xlarge'; // 4x2 or bigger
                }

                setSize(newSize);
            }
        });

        observer.observe(containerRef.current);
        return () => observer.disconnect();
    }, []);

    return (
        <GlassPanel
            ref={containerRef}
            className={cn("h-full flex flex-col p-4", className)}
            variant={variant}
            glow={glow}
        >
            <div className="flex items-center justify-between mb-2">
                <h3 className="font-header tracking-wider text-sm text-lyra-text-secondary uppercase">
                    {title}
                </h3>
                {/* Optional Status Dot or Mini-Metric can go here */}
            </div>

            <div className="flex-1 overflow-hidden relative">
                {children(size)}
            </div>
        </GlassPanel>
    );
}
