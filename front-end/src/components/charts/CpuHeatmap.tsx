import { cn } from "@/lib/utils";
import { memo, useMemo } from "react";

interface CpuHeatmapProps {
    coreCount: number;
    overallLoad: number;
}

// Deterministic variance based on core index (no Math.random)
const getCoreVariance = (index: number): number => {
    // Pseudo-random but deterministic: sin produces values between -1 and 1
    return Math.sin(index * 12.9898 + 78.233) * 10; // +/- 10%
};

const getColor = (load: number): string => {
    if (load > 80) return "bg-red-500";
    if (load > 50) return "bg-yellow-500";
    return "bg-green-500";
};

export const CpuHeatmap = memo(function CpuHeatmap({ coreCount, overallLoad }: CpuHeatmapProps) {
    // Core indices are stable, only recalculate when coreCount changes
    const coreIndices = useMemo(() =>
        Array.from({ length: coreCount }, (_, i) => i),
        [coreCount]
    );

    return (
        <div className="mt-4">
            <div className="text-xs text-muted-foreground mb-2">Core Activity (Simulated)</div>
            <div className="grid grid-cols-8 gap-1">
                {coreIndices.map((i) => {
                    const load = Math.min(Math.max(overallLoad + getCoreVariance(i), 0), 100);
                    return (
                        <div
                            key={i}
                            className={cn(
                                "h-3 w-full rounded-sm transition-colors duration-500",
                                getColor(load)
                            )}
                            title={`Core ${i}: ${load.toFixed(1)}%`}
                        />
                    );
                })}
            </div>
        </div>
    );
});
