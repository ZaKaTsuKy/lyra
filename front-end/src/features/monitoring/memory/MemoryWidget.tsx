import { memo } from "react";
import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Server, Activity } from "lucide-react";
import { formatBytes } from "@/lib/formatters";

/**
 * ✅ ENHANCED MEMORY WIDGET
 * 
 * Now displays:
 * - RAM usage with percentage
 * - Swap usage
 * - Memory Pressure (Linux PSI)
 * - Spike detection
 */
export const MemoryWidget = memo(function MemoryWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);

    const ramUsagePercent = liveData ? (liveData.memory.used_kb / liveData.memory.total_kb) * 100 : 0;
    const swapUsage = liveData && liveData.memory.swap_total_kb > 0
        ? (liveData.memory.swap_used_kb / liveData.memory.swap_total_kb) * 100
        : 0;

    // Memory Pressure (Linux PSI)
    const pressure = liveData?.memory.pressure_avg10 ?? 0;
    const memSpike = liveData?.anomaly.mem_spike ?? false;

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Memory</CardTitle>
                <div className="flex items-center gap-2">
                    {memSpike && (
                        <Badge variant="danger" className="animate-pulse text-xs">SPIKE</Badge>
                    )}
                    <Server className="h-4 w-4 text-muted-foreground" />
                </div>
            </CardHeader>
            <CardContent className="space-y-3">
                {/* Main RAM Display */}
                <div className="flex justify-between items-baseline">
                    <div className="text-2xl font-bold">
                        {liveData ? formatBytes(liveData.memory.used_kb * 1024) : '0 GB'}
                    </div>
                    <span className="text-xs text-muted-foreground">
                        of {liveData ? formatBytes(liveData.memory.total_kb * 1024) : '...'}
                    </span>
                </div>

                <ProgressBar
                    value={ramUsagePercent}
                    variant={ramUsagePercent > 90 ? "danger" : ramUsagePercent > 75 ? "warning" : "default"}
                />

                {/* Memory Pressure Indicator */}
                {pressure > 0 && (
                    <div className="flex items-center gap-2 text-xs bg-secondary/30 rounded-md px-2 py-1.5">
                        <Activity className={`w-3 h-3 ${pressure > 10 ? 'text-red-500' : pressure > 5 ? 'text-yellow-500' : 'text-green-500'}`} />
                        <span className="text-muted-foreground">Memory Pressure:</span>
                        <span className={`font-mono ${pressure > 10 ? 'text-red-500 font-semibold' : ''}`}>
                            {pressure.toFixed(1)}%
                        </span>
                        {pressure > 10 && (
                            <Badge variant="warning" className="text-[10px] px-1 py-0">Stalled</Badge>
                        )}
                    </div>
                )}

                {/* Swap Section */}
                {liveData && liveData.memory.swap_total_kb > 0 && (
                    <div className="pt-2 border-t border-border/50">
                        <div className="flex justify-between text-xs mb-1.5">
                            <span className="text-muted-foreground">Swap</span>
                            <span className={`font-mono ${swapUsage > 50 ? 'text-destructive font-medium' : 'text-muted-foreground'}`}>
                                {formatBytes(liveData.memory.swap_used_kb * 1024)}
                                <span className="text-muted-foreground/60"> / {formatBytes(liveData.memory.swap_total_kb * 1024)}</span>
                            </span>
                        </div>
                        <ProgressBar
                            value={swapUsage}
                            variant={swapUsage > 50 ? "danger" : swapUsage > 25 ? "warning" : "default"}
                            className="h-1.5"
                        />
                    </div>
                )}
            </CardContent>
        </Card>
    );
});
