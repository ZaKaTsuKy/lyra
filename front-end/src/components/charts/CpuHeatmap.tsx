import { cn } from "@/lib/utils";
import { useMemo } from "react";

interface CpuHeatmapProps {
    coreCount: number;
    overallLoad: number; // Placeholder: using overall load to simulate per-core if not available
}

export function CpuHeatmap({ coreCount, overallLoad }: CpuHeatmapProps) {
    // Generate dummy core loads around the overall load for visual variety
    // In a real scenario, this would come from `UpdatePayload.cpu.cores`
    const cores = useMemo(() => Array.from({ length: coreCount }, () => {
        const variance = (Math.random() - 0.5) * 20; // +/- 10%
        return Math.min(Math.max(overallLoad + variance, 0), 100);
    }), [coreCount, overallLoad]);

    const getColor = (load: number) => {
        if (load > 80) return "bg-red-500";
        if (load > 50) return "bg-yellow-500";
        return "bg-green-500";
    };

    return (
        <div className="mt-4">
            <div className="text-xs text-muted-foreground mb-2">Core Activity (Simulated)</div>
            <div className="grid grid-cols-8 gap-1">
                {cores.map((load, i) => (
                    <div
                        key={i}
                        className={cn(
                            "h-3 w-full rounded-sm transition-colors duration-500",
                            getColor(load)
                        )}
                        title={`Core ${i}: ${load.toFixed(1)}%`}
                    />
                ))}
            </div>
        </div>
    );
}
