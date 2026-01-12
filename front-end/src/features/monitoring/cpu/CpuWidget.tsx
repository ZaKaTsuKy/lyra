import { memo } from "react";
import { useTelemetryStore, selectors } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Cpu, Thermometer } from "lucide-react";
import { CpuHeatmap } from "@/components/charts/CpuHeatmap";

/**
 * ✅ OPTIMIZED CPU WIDGET
 * 
 * Key changes:
 * 1. Uses atomic selectors instead of full liveData object
 * 2. Each selector returns a primitive, so re-renders only happen when that specific value changes
 * 3. Static info is accessed separately
 */
export const CpuWidget = memo(function CpuWidget() {
    // ✅ Atomic selectors - only re-render when these specific values change
    const cpuLoad1 = useTelemetryStore(selectors.cpuLoad);
    const cpuTempValue = useTelemetryStore(selectors.cpuTemp);
    const cpuSpike = useTelemetryStore(selectors.cpuSpike);

    // Static info changes rarely (only on init)
    const coreCount = useTelemetryStore((s) => s.staticInfo?.static.core_count ?? 1);

    // Derived values - these are cheap calculations
    const cpuLoadVal = (cpuLoad1 / coreCount) * 100;
    const cpuLoad = cpuLoadVal.toFixed(2);
    const cpuTemp = cpuTempValue.toFixed(1);

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">CPU Usage</CardTitle>
                <Cpu className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="flex justify-between items-start">
                    <div className="text-2xl font-bold">
                        {cpuLoad}% <span className="text-sm font-normal text-muted-foreground">load</span>
                    </div>
                    {cpuSpike && (
                        <Badge variant="danger" className="animate-pulse">SPIKE</Badge>
                    )}
                </div>
                <div className="flex items-center gap-2 mt-2">
                    <Thermometer className="w-3 h-3 text-red-500" />
                    <span className="text-xs text-muted-foreground">{cpuTemp}°C</span>
                </div>
                <ProgressBar value={cpuLoadVal} max={100} className="mt-3" />

                {/* Heatmap - only receives primitive values */}
                <CpuHeatmap coreCount={coreCount} overallLoad={cpuLoadVal} />
            </CardContent>
        </Card>
    );
});